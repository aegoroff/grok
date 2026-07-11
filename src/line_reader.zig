const std = @import("std");
const encoding = @import("encoding.zig");

/// How wide-encoded lines are trimmed and advanced after streamDelimiter finds `\n`.
const WideLineOpts = struct {
    unit_size: usize,
    /// Trailing zero bytes before `\n` in big-endian encodings.
    be_trim: usize,
    /// After `\n`, skip the rest of the code unit (LE) instead of one byte.
    le_toss: bool,
};

fn wideLineOpts(enc: encoding.Encoding) ?WideLineOpts {
    return switch (enc) {
        .utf16le => .{ .unit_size = 2, .be_trim = 0, .le_toss = true },
        .utf16be => .{ .unit_size = 2, .be_trim = 1, .le_toss = false },
        .utf32le => .{ .unit_size = 4, .be_trim = 0, .le_toss = true },
        .utf32be => .{ .unit_size = 4, .be_trim = 3, .le_toss = false },
        else => null,
    };
}

fn trimWideLine(line: []const u8, opts: WideLineOpts) []const u8 {
    if (opts.be_trim != 0 and line.len >= opts.unit_size) {
        return line[0 .. line.len - opts.be_trim];
    }
    return line;
}

fn tossAfterDelimiter(reader: *std.Io.Reader, opts: WideLineOpts) void {
    const skip = if (opts.le_toss)
        @min(reader.end - reader.seek, opts.unit_size)
    else
        1;
    reader.toss(skip);
}

fn decodeWideLine(gpa: std.mem.Allocator, line: []const u8, enc: encoding.Encoding) ![]const u8 {
    return switch (enc) {
        .utf16le, .utf16be => encoding.convertRawUtf16ToUtf8(gpa, line, enc),
        .utf32le, .utf32be => encoding.convertRawUtf32ToUtf8(gpa, line, enc),
        else => unreachable,
    };
}

pub const LineReader = struct {
    reader: *std.Io.Reader,
    /// Fixed file encoding, or null for stdin (detect BOM per line).
    file_encoding: ?encoding.Encoding,
    current_encoding: encoding.Encoding,

    pub fn init(reader: *std.Io.Reader, file_encoding: ?encoding.Encoding) LineReader {
        return .{
            .reader = reader,
            .file_encoding = file_encoding,
            .current_encoding = file_encoding orelse .unknown,
        };
    }

    /// Reads the next line, decoding to UTF-8. Returns null at EOF.
    pub fn readLine(self: *LineReader, gpa: std.mem.Allocator) !?[]const u8 {
        var aw = std.Io.Writer.Allocating.init(gpa);

        var not_eof = true;
        _ = self.reader.streamDelimiter(&aw.writer, '\n') catch |err| switch (err) {
            error.EndOfStream => {
                if (aw.written().len == 0) return null;
                not_eof = false;
            },
            else => return err,
        };

        var line = aw.written();

        if (self.file_encoding) |e| {
            self.current_encoding = e;
        } else {
            // stdin: detect encoding on each line because stdin can be
            // concatenated from several files using cat
            const detected = encoding.detectBomMemory(line);
            if (detected.encoding != .unknown) {
                self.current_encoding = detected.encoding;
                line = line[detected.offset..line.len];
            }
        }

        return try self.decodeLine(gpa, line, self.current_encoding, not_eof);
    }

    fn decodeLine(
        self: *LineReader,
        gpa: std.mem.Allocator,
        line: []const u8,
        current_encoding: encoding.Encoding,
        not_eof: bool,
    ) ![]const u8 {
        if (wideLineOpts(current_encoding)) |opts| {
            const raw = trimWideLine(line, opts);
            const decoded: []const u8 = if (opts.le_toss or raw.len >= opts.unit_size)
                try decodeWideLine(gpa, raw, current_encoding)
            else
                line;
            if (not_eof) tossAfterDelimiter(self.reader, opts);
            return decoded;
        }

        if (not_eof) self.reader.toss(1);
        return line;
    }
};

/// Probes the first bytes of a file for BOM. Advances `reader`; seek to
/// `result.offset` before reading lines.
pub fn probeFileEncoding(reader: *std.Io.Reader, file_size: u64) !encoding.DetectResult {
    if (file_size < 2) {
        return .{ .encoding = .utf8, .offset = 0 };
    }
    const min = @min(file_size, 4);
    const encoding_buffer = try reader.take(min);
    return encoding.detectBomMemory(encoding_buffer);
}

pub fn encodingFromDetection(detection: encoding.DetectResult) encoding.Encoding {
    if (detection.encoding == .unknown) return .utf8;
    return detection.encoding;
}

test "trimWideLine utf16be drops trailing zero before newline" {
    const line = &[_]u8{ 0x00, 0x48, 0x00, 0x69, 0x00 };
    const trimmed = trimWideLine(line, wideLineOpts(.utf16be).?);
    try std.testing.expectEqual(@as(usize, 4), trimmed.len);
    try std.testing.expectEqual(@as(u8, 0x69), trimmed[3]);
}

test "trimWideLine utf32be drops three trailing zeros before newline" {
    const line = &[_]u8{ 0x00, 0x00, 0x00, 0x68, 0x00, 0x00, 0x00 };
    const trimmed = trimWideLine(line, wideLineOpts(.utf32be).?);
    try std.testing.expectEqual(@as(usize, 4), trimmed.len);
    try std.testing.expectEqual(@as(u8, 0x68), trimmed[3]);
}

test "trimWideLine leaves le encodings unchanged" {
    const line = &[_]u8{ 0x48, 0x00, 0x65, 0x00 };
    const trimmed = trimWideLine(line, wideLineOpts(.utf16le).?);
    try std.testing.expectEqualSlices(u8, line, trimmed);
}
