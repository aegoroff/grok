const std = @import("std");
const grok = @import("grok.zig");

pub const Encoding = enum {
    unknown,
    utf8,
    utf16le,
    utf16be,
    utf32be,
    utf32le,
};

const Bom = struct {
    encoding: Encoding,
    signature: []const u8,
};

const signatures: []const Bom = &[_]Bom{
    Bom{
        .encoding = .utf32be,
        .signature = &[_]u8{ 0x00, 0x00, 0xFE, 0xFF },
    },
    Bom{
        .encoding = .utf32le,
        .signature = &[_]u8{ 0xFF, 0xFE, 0x00, 0x00 },
    },
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
        .encoding = .unknown,
        .signature = &[_]u8{},
    },
};

pub const DetectResult = struct {
    encoding: Encoding,
    offset: usize,
};

pub fn convertRawUtf16ToUtf8(gpa: std.mem.Allocator, rawBytes: []const u8, encoding: Encoding) ![]u8 {
    const wide = try bytesToCodeUnits(
        gpa,
        rawBytes,
        encoding,
        u16,
        2,
        error.InvalidUtf16LineLength,
        .utf16le,
        .utf16be,
    );
    defer gpa.free(wide);
    return std.unicode.utf16LeToUtf8Alloc(gpa, wide);
}

pub fn convertRawUtf32ToUtf8(gpa: std.mem.Allocator, rawBytes: []const u8, encoding: Encoding) ![]u8 {
    const wide = try bytesToCodeUnits(
        gpa,
        rawBytes,
        encoding,
        u32,
        4,
        error.InvalidUtf32LineLength,
        .utf32le,
        .utf32be,
    );
    defer gpa.free(wide);
    return utf32ToUtf8Alloc(gpa, wide);
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

fn bytesToCodeUnits(
    gpa: std.mem.Allocator,
    buffer: []const u8,
    encoding: Encoding,
    comptime Unit: type,
    comptime unit_size: usize,
    comptime invalid_length: grok.GrokError,
    comptime le_encoding: Encoding,
    comptime be_encoding: Encoding,
) ![]Unit {
    comptime std.debug.assert(@sizeOf(Unit) == unit_size);

    if (buffer.len % unit_size != 0) return invalid_length;
    const len = buffer.len / unit_size;

    var wide_buffer = try gpa.alloc(Unit, len);
    errdefer gpa.free(wide_buffer);

    var i: usize = 0;
    while (i < len) : (i += 1) {
        const bytes = buffer[i * unit_size .. (i + 1) * unit_size][0..unit_size].*;

        wide_buffer[i] = switch (encoding) {
            le_encoding => std.mem.readInt(Unit, &bytes, .little),
            be_encoding => std.mem.readInt(Unit, &bytes, .big),
            else => return grok.GrokError.InvalidEncoding,
        };
    }

    return wide_buffer;
}

fn utf32ToUtf8Alloc(gpa: std.mem.Allocator, utf32_input: []const u32) ![]u8 {
    var utf8_list = try std.ArrayList(u8).initCapacity(gpa, utf32_input.len * 4);
    errdefer utf8_list.deinit(gpa);

    var temp_buf: [4]u8 = undefined;

    for (utf32_input) |utf32_val| {
        if (utf32_val > 0x10FFFF or (utf32_val >= 0xD800 and utf32_val <= 0xDFFF)) {
            return grok.GrokError.InvalidUtf32;
        }

        const codepoint: u21 = @intCast(utf32_val);
        const len = try std.unicode.utf8Encode(codepoint, &temp_buf);
        try utf8_list.appendSlice(gpa, temp_buf[0..len]);
    }

    return utf8_list.toOwnedSlice(gpa);
}

test "detect Utf8" {
    const buffer = &[_]u8{ 0xEF, 0xBB, 0xBF, 0xD1, 0x82, 0xD0, 0xB5, 0xD1, 0x81, 0xD1, 0x82 };
    const result = detectBomMemory(buffer);
    try std.testing.expectEqual(.utf8, result.encoding);
    try std.testing.expectEqual(3, result.offset);
}

test "detect Utf16le" {
    const buffer = &[_]u8{ 0xFF, 0xFE, 0x48, 0x00, 0x65, 0x00, 0x6C, 0x00, 0x6C, 0x00, 0x6F, 0x00 };
    const result = detectBomMemory(buffer);
    try std.testing.expectEqual(.utf16le, result.encoding);
    try std.testing.expectEqual(2, result.offset);
}

test "decode Utf16le" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const buffer = &[_]u8{ 0x48, 0x00, 0x65, 0x00, 0x6C, 0x00, 0x6C, 0x00, 0x6F, 0x00 };
    const decoded = try convertRawUtf16ToUtf8(arena.allocator(), buffer, .utf16le);
    try std.testing.expectEqualStrings("Hello", decoded);
}

test "detect Utf16be" {
    const buffer = &[_]u8{ 0xFE, 0xFF, 0x00, 0x48, 0x00, 0x65, 0x00, 0x6C, 0x00, 0x6C, 0x00, 0x6F };
    const result = detectBomMemory(buffer);
    try std.testing.expectEqual(.utf16be, result.encoding);
    try std.testing.expectEqual(2, result.offset);
}

test "decode Utf16be" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const buffer = &[_]u8{ 0x00, 0x48, 0x00, 0x65, 0x00, 0x6C, 0x00, 0x6C, 0x00, 0x6F };
    const decoded = try convertRawUtf16ToUtf8(arena.allocator(), buffer, .utf16be);
    try std.testing.expectEqualStrings("Hello", decoded);
}

test "detect Utf32be" {
    const buffer = &[_]u8{ 0x00, 0x00, 0xFE, 0xFF, 0x00, 0x00, 0x00, 0x68, 0x00, 0x00, 0x00, 0x69 };
    const result = detectBomMemory(buffer);
    try std.testing.expectEqual(.utf32be, result.encoding);
    try std.testing.expectEqual(4, result.offset);
}

test "decode Utf32be" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const buffer = &[_]u8{ 0x00, 0x00, 0x00, 0x68, 0x00, 0x00, 0x00, 0x69 };
    const decoded = try convertRawUtf32ToUtf8(arena.allocator(), buffer, .utf32be);
    try std.testing.expectEqualStrings("hi", decoded);
}

test "detect Utf32le" {
    const buffer = &[_]u8{ 0xFF, 0xFE, 0x00, 0x00, 0x68, 0x00, 0x00, 0x00, 0x69, 0x00, 0x00, 0x00 };
    const result = detectBomMemory(buffer);
    try std.testing.expectEqual(.utf32le, result.encoding);
    try std.testing.expectEqual(4, result.offset);
}

test "decode Utf32le" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const buffer = &[_]u8{ 0x68, 0x00, 0x00, 0x00, 0x69, 0x00, 0x00, 0x00 };
    const decoded = try convertRawUtf32ToUtf8(arena.allocator(), buffer, .utf32le);
    try std.testing.expectEqualStrings("hi", decoded);
}

test "detect no bom" {
    const buffer = &[_]u8{ 0xD1, 0x82, 0xD0, 0xB5, 0xD1, 0x81, 0xD1, 0x82 };
    const result = detectBomMemory(buffer);
    try std.testing.expectEqual(.unknown, result.encoding);
    try std.testing.expectEqual(0, result.offset);
}
