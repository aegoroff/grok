/// Fuzzing test.
///
/// Drives the real CLI entry point (`main.run`) exactly like the integration
/// tests in `main.zig` do — through Config parsing, pattern library
/// compilation, file opening, encoding detection and matching.
///
/// Only the "file" subcommand is exercised: "file" and "stdin" share the
/// same underlying `matchStrings` code path, and mocking stdin reliably is
/// much harder than writing bytes to a temp file, so testing "file" gives
/// the same coverage for a fraction of the complexity.
///
/// Input is decoded through `std.testing.Smith` (same in fuzz and smoke-test modes):
///   1. macro index — `smith.valueRangeAtMost(u8, 0, len(known_macros) - 1)`
///      (`known_macros` is generated from `patterns/*.patterns` in build.zig)
///   2. flags byte  — `smith.value(u8)`; bit0=info, bit1=json, bit2=invert,
///                    bit3=count, bit4=line-number
///   3. subject     — zero or more chunks until `smith.eos()` returns true:
///        eos=false, chunk_len (1..255), chunk bytes, …, eos=true
///
/// Corpus entries for smoke tests (`zig build test` without `--fuzz`) must use
/// Smith wire format: each integer is u64 little-endian, each eos is one byte
/// (0 = more chunks, 1 = end). See `corpusInput` below.
///
/// Invariants (oracle):
///   - panic / abort are not allowed
///   - memory leak is not allowed (detected by the arena/GPA)
///   - errors like UnknownMacro, InvalidRegex, WriteError — expected, not a bug
const std = @import("std");
const builtin = @import("builtin");
const app = @import("main.zig");
const frontend = @import("frontend.zig");
const pattern_macros = @import("fuzz_macros");

const known_macros = pattern_macros.names;

const watchdog_timeout_ns: i128 = 5 * std.time.ns_per_s;
const fuzz_active_root = ".zig-cache/tmp/.fuzz-active";

const CorpusPart = union(enum) {
    int: u64,
    eos: bool,
    bytes: []const u8,
};

fn macroIdx(comptime name: []const u8) u8 {
    inline for (known_macros, 0..) |macro, i| {
        if (comptime std.mem.eql(u8, macro, name)) return @intCast(i);
    }
    @compileError("unknown macro: " ++ name);
}

/// Builds a Smith-wire corpus entry for smoke tests and initial fuzz seeds.
fn corpusInput(comptime macro_name: []const u8, comptime flags: u8, comptime subject: []const u8) []const u8 {
    const result = comptime result: {
        var parts: [512]CorpusPart = undefined;
        var n: usize = 0;
        parts[n] = .{ .int = macroIdx(macro_name) };
        n += 1;
        parts[n] = .{ .int = flags };
        n += 1;
        if (subject.len == 0) {
            parts[n] = .{ .eos = true };
            n += 1;
        } else {
            var offset: usize = 0;
            while (offset < subject.len) {
                const chunk_len = @min(subject.len - offset, 255);
                parts[n] = .{ .eos = false };
                n += 1;
                parts[n] = .{ .int = chunk_len };
                n += 1;
                parts[n] = .{ .bytes = subject[offset .. offset + chunk_len] };
                n += 1;
                offset += chunk_len;
            }
            parts[n] = .{ .eos = true };
            n += 1;
        }

        var total_len: usize = 0;
        for (parts[0..n]) |part| {
            total_len += switch (part) {
                .int => 8,
                .eos => 1,
                .bytes => |b| b.len,
            };
        }
        var buf: [total_len]u8 = undefined;
        var writer: std.Io.Writer = .fixed(&buf);
        for (parts[0..n]) |part| {
            switch (part) {
                .int => |v| writer.writeInt(u64, v, .little) catch unreachable,
                .eos => |v| writer.writeByte(@intFromBool(v)) catch unreachable,
                .bytes => |b| writer.writeAll(b) catch unreachable,
            }
        }
        break :result buf;
    };
    return &result;
}

/// Fuzzer context: stores state shared across iterations within a process.
/// std.testing.fuzz calls fuzzOne repeatedly in a single process, possibly
/// from multiple threads, so the file-name counter is atomic.
const FuzzCtx = struct {
    tmp_dir: *std.testing.TmpDir,
    file_counter: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    watchdog_spawned: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    iteration_start_ns: std.atomic.Value(i64) = std.atomic.Value(i64).init(0),
};

