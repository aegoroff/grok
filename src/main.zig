const std = @import("std");
const builtin = @import("builtin");
const front = @import("frontend.zig");
const matcher = @import("matcher.zig");
const encoding = @import("encoding.zig");
const configuration = @import("configuration.zig");
const yazap = @import("yazap");

const Action = struct {
    name: []const u8,
    handler: *const fn (std.mem.Allocator, *std.Io.Writer, std.Io, yazap.ArgMatches) void,
};

extern "kernel32" fn SetConsoleOutputCP(wCodePageID: u32) callconv(.winapi) i32;
extern "kernel32" fn SetConsoleCP(wCodePageID: u32) callconv(.winapi) i32;

pub fn main(init: std.process.Init) !void {
    if (builtin.os.tag == .windows) {
        // Windows-specific UTF-8 setup
        _ = SetConsoleOutputCP(65001);
        _ = SetConsoleCP(65001);
    }
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    var stdout = &stdout_writer.interface;
    defer {
        stdout.flush() catch {};
    }

    const gpa = init.arena.allocator();

    const args = try init.minimal.args.toSlice(gpa);
    try run(gpa, stdout, init.io, args[1..]); // skip exe itself
}

fn run(gpa: std.mem.Allocator, writer: *std.Io.Writer, io: std.Io, argv: []const [:0]const u8) !void {
    var config = try configuration.Config.init(gpa, io, argv);
    defer config.deinit();

    const actions = &[_]Action{
        .{ .name = configuration.string_command_name, .handler = &stringAction },
        .{ .name = configuration.file_command_name, .handler = &fileAction },
        .{ .name = configuration.stdin_command_name, .handler = &stdinAction },
        .{ .name = configuration.macro_name, .handler = &macroAction },
    };

    for (actions) |action| {
        if (config.run(action.name, writer, action.handler)) {
            return;
        }
    }
}

fn stringAction(gpa: std.mem.Allocator, writer: *std.Io.Writer, _: std.Io, cmd: yazap.ArgMatches) void {
    if (configuration.getMacroOpt(cmd)) |macro| {
        if (configuration.getStringArgValue(cmd)) |str| {
            matchString(gpa, writer, macro, str, .{
                .info = configuration.isInfoMode(cmd),
                .json = configuration.isJsonMode(cmd),
                .invert_match = configuration.isInvertMatch(cmd),
            }) catch |e| {
                writer.print("Failed string match: {}\n", .{e}) catch |write_err| {
                    std.debug.print("{}\n", .{write_err});
                };
            };
        }
    }
}

fn fileAction(gpa: std.mem.Allocator, writer: *std.Io.Writer, io: std.Io, cmd: yazap.ArgMatches) void {
    if (configuration.getMacroOpt(cmd)) |macro| {
        if (configuration.getPathArgValue(cmd)) |path| {
            matchFile(gpa, writer, io, macro, path, .{
                .info = configuration.isInfoMode(cmd),
                .json = configuration.isJsonMode(cmd),
                .count = configuration.isCountMode(cmd),
                .print_line_num = configuration.printLineNumber(cmd),
                .invert_match = configuration.isInvertMatch(cmd),
            }) catch |e| {
                writer.print("Failed file match: {}\n", .{e}) catch |write_err| {
                    std.debug.print("{}\n", .{write_err});
                };
            };
        }
    }
}

fn stdinAction(gpa: std.mem.Allocator, writer: *std.Io.Writer, io: std.Io, cmd: yazap.ArgMatches) void {
    if (configuration.getMacroOpt(cmd)) |macro| {
        matchStdin(gpa, writer, io, macro, .{
            .info = configuration.isInfoMode(cmd),
            .json = configuration.isJsonMode(cmd),
            .count = configuration.isCountMode(cmd),
            .print_line_num = configuration.printLineNumber(cmd),
            .invert_match = configuration.isInvertMatch(cmd),
        }) catch |e| {
            writer.print("Failed stdin match: {}\n", .{e}) catch |write_err| {
                std.debug.print("{}\n", .{write_err});
            };
        };
    }
}

