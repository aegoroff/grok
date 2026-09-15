const std = @import("std");
const main = @import("main.zig");

const NLOG_MATCHES =
    \\2016-08-13 01:46:09,637 INFO logviewer Value cannot be null.
    \\2016-08-13 10:21:58,814 INFO logviewer Минимальный уровень должен быть меньше или равен максимальному
    \\
;

const NLOG_LINE_NUMBERS =
    \\1: 2016-08-13 01:46:09,637 INFO logviewer Value cannot be null.
    \\2: 2016-08-13 10:21:58,814 INFO logviewer Минимальный уровень должен быть меньше или равен максимальному
    \\
;

const NLOG_INFO =
    \\line: 1 match: true | pattern: NLOG
    \\
    \\  Meta properties found:
    \\    Occured: 2016-08-13 01:46:09,637
    \\    Level: INFO
    \\
    \\
    \\line: 2 match: true | pattern: NLOG
    \\
    \\  Meta properties found:
    \\    Occured: 2016-08-13 10:21:58,814
    \\    Level: INFO
    \\
    \\
    \\
;

const NLOG_JSON =
    \\{"line":1,"matched":true,"pattern":"NLOG","text":"2016-08-13 01:46:09,637 INFO logviewer Value cannot be null.","properties":{"Occured":"2016-08-13 01:46:09,637","Level":"INFO"}}
    \\{"line":2,"matched":true,"pattern":"NLOG","text":"2016-08-13 10:21:58,814 INFO logviewer Минимальный уровень должен быть меньше или равен максимальному","properties":{"Occured":"2016-08-13 10:21:58,814","Level":"INFO"}}
    \\
;

const NLOG_STRING_INFO =
    \\line: 1 match: true | pattern: NLOG
    \\
    \\  Meta properties found:
    \\    Occured: 2016-08-13 01:46:09,637
    \\    Level: INFO
    \\
    \\
    \\
;

const PATTERNS = "./patterns/";
const NLOG_FILE_UTF8 = "./test_assets/logUTF8.log";
const NLOG_FILE_UTF8_BOM = "./test_assets/logUTF8BOM.log";
const NLOG_FILE_UTF16LE = "./test_assets/logUTF16LE.log";
const NLOG_FILE_UTF16BE = "./test_assets/logUTF16BE.log";
const NLOG_FILE_UTF32LE = "./test_assets/logUTF32LE.log";
const NLOG_FILE_UTF32BE = "./test_assets/logUTF32BE.log";

const Expected = union(enum) {
    success: []const u8,
    failure: struct {
        output: []const u8,
        err: ?anyerror = null,
    },
    contains: []const []const u8,
};

const Case = struct {
    name: []const u8,
    argv: []const [:0]const u8,
    expected: Expected,
};