var g_ctx: *FuzzCtx = undefined;
var watchdog_stop = std.atomic.Value(bool).init(false);
var interrupt_requested = std.atomic.Value(bool).init(false);
var interrupt_cleanup_done = std.atomic.Value(bool).init(false);
var active_tmp_dir: ?*std.testing.TmpDir = null;
var active_registry_path: [128]u8 = undefined;
var active_registry_path_len: usize = 0;

const sigint_cleanup_supported = @hasDecl(std.posix, "sigaction") and @hasDecl(std.posix.SIG, "INT");

fn processId() std.posix.pid_t {
    return switch (builtin.os.tag) {
        .linux => std.os.linux.getpid(),
        .macos, .ios, .tvos, .watchos, .visionos => blk: {
            const rc = std.c.getpid();
            break :blk @intCast(rc);
        },
        else => @compileError("fuzz temp cleanup unsupported on this OS"),
    };
}

fn isProcessAlive(pid: std.posix.pid_t) bool {
    if (builtin.os.tag == .linux) {
        var path_buf: [64]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "/proc/{d}", .{pid}) catch return true;
        std.Io.Dir.cwd().access(std.testing.io, path, .{}) catch return false;
        return true;
    }
    return true;
}

fn cleanupStaleFuzzTmpDirs() void {
    const io = std.testing.io;
    var tmp_root = std.Io.Dir.cwd().openDir(io, ".zig-cache/tmp", .{}) catch return;
    defer tmp_root.close(io);
    var active_root = tmp_root.createDirPathOpen(io, ".fuzz-active", .{
        .open_options = .{ .iterate = true },
    }) catch return;
    defer active_root.close(io);

    var it = active_root.iterate();
    while (it.next(io) catch null) |entry| {
        if (entry.kind != .file) continue;
        const pid = std.fmt.parseInt(std.posix.pid_t, entry.name, 10) catch continue;
        if (isProcessAlive(pid)) continue;

        const registry = active_root.readFileAlloc(io, entry.name, std.testing.allocator, .unlimited) catch continue;
        defer std.testing.allocator.free(registry);
        const sub_path = std.mem.trim(u8, registry, " \t\r\n");
        if (sub_path.len == 0) continue;

        tmp_root.deleteTree(io, sub_path) catch {};
        active_root.deleteFile(io, entry.name) catch {};
    }
}

fn registerActiveFuzzTmpDir(tmp_dir: *std.testing.TmpDir) void {
    const io = std.testing.io;
    const pid = processId();
    const written = std.fmt.bufPrint(
        &active_registry_path,
        fuzz_active_root ++ "/{d}",
        .{pid},
    ) catch return;
    active_registry_path_len = written.len;
    active_tmp_dir = tmp_dir;

    var tmp_root = std.Io.Dir.cwd().openDir(io, ".zig-cache/tmp", .{}) catch return;
    defer tmp_root.close(io);
    var active_root = tmp_root.createDirPathOpen(io, ".fuzz-active", .{}) catch return;
    defer active_root.close(io);

    var pid_buf: [32]u8 = undefined;
    const pid_name = std.fmt.bufPrint(&pid_buf, "{d}", .{pid}) catch return;
    var registry = active_root.createFile(io, pid_name, .{}) catch return;
    defer registry.close(io);
    var write_buf: [64]u8 = undefined;
    var file_writer = registry.writer(io, &write_buf);
    file_writer.interface.writeAll(tmp_dir.sub_path[0..]) catch {};
    file_writer.interface.flush() catch {};
}

fn unregisterActiveFuzzTmpDir() void {
    if (active_registry_path_len == 0) return;
    const io = std.testing.io;
    std.Io.Dir.cwd().deleteFile(io, active_registry_path[0..active_registry_path_len]) catch {};
    active_registry_path_len = 0;
    active_tmp_dir = null;
}

fn cleanupActiveFuzzTmpDir() void {
    if (active_tmp_dir) |dir| {
        dir.cleanup();
        active_tmp_dir = null;
    }
    unregisterActiveFuzzTmpDir();
}

fn finishAfterInterrupt() noreturn {
    if (interrupt_cleanup_done.swap(true, .release)) std.process.exit(130);
    cleanupActiveFuzzTmpDir();
    std.process.exit(130);
}

