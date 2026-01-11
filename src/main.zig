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

    var gpa = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer gpa.deinit();

    const argv = try std.process.argsAlloc(gpa.allocator());
    var config = try configuration.Config.init(gpa.allocator(), argv[1..]);
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

fn stringAction(gpa: std.mem.Allocator, cmd: yazap.ArgMatches) void {
    if (configuration.getMacroOpt(cmd)) |macro| {
        if (configuration.getStringArgValue(cmd)) |str| {
            matchString(gpa, macro, str, .{
                .info = configuration.isInfoMode(cmd),
            }) catch |e| {
                std.debug.print("Failed string match: {}\n", .{e});
            };
        }
    }
}

fn fileAction(gpa: std.mem.Allocator, cmd: yazap.ArgMatches) void {
    if (configuration.getMacroOpt(cmd)) |macro| {
        if (configuration.getPathArgValue(cmd)) |path| {
            matchFile(gpa, macro, path, .{
                .info = configuration.isInfoMode(cmd),
                .count = configuration.isCountMode(cmd),
                .print_line_num = configuration.printLineNumber(cmd),
            }) catch |e| {
                std.debug.print("Failed file match: {}\n", .{e});
            };
        }
    }
}

fn stdinAction(gpa: std.mem.Allocator, cmd: yazap.ArgMatches) void {
    if (configuration.getMacroOpt(cmd)) |macro| {
        matchStdin(gpa, macro, .{
            .info = configuration.isInfoMode(cmd),
            .count = configuration.isCountMode(cmd),
            .print_line_num = configuration.printLineNumber(cmd),
        }) catch |e| {
            std.debug.print("Failed stdin match: {}\n", .{e});
        };
    }
}

fn macroAction(gpa: std.mem.Allocator, cmd: yazap.ArgMatches) void {
    if (configuration.getMacroArgValue(cmd)) |macro| {
        showMacroRegex(gpa, macro) catch |e| {
            std.debug.print("Failed show macro: {}\n", .{e});
        };
    } else {
        listAllMacroses(gpa) catch |e| {
            std.debug.print("Failed to list macroses: {}\n", .{e});
        };
    }
}

fn matchString(gpa: std.mem.Allocator, macro: []const u8, subject: []const u8, flags: matcher.OutputFlags) !void {
    var match = try matcher.Matcher.init(gpa, stdout, macro);
    try match.matchString(subject, flags);
}

fn matchFile(gpa: std.mem.Allocator, macro: []const u8, path: []const u8, flags: matcher.OutputFlags) !void {
    var file = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });
    defer file.close();
    const stat = try file.stat();
    var file_buffer: [16384]u8 = undefined;
    var file_reader = file.reader(&file_buffer);
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

    var match = try matcher.Matcher.init(gpa, stdout, macro);
    try match.matchStrings(reader, flags, file_encoding);
}

fn matchStdin(gpa: std.mem.Allocator, macro: []const u8, flags: matcher.OutputFlags) !void {
    var file_buffer: [16384]u8 = undefined;
    var file_reader = std.fs.File.stdin().reader(&file_buffer);
    var match = try matcher.Matcher.init(gpa, stdout, macro);
    try match.matchStrings(&file_reader.interface, flags, null);
}

fn showMacroRegex(gpa: std.mem.Allocator, macro: []const u8) !void {
    const match = try matcher.Matcher.init(gpa, stdout, macro);
    try match.showRegex();
}

fn listAllMacroses(gpa: std.mem.Allocator) !void {
    var it = front.getPatterns().keyIterator();
    var macroses: std.ArrayList([]const u8) = try .initCapacity(gpa, it.len);
    while (it.next()) |item| {
        try macroses.append(gpa, item.*);
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
