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
    properties: std.StringHashMap([]const u8),
};

var backend_allocator: std.mem.Allocator = undefined;
var general_context: *re.pcre2_general_context_8 = undefined;

pub fn init(a: std.mem.Allocator) void {
    backend_allocator = a;
    general_context = re.pcre2_general_context_create_8(&pcre_alloc, &pcre_free, null).?;
}

pub export fn pcre_alloc(size: usize, _: ?*anyopaque) ?*anyopaque {
    const aligned_size = std.mem.alignForward(usize, size, 8);
    const slice = backend_allocator.alloc(u8, aligned_size) catch {
        return null;
    };
    return @ptrCast(slice.ptr);
}

pub export fn pcre_free(_: ?*anyopaque, _: ?*anyopaque) void {}

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
                        reference = concat.items[0.. :0];
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

pub fn prepare_re(pattern: Pattern) !Prepared {
    var errornumber: c_int = undefined;
    var erroroffset: re.PCRE2_SIZE = undefined;

    const compile_ctx = re.pcre2_compile_context_create_8(general_context);

    const regex = re.pcre2_compile_8(pattern.regex.ptr, pattern.regex.len, 0, &errornumber, &erroroffset, compile_ctx) orelse {
        const len = 256;
        const buffer = backend_allocator.alloc(u8, len) catch {
            return grok.GrokError.MemoryAllocationError;
        };
        defer backend_allocator.free(buffer);
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

    const rc: c_int = re.pcre2_match_8(prepared.re, subject.ptr, subject.len, 0, 0, match_data, match_ctx);
    const matched = rc > 0;
    if (rc < 0) {
        std.debug.print("Return code: {d}\n", .{rc});
    }

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
            .properties = undefined,
        };
    }
}
