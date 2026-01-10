const std = @import("std");
const front = @import("frontend.zig");
const grok = @import("grok.zig");
const re = @cImport({
    @cDefine("PCRE2_CODE_UNIT_WIDTH", "8");
    @cInclude("pcre2.h");
});

/// A pattern structure that holds a regex string and its associated properties.
/// This represents a compiled pattern that can be used for matching against text.
pub const Pattern = struct {
    /// The regex pattern string
    regex: []const u8,
    /// List of property names that this pattern captures
    properties: std.ArrayList([]const u8),
};

/// A prepared pattern that has been compiled and is ready for matching.
/// This contains the compiled PCRE2 regex object and associated properties.
pub const Prepared = struct {
    /// Pointer to the compiled PCRE2 code
    re: *re.pcre2_code_8,
    /// List of property names that this pattern captures
    properties: std.ArrayList([]const u8),
};

/// Result of a regex match operation.
/// Contains information about whether the match was successful and any captured properties.
pub const MatchResult = struct {
    /// Whether the pattern matched the subject text
    matched: bool,
    /// The original subject text that was matched against
    original: []const u8,
    /// Optional map of captured property names to their values
    properties: ?std.StringHashMap([]const u8),
};

var backend_allocator: std.mem.Allocator = undefined;
var general_context: *re.pcre2_general_context_8 = undefined;

/// Initialize the regex module with the given allocator.
/// This sets up the PCRE2 context and allocator for subsequent operations.
///
/// `gpa` The allocator to use for memory allocations
pub fn init(gpa: std.mem.Allocator) void {
    backend_allocator = gpa;
    general_context = re.pcre2_general_context_create_8(&pcre_alloc, &pcre_free, null).?;
}

const AllocationHeader = extern struct {
    original_ptr: [*]u8,
    size: usize,
};

/// Custom allocator function for PCRE2 that ensures proper alignment.
/// This function allocates memory with a header for tracking and ensures
/// 8-byte alignment for the data portion.
///
/// `size` The size of memory to allocate
/// _: Unused parameter (PCRE2 context)
/// @return Pointer to the allocated memory or null on failure
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

/// Custom deallocator function for PCRE2 that frees memory allocated by pcre_alloc.
/// This function retrieves the original allocation information from the header
/// and frees the entire memory block.
///
/// `ptr` Pointer to the memory to free
/// _: Unused parameter (PCRE2 context)
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

/// Create a pattern from a macro string by processing nested patterns and references.
/// This function expands macros and creates a regex pattern with named capture groups.
///
/// `gpa` The allocator to use for memory allocations
/// `macro` The macro string to process
/// @return A Pattern struct containing the processed regex and properties, or an error
pub fn createPattern(gpa: std.mem.Allocator, macro: []const u8) !Pattern {
    const m = try front.getPattern(macro);
    var stack: std.ArrayList(front.Info) = .empty;
    var composition: std.ArrayList(u8) = .empty;
    var used_properties = std.StringHashMap(bool).init(gpa);
    var result = Pattern{ .properties = .empty, .regex = "" };
    for (m.items) |value| {
        try stack.append(gpa, value);
        while (stack.pop()) |current| {
            const current_slice = std.mem.span(current.data);
            if (current.part == .literal) {
                // plain literal case
                try composition.appendSlice(gpa, current_slice);
            } else {
                if (current.reference) |current_reference| {
                    // leading (?<name> immediately into composition
                    var reference = std.mem.span(current_reference);
                    if (used_properties.contains(reference)) {
                        var concat: std.ArrayList(u8) = .empty;
                        try concat.appendSlice(gpa, current_slice);
                        try concat.appendSlice(gpa, "_");
                        try concat.appendSlice(gpa, reference);
                        try concat.append(gpa, 0);
                        reference = concat.items[0 .. concat.items.len - 1 :0];
                    }
                    try used_properties.put(reference, true);

                    try composition.appendSlice(gpa, "(?<");
                    try composition.appendSlice(gpa, reference);
                    try composition.appendSlice(gpa, ">");
                    try result.properties.append(gpa, reference);

                    // trailing ) into stack bottom
                    const trail_paren = front.Info{ .data = ")", .reference = null, .part = .literal };
                    try stack.append(gpa, trail_paren);
                }
                const childs = front.getPattern(current_slice) catch {
                    continue;
                };
                var rev_iter = std.mem.reverseIterator(childs.items);
                while (rev_iter.next()) |child| {
                    try stack.append(gpa, child);
                }
            }
        }
    }
    result.regex = composition.items;
    return result;
}

/// Prepare a pattern for matching by compiling it with PCRE2.
/// This function takes a Pattern and compiles it into a PCRE2 regex object
/// that can be used for matching operations.
///
/// `pattern` The Pattern to compile
/// @return A Prepared struct containing the compiled regex and properties, or an error
pub fn prepare(pattern: Pattern) !Prepared {
    var errornumber: c_int = undefined;
    var erroroffset: re.PCRE2_SIZE = undefined;

    const compile_ctx = re.pcre2_compile_context_create_8(general_context);
    defer re.pcre2_compile_context_free_8(compile_ctx);

    const regex = re.pcre2_compile_8(pattern.regex.ptr, pattern.regex.len, 0, &errornumber, &erroroffset, compile_ctx) orelse {
        const len = 256;
        const buffer = try backend_allocator.alloc(u8, len);
        defer backend_allocator.free(buffer);
        _ = re.pcre2_get_error_message_8(errornumber, buffer.ptr, len);
        std.debug.print("PCRE2 compilation failed at offset {d}: {s}\nProblem regexp: {s}\n", .{ erroroffset, buffer, pattern.regex });
        return grok.GrokError.InvalidRegex;
    };
    return Prepared{
        .re = regex,
        .properties = pattern.properties,
    };
}

/// Match a prepared pattern against a subject string.
/// This function performs the actual regex matching and extracts any captured properties.
///
/// `gpa` The allocator to use for memory allocations
/// `prepared` The prepared pattern to match against
/// `subject` The subject string to match
/// @return A MatchResult containing the match status and captured properties
pub fn match(gpa: std.mem.Allocator, prepared: *const Prepared, subject: []const u8) MatchResult {
    backend_allocator = gpa; // IMPORTANT
    const match_data = re.pcre2_match_data_create_from_pattern_8(prepared.re, general_context);
    defer re.pcre2_match_data_free_8(match_data);
    const match_ctx = re.pcre2_match_context_create_8(general_context);
    defer re.pcre2_match_context_free_8(match_ctx);

    const rc: c_int = re.pcre2_match_8(prepared.re, subject.ptr, subject.len, 0, re.PCRE2_NOTEMPTY, match_data, match_ctx);
    const matched = rc > 0;

    var properties: ?std.StringHashMap([]const u8) = null;
    if (matched and prepared.properties.items.len > 0) {
        properties = std.StringHashMap([]const u8).init(gpa);
        for (prepared.properties.items) |value| {
            var buffer: [*c]re.PCRE2_UCHAR8 = undefined;
            var buffer_size_in_chars: re.PCRE2_SIZE = undefined;
            const get_string_result = re.pcre2_substring_get_byname_8(match_data, value.ptr, &buffer, &buffer_size_in_chars);
            if (get_string_result == 0) {
                properties.?.put(value, std.mem.span(buffer)) catch {
                    continue;
                };
            }
        }
    }
    return MatchResult{
        .matched = matched,
        .original = subject,
        .properties = properties,
    };
}