const CASES = [_]Case{
    .{
        .name = "match plain string",
        .argv = &.{ "string", "-p", PATTERNS, "-m", "YEAR", "2010" },
        .expected = .{ .success = "2010\n" },
    },
    .{
        .name = "invert match plain string",
        .argv = &.{ "string", "-p", PATTERNS, "-v", "-m", "YEAR", "2010" },
        .expected = .{ .success = "" },
    },
    .{
        .name = "macro view",
        .argv = &.{ "macro", "YEAR", "-p", PATTERNS },
        .expected = .{ .success = "(?>\\d\\d){1,2}\n" },
    },
    .{
        .name = "macro view complex pattern",
        .argv = &.{ "macro", "NUMBER", "-p", PATTERNS },
        .expected = .{ .success = "(?:(?<![0-9.+-])(?>[+-]?(?:(?:[0-9]+(?:\\.[0-9]+)?)|(?:\\.[0-9]+))))\n" },
    },
    .{
        .name = "macro view bad (not exist) pattern",
        .argv = &.{ "macro", "BAD", "-p", PATTERNS },
        .expected = .{
            .failure = .{
                .err = error.UnknownMacro,
                .output = "Failed show macro: error.UnknownMacro\n",
            },
        },
    },
    .{
        .name = "macro with unknown nested reference",
        .argv = &.{ "macro", "BADNESTED", "-p", "./test_assets/bad_nested.patterns" },
        .expected = .{
            .failure = .{
                .err = error.UnknownMacro,
                .output = "Failed show macro: error.UnknownMacro\n",
            },
        },
    },
    .{
        .name = "macro with circular reference",
        .argv = &.{ "macro", "CYCLEA", "-p", "./test_assets/circular.patterns" },
        .expected = .{
            .failure = .{
                .err = error.CircularMacro,
                .output = "Failed show macro: error.CircularMacro\n",
            },
        },
    },
    .{
        .name = "macro with self reference",
        .argv = &.{ "macro", "SELFREF", "-p", "./test_assets/circular.patterns" },
        .expected = .{
            .failure = .{
                .err = error.CircularMacro,
                .output = "Failed show macro: error.CircularMacro\n",
            },
        },
    },
    .{
        .name = "match file UTF-8 without flags",
        .argv = &.{ "file", "-p", PATTERNS, "-m", "NLOG", NLOG_FILE_UTF8 },
        .expected = .{ .success = NLOG_MATCHES },
    },
    .{
        .name = "match file UTF-8 no match",
        .argv = &.{ "file", "-p", PATTERNS, "-m", "NGINXPROXYACCESS", NLOG_FILE_UTF8 },
        .expected = .{ .success = "" },
    },
    .{
        .name = "match file UTF-8 count",
        .argv = &.{ "file", "-p", PATTERNS, "-m", "NLOG", "-c", NLOG_FILE_UTF8 },
        .expected = .{ .success = "2\n" },
    },
    .{
        .name = "match file UTF-8 count no matches",
        .argv = &.{ "file", "-p", PATTERNS, "-m", "NGINXPROXYACCESS", "-c", NLOG_FILE_UTF8 },
        .expected = .{ .success = "0\n" },
    },
    .{
        .name = "match file UTF-8 invert match - no results",
        .argv = &.{ "file", "-p", PATTERNS, "-m", "NLOG", "-v", NLOG_FILE_UTF8 },
        .expected = .{ .success = "" },
    },
    .{
        .name = "match file UTF-8 info",
        .argv = &.{ "file", "-p", PATTERNS, "-m", "NLOG", "-i", NLOG_FILE_UTF8 },
        .expected = .{ .success = NLOG_INFO },
    },
    .{
        .name = "match file UTF-8 json",
        .argv = &.{ "file", "-p", PATTERNS, "-m", "NLOG", "-j", NLOG_FILE_UTF8 },
        .expected = .{ .success = NLOG_JSON },
    },
    .{
        .name = "match file UTF-16LE count",
        .argv = &.{ "file", "-p", PATTERNS, "-m", "NLOG", "-c", NLOG_FILE_UTF16LE },
        .expected = .{ .success = "2\n" },
    },
    .{
        .name = "match file UTF-16LE",
        .argv = &.{ "file", "-p", PATTERNS, "-m", "NLOG", NLOG_FILE_UTF16LE },
        .expected = .{ .success = NLOG_MATCHES },
    },
    .{
        .name = "match file UTF-16BE count",
        .argv = &.{ "file", "-p", PATTERNS, "-m", "NLOG", "-c", NLOG_FILE_UTF16BE },
        .expected = .{ .success = "2\n" },
    },
    .{
        .name = "match file UTF-16BE",
        .argv = &.{ "file", "-p", PATTERNS, "-m", "NLOG", NLOG_FILE_UTF16BE },
        .expected = .{ .success = NLOG_MATCHES },
    },
    .{
        .name = "match empty file UTF-16BE",
        .argv = &.{ "file", "-p", PATTERNS, "-m", "DATA", "./test_assets/emptyUTF16BE.log" },
        .expected = .{ .success = "" },
    },
    .{
        .name = "match file UTF-32LE count",
        .argv = &.{ "file", "-p", PATTERNS, "-m", "NLOG", "-c", NLOG_FILE_UTF32LE },
        .expected = .{ .success = "2\n" },
    },
    .{
        .name = "match file UTF-32LE",
        .argv = &.{ "file", "-p", PATTERNS, "-m", "NLOG", NLOG_FILE_UTF32LE },
        .expected = .{ .success = NLOG_MATCHES },
    },
    .{
        .name = "match invalid file UTF-32LE",
        .argv = &.{ "file", "-p", PATTERNS, "-m", "NLOG", "./test_assets/invalidUTF32LE.log" },
        .expected = .{
            .failure = .{
                .err = error.InvalidUtf32LineLength,
                .output = "Failed file match: error.InvalidUtf32LineLength\n",
            },
        },
    },
    .{
        .name = "match file UTF-32BE count",
        .argv = &.{ "file", "-p", PATTERNS, "-m", "NLOG", "-c", NLOG_FILE_UTF32BE },
        .expected = .{ .success = "2\n" },
    },
    .{
        .name = "match file UTF-32BE",
        .argv = &.{ "file", "-p", PATTERNS, "-m", "NLOG", NLOG_FILE_UTF32BE },
        .expected = .{ .success = NLOG_MATCHES },
    },
    .{
        .name = "match empty file UTF-32BE",
        .argv = &.{ "file", "-p", PATTERNS, "-m", "DATA", "./test_assets/emptyUTF32BE.log" },
        .expected = .{ .success = "" },
    },
    .{
        .name = "match invalid file UTF-32BE",
        .argv = &.{ "file", "-p", PATTERNS, "-m", "NLOG", "./test_assets/invalidUTF32BE.log" },
        .expected = .{ .success = "" },
    },
    .{
        .name = "list all macros",
        .argv = &.{ "macro", "-p", PATTERNS },
        .expected = .{ .contains = &.{ "NLOG", "NGINXPROXYACCESS", "NGINXPROXYDEFAULTACCESS" } },
    },
    .{
        .name = "match string with NUMBER pattern",
        .argv = &.{ "string", "-p", PATTERNS, "-m", "NUMBER", "12345" },
        .expected = .{ .success = "12345\n" },
    },
    .{
        .name = "match string with NUMBER pattern no match",
        .argv = &.{ "string", "-p", PATTERNS, "-m", "NUMBER", "abc" },
        .expected = .{ .success = "" },
    },
    .{
        .name = "match string invert with NUMBER pattern",
        .argv = &.{ "string", "-p", PATTERNS, "-m", "NUMBER", "-v", "abc" },
        .expected = .{ .success = "abc\n" },
    },
    .{
        .name = "match string with IP pattern",
        .argv = &.{ "string", "-p", PATTERNS, "-m", "IP", "192.168.1.1" },
        .expected = .{ .success = "192.168.1.1\n" },
    },
    .{
        .name = "match string with IP pattern invalid",
        .argv = &.{ "string", "-p", PATTERNS, "-m", "IP", "999.999.999.999" },
        .expected = .{ .success = "" },
    },
    .{
        .name = "match string with TIMESTAMP_ISO8601 pattern",
        .argv = &.{ "string", "-p", PATTERNS, "-m", "TIMESTAMP_ISO8601", "2016-08-13 01:46:09,637" },
        .expected = .{ .success = "2016-08-13 01:46:09,637\n" },
    },
    .{
        .name = "match file UTF-8 with line numbers",
        .argv = &.{ "file", "-p", PATTERNS, "-m", "NLOG", "-n", NLOG_FILE_UTF8 },
        .expected = .{ .success = NLOG_LINE_NUMBERS },
    },
    .{
        .name = "match file UTF-16LE with line numbers",
        .argv = &.{ "file", "-p", PATTERNS, "-m", "NLOG", "-n", NLOG_FILE_UTF16LE },
        .expected = .{ .success = NLOG_LINE_NUMBERS },
    },
    .{
        .name = "match file UTF-32LE with line numbers",
        .argv = &.{ "file", "-p", PATTERNS, "-m", "NLOG", "-n", NLOG_FILE_UTF32LE },
        .expected = .{ .success = NLOG_LINE_NUMBERS },
    },
    .{
        .name = "match file UTF-32BE with line numbers",
        .argv = &.{ "file", "-p", PATTERNS, "-m", "NLOG", "-n", NLOG_FILE_UTF32BE },
        .expected = .{ .success = NLOG_LINE_NUMBERS },
    },
    .{
        .name = "match file UTF-16BE with line numbers",
        .argv = &.{ "file", "-p", PATTERNS, "-m", "NLOG", "-n", NLOG_FILE_UTF16BE },
        .expected = .{ .success = NLOG_LINE_NUMBERS },
    },
    .{
        .name = "match file UTF-16LE crash",
        .argv = &.{ "file", "-p", PATTERNS, "-m", "NLOG", "./test_assets/crash.log" },
        .expected = .{ .success = "" },
    },
    .{
        .name = "match file UTF-16BE crash1",
        .argv = &.{ "file", "-p", PATTERNS, "-m", "NLOG", "./test_assets/crash1.log" },
        .expected = .{
            .failure = .{
                .output = "Failed file match: error.UnexpectedSecondSurrogateHalf\n",
            },
        },
    },
    .{
        .name = "match file UTF-16BE crash2",
        .argv = &.{ "file", "-p", PATTERNS, "-m", "NLOG", "./test_assets/crash2.log" },
        .expected = .{
            .failure = .{
                .err = error.InvalidUtf16LineLength,
                .output = "Failed file match: error.InvalidUtf16LineLength\n",
            },
        },
    },
    .{
        .name = "match string info with NLOG captures",
        .argv = &.{ "string", "-p", PATTERNS, "-m", "NLOG", "-i", "2016-08-13 01:46:09,637 INFO logviewer Value cannot be null." },
        .expected = .{ .success = NLOG_STRING_INFO },
    },
    .{
        .name = "match file invert NGINXPROXYACCESS",
        .argv = &.{ "file", "-p", PATTERNS, "-m", "NGINXPROXYACCESS", "-v", NLOG_FILE_UTF8 },
        .expected = .{ .success = NLOG_MATCHES },
    },
    .{
        .name = "match string unknown macro",
        .argv = &.{ "string", "-p", PATTERNS, "-m", "UNKNOWN", "foo" },
        .expected = .{
            .failure = .{
                .err = error.UnknownMacro,
                .output = "Failed string match: error.UnknownMacro\n",
            },
        },
    },
    .{
        .name = "match file UTF-8 BOM",
        .argv = &.{ "file", "-p", PATTERNS, "-m", "NLOG", NLOG_FILE_UTF8_BOM },
        .expected = .{ .success = NLOG_MATCHES },
    },
    .{
        .name = "file without macro",
        .argv = &.{ "file", "-p", PATTERNS, NLOG_FILE_UTF8 },
        .expected = .{
            .failure = .{
                .err = error.MacroNotProvided,
                .output = "Failed file match: error.MacroNotProvided\n",
            },
        },
    },
    .{
        .name = "string without macro",
        .argv = &.{ "string", "-p", PATTERNS, "2010" },
        .expected = .{
            .failure = .{
                .err = error.MacroNotProvided,
                .output = "Failed string match: error.MacroNotProvided\n",
            },
        },
    },
    .{
        .name = "stdin without macro",
        .argv = &.{ "stdin", "-p", PATTERNS },
        .expected = .{
            .failure = .{
                .err = error.MacroNotProvided,
                .output = "Failed stdin match: error.MacroNotProvided\n",
            },
        },
    },
};

fn runCase(tc: Case) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const run_result = main.run(arena.allocator(), &writer.writer, std.testing.io, tc.argv);

    switch (tc.expected) {
        .success => |expected| {
            try run_result;
            try std.testing.expectEqualStrings(expected, writer.written());
        },
        .failure => |failure| {
            if (failure.err) |expected_err| {
                try std.testing.expectError(expected_err, run_result);
            } else {
                run_result catch {
                    try std.testing.expectEqualStrings(failure.output, writer.written());
                    return;
                };
                return error.TestExpectedError;
            }
            try std.testing.expectEqualStrings(failure.output, writer.written());
        },
        .contains => |subs| {
            try run_result;
            const output = writer.written();
            for (subs) |sub| {
                try std.testing.expect(std.mem.indexOf(u8, output, sub) != null);
            }
        },
    }
}

fn integrationTest(comptime tc: Case) type {
    return struct {
        test {
            runCase(tc) catch |err| {
                std.debug.print("integration: {s}\n", .{tc.name});
                return err;
            };
        }
    };
}

comptime {
    for (CASES) |tc| {
        _ = integrationTest(tc);
    }
}
