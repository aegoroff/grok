const std = @import("std");
const builtin = @import("builtin");
const front = @import("frontend.zig");
const back = @import("backend.zig");
const encoding = @import("encoding.zig");
const config = @import("configuration.zig");
const yazap = @import("yazap");

var stdout: *std.Io.Writer = undefined;

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

    var grok = try config.Grok.init(arena.allocator());
    defer grok.deinit();
    if (grok.run(config.string_command_name, stringAction)) {
        return;
    }
    if (grok.run(config.file_command_name, fileAction)) {
        return;
    }
    if (grok.run(config.stdin_command_name, stdinAction)) {
        return;
    }
    _ = grok.run(config.macro_name, macroAction);
}

fn stringAction(allocator: std.mem.Allocator, cmd_matches: yazap.ArgMatches) void {
    if (config.getMacro(cmd_matches)) |macro| {
        if (cmd_matches.getSingleValue("STRING")) |str| {
            const info_mode = config.isInfoMode(cmd_matches);
            onString(allocator, macro, str, info_mode) catch |e| {
                std.debug.print("Failed string match: {}\n", .{e});
            };
        }
    }
}

fn fileAction(allocator: std.mem.Allocator, cmd_matches: yazap.ArgMatches) void {
    if (config.getMacro(cmd_matches)) |macro| {
        if (cmd_matches.getSingleValue("PATH")) |path| {
            const info_mode = config.isInfoMode(cmd_matches);
            onFile(allocator, macro, path, info_mode) catch |e| {
                std.debug.print("Failed file match: {}\n", .{e});
            };
        }
    }
}

fn stdinAction(allocator: std.mem.Allocator, cmd_matches: yazap.ArgMatches) void {
    if (config.getMacro(cmd_matches)) |macro| {
        const info_mode = config.isInfoMode(cmd_matches);
        onStdin(allocator, macro, info_mode) catch |e| {
            std.debug.print("Failed stdin match: {}\n", .{e});
        };
    }
}

fn macroAction(allocator: std.mem.Allocator, cmd_matches: yazap.ArgMatches) void {
    if (cmd_matches.getSingleValue("MACRO")) |macro| {
        onTemplate(allocator, macro) catch |e| {
            std.debug.print("Failed macro match: {}\n", .{e});
        };
    } else {
        onTemplates(allocator) catch |e| {
            std.debug.print("Failed to list macro: {}\n", .{e});
        };
    }
}

fn onString(
    allocator: std.mem.Allocator,
    macro: []const u8,
    subject: []const u8,
    info_mode: bool,
) !void {
    back.init(allocator);
    const pattern = try back.createPattern(allocator, macro);
    const prepared = try back.prepareRegex(pattern);
    const matched = back.matchRegex(allocator, &pattern, subject, &prepared);
    if (info_mode) {
        if (matched.matched) {
            try stdout.print("Match found\n", .{});
            if (matched.properties) |properties| {
                var it = properties.iterator();
                while (it.next()) |entry| {
                    const key = entry.key_ptr.*;
                    const val = entry.value_ptr.*;
                    try stdout.print("\t{s}: {s}\n", .{ key, val });
                }
            }
        } else {
            try stdout.print("No match found\n", .{});
        }
    } else if (matched.matched) {
        try stdout.print("{s}\n", .{subject});
    }
}

fn onFile(
    allocator: std.mem.Allocator,
    macro: []const u8,
    path: []const u8,
    info_mode: bool,
) !void {
    var file = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });
    defer file.close();
    var file_buffer: [16384]u8 = undefined;
    var file_reader = file.reader(&file_buffer);
    const reader = &file_reader.interface;
    const encoding_buffer = try reader.take(4);
    const detection = encoding.detectBomMemory(encoding_buffer);
    try file_reader.seekTo(detection.offset);
    var file_encoding: encoding.Encoding = undefined;
    if (detection.encoding == .unknown) {
        file_encoding = .utf8; // set default to utf-8
    } else {
        file_encoding = detection.encoding;
    }
    return readFromReader(allocator, macro, reader, info_mode, file_encoding);
}

fn onStdin(
    allocator: std.mem.Allocator,
    macro: []const u8,
    info_mode: bool,
) !void {
    var file_buffer: [16384]u8 = undefined;
    var file_reader = std.fs.File.stdin().reader(&file_buffer);
    const reader = &file_reader.interface;
    return readFromReader(allocator, macro, reader, info_mode, null);
}

fn onTemplate(allocator: std.mem.Allocator, macro: []const u8) !void {
    const pattern = try back.createPattern(allocator, macro);
    return stdout.print("{s}\n", .{pattern.regex});
}

fn onTemplates(allocator: std.mem.Allocator) !void {
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

fn readFromReader(
    allocator: std.mem.Allocator,
    macro: []const u8,
    reader: *std.Io.Reader,
    info_mode: bool,
    file_encoding: ?encoding.Encoding, // null means reading from stdin
) !void {
    back.init(allocator);
    const pattern = try back.createPattern(allocator, macro);
    const prepared = try back.prepareRegex(pattern);

    var line_no: usize = 1;

    var arena = std.heap.ArenaAllocator.init(allocator);
    var current_encoding: encoding.Encoding = undefined;

    while (true) {
        defer _ = arena.reset(.retain_capacity);
        const loop_allocator = arena.allocator();
        var aw = std.Io.Writer.Allocating.init(loop_allocator);
        defer aw.deinit();
        _ = reader.streamDelimiter(&aw.writer, '\n') catch |err| switch (err) {
            error.EndOfStream => {
                if (aw.written().len == 0) break;
                // Process the very last line if it doesn't end with \n
                break;
            },
            else => return err,
        };

        var line = aw.written();

        if (file_encoding) |e| {
            current_encoding = e;
        } else {
            // stdin case. Detect encoding on each line because stdin can be
            // concatenated from several files using cat
            const detected = encoding.detectBomMemory(line);
            if (detected.encoding != .unknown) {
                current_encoding = detected.encoding;
            }
        }

        if (current_encoding == .utf16be or current_encoding == .utf16le) {
            reader.toss(2); // IMPORTANT: or we damage lines after the first one
            line = try encoding.convertRawUtf16ToUtf8(loop_allocator, line, current_encoding);
        } else {
            reader.toss(1);
        }

        const matched = back.matchRegex(loop_allocator, &pattern, line, &prepared);
        if (info_mode) {
            try stdout.print("line: {d} match: {} | pattern: {s}\n", .{ line_no, matched.matched, macro });
            if (matched.properties) |properties| {
                try stdout.print("\n  Meta properties found:\n", .{});
                var it = properties.iterator();
                while (it.next()) |entry| {
                    const key = entry.key_ptr.*;
                    const val = entry.value_ptr.*;
                    try stdout.print("\t{s}: {s}\n", .{ key, val });
                }
                try stdout.print("\n\n", .{});
            }
        } else {
            if (matched.matched) {
                try stdout.print("{s}\n", .{line});
            }
        }
        line_no += 1;
    }
}

test {
    @import("std").testing.refAllDecls(@This());
}
