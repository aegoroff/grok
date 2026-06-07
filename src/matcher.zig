pub const Matcher = @This();

const std = @import("std");
const regex = @import("regex.zig");
const encoding = @import("encoding.zig");

allocator: std.mem.Allocator,
prepared: regex.Prepared,
pattern: regex.Pattern,
writer: *std.Io.Writer,
macro: []const u8,

pub const OutputFlags = packed struct {
    info: bool = false,
    count: bool = false,
    print_line_num: bool = false,
};

pub fn init(gpa: std.mem.Allocator, writer: *std.Io.Writer, macro: []const u8) !Matcher {
    regex.init(gpa);
    const pattern = try regex.createPattern(gpa, macro);
    const prepared = try regex.prepare(pattern);
    return Matcher{
        .allocator = gpa,
        .prepared = prepared,
        .pattern = pattern,
        .writer = writer,
        .macro = macro,
    };
}

/// Matches single string specified in `str` argument
pub fn matchString(self: *Matcher, str: []const u8, flags: OutputFlags) !void {
    const result = regex.match(self.allocator, &self.prepared, str);
    try self.output(1, result, flags);
}

pub fn showRegex(self: *const Matcher) !void {
    try self.writer.print("{s}\n", .{self.pattern.regex});
}

/// Reads strings separated by \n from `reader` and matches them
pub fn matchStrings(
    self: *Matcher,
    reader: *std.Io.Reader,
    flags: OutputFlags,
    file_encoding: ?encoding.Encoding, // null means reading from stdin
) !void {
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();

    var line_no: usize = 0;
    var match_counter: u64 = 0;

    var current_encoding = file_encoding orelse .unknown;

    while (true) {
        defer _ = arena.reset(.retain_capacity);
        const loop_allocator = arena.allocator();

        var line: []const u8 = undefined;

        if (current_encoding == .utf16be or current_encoding == .utf16le) {
            // Read raw UTF-16 line up to two-byte \n, convert to
            const raw = readUtf16Line(loop_allocator, reader, current_encoding) catch |err| switch (err) {
                error.EndOfStream => break,
                else => return err,
            };
            line = try encoding.convertRawUtf16ToUtf8(loop_allocator, raw, current_encoding);
        } else {
            var aw = std.Io.Writer.Allocating.init(loop_allocator);
            _ = reader.streamDelimiter(&aw.writer, '\n') catch |err| switch (err) {
                error.EndOfStream => {
                    if (aw.written().len == 0) break;
                },
                else => return err,
            };

            line = aw.written();
            reader.toss(1);

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
        }

        line_no += 1;
        const result = regex.match(loop_allocator, &self.prepared, line);
        if (result.matched) {
            match_counter += 1;
        }
        try self.output(line_no, result, flags);
    }

    if (flags.count) {
        try self.writer.print("{d}\n", .{match_counter});
    }
}

/// Reads one line from a UTF-16 stream (up to a two-byte \n or EOF).
/// Returns the raw bytes of the line without the delimiter.
fn readUtf16Line(gpa: std.mem.Allocator, reader: *std.Io.Reader, enc: encoding.Encoding) ![]u8 {
    const newline: [2]u8 = switch (enc) {
        .utf16be => .{ 0x00, 0x0A },
        .utf16le => .{ 0x0A, 0x00 },
        else => unreachable,
    };

    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(gpa);

    while (true) {
        var pair: [2]u8 = undefined;
        reader.readSliceAll(&pair) catch |err| switch (err) {
            error.EndOfStream => {
                if (buf.items.len == 0) return error.EndOfStream;
                break;
            },
            error.ReadFailed => return error.ReadFailed,
        };
        if (std.mem.eql(u8, &pair, &newline)) break;
        try buf.appendSlice(gpa, &pair);
    }

    return buf.toOwnedSlice(gpa);
}

fn output(self: *Matcher, line_no: usize, result: regex.MatchResult, flags: OutputFlags) !void {
    if (flags.count) {
        return;
    }
    if (flags.info) {
        try self.writer.print("line: {d} match: {} | pattern: {s}\n", .{ line_no, result.matched, self.macro });
        if (result.properties) |properties| {
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
        if (result.matched) {
            if (flags.print_line_num) {
                try self.writer.print("{d}: {s}\n", .{ line_no, result.original });
            } else {
                try self.writer.print("{s}\n", .{result.original});
            }
        }
    }
}
