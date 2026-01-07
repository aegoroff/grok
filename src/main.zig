const std = @import("std");
const builtin = @import("builtin");
const front = @import("frontend.zig");
const matcher = @import("matcher.zig");
const encoding = @import("encoding.zig");
const configuration = @import("configuration.zig");
const yazap = @import("yazap");

var stdout: *std.Io.Writer = undefined;

const Action = struct {
    name: []const u8,
    handler: *const fn (std.mem.Allocator, yazap.ArgMatches) void,
};

pub fn main() !void {
    if (builtin.os.tag == .windows) {
        // Windows-specific UTF-8 setup
        const kernel32 = std.os.windows.kernel32;
        _ = kernel32.SetConsoleOutputCP(65001);
    }
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    stdout = &stdout_writer.interface;
    defer {
        stdout.flush() catch {};
    }

    const allocator = std.heap.c_allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const argv = try std.process.argsAlloc(arena.allocator());
    var config = try configuration.Config.init(arena.allocator(), argv[1..]);
    defer config.deinit();

    const actions = &[_]Action{
        .{ .name = configuration.string_command_name, .handler = &stringAction },
        .{ .name = configuration.file_command_name, .handler = &fileAction },
        .{ .name = configuration.stdin_command_name, .handler = &stdinAction },
        .{ .name = configuration.macro_name, .handler = &macroAction },
    };

    for (actions) |action| {
        if (config.run(action.name, action.handler)) {
            return;
        }
    }
}

fn stringAction(allocator: std.mem.Allocator, cmd_matches: yazap.ArgMatches) void {
    if (configuration.getMacro(cmd_matches)) |macro| {
        if (cmd_matches.getSingleValue("STRING")) |str| {
            matchString(allocator, macro, str, .{
                .info = configuration.isInfoMode(cmd_matches),
            }) catch |e| {
                std.debug.print("Failed string match: {}\n", .{e});
            };
        }
    }
}

fn fileAction(allocator: std.mem.Allocator, cmd_matches: yazap.ArgMatches) void {
    if (configuration.getMacro(cmd_matches)) |macro| {
        if (cmd_matches.getSingleValue("PATH")) |path| {
            matchFile(allocator, macro, path, .{
                .info = configuration.isInfoMode(cmd_matches),
                .count = configuration.isCountMode(cmd_matches),
                .print_line_num = configuration.printLineNumber(cmd_matches),
            }) catch |e| {
                std.debug.print("Failed file match: {}\n", .{e});
            };
        }
    }
}

fn stdinAction(allocator: std.mem.Allocator, cmd_matches: yazap.ArgMatches) void {
    if (configuration.getMacro(cmd_matches)) |macro| {
        matchStdin(allocator, macro, .{
            .info = configuration.isInfoMode(cmd_matches),
            .count = configuration.isCountMode(cmd_matches),
            .print_line_num = configuration.printLineNumber(cmd_matches),
        }) catch |e| {
            std.debug.print("Failed stdin match: {}\n", .{e});
        };
    }
}

fn macroAction(allocator: std.mem.Allocator, cmd_matches: yazap.ArgMatches) void {
    if (cmd_matches.getSingleValue("MACRO")) |macro| {
        showMacroRegex(allocator, macro) catch |e| {
            std.debug.print("Failed show macro: {}\n", .{e});
        };
    } else {
        listAllMacroses(allocator) catch |e| {
            std.debug.print("Failed to list macroses: {}\n", .{e});
        };
    }
}

fn matchString(allocator: std.mem.Allocator, macro: []const u8, subject: []const u8, flags: matcher.OutputFlags) !void {
    var match = try matcher.Matcher.init(allocator, stdout, macro);
    try match.matchString(subject, flags);
}

fn matchFile(allocator: std.mem.Allocator, macro: []const u8, path: []const u8, flags: matcher.OutputFlags) !void {
    var file = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });
    defer file.close();
    var file_buffer: [16384]u8 = undefined;
    var file_reader = file.reader(&file_buffer);
    const reader = &file_reader.interface;
    const encoding_buffer = try reader.take(4);
    const detection = encoding.detectBomMemory(encoding_buffer);
    try file_reader.seekTo(detection.offset); // skip bom if any
    var file_encoding: encoding.Encoding = undefined;
    if (detection.encoding == .unknown) {
        file_encoding = .utf8; // set default to utf-8
    } else {
        file_encoding = detection.encoding;
    }
    var match = try matcher.Matcher.init(allocator, stdout, macro);
    try match.matchStrings(reader, flags, file_encoding);
}

fn matchStdin(allocator: std.mem.Allocator, macro: []const u8, flags: matcher.OutputFlags) !void {
    var file_buffer: [16384]u8 = undefined;
    var file_reader = std.fs.File.stdin().reader(&file_buffer);
    var match = try matcher.Matcher.init(allocator, stdout, macro);
    try match.matchStrings(&file_reader.interface, flags, null);
}

fn showMacroRegex(allocator: std.mem.Allocator, macro: []const u8) !void {
    const match = try matcher.Matcher.init(allocator, stdout, macro);
    try match.showRegex();
}

fn listAllMacroses(allocator: std.mem.Allocator) !void {
    var it = front.getPatterns().keyIterator();
    var macroses = std.ArrayList([]const u8){};
    while (it.next()) |item| {
        try macroses.append(allocator, item.*);
    }
    std.mem.sort([]const u8, macroses.items, {}, stringLessThan);
    for (macroses.items) |item| {
        try stdout.print("{s}\n", .{item});
    }
}

fn stringLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}

test {
    @import("std").testing.refAllDecls(@This());
}
