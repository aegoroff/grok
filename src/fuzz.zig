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
/// Input format (layout is fixed so fuzzer quickly learns semantics):
///   input[0]  — pattern index: input[0] % len(known_macros)
///   input[1]  — flags bit mask: bit0=info, bit1=json, bit2=invert,
///                                bit3=count, bit4=line-number
///   input[2:] — subject (arbitrary bytes, including garbage and UTF-8)
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

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // ── 1. Select pattern ──────────────────────────────────────────────────
    const macro_idx = smith.valueRangeAtMost(u8, 0, known_macros.len - 1);
    const macro = known_macros[macro_idx];

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
    const subject = subject_list.items;

    // std.debug.print("fuzz: macro={s} flags=0x{x:0>2} subject_len={d} subject_hex={x}\n", .{
    //     macro, flags_byte, subject.len, subject,
    // });

    // ── 4. Write subject into a temp file ──────────────
    const id = g_ctx.file_counter.fetchAdd(1, .monotonic);
    const rel_path = try std.fmt.allocPrintSentinel(gpa, "fuzz_tmp_{d}.log", .{id}, 0);
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

    var argv_list: std.ArrayList([:0]const u8) = .empty;
    try argv_list.appendSlice(gpa, &[_][:0]const u8{ "file", "-p", "./patterns/", "-m", macro_z });
    if (flags_byte & 0b00001 != 0) try argv_list.append(gpa, "-i");
    if (flags_byte & 0b00010 != 0) try argv_list.append(gpa, "-j");
    if (flags_byte & 0b00100 != 0) try argv_list.append(gpa, "-v");
    if (flags_byte & 0b01000 != 0) try argv_list.append(gpa, "-c");
    if (flags_byte & 0b10000 != 0) try argv_list.append(gpa, "-n");
    try argv_list.append(gpa, rel_path);

    // ── 6. Writer ──────────────────────────────────────────────────────────
    var sink = std.Io.Writer.Allocating.init(arena.allocator());

    // ── 7. Run through the same entry point as main() / integration tests ────
    app.run(gpa, &sink.writer, std.testing.io, argv_list.items) catch {};
}

test "fuzz file mode" {
    var ctx = FuzzCtx{};

    try std.testing.fuzz(&ctx, fuzzOne, .{
        // Initial corpus: covers different patterns, flags, and edge cases.
        // byte[0]=macro_idx, byte[1]=flags_bits, rest=subject
        .corpus = &[_][]const u8{
            "\x00\x00" ++ "2024", // YEAR, plain, match
            "\x00\x02" ++ "2024", // YEAR, json, match
            "\x00\x01" ++ "2024", // YEAR, info, match
            "\x00\x00" ++ "not-a-year", // YEAR, plain, no match
            "\x00\x04" ++ "not-a-year", // YEAR, invert, should output
            "\x08\x00" ++ "12345", // NUMBER, plain, match
            "\x08\x00" ++ "-3.14", // NUMBER, negative float
            "\x08\x01" ++ "not-a-number", // NUMBER, info, no match
            "\x08\x04" ++ "no-match", // NUMBER, invert
            "\x11\x00" ++ "192.168.1.1", // IP, match
            "\x11\x00" ++ "999.999.999.999", // IP, no match
            "\x11\x02" ++ "10.0.0.1", // IP, json
            "\x20\x02" ++ "user@example.com", // EMAILADDRESS, json
            "\x23\x01" ++ "2016-08-13 01:46:09,637 INFO x", // NLOG, info
            "\x23\x08" ++ "2016-08-13 01:46:09,637 INFO x\nplain line", // NLOG, count
            "\x23\x10" ++ "2016-08-13 01:46:09,637 INFO x", // NLOG, line-number
            // Edge cases for subject
            "\x00\x00" ++ "", // empty subject
            "\x10\x00" ++ "", // GREEDYDATA + empty
            "\x00\x00\x00\xff\xfe", // binary garbage
            "\x00\x00\n\r\t", // control characters
            // UTF-8 multibyte characters (Cyrillic)
            "\x00\x00\xd0\xb3\xd1\x80\xd0\xbe\xd0\xba",
            // Stress test for PCRE2 backtracking
            "\x0e\x00" ++ "a" ** 512, // NOTSPACE, long input
            "\x0f\x00" ++ " " ** 512, // SPACE, long input
            "\x10\x00" ++ "x" ** 1024, // GREEDYDATA, very long
            // Null bytes inside subject
            "\x00\x00" ++ "20\x0024",
            // Multi-line file content
            "\x00\x00" ++ "2024\nnot-a-year\n2025",
            // Crash reports
            "\x13\xa2\x0b", // HOSTPORT, json + line-number, vertical tab
            "\x1f\xca", // NGINXPROXYDEFAULTACCESS, json + count, empty subject
        },
    });
}