fn macroAction(gpa: std.mem.Allocator, writer: *std.Io.Writer, _: std.Io, cmd: yazap.ArgMatches) void {
    if (configuration.getMacroArgValue(cmd)) |macro| {
        showMacroRegex(gpa, writer, macro) catch |e| {
            writer.print("Failed show macro: {}\n", .{e}) catch |write_err| {
                std.debug.print("{}\n", .{write_err});
            };
        };
    } else {
        listAllMacroses(gpa, writer) catch |e| {
            writer.print("Failed to list macroses: {}\n", .{e}) catch |write_err| {
                std.debug.print("{}\n", .{write_err});
            };
        };
    }
}

fn matchString(
    gpa: std.mem.Allocator,
    writer: *std.Io.Writer,
    macro: []const u8,
    subject: []const u8,
    flags: matcher.OutputFlags,
) !void {
    var match = try matcher.Matcher.init(gpa, writer, macro);
    defer match.deinit();
    try match.matchString(subject, flags);
}

fn matchFile(
    gpa: std.mem.Allocator,
    writer: *std.Io.Writer,
    io: std.Io,
    macro: []const u8,
    path: []const u8,
    flags: matcher.OutputFlags,
) !void {
    var file = try std.Io.Dir.cwd().openFile(io, path, .{ .mode = .read_only });
    defer file.close(io);
    const stat = try file.stat(io);
    var file_buffer: [64 * 1024]u8 = undefined;
    var file_reader = file.reader(io, &file_buffer);
    const reader = &file_reader.interface;
    var file_encoding: encoding.Encoding = undefined;
    if (stat.size < 2) {
        file_encoding = .utf8;
    } else {
        const min = @min(stat.size, 4); // 4 is max possible BOM size
        const encoding_buffer = try reader.take(min);
        const detection = encoding.detectBomMemory(encoding_buffer);
        try file_reader.seekTo(detection.offset); // skip bom if any or set to begin if no bom detected

        if (detection.encoding == .unknown) {
            file_encoding = .utf8; // set default to utf-8
        } else {
            file_encoding = detection.encoding;
        }
    }

    var match = try matcher.Matcher.init(gpa, writer, macro);
    defer match.deinit();
    try match.matchStrings(reader, flags, file_encoding);
}

fn matchStdin(
    gpa: std.mem.Allocator,
    writer: *std.Io.Writer,
    io: std.Io,
    macro: []const u8,
    flags: matcher.OutputFlags,
) !void {
    var file_buffer: [16384]u8 = undefined;
    var file_reader = std.Io.File.stdin().reader(io, &file_buffer);
    var match = try matcher.Matcher.init(gpa, writer, macro);
    defer match.deinit();
    try match.matchStrings(&file_reader.interface, flags, null);
}

fn showMacroRegex(
    gpa: std.mem.Allocator,
    writer: *std.Io.Writer,
    macro: []const u8,
) !void {
    var match = try matcher.Matcher.init(gpa, writer, macro);
    defer match.deinit();
    try match.showRegex();
}

fn listAllMacroses(
    gpa: std.mem.Allocator,
    writer: *std.Io.Writer,
) !void {
    var it = front.getPatterns().keyIterator();
    var macroses: std.ArrayList([]const u8) = try .initCapacity(gpa, it.len);
    while (it.next()) |item| {
        try macroses.append(gpa, item.*);
    }
    std.mem.sort([]const u8, macroses.items, {}, stringLessThan);
    for (macroses.items) |item| {
        try writer.print("{s}\n", .{item});
    }
}

fn stringLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}

test "integration test match plain string" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "string", "-p", "./patterns/", "-m", "YEAR", "2010" };

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert
    try std.testing.expectEqualStrings("2010\n", writer.written());
}

test "integration test invert match plain string" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "string", "-p", "./patterns/", "-v", "-m", "YEAR", "2010" };

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert
    try std.testing.expectEqualStrings("", writer.written());
}

