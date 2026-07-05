const std = @import("std");
const encoding = @import("encoding.zig");

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
        switch (current_encoding) {
            .utf16le => {
                const decoded = try encoding.convertRawUtf16ToUtf8(gpa, line, current_encoding);
                if (not_eof) {
                    const skip = @min(self.reader.end - self.reader.seek, 2);
                    self.reader.toss(skip); // zero byte after delimiter so skip 2 bytes or rest
                }
                return decoded;
            },
            .utf16be => {
                var decoded = line;
                // if length is less then 2 - we read trash
                if (line.len >= 2) {
                    // trim 0x00 before 0x0A
                    decoded = try encoding.convertRawUtf16ToUtf8(gpa, line[0 .. line.len - 1], current_encoding);
                }
                if (not_eof) {
                    self.reader.toss(1); // zero byte before delimiter so skip 1 byte
                }
                return decoded;
            },
            .utf32le => {
                const decoded = try encoding.convertRawUtf32ToUtf8(gpa, line, current_encoding);
                if (not_eof) {
                    const skip = @min(self.reader.end - self.reader.seek, 4);
                    self.reader.toss(skip); // 3 zero bytes after delimiter so skip 4 bytes or rest
                }
                return decoded;
            },
            .utf32be => {
                var decoded = line;
                // if length is less then 4 - we read trash
                if (line.len >= 4) {
                    // trim 3 0x00 before 0x0A
                    decoded = try encoding.convertRawUtf32ToUtf8(gpa, line[0 .. line.len - 3], current_encoding);
                }
                if (not_eof) {
                    self.reader.toss(1); // 3 zero bytes before delimiter so skip 1 byte
                }
                return decoded;
            },
            else => {
                if (not_eof) {
                    self.reader.toss(1); // skip delimiter itself if not end of file
                }
                return line;
            },
        }
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
