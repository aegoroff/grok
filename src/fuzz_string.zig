/// Fuzz test for `string` mode (matchString).
///
/// Input format (layout is fixed so fuzzer quickly learns semantics):
///   input[0]  — pattern index: input[0] % len(known_macros)
///   input[1]  — OutputFlags bit mask: bit0=info, bit1=json, bit2=invert
///   input[2:] — subject (arbitrary bytes, including garbage and UTF-8)
///
/// Invariants (oracle):
///   - panic / abort are not allowed
///   - memory leak is not allowed (detected by GPA)
///   - errors like UnknownMacro, InvalidRegex, WriteError — expected, not a bug
const std = @import("std");
const matcher = @import("matcher.zig");
const front = @import("frontend.zig");

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

/// Fuzzer context: stores state initialized once per process.
/// std.testing.fuzz calls testOne repeatedly in a single process.
const FuzzCtx = struct {
    frontend_ready: bool,
};

/// Single fuzz iteration. Called by fuzzer with mutated bytes.
fn fuzzOne(ctx: *FuzzCtx, smith: *std.testing.Smith) anyerror!void {
    var buf: [4096]u8 = undefined;
    const input_len = smith.slice(&buf);
    if (input_len < 2) return;

    const input = buf[0..@intCast(input_len)];

    // ── 1. Initialize frontend once per process ──────────────────────────────
    if (!ctx.frontend_ready) {
        var paths = [_][]const u8{"./patterns/"};
        front.compileLib(
            std.heap.page_allocator,
            std.testing.io,
            paths[0..],
        ) catch |err| {
            _ = @errorName(err);
        };
        ctx.frontend_ready = true;
    }

    // ── 2. Select pattern ────────────────────────────────────────────────────
    const macro_idx = input[0] % known_macros.len;
    const macro = known_macros[macro_idx];

    // ── 3. Select output flags ───────────────────────────────────────────────
    const flags_byte = input[1];
    const flags = matcher.OutputFlags{
        .info = (flags_byte & 0b001) != 0,
        .json = (flags_byte & 0b010) != 0,
        .count = false,
        .print_line_num = false,
        .invert_match = (flags_byte & 0b100) != 0,
    };

    // ── 4. Subject ───────────────────────────────────────────────────────────
    const subject = input[2..];

    // ── 5. Allocator with leak detector ──────────────────────────────────────
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // ── 6. Writer ────────────────────────────────────────────────────────────
    var sink_buf: [4096]u8 = undefined;
    var sink: std.Io.Writer = .fixed(&sink_buf);

    // ── 7. Matcher.init + matchString ────────────────────────────────────────
    var m = matcher.Matcher.init(gpa, &sink, macro) catch return;
    defer m.deinit();

    m.matchString(subject, flags) catch {};
}

test "fuzz string mode" {
    var ctx = FuzzCtx{ .frontend_ready = false };

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
        },
    });
}
