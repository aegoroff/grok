const std = @import("std");
const encoding = @import("encoding.zig");

/// File encoding selected by bits 5–7 of the fuzz flags byte.
pub const FileEncoding = enum(u3) {
    raw = 0,
    utf8_bom = 1,
    utf16le = 2,
    utf16be = 3,
    utf32le = 4,
    utf32be = 5,

    pub fn fromFlagsByte(flags_byte: u8) FileEncoding {
        return switch ((flags_byte >> 5) & 0x7) {
            0 => .raw,
            1 => .utf8_bom,
            2 => .utf16le,
            3 => .utf16be,
            4 => .utf32le,
            5 => .utf32be,
            else => .raw,
        };
    }
};

const bom_utf8 = [_]u8{ 0xEF, 0xBB, 0xBF };
const bom_utf16le = [_]u8{ 0xFF, 0xFE };
const bom_utf16be = [_]u8{ 0xFE, 0xFF };
const bom_utf32le = [_]u8{ 0xFF, 0xFE, 0x00, 0x00 };
const bom_utf32be = [_]u8{ 0x00, 0x00, 0xFE, 0xFF };

const LenientUtf8 = struct {
    bytes: []const u8,
    index: usize = 0,

    fn next(self: *LenientUtf8) ?u21 {
        if (self.index >= self.bytes.len) return null;
        const first = self.bytes[self.index];
        if (first < 0x80) {
            self.index += 1;
            return first;
        }

        const seq_len = std.unicode.utf8ByteSequenceLength(first) catch {
            self.index += 1;
            return first;
        };
        if (self.index + seq_len > self.bytes.len) {
            self.index += 1;
            return first;
        }

        const chunk = self.bytes[self.index .. self.index + seq_len];
        if (std.unicode.utf8Decode(chunk)) |cp| {
            self.index += seq_len;
            return cp;
        } else |_| {
            self.index += 1;
            return first;
        }
    }
};

/// Encode Smith subject bytes for writing to the fuzz temp file.
pub fn encodeSubjectForFile(gpa: std.mem.Allocator, subject: []const u8, file_encoding: FileEncoding) ![]u8 {
    return switch (file_encoding) {
        .raw => try gpa.dupe(u8, subject),
        .utf8_bom => try prependBom(gpa, subject, &bom_utf8),
        .utf16le => try encodeUtf16(gpa, subject, .little, &bom_utf16le),
        .utf16be => try encodeUtf16(gpa, subject, .big, &bom_utf16be),
        .utf32le => try encodeUtf32(gpa, subject, .little, &bom_utf32le),
        .utf32be => try encodeUtf32(gpa, subject, .big, &bom_utf32be),
    };
}

fn prependBom(gpa: std.mem.Allocator, subject: []const u8, bom: []const u8) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(gpa, bom.len + subject.len);
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, bom);
    try out.appendSlice(gpa, subject);
    return out.toOwnedSlice(gpa);
}

fn encodeUtf16(gpa: std.mem.Allocator, subject: []const u8, endian: std.builtin.Endian, bom: []const u8) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(gpa, bom.len + subject.len * 2);
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, bom);

    var it = LenientUtf8{ .bytes = subject };
    while (it.next()) |cp| {
        if (cp <= 0xFFFF) {
            var buf: [2]u8 = undefined;
            std.mem.writeInt(u16, &buf, @intCast(cp), endian);
            try out.appendSlice(gpa, &buf);
        } else {
            const adj = cp - 0x10000;
            const high: u16 = @intCast((adj >> 10) + 0xD800);
            const low: u16 = @intCast((adj & 0x3FF) + 0xDC00);
            var buf: [4]u8 = undefined;
            std.mem.writeInt(u16, buf[0..2], high, endian);
            std.mem.writeInt(u16, buf[2..4], low, endian);
            try out.appendSlice(gpa, &buf);
        }
    }
    return out.toOwnedSlice(gpa);
}

fn encodeUtf32(gpa: std.mem.Allocator, subject: []const u8, endian: std.builtin.Endian, bom: []const u8) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(gpa, bom.len + subject.len * 4);
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, bom);

    var it = LenientUtf8{ .bytes = subject };
    while (it.next()) |cp| {
        var buf: [4]u8 = undefined;
        std.mem.writeInt(u32, &buf, @intCast(cp), endian);
        try out.appendSlice(gpa, &buf);
    }
    return out.toOwnedSlice(gpa);
}

test "fromFlagsByte maps encoding bits" {
    try std.testing.expectEqual(.raw, FileEncoding.fromFlagsByte(0));
    try std.testing.expectEqual(.utf8_bom, FileEncoding.fromFlagsByte(0b0010_0000));
    try std.testing.expectEqual(.utf16le, FileEncoding.fromFlagsByte(0b0100_0000));
    try std.testing.expectEqual(.utf32be, FileEncoding.fromFlagsByte(0b1010_0000));
    try std.testing.expectEqual(.raw, FileEncoding.fromFlagsByte(0b1100_0000));
    try std.testing.expectEqual(.raw, FileEncoding.fromFlagsByte(0b1110_0000));
}

test "encodeSubjectForFile utf16le roundtrip via BOM detection" {
    const subject = "Hello\nworld";
    const encoded = try encodeSubjectForFile(std.testing.allocator, subject, .utf16le);
    defer std.testing.allocator.free(encoded);

    const detected = encoding.detectBomMemory(encoded);
    try std.testing.expectEqual(.utf16le, detected.encoding);
    try std.testing.expectEqual(@as(usize, 2), detected.offset);

    const decoded = try encoding.convertRawUtf16ToUtf8(
        std.testing.allocator,
        encoded[detected.offset..],
        .utf16le,
    );
    defer std.testing.allocator.free(decoded);
    try std.testing.expectEqualStrings(subject, decoded);
}

test "encodeSubjectForFile utf8 bom" {
    const subject = "test";
    const encoded = try encodeSubjectForFile(std.testing.allocator, subject, .utf8_bom);
    defer std.testing.allocator.free(encoded);

    const detected = encoding.detectBomMemory(encoded);
    try std.testing.expectEqual(.utf8, detected.encoding);
    try std.testing.expectEqualStrings(subject, encoded[detected.offset..]);
}

test "encodeSubjectForFile utf32be multiline newlines" {
    const subject = "a\nb";
    const encoded = try encodeSubjectForFile(std.testing.allocator, subject, .utf32be);
    defer std.testing.allocator.free(encoded);

    const detected = encoding.detectBomMemory(encoded);
    try std.testing.expectEqual(.utf32be, detected.encoding);

    const payload = encoded[detected.offset..];
    try std.testing.expectEqual(@as(usize, 12), payload.len);
    try std.testing.expectEqual(@as(u8, 0x00), payload[4]);
    try std.testing.expectEqual(@as(u8, 0x00), payload[5]);
    try std.testing.expectEqual(@as(u8, 0x00), payload[6]);
    try std.testing.expectEqual(@as(u8, 0x0A), payload[7]);
}