test "integration test macro view" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "macro", "YEAR", "-p", "./patterns/" };

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert
    try std.testing.expectEqualStrings("(?>\\d\\d){1,2}\n", writer.written());
}

test "integration test macro view complex pattern" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "macro", "NUMBER", "-p", "./patterns/" };

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert
    try std.testing.expectEqualStrings("(?:(?<![0-9.+-])(?>[+-]?(?:(?:[0-9]+(?:\\.[0-9]+)?)|(?:\\.[0-9]+))))\n", writer.written());
}

test "integration test macro view bad (not exist) pattern" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "macro", "BAD", "-p", "./patterns/" };

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert
    try std.testing.expectEqualStrings("Failed show macro: error.UnknownMacro\n", writer.written());
}

test "integration test match file UTF-8 count" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "file", "-p", "./patterns/", "-m", "NLOG", "-c", "./test_assets/logUTF8.log" };

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert
    try std.testing.expectEqualStrings("2\n", writer.written());
}

test "integration test match file UTF-8 invert match - no results" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "file", "-p", "./patterns/", "-m", "NLOG", "-v", "./test_assets/logUTF8.log" };

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert
    try std.testing.expectEqualStrings("", writer.written());
}

test "integration test match file UTF-8 info" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "file", "-p", "./patterns/", "-m", "NLOG", "-i", "./test_assets/logUTF8.log" };

    const expected =
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

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert
    try std.testing.expectEqualStrings(expected, writer.written());
}

test "integration test match file UTF-8 json" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "file", "-p", "./patterns/", "-m", "NLOG", "-j", "./test_assets/logUTF8.log" };

    const expected =
        \\{"line":1,"matched":true,"pattern":"NLOG","text":"2016-08-13 01:46:09,637 INFO logviewer Value cannot be null.","properties":{"Occured":"2016-08-13 01:46:09,637","Level":"INFO"}}
        \\{"line":2,"matched":true,"pattern":"NLOG","text":"2016-08-13 10:21:58,814 INFO logviewer Минимальный уровень должен быть меньше или равен максимальному","properties":{"Occured":"2016-08-13 10:21:58,814","Level":"INFO"}}
        \\
    ;

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert
    try std.testing.expectEqualStrings(expected, writer.written());
}

test "integration test match file UTF-16LE count" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "file", "-p", "./patterns/", "-m", "NLOG", "-c", "./test_assets/logUTF16LE.log" };

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert
    try std.testing.expectEqualStrings("2\n", writer.written());
}

test "integration test match file UTF-16LE" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "file", "-p", "./patterns/", "-m", "NLOG", "./test_assets/logUTF16LE.log" };

    const expected =
        \\2016-08-13 01:46:09,637 INFO logviewer Value cannot be null.
        \\2016-08-13 10:21:58,814 INFO logviewer Минимальный уровень должен быть меньше или равен максимальному
        \\
    ;

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert
    try std.testing.expectEqualStrings(expected, writer.written());
}

test "integration test match file UTF-16BE count" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "file", "-p", "./patterns/", "-m", "NLOG", "-c", "./test_assets/logUTF16BE.log" };

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert
    try std.testing.expectEqualStrings("2\n", writer.written());
}

test "integration test match file UTF-16BE" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "file", "-p", "./patterns/", "-m", "NLOG", "./test_assets/logUTF16BE.log" };

    const expected =
        \\2016-08-13 01:46:09,637 INFO logviewer Value cannot be null.
        \\2016-08-13 10:21:58,814 INFO logviewer Минимальный уровень должен быть меньше или равен максимальному
        \\
    ;

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert
    try std.testing.expectEqualStrings(expected, writer.written());
}

test "integration test match empty file UTF-16BE" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "file", "-p", "./patterns/", "-m", "DATA", "./test_assets/emptyUTF16BE.log" };

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert
    try std.testing.expectEqualStrings("", writer.written());
}

test "integration test match file UTF-32LE count" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "file", "-p", "./patterns/", "-m", "NLOG", "-c", "./test_assets/logUTF32LE.log" };

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert
    try std.testing.expectEqualStrings("2\n", writer.written());
}