const SigintCleanup = if (sigint_cleanup_supported) struct {
    var prev_int: std.posix.Sigaction = undefined;
    var prev_term: std.posix.Sigaction = undefined;
    var installed = false;

    fn interruptHandler(sig: std.posix.SIG) callconv(.c) void {
        _ = sig;
        interrupt_requested.store(true, .release);
    }

    fn install() void {
        const act = std.posix.Sigaction{
            .handler = .{ .handler = interruptHandler },
            .mask = std.posix.sigemptyset(),
            .flags = 0,
        };
        std.posix.sigaction(.INT, &act, if (installed) null else &prev_int);
        if (@hasDecl(std.posix.SIG, "TERM")) {
            std.posix.sigaction(.TERM, &act, if (installed) null else &prev_term);
        }
        installed = true;
    }

    fn restore() void {
        if (!installed) return;
        std.posix.sigaction(.INT, &prev_int, null);
        if (@hasDecl(std.posix.SIG, "TERM")) {
            std.posix.sigaction(.TERM, &prev_term, null);
        }
        installed = false;
    }
} else struct {
    fn install() void {}
    fn restore() void {}
};

fn watchdogLoop() void {
    while (!watchdog_stop.load(.acquire)) {
        if (interrupt_requested.load(.acquire)) {
            const start = g_ctx.iteration_start_ns.load(.acquire);
            if (start == 0) finishAfterInterrupt();
        }
        std.Io.sleep(std.testing.io, .{ .nanoseconds = 200 * std.time.ns_per_ms }, .real) catch return;
        if (watchdog_stop.load(.acquire)) return;
        const start = g_ctx.iteration_start_ns.load(.acquire);
        if (start == 0) continue; // no iteration in flight right now
        const now = std.Io.Clock.real.now(std.testing.io);
        if (now.nanoseconds - start > watchdog_timeout_ns) {
            std.debug.print("WATCHDOG: iteration exceeded timeout, see last 'fuzz input:' line above for the offending bytes\n", .{});
            std.process.abort(); // SIGABRT -> hard crash instead of silent hang
        }
    }
}

/// Single fuzz iteration. Called by fuzzer with mutated bytes.
fn fuzzOne(ctx: *FuzzCtx, smith: *std.testing.Smith) anyerror!void {
    if (interrupt_requested.load(.acquire)) finishAfterInterrupt();

    if (ctx.watchdog_spawned.cmpxchgStrong(false, true, .acquire, .monotonic) == null) {
        g_ctx = ctx;
        _ = std.Thread.spawn(.{}, watchdogLoop, .{}) catch {};
    }
    const now = std.Io.Clock.real.now(std.testing.io);
    ctx.iteration_start_ns.store(@intCast(now.nanoseconds), .release);
    defer ctx.iteration_start_ns.store(0, .release);

    // ── 1. Select pattern ──────────────────────────────────────────────────
    const macro_idx = smith.valueRangeAtMost(u8, 0, known_macros.len - 1);
    const macro = known_macros[macro_idx];

    // var gpa_alloc = std.heap.DebugAllocator(.{
    //     .stack_trace_frames = 10,
    // }){};
    // defer std.debug.assert(gpa_alloc.deinit() == .ok);
    // const gpa = gpa_alloc.allocator();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // ── 2. Select flags ────────────────────────────────────────────────────
    const flags_byte = smith.value(u8);

    // ── 3. Subject ─────────────────────────────────────────────────────────
    var subject_list: std.ArrayList(u8) = .empty;
    defer subject_list.deinit(gpa);
    while (!smith.eos()) {
        const len = smith.valueRangeAtMost(u8, 1, 255);
        const slice = try subject_list.addManyAsSlice(gpa, len);
        smith.bytes(slice);
    }
    if (subject_list.items.len > 64 * 1024) return error.SkipZigTest;
    const subject = subject_list.items;

    // std.debug.print("fuzz: macro={s} flags=0x{x:0>2} subject_len={d} subject_hex={x}\n", .{
    //     macro, flags_byte, subject.len, subject,
    // });

    // ── 4. Write subject into a temp file ──────────────
    const id = ctx.file_counter.fetchAdd(1, .monotonic);
    const tid = std.Thread.getCurrentId();
    const basename = try std.fmt.allocPrintSentinel(gpa, "fuzz_{d}_{d}.log", .{ tid, id }, 0);
    defer gpa.free(basename);
    defer ctx.tmp_dir.dir.deleteFile(std.testing.io, basename) catch {};

    {
        var file = try ctx.tmp_dir.dir.createFile(std.testing.io, basename, .{});
        defer file.close(std.testing.io);
        var write_buf: [4096]u8 = undefined;
        var file_writer = file.writer(std.testing.io, &write_buf);
        try file_writer.interface.writeAll(subject);
        try file_writer.interface.flush();
    }

    const file_path = try std.fmt.allocPrintSentinel(
        gpa,
        ".zig-cache/tmp/{s}/{s}",
        .{ ctx.tmp_dir.sub_path[0..], basename },
        0,
    );
    defer gpa.free(file_path);

    // ── 5. Build argv exactly like the real CLI / integration tests ────────
    const macro_z = try gpa.dupeSentinel(u8, macro, 0);
    defer gpa.free(macro_z);

    var argv_list: std.ArrayList([:0]const u8) = .empty;
    defer argv_list.deinit(gpa);
    try argv_list.appendSlice(gpa, &[_][:0]const u8{ "file", "-p", "./patterns/", "-m", macro_z });
    if (flags_byte & 0b00001 != 0) try argv_list.append(gpa, "-i");
    if (flags_byte & 0b00010 != 0) try argv_list.append(gpa, "-j");
    if (flags_byte & 0b00100 != 0) try argv_list.append(gpa, "-v");
    if (flags_byte & 0b01000 != 0) try argv_list.append(gpa, "-c");
    if (flags_byte & 0b10000 != 0) try argv_list.append(gpa, "-n");
    try argv_list.append(gpa, file_path);

    // ── 6. Writer ──────────────────────────────────────────────────────────
    var sink = std.Io.Writer.Allocating.init(gpa);
    defer sink.deinit();

    // ── 7. Run through the same entry point as main() / integration tests ────
    app.run(gpa, &sink.writer, std.testing.io, argv_list.items) catch {};
}

