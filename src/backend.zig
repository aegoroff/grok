const std = @import("std");
const front = @import("frontend.zig");
const grok = @import("grok.zig");
const re = @cImport({
    @cDefine("PCRE2_CODE_UNIT_WIDTH", "8");
    @cInclude("pcre2.h");
});

pub const Pattern = struct {
    regex: []const u8,
    properties: std.ArrayList([]const u8),
};

pub const Prepared = struct {
    re: *re.pcre2_code_8,
};

pub const MatchResult = struct {
    matched: bool,
    properties: ?std.StringHashMap([]const u8),
};

var backend_allocator: std.mem.Allocator = undefined;
var general_context: *re.pcre2_general_context_8 = undefined;

pub fn init(a: std.mem.Allocator) void {
    backend_allocator = a;
    general_context = re.pcre2_general_context_create_8(&pcre_alloc, &pcre_free, null).?;
}

const AllocationHeader = extern struct {
    original_ptr: [*]u8,
    size: usize,
};

pub export fn pcre_alloc(size: usize, _: ?*anyopaque) ?*anyopaque {
    // Allocate space for header + data + padding for alignment
    const header_size = @sizeOf(AllocationHeader);
    const total_size = header_size + size + 7; // +7 for guaranteed alignment

    const raw_mem = backend_allocator.alloc(u8, total_size) catch return null;

    // Find aligned pointer for data
    const data_start_ptr = raw_mem.ptr + header_size;
    const data_start_addr = @intFromPtr(data_start_ptr);
    const aligned_data_addr = std.mem.alignForward(usize, data_start_addr, 8);
    const aligned_data_ptr = @as([*]u8, @ptrFromInt(aligned_data_addr));

    // Save header before data
    const header_addr = aligned_data_addr - header_size;
    const header_ptr = @as(*AllocationHeader, @ptrFromInt(header_addr));
    header_ptr.* = .{
        .original_ptr = raw_mem.ptr,
        .size = total_size,
    };

    return @ptrCast(aligned_data_ptr);
}

pub export fn pcre_free(ptr: ?*anyopaque, _: ?*anyopaque) void {
    if (ptr) |p| {
        const data_ptr = @as([*]u8, @ptrCast(p));
        const data_addr = @intFromPtr(data_ptr);

        // Find header before data
        const header_addr = data_addr - @sizeOf(AllocationHeader);
        const header = @as(*const AllocationHeader, @ptrFromInt(header_addr));

        // Free original memory
        const slice = header.original_ptr[0..header.size];
        backend_allocator.free(slice);
    }
}

pub fn create_pattern(allocator: std.mem.Allocator, macro: []const u8) !?Pattern {
    const m = front.get_pattern(macro).?;
    var stack = std.ArrayList(front.Info){};
    var composition = std.ArrayList(u8){};
    var used_properties = std.StringHashMap(bool).init(allocator);
    var result = Pattern{ .properties = std.ArrayList([]const u8){}, .regex = "" };
    for (m.items) |value| {
        try stack.append(allocator, value);
        while (stack.items.len > 0) {
            const current = stack.pop().?;
            const current_slice = std.mem.span(current.data);
            if (current.part == .literal) {
                // plain literal case
                try composition.appendSlice(allocator, current_slice);
            } else {
                if (current.reference != null) {
                    // leading (?<name> immediately into composition
                    var reference = std.mem.span(current.reference);
                    if (used_properties.contains(reference)) {
                        var concat = std.ArrayList(u8){};
                        try concat.appendSlice(allocator, current_slice);
                        try concat.appendSlice(allocator, "_");
                        try concat.appendSlice(allocator, reference);
                        try concat.append(allocator, 0);
                        reference = concat.items[0 .. concat.items.len - 1 :0];
                    }
                    try used_properties.put(reference, true);

                    try composition.appendSlice(allocator, "(?<");
                    try composition.appendSlice(allocator, reference);
                    try composition.appendSlice(allocator, ">");
                    try result.properties.append(allocator, reference);

                    // trailing ) into stack bottom
                    const trail_paren = front.Info{ .data = ")", .reference = null, .part = .literal };
                    try stack.append(allocator, trail_paren);
                }
                const childs = front.get_pattern(current_slice) orelse {
                    continue;
                };
                var rev_iter = std.mem.reverseIterator(childs.items);
                while (rev_iter.next()) |child| {
                    try stack.append(allocator, child);
                }
            }
        }
    }
    result.regex = composition.items;
    return result;
}

pub fn prepare_re(allocator: std.mem.Allocator, pattern: Pattern) !Prepared {
    var errornumber: c_int = undefined;
    var erroroffset: re.PCRE2_SIZE = undefined;

    const compile_ctx = re.pcre2_compile_context_create_8(general_context);

    const regex = re.pcre2_compile_8(pattern.regex.ptr, pattern.regex.len, 0, &errornumber, &erroroffset, compile_ctx) orelse {
        const len = 256;
        const buffer = allocator.alloc(u8, len) catch {
            return grok.GrokError.MemoryAllocationError;
        };
        defer allocator.free(buffer);
        _ = re.pcre2_get_error_message_8(errornumber, buffer.ptr, len);
        std.debug.print("PCRE2 compilation failed at offset {d}: {s}\n", .{ erroroffset, buffer });
        return grok.GrokError.InvalidRegex;
    };
    return Prepared{ .re = regex };
}

pub fn match_re(pattern: *const Pattern, subject: []const u8, prepared: *const Prepared) MatchResult {
    const match_data = re.pcre2_match_data_create_from_pattern_8(prepared.re, general_context);
    defer re.pcre2_match_data_free_8(match_data);
    const match_ctx = re.pcre2_match_context_create_8(general_context);

    const rc: c_int = re.pcre2_match_8(prepared.re, subject.ptr, subject.len, 0, re.PCRE2_NOTEMPTY, match_data, match_ctx);
    const matched = rc > 0;

    if (matched and pattern.properties.items.len > 0) {
        var properties = std.StringHashMap([]const u8).init(backend_allocator);
        for (pattern.properties.items) |value| {
            var buffer: [*c]re.PCRE2_UCHAR8 = undefined;
            var buffer_size_in_chars: re.PCRE2_SIZE = undefined;
            const get_string_result = re.pcre2_substring_get_byname_8(match_data, value.ptr, &buffer, &buffer_size_in_chars);
            if (get_string_result == 0) {
                properties.put(value, std.mem.span(buffer)) catch {
                    continue;
                };
            }
        }
        return MatchResult{
            .matched = matched,
            .properties = properties,
        };
    } else {
        return MatchResult{
            .matched = matched,
            .properties = null,
        };
    }
}