test "integration test match file UTF-32LE" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "file", "-p", "./patterns/", "-m", "NLOG", "./test_assets/logUTF32LE.log" };

    const expected =
        \\2016-08-13 01:46:09,637 INFO logviewer Value cannot be null.
        \\2016-08-13 10:21:58,814 INFO logviewer Минимальный уровень должен быть меньше или равен максимальному
        \\
    ;

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert
    try std.testing.expectEqualStrings(expected, writer.written());
}

test "integration test match file UTF-32BE count" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "file", "-p", "./patterns/", "-m", "NLOG", "-c", "./test_assets/logUTF32BE.log" };

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert
    try std.testing.expectEqualStrings("2\n", writer.written());
}

test "integration test match file UTF-32BE" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "file", "-p", "./patterns/", "-m", "NLOG", "./test_assets/logUTF32BE.log" };

    const expected =
        \\2016-08-13 01:46:09,637 INFO logviewer Value cannot be null.
        \\2016-08-13 10:21:58,814 INFO logviewer Минимальный уровень должен быть меньше или равен максимальному
        \\
    ;

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert
    try std.testing.expectEqualStrings(expected, writer.written());
}

test "integration test match empty file UTF-32BE" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "file", "-p", "./patterns/", "-m", "DATA", "./test_assets/emptyUTF32BE.log" };

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert
    try std.testing.expectEqualStrings("", writer.written());
}

test "integration test list all macros" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "macro", "-p", "./patterns/" };

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert - should list at least NLOG, NGINXPROXYACCESS, NGINXPROXYDEFAULTACCESS
    const output = writer.written();
    try std.testing.expect(std.mem.indexOf(u8, output, "NLOG") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "NGINXPROXYACCESS") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "NGINXPROXYDEFAULTACCESS") != null);
}

test "integration test match string with NUMBER pattern" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "string", "-p", "./patterns/", "-m", "NUMBER", "12345" };

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert
    try std.testing.expectEqualStrings("12345\n", writer.written());
}

test "integration test match string with NUMBER pattern no match" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "string", "-p", "./patterns/", "-m", "NUMBER", "abc" };

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert
    try std.testing.expectEqualStrings("", writer.written());
}

test "integration test match string with IP pattern" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "string", "-p", "./patterns/", "-m", "IP", "192.168.1.1" };

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert
    try std.testing.expectEqualStrings("192.168.1.1\n", writer.written());
}

test "integration test match string with IP pattern invalid" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "string", "-p", "./patterns/", "-m", "IP", "999.999.999.999" };

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert
    try std.testing.expectEqualStrings("", writer.written());
}

test "integration test match string with TIMESTAMP_ISO8601 pattern" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "string", "-p", "./patterns/", "-m", "TIMESTAMP_ISO8601", "2016-08-13 01:46:09,637" };

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert
    try std.testing.expectEqualStrings("2016-08-13 01:46:09,637\n", writer.written());
}

test "integration test match string with LOGLEVEL pattern" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "string", "-p", "./patterns/", "-m", "LOGLEVEL", "INFO" };

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert
    try std.testing.expectEqualStrings("INFO\n", writer.written());
}

test "integration test match string with LOGLEVEL pattern debug" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "string", "-p", "./patterns/", "-m", "LOGLEVEL", "DEBUG" };

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert
    try std.testing.expectEqualStrings("DEBUG\n", writer.written());
}

test "integration test match file UTF-8 without flags" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "file", "-p", "./patterns/", "-m", "NLOG", "./test_assets/logUTF8.log" };

    const expected =
        \\2016-08-13 01:46:09,637 INFO logviewer Value cannot be null.
        \\2016-08-13 10:21:58,814 INFO logviewer Минимальный уровень должен быть меньше или равен максимальному
        \\
    ;

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert
    try std.testing.expectEqualStrings(expected, writer.written());
}

