const std = @import("std");
const grok = @import("grok.zig");
const main = @import("main.zig");

const nlog_matches =
    \\2016-08-13 01:46:09,637 INFO logviewer Value cannot be null.
    \\2016-08-13 10:21:58,814 INFO logviewer Минимальный уровень должен быть меньше или равен максимальному
    \\
;

const nlog_line_numbers =
    \\1: 2016-08-13 01:46:09,637 INFO logviewer Value cannot be null.
    \\2: 2016-08-13 10:21:58,814 INFO logviewer Минимальный уровень должен быть меньше или равен максимальному
    \\
;

const nlog_info =
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

const nlog_json =
    \\{"line":1,"matched":true,"pattern":"NLOG","text":"2016-08-13 01:46:09,637 INFO logviewer Value cannot be null.","properties":{"Occured":"2016-08-13 01:46:09,637","Level":"INFO"}}
    \\{"line":2,"matched":true,"pattern":"NLOG","text":"2016-08-13 10:21:58,814 INFO logviewer Минимальный уровень должен быть меньше или равен максимальному","properties":{"Occured":"2016-08-13 10:21:58,814","Level":"INFO"}}
    \\
;

const patterns = "./patterns/";
const nlog_file_utf8 = "./test_assets/logUTF8.log";
const nlog_file_utf16le = "./test_assets/logUTF16LE.log";
const nlog_file_utf16be = "./test_assets/logUTF16BE.log";
const nlog_file_utf32le = "./test_assets/logUTF32LE.log";
const nlog_file_utf32be = "./test_assets/logUTF32BE.log";

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

