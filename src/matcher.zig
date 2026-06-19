pub const Matcher = @This();

const std = @import("std");
const regex = @import("regex.zig");
const encoding = @import("encoding.zig");
const printer = @import("printer.zig");

allocator: std.mem.Allocator,
prepared: regex.Prepared,
print: printer.Printer,

pub const OutputFlags = printer.OutputFlags;

pub fn init(gpa: std.mem.Allocator, writer: *std.Io.Writer, macro: []const u8) !Matcher {
    regex.init(gpa);
    const pattern = try regex.createPattern(gpa, macro);
    const prepared = try regex.prepare(gpa, pattern);
    return Matcher{
        .allocator = gpa,
        .prepared = prepared,
        .print = printer.Printer.init(writer, macro),
    };
}

/// Matches single string specified in `str` argument
pub fn matchString(self: *Matcher, str: []const u8, flags: OutputFlags) !void {
    var result = regex.match(self.allocator, &self.prepared, str);
    if (flags.invert_match) {
        result = invertResult(result);
    }
    try self.print.printResult(1, result, flags);
}

/// Inverts the match result - returns matched if original didn't match
fn invertResult(result: regex.MatchResult) regex.MatchResult {
    return regex.MatchResult{
        .matched = !result.matched,
        .original = result.original,
        .properties = result.properties,
    };
}

pub fn showRegex(self: *const Matcher) !void {
    try self.print.printRegex(self.prepared.regex);
}

pub fn deinit(self: *Matcher) void {
    self.prepared.deinit(self.allocator);
    regex.deinit();
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
        // Automatically releases all memory allocated via loop_allocator at the end of the iteration
        defer _ = arena.reset(.retain_capacity);
        const loop_allocator = arena.allocator();

        var line: []const u8 = undefined;

        var aw = std.Io.Writer.Allocating.init(loop_allocator);

        var not_eof = true;
        _ = reader.streamDelimiter(&aw.writer, '\n') catch |err| switch (err) {
            error.EndOfStream => {
                if (aw.written().len == 0) break;
                not_eof = false;
            },
            else => return err,
        };

        line = aw.written();

        if (file_encoding) |e| {
            current_encoding = e;
        } else {
            // stdin case. Detect encoding on each line because stdin can be
            // concatenated from several files using cat
            const detected = encoding.detectBomMemory(line);
            if (detected.encoding != .unknown) {
                current_encoding = detected.encoding;
                line = line[detected.offset..line.len];
            }
        }

        switch (current_encoding) {
            .utf16le => {
                line = try encoding.convertRawUtf16ToUtf8(loop_allocator, line, current_encoding);
                if (not_eof) {
                    const skip = @min(reader.end - reader.seek, 2);
                    reader.toss(skip); // zero byte after delimiter so skip 2 bytes or rest
                }
            },
            .utf16be => {
                // if length is less then 2 - we read trash
                if (line.len >= 2) {
                    // trim 0x00 before 0x0A
                    line = try encoding.convertRawUtf16ToUtf8(loop_allocator, line[0 .. line.len - 1], current_encoding);
                }
                if (not_eof) {
                    reader.toss(1); // zero byte before delimiter so skip 1 byte
                }
            },
            .utf32le => {
                line = try encoding.convertRawUtf32ToUtf8(loop_allocator, line, current_encoding);
                if (not_eof) {
                    const skip = @min(reader.end - reader.seek, 4);
                    reader.toss(skip); // 3 zero bytes after delimiter so skip 4 bytes or rest
                }
            },
            .utf32be => {
                // if length is less then 4 - we read trash
                if (line.len >= 4) {
                    // trim 3 0x00 before 0x0A
                    line = try encoding.convertRawUtf32ToUtf8(loop_allocator, line[0 .. line.len - 3], current_encoding);
                }
                if (not_eof) {
                    reader.toss(1); // 3 zero bytes before delimiter so skip 1 byte
                }
            },
            else => {
                if (not_eof) {
                    reader.toss(1); // skip delimiter itself if not end of file
                }
            },
        }

        line_no += 1;
        var result = regex.match(loop_allocator, &self.prepared, line);
        if (flags.invert_match) {
            result = invertResult(result);
        }
        if (result.matched) {
            match_counter += 1;
        }
        try self.print.printResult(line_no, result, flags);
    }

    if (flags.count) {
        try self.print.printCount(match_counter);
    }
}
