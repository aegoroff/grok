pub const Matcher = @This();

const std = @import("std");
const back = @import("backend.zig");
const encoding = @import("encoding.zig");

allocator: std.mem.Allocator,
prepared: back.Prepared,
pattern: back.Pattern,
writer: *std.Io.Writer,
macro: []const u8,

pub const OutputFlags = packed struct {
    info: bool = false,
    count: bool = false,
    print_line_num: bool = false,
};

pub fn init(allocator: std.mem.Allocator, writer: *std.Io.Writer, macro: []const u8) !Matcher {
    back.init(allocator);
    const pattern = try back.createPattern(allocator, macro);
    const prepared = try back.prepareRegex(pattern);
    return Matcher{
        .allocator = allocator,
        .prepared = prepared,
        .pattern = pattern,
        .writer = writer,
        .macro = macro,
    };
}

/// Matches single string specified in `str` argument
pub fn matchString(self: *Matcher, str: []const u8, info_mode: bool) !void {
    const matched = back.matchRegex(self.allocator, &self.pattern, str, &self.prepared);
    if (info_mode) {
        if (matched.matched) {
            try self.writer.print("Match found\n", .{});
            if (matched.properties) |properties| {
                var it = properties.iterator();
                while (it.next()) |entry| {
                    const key = entry.key_ptr.*;
                    const val = entry.value_ptr.*;
                    try self.writer.print("\t{s}: {s}\n", .{ key, val });
                }
            }
        } else {
            try self.writer.print("No match found\n", .{});
        }
    } else if (matched.matched) {
        try self.writer.print("{s}\n", .{str});
    }
}

pub fn showRegex(self: *const Matcher) !void {
    try self.writer.print("{s}\n", .{self.pattern.regex});
}

/// Reads strings sepatated by \n from `reader` and matches them
pub fn matchStrings(
    self: *Matcher,
    reader: *std.Io.Reader,
    flags: OutputFlags,
    file_encoding: ?encoding.Encoding, // null means reading from stdin
) !void {
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    var current_encoding: encoding.Encoding = undefined;

    var line_no: usize = 0;
    var match_counter: u64 = 0;
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
        line_no += 1;

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

        const matched = back.matchRegex(loop_allocator, &self.pattern, line, &self.prepared);

        if (matched.matched) {
            match_counter += 1;
        }
        if (flags.count) {
            continue;
        } else if (flags.info) {
            try self.writer.print("line: {d} match: {} | pattern: {s}\n", .{ line_no, matched.matched, self.macro });
            if (matched.properties) |properties| {
                try self.writer.print("\n  Meta properties found:\n", .{});
                var it = properties.iterator();
                while (it.next()) |entry| {
                    const key = entry.key_ptr.*;
                    const val = entry.value_ptr.*;
                    try self.writer.print("\t{s}: {s}\n", .{ key, val });
                }
                try self.writer.print("\n\n", .{});
            }
        } else {
            if (matched.matched) {
                if (flags.print_line_num) {
                    try self.writer.print("{d}: {s}\n", .{ line_no, line });
                } else {
                    try self.writer.print("{s}\n", .{line});
                }
            }
        }
    }
    if (flags.count) {
        try self.writer.print("{d}\n", .{match_counter});
    }
}