const cases = [_]Case{
    .{
        .name = "match plain string",
        .argv = &.{ "string", "-p", patterns, "-m", "YEAR", "2010" },
        .expected = .{ .success = "2010\n" },
    },
    .{
        .name = "invert match plain string",
        .argv = &.{ "string", "-p", patterns, "-v", "-m", "YEAR", "2010" },
        .expected = .{ .success = "" },
    },
    .{
        .name = "macro view",
        .argv = &.{ "macro", "YEAR", "-p", patterns },
        .expected = .{ .success = "(?>\\d\\d){1,2}\n" },
    },
    .{
        .name = "macro view complex pattern",
        .argv = &.{ "macro", "NUMBER", "-p", patterns },
        .expected = .{ .success = "(?:(?<![0-9.+-])(?>[+-]?(?:(?:[0-9]+(?:\\.[0-9]+)?)|(?:\\.[0-9]+))))\n" },
    },
    .{
        .name = "macro view bad (not exist) pattern",
        .argv = &.{ "macro", "BAD", "-p", patterns },
        .expected = .{
            .failure = .{
                .err = grok.GrokError.UnknownMacro,
                .output = "Failed show macro: error.UnknownMacro\n",
            },
        },
    },
    .{
        .name = "macro with unknown nested reference",
        .argv = &.{ "macro", "BADNESTED", "-p", "./test_assets/bad_nested.patterns" },
        .expected = .{
            .failure = .{
                .err = grok.GrokError.UnknownMacro,
                .output = "Failed show macro: error.UnknownMacro\n",
            },
        },
    },
    .{
        .name = "match file UTF-8 without flags",
        .argv = &.{ "file", "-p", patterns, "-m", "NLOG", nlog_file_utf8 },
        .expected = .{ .success = nlog_matches },
    },
    .{
        .name = "match file UTF-8 no match",
        .argv = &.{ "file", "-p", patterns, "-m", "NGINXPROXYACCESS", nlog_file_utf8 },
        .expected = .{ .success = "" },
    },
    .{
        .name = "match file UTF-8 count",
        .argv = &.{ "file", "-p", patterns, "-m", "NLOG", "-c", nlog_file_utf8 },
        .expected = .{ .success = "2\n" },
    },
    .{
        .name = "match file UTF-8 count no matches",
        .argv = &.{ "file", "-p", patterns, "-m", "NGINXPROXYACCESS", "-c", nlog_file_utf8 },
        .expected = .{ .success = "0\n" },
    },
    .{
        .name = "match file UTF-8 invert match - no results",
        .argv = &.{ "file", "-p", patterns, "-m", "NLOG", "-v", nlog_file_utf8 },
        .expected = .{ .success = "" },
    },
    .{
        .name = "match file UTF-8 info",
        .argv = &.{ "file", "-p", patterns, "-m", "NLOG", "-i", nlog_file_utf8 },
        .expected = .{ .success = nlog_info },
    },
    .{
        .name = "match file UTF-8 json",
        .argv = &.{ "file", "-p", patterns, "-m", "NLOG", "-j", nlog_file_utf8 },
        .expected = .{ .success = nlog_json },
    },
    .{
        .name = "match file UTF-16LE count",
        .argv = &.{ "file", "-p", patterns, "-m", "NLOG", "-c", nlog_file_utf16le },
        .expected = .{ .success = "2\n" },
    },
    .{
        .name = "match file UTF-16LE",
        .argv = &.{ "file", "-p", patterns, "-m", "NLOG", nlog_file_utf16le },
        .expected = .{ .success = nlog_matches },
    },
    .{
        .name = "match file UTF-16BE count",
        .argv = &.{ "file", "-p", patterns, "-m", "NLOG", "-c", nlog_file_utf16be },
        .expected = .{ .success = "2\n" },
    },
    .{
        .name = "match file UTF-16BE",
        .argv = &.{ "file", "-p", patterns, "-m", "NLOG", nlog_file_utf16be },
        .expected = .{ .success = nlog_matches },
    },
    .{
        .name = "match empty file UTF-16BE",
        .argv = &.{ "file", "-p", patterns, "-m", "DATA", "./test_assets/emptyUTF16BE.log" },
        .expected = .{ .success = "" },
    },
    .{
        .name = "match file UTF-32LE count",
        .argv = &.{ "file", "-p", patterns, "-m", "NLOG", "-c", nlog_file_utf32le },
        .expected = .{ .success = "2\n" },
    },
    .{
        .name = "match file UTF-32LE",
        .argv = &.{ "file", "-p", patterns, "-m", "NLOG", nlog_file_utf32le },
        .expected = .{ .success = nlog_matches },
    },
    .{
        .name = "match invalid file UTF-32LE",
        .argv = &.{ "file", "-p", patterns, "-m", "NLOG", "./test_assets/invalidUTF32LE.log" },
        .expected = .{
            .failure = .{
                .err = grok.GrokError.InvalidUtf32LineLength,
                .output = "Failed file match: error.InvalidUtf32LineLength\n",
            },
        },
    },
    .{
        .name = "match file UTF-32BE count",
        .argv = &.{ "file", "-p", patterns, "-m", "NLOG", "-c", nlog_file_utf32be },
        .expected = .{ .success = "2\n" },
    },
    .{
        .name = "match file UTF-32BE",
        .argv = &.{ "file", "-p", patterns, "-m", "NLOG", nlog_file_utf32be },
        .expected = .{ .success = nlog_matches },
    },
    .{
        .name = "match empty file UTF-32BE",
        .argv = &.{ "file", "-p", patterns, "-m", "DATA", "./test_assets/emptyUTF32BE.log" },
        .expected = .{ .success = "" },
    },
    .{
        .name = "match invalid file UTF-32BE",
        .argv = &.{ "file", "-p", patterns, "-m", "NLOG", "./test_assets/invalidUTF32BE.log" },
        .expected = .{ .success = "" },
    },
    .{
        .name = "list all macros",
        .argv = &.{ "macro", "-p", patterns },
        .expected = .{ .contains = &.{ "NLOG", "NGINXPROXYACCESS", "NGINXPROXYDEFAULTACCESS" } },
    },
    .{
        .name = "match string with NUMBER pattern",
        .argv = &.{ "string", "-p", patterns, "-m", "NUMBER", "12345" },
        .expected = .{ .success = "12345\n" },
    },
    .{
        .name = "match string with NUMBER pattern no match",
        .argv = &.{ "string", "-p", patterns, "-m", "NUMBER", "abc" },
        .expected = .{ .success = "" },
    },
    .{
        .name = "match string invert with NUMBER pattern",
        .argv = &.{ "string", "-p", patterns, "-m", "NUMBER", "-v", "abc" },
        .expected = .{ .success = "abc\n" },
    },
    .{
        .name = "match string with IP pattern",
        .argv = &.{ "string", "-p", patterns, "-m", "IP", "192.168.1.1" },
        .expected = .{ .success = "192.168.1.1\n" },
    },
    .{
        .name = "match string with IP pattern invalid",
        .argv = &.{ "string", "-p", patterns, "-m", "IP", "999.999.999.999" },
        .expected = .{ .success = "" },
    },
    .{
        .name = "match string with TIMESTAMP_ISO8601 pattern",
        .argv = &.{ "string", "-p", patterns, "-m", "TIMESTAMP_ISO8601", "2016-08-13 01:46:09,637" },
        .expected = .{ .success = "2016-08-13 01:46:09,637\n" },
    },
    .{
        .name = "match file UTF-8 with line numbers",
        .argv = &.{ "file", "-p", patterns, "-m", "NLOG", "-n", nlog_file_utf8 },
        .expected = .{ .success = nlog_line_numbers },
    },
    .{
        .name = "match file UTF-16LE with line numbers",
        .argv = &.{ "file", "-p", patterns, "-m", "NLOG", "-n", nlog_file_utf16le },
        .expected = .{ .success = nlog_line_numbers },
    },
    .{
        .name = "match file UTF-32LE with line numbers",
        .argv = &.{ "file", "-p", patterns, "-m", "NLOG", "-n", nlog_file_utf32le },
        .expected = .{ .success = nlog_line_numbers },
    },
    .{
        .name = "match file UTF-32BE with line numbers",
        .argv = &.{ "file", "-p", patterns, "-m", "NLOG", "-n", nlog_file_utf32be },
        .expected = .{ .success = nlog_line_numbers },
    },
    .{
        .name = "match file UTF-16BE with line numbers",
        .argv = &.{ "file", "-p", patterns, "-m", "NLOG", "-n", nlog_file_utf16be },
        .expected = .{ .success = nlog_line_numbers },
    },
    .{
        .name = "match file UTF-16LE crash",
        .argv = &.{ "file", "-p", patterns, "-m", "NLOG", "./test_assets/crash.log" },
        .expected = .{ .success = "" },
    },
    .{
        .name = "match file UTF-16BE crash1",
        .argv = &.{ "file", "-p", patterns, "-m", "NLOG", "./test_assets/crash1.log" },
        .expected = .{
            .failure = .{
                .output = "Failed file match: error.UnexpectedSecondSurrogateHalf\n",
            },
        },
    },
    .{
        .name = "match file UTF-16BE crash2",
        .argv = &.{ "file", "-p", patterns, "-m", "NLOG", "./test_assets/crash2.log" },
        .expected = .{
            .failure = .{
                .err = grok.GrokError.InvalidUtf16LineLength,
                .output = "Failed file match: error.InvalidUtf16LineLength\n",
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
    for (cases) |tc| {
        _ = integrationTest(tc);
    }
}
