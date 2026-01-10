const std = @import("std");

pub const Encoding = enum {
    unknown,
    utf8,
    utf16le,
    utf16be,
    utf32be,
};

const Bom = struct {
    encoding: Encoding,
    signature: []const u8,
};

const signatures: []const Bom = &[_]Bom{
    Bom{
        .encoding = .utf8,
        .signature = &[_]u8{ 0xEF, 0xBB, 0xBF },
    },
    Bom{
        .encoding = .utf16le,
        .signature = &[_]u8{ 0xFF, 0xFE },
    },
    Bom{
        .encoding = .utf16be,
        .signature = &[_]u8{ 0xFE, 0xFF },
    },
    Bom{
        .encoding = .utf32be,
        .signature = &[_]u8{ 0x00, 0x00, 0xFE, 0xFF },
    },
    Bom{
        .encoding = .unknown,
        .signature = &[_]u8{},
    },
};

pub const DetectResult = struct {
    encoding: Encoding,
    offset: usize,
};

pub fn convertRawUtf16ToUtf8(gpa: std.mem.Allocator, rawBytes: []u8, encoding: Encoding) ![]u8 {
    const wide = try charToWchar(gpa, rawBytes, encoding);
    return std.unicode.utf16LeToUtf8Alloc(gpa, wide);
}

pub fn detectBomMemory(buffer: []const u8) DetectResult {
    for (signatures) |bom| {
        if (bom.signature.len == 0) continue;

        if (buffer.len >= bom.signature.len and
            std.mem.startsWith(u8, buffer, bom.signature))
        {
            return .{
                .encoding = bom.encoding,
                .offset = bom.signature.len,
            };
        }
    }

    return .{ .encoding = .unknown, .offset = 0 };
}

fn charToWchar(gpa: std.mem.Allocator, buffer: []const u8, encoding: Encoding) ![]u16 {
    const len = buffer.len / 2;

    var wide_buffer = try gpa.alloc(u16, len);

    var i: usize = 0;
    var counter: usize = 0;
    while (i + 1 < buffer.len) : (i += 2) {
        const b1 = buffer[i];
        const b2 = buffer[i + 1];

        const val: u16 = switch (encoding) {
            .utf16le => @as(u16, b2) << 8 | b1,
            else => @as(u16, b1) << 8 | b2,
        };

        wide_buffer[counter] = val;
        counter += 1;
    }

    return wide_buffer;
}

test "detect Utf8" {
    const buffer = &[_]u8{ 0xEF, 0xBB, 0xBF, 0xD1, 0x82, 0xD0, 0xB5, 0xD1, 0x81, 0xD1, 0x82 };
    const result = detectBomMemory(buffer);
    try std.testing.expectEqual(.utf8, result.encoding);
    try std.testing.expectEqual(3, result.offset);
}

test "detect Utf16le" {
    const buffer = &[_]u8{ 0xFF, 0xFE, 0x00, 0x00, 0x00, 0x00, 0x00, 0xD1, 0x81, 0xD1, 0x82 };
    const result = detectBomMemory(buffer);
    try std.testing.expectEqual(.utf16le, result.encoding);
    try std.testing.expectEqual(2, result.offset);
}

test "detect Utf16be" {
    const buffer = &[_]u8{ 0xFE, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0xD1, 0x81, 0xD1, 0x82 };
    const result = detectBomMemory(buffer);
    try std.testing.expectEqual(.utf16be, result.encoding);
    try std.testing.expectEqual(2, result.offset);
}

test "detect Utf32be" {
    const buffer = &[_]u8{ 0x00, 0x00, 0xFE, 0xFF, 0x00, 0x00, 0x00, 0xD1, 0x81, 0xD1, 0x82 };
    const result = detectBomMemory(buffer);
    try std.testing.expectEqual(.utf32be, result.encoding);
    try std.testing.expectEqual(4, result.offset);
}

test "detect no bom" {
    const buffer = &[_]u8{ 0xD1, 0x82, 0xD0, 0xB5, 0xD1, 0x81, 0xD1, 0x82 };
    const result = detectBomMemory(buffer);
    try std.testing.expectEqual(.unknown, result.encoding);
    try std.testing.expectEqual(0, result.offset);
}