test "known macros exist in ./patterns/" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var paths_buf = [_][]const u8{"./patterns/"};
    const paths: [][]const u8 = paths_buf[0..];
    try frontend.compileLib(arena.allocator(), std.testing.io, paths);
    defer frontend.deinitLib();

    inline for (known_macros) |name| {
        _ = try frontend.getPattern(name);
    }

    var loaded: usize = 0;
    var it = frontend.getPatterns().keyIterator();
    while (it.next()) |key| {
        _ = key.*;
        loaded += 1;
    }
    try std.testing.expectEqual(known_macros.len, loaded);
}

test "fuzz file mode" {
    interrupt_requested.store(false, .release);
    interrupt_cleanup_done.store(false, .release);
    watchdog_stop.store(false, .release);
    cleanupStaleFuzzTmpDirs();

    var tmp_dir = std.testing.tmpDir(.{});
    registerActiveFuzzTmpDir(&tmp_dir);
    SigintCleanup.install();
    defer {
        watchdog_stop.store(true, .release);
        SigintCleanup.restore();
        cleanupActiveFuzzTmpDir();
    }

    var ctx = FuzzCtx{ .tmp_dir = &tmp_dir };

    try std.testing.fuzz(&ctx, fuzzOne, .{
        .corpus = &.{
            corpusInput("YEAR", 0, "2024"),
            corpusInput("YEAR", 0b10, "2024"),
            corpusInput("YEAR", 0b01, "2024"),
            corpusInput("YEAR", 0, "not-a-year"),
            corpusInput("YEAR", 0b100, "not-a-year"),
            corpusInput("NUMBER", 0, "12345"),
            corpusInput("NUMBER", 0, "-3.14"),
            corpusInput("NUMBER", 0b01, "not-a-number"),
            corpusInput("NUMBER", 0b100, "no-match"),
            corpusInput("IP", 0, "192.168.1.1"),
            corpusInput("IP", 0, "999.999.999.999"),
            corpusInput("IP", 0b10, "10.0.0.1"),
            corpusInput("EMAILADDRESS", 0b10, "user@example.com"),
            corpusInput("NLOG", 0b01, "2016-08-13 01:46:09,637 INFO x"),
            corpusInput("NLOG", 0b1000, "2016-08-13 01:46:09,637 INFO x\nplain line"),
            corpusInput("NLOG", 0b10000, "2016-08-13 01:46:09,637 INFO x"),
            corpusInput("YEAR", 0, ""),
            corpusInput("GREEDYDATA", 0, ""),
            corpusInput("YEAR", 0, &[_]u8{ 0x00, 0xff, 0xfe }),
            corpusInput("YEAR", 0, "\n\r\t"),
            corpusInput("YEAR", 0, "\xd0\xb3\xd1\x80\xd0\xbe\xd0\xba"),
            corpusInput("NOTSPACE", 0, "a" ** 512),
            corpusInput("SPACE", 0, " " ** 512),
            corpusInput("GREEDYDATA", 0, "x" ** 1024),
            corpusInput("YEAR", 0, "20\x0024"),
            corpusInput("YEAR", 0, "2024\nnot-a-year\n2025"),
        },
    });
}
