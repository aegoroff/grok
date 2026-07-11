const std = @import("std");
const front = @import("frontend.zig");
const grok = @import("grok.zig");
const re = @import("re");

/// A pattern structure that holds a regex string and its associated properties.
/// This represents a compiled pattern that can be used for matching against text.
pub const Pattern = struct {
    /// The regex pattern string
    regex: []const u8,
    /// List of property names that this pattern captures
    properties: std.ArrayList([:0]const u8),
};

/// A prepared pattern that has been compiled and is ready for matching.
/// This contains the compiled PCRE2 regex object and associated properties.
pub const Prepared = struct {
    /// Pointer to the compiled PCRE2 code
    re: *re.pcre2_code_8,
    /// List of property names that this pattern captures
    properties: std.ArrayList([:0]const u8),
    regex: []const u8,
    /// Allocator used to prepare this pattern - stored for proper deallocation
    allocator: std.mem.Allocator,
    boxed_allocator: *std.mem.Allocator, // heap-owned
    general_context: *re.pcre2_general_context_8,

    /// Match a prepared pattern against a subject string.
    pub fn match(self: *const Prepared, gpa: std.mem.Allocator, subject: []const u8) MatchResult {
        var call_allocator = gpa;
        const general_ctx = createGeneralContext(&call_allocator).?;
        defer freeGeneralContext(general_ctx);

        const match_data = re.pcre2_match_data_create_from_pattern_8(self.re, general_ctx);
        defer re.pcre2_match_data_free_8(match_data);
        const match_ctx = re.pcre2_match_context_create_8(general_ctx);
        defer re.pcre2_match_context_free_8(match_ctx);

        const rc: c_int = re.pcre2_match_8(self.re, subject.ptr, subject.len, 0, re.PCRE2_NOTEMPTY, match_data, match_ctx);
        const matched = rc > 0;

        var properties: ?std.StringHashMap([]const u8) = null;
        if (matched and self.properties.items.len > 0) {
            properties = std.StringHashMap([]const u8).init(gpa);
            for (self.properties.items) |value| {
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
        return .{
            .matched = matched,
            .original = subject,
            .properties = properties,
        };
    }

    pub fn deinit(self: *Prepared) void {
        re.pcre2_code_free_8(self.re);
        for (self.properties.items) |prop| {
            self.allocator.free(prop);
        }
        self.properties.deinit(self.allocator);
        self.allocator.free(self.regex);
        freeGeneralContext(self.general_context);
        self.allocator.destroy(self.boxed_allocator);
    }
};

/// Result of a regex match operation.
/// Contains information about whether the match was successful and any captured properties.
///
/// Captured property values point into memory allocated by the `gpa` passed to
/// `Prepared.match`. The caller should use an arena (or otherwise reclaim that
/// allocator in bulk). `StringHashMap.deinit` on `properties` frees only the map
/// nodes, not the captured value slices.
pub const MatchResult = struct {
    /// Whether the pattern matched the subject text
    matched: bool,
    /// The original subject text that was matched against
    original: []const u8,
    /// Optional map of captured property names to their values
    properties: ?std.StringHashMap([]const u8),
};

const AllocationHeader = extern struct {
    original_ptr: [*]u8,
    size: usize,
};

/// Custom allocator function for PCRE2 that ensures proper alignment.
fn pcre_alloc(size: usize, user_data: ?*anyopaque) callconv(.c) ?*anyopaque {
    const allocator: *std.mem.Allocator = @ptrCast(@alignCast(user_data.?));
    const header_size = @sizeOf(AllocationHeader);
    const total_size = header_size + size + 7;

    const raw_mem = allocator.alloc(u8, total_size) catch return null;

    const data_start_ptr = raw_mem.ptr + header_size;
    const data_start_addr = @intFromPtr(data_start_ptr);
    const aligned_data_addr = std.mem.alignForward(usize, data_start_addr, 8);
    const aligned_data_ptr = @as([*]u8, @ptrFromInt(aligned_data_addr));

    const header_addr = aligned_data_addr - header_size;
    const header_ptr = @as(*AllocationHeader, @ptrFromInt(header_addr));
    header_ptr.* = .{
        .original_ptr = raw_mem.ptr,
        .size = total_size,
    };

    return @ptrCast(aligned_data_ptr);
}

/// Custom deallocator function for PCRE2 that frees memory allocated by pcre_alloc.
fn pcre_free(ptr: ?*anyopaque, user_data: ?*anyopaque) callconv(.c) void {
    if (ptr) |p| {
        const allocator: *std.mem.Allocator = @ptrCast(@alignCast(user_data.?));
        const data_ptr = @as([*]u8, @ptrCast(p));
        const data_addr = @intFromPtr(data_ptr);

        const header_addr = data_addr - @sizeOf(AllocationHeader);
        const header = @as(*const AllocationHeader, @ptrFromInt(header_addr));

        const slice = header.original_ptr[0..header.size];
        allocator.free(slice);
    }
}

/// Create a PCRE2 general context bound to the given allocator.
/// `allocator` must remain stable (same address) for the lifetime of the
/// returned context, since PCRE2 stores the pointer as opaque user data.
fn createGeneralContext(allocator: *std.mem.Allocator) ?*re.pcre2_general_context_8 {
    return re.pcre2_general_context_create_8(&pcre_alloc, &pcre_free, allocator);
}

/// Free a context created by `createGeneralContext`.
fn freeGeneralContext(ctx: *re.pcre2_general_context_8) void {
    re.pcre2_general_context_free_8(ctx);
}

const StackItem = union(enum) {
    info: front.Info,
    expansion_end: []const u8,
};

/// Create a pattern from a macro string by processing nested patterns and references.
/// This function expands macros and creates a regex pattern with named capture groups.
///
/// `gpa` The allocator to use for memory allocations
/// `macro` The macro string to process
/// @return A Pattern struct containing the processed regex and properties, or an error
pub fn createPattern(gpa: std.mem.Allocator, macro: []const u8) !Pattern {
    const m = try front.getPattern(macro);
    var stack: std.ArrayList(StackItem) = .empty;
    defer stack.deinit(gpa);
    var expanding = std.StringHashMap(void).init(gpa);
    defer expanding.deinit();
    var composition: std.ArrayList(u8) = .empty;
    defer composition.deinit(gpa);
    var used_properties = std.StringHashMap(bool).init(gpa);
    defer used_properties.deinit();
    var result = Pattern{ .properties = .empty, .regex = "" };
    errdefer {
        for (result.properties.items) |prop| {
            gpa.free(prop);
        }
        result.properties.deinit(gpa);
    }
    for (m.items) |value| {
        try stack.append(gpa, .{ .info = value });
        while (stack.pop()) |item| {
            switch (item) {
                .expansion_end => |macro_name| {
                    _ = expanding.remove(macro_name);
                },
                .info => |current| {
                    const current_slice = std.mem.span(current.data);
                    if (current.part == .literal) {
                        try composition.appendSlice(gpa, current_slice);
                    } else {
                        const gop = try expanding.getOrPut(current_slice);
                        if (gop.found_existing) return grok.GrokError.CircularMacro;

                        const childs = try front.getPattern(current_slice);

                        if (current.reference) |current_reference| {
                            // leading (?<name> immediately into composition
                            var reference = std.mem.span(current_reference);
                            var concat: std.ArrayList(u8) = .empty;
                            defer concat.deinit(gpa);

                            if (used_properties.contains(reference)) {
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

                            const owned = try gpa.dupeSentinel(u8, reference, 0);
                            try result.properties.append(gpa, owned);

                            // trailing ) into stack bottom
                            const trail_paren = front.Info{ .data = ")", .reference = null, .part = .literal };
                            try stack.append(gpa, .{ .info = trail_paren });
                        }
                        try stack.append(gpa, .{ .expansion_end = current_slice });
                        var rev_iter = std.mem.reverseIterator(childs.items);
                        while (rev_iter.next()) |child| {
                            try stack.append(gpa, .{ .info = child });
                        }
                    }
                },
            }
        }
    }
    result.regex = try composition.toOwnedSlice(gpa);
    return result;
}

/// Prepare a pattern for matching by compiling it with PCRE2.
/// This function takes a Pattern and compiles it into a PCRE2 regex object
/// that can be used for matching operations.
///
/// `gpa` The allocator to use for memory allocations
/// `pattern` The Pattern to compile
/// @return A Prepared struct containing the compiled regex and properties, or an error
pub fn prepare(gpa: std.mem.Allocator, pattern: Pattern) !Prepared {
    const boxed_allocator = try gpa.create(std.mem.Allocator);
    boxed_allocator.* = gpa;
    errdefer gpa.destroy(boxed_allocator);

    const general_ctx = createGeneralContext(boxed_allocator).?;
    errdefer freeGeneralContext(general_ctx);

    var errornumber: c_int = undefined;
    var erroroffset: re.PCRE2_SIZE = undefined;
    const compile_ctx = re.pcre2_compile_context_create_8(general_ctx);
    defer re.pcre2_compile_context_free_8(compile_ctx);

    const regex = re.pcre2_compile_8(pattern.regex.ptr, pattern.regex.len, 0, &errornumber, &erroroffset, compile_ctx) orelse {
        var buffer: [256]u8 = undefined;
        _ = re.pcre2_get_error_message_8(errornumber, &buffer, buffer.len);
        std.log.warn("PCRE2 compilation failed at offset {d}: {s}\nProblem regexp: {s}", .{ erroroffset, buffer, pattern.regex });

        var props = pattern.properties;
        for (props.items) |prop| {
            gpa.free(prop);
        }
        props.deinit(gpa);
        gpa.free(pattern.regex);

        return grok.GrokError.InvalidRegex;
    };
    return .{
        .re = regex,
        .properties = pattern.properties,
        .regex = pattern.regex,
        .allocator = gpa,
        .boxed_allocator = boxed_allocator,
        .general_context = general_ctx,
    };
}

test "createPattern detects circular macros" {
    const gpa = std.testing.allocator;
    front.deinitLib();
    defer front.deinitLib();

    var paths_buf = [_][]const u8{"./test_assets/circular.patterns"};
    const paths: [][]const u8 = paths_buf[0..];
    try front.compileLib(gpa, std.testing.io, paths);

    try std.testing.expectError(grok.GrokError.CircularMacro, createPattern(gpa, "CYCLEA"));
    try std.testing.expectError(grok.GrokError.CircularMacro, createPattern(gpa, "CYCLEB"));
    try std.testing.expectError(grok.GrokError.CircularMacro, createPattern(gpa, "SELFREF"));
}
