const std = @import("std");
const builtin = @import("builtin");
const front = @import("frontend.zig");
const matcher = @import("matcher.zig");
const line_reader = @import("line_reader.zig");
const configuration = @import("configuration.zig");
const yazap = @import("yazap");

const Action = struct {
    name: []const u8,
    handler: *const fn (std.mem.Allocator, *std.Io.Writer, std.Io, yazap.ArgMatches) anyerror!void,
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
    run(gpa, stdout, init.io, args[1..]) catch { // skip exe itself
        std.process.exit(1);
    };
}

pub fn run(gpa: std.mem.Allocator, writer: *std.Io.Writer, io: std.Io, argv: []const [:0]const u8) !void {
    var config = try configuration.Config.init(gpa, io, argv);
    defer config.deinit();

    const actions = &[_]Action{
        .{ .name = configuration.string_command_name, .handler = &stringAction },
        .{ .name = configuration.file_command_name, .handler = &fileAction },
        .{ .name = configuration.stdin_command_name, .handler = &stdinAction },
        .{ .name = configuration.macro_name, .handler = &macroAction },
    };

    for (actions) |action| {
        if (try config.run(action.name, writer, action.handler)) {
            return;
        }
    }
}

fn stringAction(gpa: std.mem.Allocator, writer: *std.Io.Writer, _: std.Io, cmd: yazap.ArgMatches) !void {
    const macro = configuration.getMacroOpt(cmd) orelse return;
    const str = configuration.getStringArgValue(cmd) orelse return;
    matchString(gpa, writer, macro, str, .{
        .info = configuration.isInfoMode(cmd),
        .json = configuration.isJsonMode(cmd),
        .invert_match = configuration.isInvertMatch(cmd),
    }) catch |e| {
        try writer.print("Failed string match: {}\n", .{e});
        return e;
    };
}

fn fileAction(gpa: std.mem.Allocator, writer: *std.Io.Writer, io: std.Io, cmd: yazap.ArgMatches) !void {
    const macro = configuration.getMacroOpt(cmd) orelse return;
    const path = configuration.getPathArgValue(cmd) orelse return;
    matchFile(gpa, writer, io, macro, path, .{
        .info = configuration.isInfoMode(cmd),
        .json = configuration.isJsonMode(cmd),
        .count = configuration.isCountMode(cmd),
        .print_line_num = configuration.printLineNumber(cmd),
        .invert_match = configuration.isInvertMatch(cmd),
    }) catch |e| {
        try writer.print("Failed file match: {}\n", .{e});
        return e;
    };
}

fn stdinAction(gpa: std.mem.Allocator, writer: *std.Io.Writer, io: std.Io, cmd: yazap.ArgMatches) !void {
    const macro = configuration.getMacroOpt(cmd) orelse return;
    matchStdin(gpa, writer, io, macro, .{
        .info = configuration.isInfoMode(cmd),
        .json = configuration.isJsonMode(cmd),
        .count = configuration.isCountMode(cmd),
        .print_line_num = configuration.printLineNumber(cmd),
        .invert_match = configuration.isInvertMatch(cmd),
    }) catch |e| {
        try writer.print("Failed stdin match: {}\n", .{e});
        return e;
    };
}

fn macroAction(gpa: std.mem.Allocator, writer: *std.Io.Writer, _: std.Io, cmd: yazap.ArgMatches) !void {
    if (configuration.getMacroArgValue(cmd)) |macro| {
        showMacroRegex(gpa, writer, macro) catch |e| {
            try writer.print("Failed show macro: {}\n", .{e});
            return e;
        };
    } else {
        listAllMacroses(gpa, writer) catch |e| {
            try writer.print("Failed to list macroses: {}\n", .{e});
            return e;
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
    const detection = try line_reader.probeFileEncoding(reader, stat.size);
    try file_reader.seekTo(detection.offset);
    const file_encoding = line_reader.encodingFromDetection(detection);

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

test {
    _ = @import("integration_test.zig");
}