test "integration test match file with line numbers" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "file", "-p", "./patterns/", "-m", "NLOG", "-n", "./test_assets/logUTF8.log" };

    const expected =
        \\1: 2016-08-13 01:46:09,637 INFO logviewer Value cannot be null.
        \\2: 2016-08-13 10:21:58,814 INFO logviewer Минимальный уровень должен быть меньше или равен максимальному
        \\
    ;

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert
    try std.testing.expectEqualStrings(expected, writer.written());
}

test "integration test match file UTF-16LE with line numbers" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "file", "-p", "./patterns/", "-m", "NLOG", "-n", "./test_assets/logUTF16LE.log" };

    const expected =
        \\1: 2016-08-13 01:46:09,637 INFO logviewer Value cannot be null.
        \\2: 2016-08-13 10:21:58,814 INFO logviewer Минимальный уровень должен быть меньше или равен максимальному
        \\
    ;

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert
    try std.testing.expectEqualStrings(expected, writer.written());
}

test "integration test macro view for NLOG pattern" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "macro", "NLOG", "-p", "./patterns/" };

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert - check it produces some valid regex output with named groups
    const output = writer.written();
    try std.testing.expect(std.mem.indexOf(u8, output, "Occured") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Level") != null);
}

test "integration test macro view for NGINXPROXYACCESS pattern" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "macro", "NGINXPROXYACCESS", "-p", "./patterns/" };

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert - just check it doesn't error and produces some output
    try std.testing.expect(writer.written().len > 0);
}

test "integration test match file no match" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "file", "-p", "./patterns/", "-m", "NGINXPROXYACCESS", "./test_assets/logUTF8.log" };

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert - no matches expected for nginx pattern in log file
    try std.testing.expectEqualStrings("", writer.written());
}

test "integration test match file count no matches" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "file", "-p", "./patterns/", "-m", "NGINXPROXYACCESS", "-c", "./test_assets/logUTF8.log" };

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert - count should be 0
    try std.testing.expectEqualStrings("0\n", writer.written());
}

test "integration test match string invert with NUMBER pattern" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "string", "-p", "./patterns/", "-m", "NUMBER", "-v", "abc" };

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert - invert match on non-matching string should output the string
    try std.testing.expectEqualStrings("abc\n", writer.written());
}

test "integration test match file UTF-32LE with line numbers" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "file", "-p", "./patterns/", "-m", "NLOG", "-n", "./test_assets/logUTF32LE.log" };

    const expected =
        \\1: 2016-08-13 01:46:09,637 INFO logviewer Value cannot be null.
        \\2: 2016-08-13 10:21:58,814 INFO logviewer Минимальный уровень должен быть меньше или равен максимальному
        \\
    ;

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert
    try std.testing.expectEqualStrings(expected, writer.written());
}

test "integration test match file UTF-32BE with line numbers" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "file", "-p", "./patterns/", "-m", "NLOG", "-n", "./test_assets/logUTF32BE.log" };

    const expected =
        \\1: 2016-08-13 01:46:09,637 INFO logviewer Value cannot be null.
        \\2: 2016-08-13 10:21:58,814 INFO logviewer Минимальный уровень должен быть меньше или равен максимальному
        \\
    ;

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert
    try std.testing.expectEqualStrings(expected, writer.written());
}

test "integration test match file UTF-16BE with line numbers" {
    // Arrange
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    const argv: []const [:0]const u8 = &[_][:0]const u8{ "file", "-p", "./patterns/", "-m", "NLOG", "-n", "./test_assets/logUTF16BE.log" };

    const expected =
        \\1: 2016-08-13 01:46:09,637 INFO logviewer Value cannot be null.
        \\2: 2016-08-13 10:21:58,814 INFO logviewer Минимальный уровень должен быть меньше или равен максимальному
        \\
    ;

    // Act
    try run(arena.allocator(), &writer.writer, std.testing.io, argv);

    // Assert
    try std.testing.expectEqualStrings(expected, writer.written());
}

test {
    @import("std").testing.refAllDecls(@This());
}
