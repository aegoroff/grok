pub const Matcher = @This();

const std = @import("std");
const regex = @import("regex.zig");
const encoding = @import("encoding.zig");
const line_reader = @import("line_reader.zig");
const printer = @import("printer.zig");

allocator: std.mem.Allocator,
prepared: regex.Prepared,
print: printer.Printer,

pub const OutputFlags = printer.OutputFlags;

pub fn init(gpa: std.mem.Allocator, writer: *std.Io.Writer, macro: []const u8) !Matcher {
    const pattern = try regex.createPattern(gpa, macro);
    const prepared = try regex.prepare(gpa, pattern);
    return .{
        .allocator = gpa,
        .prepared = prepared,
        .print = printer.Printer.init(writer, macro),
    };
}

/// Matches single string specified in `str` argument
pub fn matchString(self: *Matcher, str: []const u8, flags: OutputFlags) !void {
    var result = self.prepared.match(self.allocator, str);
    defer if (result.properties) |*props| props.deinit();
    _ = try self.print.printResult(1, result, flags);
}

pub fn showRegex(self: *const Matcher) !void {
    try self.print.printRegex(self.prepared.regex);
}

pub fn deinit(self: *Matcher) void {
    self.prepared.deinit();
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

    const loop_allocator = arena.allocator();
    var liner = line_reader.LineReader.init(reader, file_encoding);

    while (try liner.readLine(loop_allocator)) |line| {
        // Each iteration is wrapped in a block so that defer statements execute
        // at the end of the iteration, not at the end of the function
        defer _ = arena.reset(.retain_capacity);

        line_no += 1;
        const result = self.prepared.match(loop_allocator, line);
        if (try self.print.printResult(line_no, result, flags)) {
            match_counter += 1;
        }
    }

    if (flags.count) {
        try self.print.printCount(match_counter);
    }
}
