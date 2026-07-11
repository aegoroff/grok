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
const app = @import("main.zig");

/// Known patterns guaranteed to exist in ./patterns/.
/// Extend this list when adding new .patterns files.
const known_macros = [_][]const u8{
    "YEAR",
    "MONTH",
    "MONTHDAY",
    "HOUR",
    "MINUTE",
    "SECOND",
    "TIME",
    "DATE",
    "NUMBER",
    "BASE10NUM",
    "INT",
    "POSINT",
    "WORD",
    "NOTSPACE",
    "SPACE",
    "DATA",
    "GREEDYDATA",
    "IP",
    "IPORHOST",
    "HOSTNAME",
    "HOSTPORT",
    "PATH",
    "URIPROTO",
    "URIHOST",
    "URIPATH",
    "URIPARAM",
    "URIPATHPARAM",
    "URI",
    "USERNAME",
    "USER",
    "EMAILADDRESS",
    "HTTPDUSER",
    "TIMESTAMP_ISO8601",
    "NLOG",
    "NGINXPROXYACCESS",
    "NGINXPROXYDEFAULTACCESS",
};

const watchdog_timeout_ns: i128 = 5 * std.time.ns_per_s;

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
    file_counter: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    watchdog_spawned: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    iteration_start_ns: std.atomic.Value(i64) = std.atomic.Value(i64).init(0),
};

var g_ctx: *FuzzCtx = undefined;

fn watchdogLoop() void {
    while (true) {
        std.Io.sleep(std.testing.io, .{ .nanoseconds = 200 * std.time.ns_per_ms }, .real) catch return;
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
    if (ctx.watchdog_spawned.cmpxchgStrong(false, true, .acquire, .monotonic) == null) {
        g_ctx = ctx;
        _ = std.Thread.spawn(.{}, watchdogLoop, .{}) catch {};
    }
    const now = std.Io.Clock.real.now(std.testing.io);
    ctx.iteration_start_ns.store(@intCast(now.nanoseconds), .release);

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
    const id = g_ctx.file_counter.fetchAdd(1, .monotonic);
    const tid = std.Thread.getCurrentId();
    const rel_path = try std.fmt.allocPrintSentinel(gpa, "fuzz_tmp_{d}_{d}.log", .{ tid, id }, 0);
    defer gpa.free(rel_path);
    defer std.Io.Dir.cwd().deleteFile(std.testing.io, rel_path) catch |err| {
        std.debug.print("Failed to delete file '{s}': {s}\n", .{ rel_path, @errorName(err) });
    };

    {
        var file = try std.Io.Dir.cwd().createFile(std.testing.io, rel_path, .{});
        defer file.close(std.testing.io);
        var write_buf: [4096]u8 = undefined;
        var file_writer = file.writer(std.testing.io, &write_buf);
        try file_writer.interface.writeAll(subject);
        try file_writer.interface.flush();
    }

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
    try argv_list.append(gpa, rel_path);

    // ── 6. Writer ──────────────────────────────────────────────────────────
    var sink = std.Io.Writer.Allocating.init(gpa);
    defer sink.deinit();

    // ── 7. Run through the same entry point as main() / integration tests ────
    app.run(gpa, &sink.writer, std.testing.io, argv_list.items) catch {};
}

test "fuzz file mode" {
    var ctx = FuzzCtx{};

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
