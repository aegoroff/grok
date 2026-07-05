pub const Printer = @This();

const std = @import("std");
const regex = @import("regex.zig");

pub const OutputFlags = packed struct {
    info: bool = false,
    json: bool = false,
    count: bool = false,
    print_line_num: bool = false,
    invert_match: bool = false,
};

writer: *std.Io.Writer,
macro: []const u8,

pub fn init(writer: *std.Io.Writer, macro: []const u8) Printer {
    return .{
        .writer = writer,
        .macro = macro,
    };
}

/// Prints the match result for a single line
pub fn printResult(self: *Printer, line_no: usize, result: regex.MatchResult, flags: OutputFlags) !void {
    if (flags.count) {
        return;
    }
    if (flags.json) {
        try self.printJson(line_no, result);
    } else if (flags.info) {
        try self.printInfo(line_no, result);
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

/// Prints match count
pub fn printCount(self: *Printer, count: u64) !void {
    try self.writer.print("{d}\n", .{count});
}

/// Prints the regex pattern
pub fn printRegex(self: *const Printer, pattern_regex: []const u8) !void {
    try self.writer.print("{s}\n", .{pattern_regex});
}

/// Info mode output
fn printInfo(self: *Printer, line_no: usize, result: regex.MatchResult) !void {
    try self.writer.print("line: {d} match: {} | pattern: {s}\n", .{ line_no, result.matched, self.macro });
    if (result.properties) |properties| {
        try self.writer.print("\n  Meta properties found:\n", .{});
        var it = properties.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            const val = entry.value_ptr.*;
            try self.writer.print("    {s}: {s}\n", .{ key, val });
        }
        try self.writer.print("\n\n", .{});
    }
}

/// JSON mode output
fn printJson(self: *Printer, line_no: usize, result: regex.MatchResult) !void {
    var jw: std.json.Stringify = .{
        .writer = self.writer,
        .options = .{},
    };

    try jw.beginObject();

    try jw.objectField("line");
    try jw.write(line_no);

    try jw.objectField("matched");
    try jw.write(result.matched);

    try jw.objectField("pattern");
    try jw.write(self.macro);

    try jw.objectField("text");
    try jw.write(result.original);

    try jw.objectField("properties");
    try jw.beginObject();
    if (result.properties) |properties| {
        var it = properties.iterator();
        while (it.next()) |entry| {
            try jw.objectField(entry.key_ptr.*);
            try jw.write(entry.value_ptr.*);
        }
    }
    try jw.endObject();

    try jw.endObject();
    try self.writer.writeByte('\n');
}
