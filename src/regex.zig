const std = @import("std");
const front = @import("frontend.zig");
const re = @import("re");

/// A pattern structure that holds a regex string and its associated properties.
/// This represents a compiled pattern that can be used for matching against text.
pub const Pattern = struct {
    /// The regex pattern string
    regex: []const u8,
    /// List of property names that this pattern captures
    properties: std.ArrayList([:0]const u8),

    /// Release everything the pattern owns. `gpa` must be the allocator
    /// `createPattern` was given.
    pub fn deinit(self: *Pattern, gpa: std.mem.Allocator) void {
        for (self.properties.items) |prop| {
            gpa.free(prop);
        }
        self.properties.deinit(gpa);
        gpa.free(self.regex);
    }
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
    boxed_context: *AllocatorContext, // heap-owned
    general_context: *re.pcre2_general_context_8,
    /// Backing stack for the JIT-compiled code, null when running interpreted
    jit_stack: ?*re.pcre2_jit_stack_8,
    /// Capture group number per entry of `properties`, resolved once at prepare time
    capture_indices: []u32,
    /// Scratch for the last match, reused across subjects. Parallel to `properties`.
    capture_values: []?[]const u8,

    /// Match a prepared pattern against a subject string.
    ///
    /// `want_properties` skips capture extraction entirely when the caller will
    /// not read it, which is the case for every output mode but `-i` and `-j`.
    pub fn match(self: *Prepared, gpa: std.mem.Allocator, subject: []const u8, want_properties: bool) !MatchResult {
        var context: AllocatorContext = .{ .gpa = gpa };
        const general_ctx = createGeneralContext(&context) orelse return error.OutOfMemory;
        defer freeGeneralContext(general_ctx);

        const match_data = re.pcre2_match_data_create_from_pattern_8(self.re, general_ctx) orelse return error.OutOfMemory;
        defer re.pcre2_match_data_free_8(match_data);
        const match_ctx = re.pcre2_match_context_create_8(general_ctx) orelse return error.OutOfMemory;
        defer re.pcre2_match_context_free_8(match_ctx);
        if (self.jit_stack) |stack| {
            re.pcre2_jit_stack_assign_8(match_ctx, null, stack);
        }

        var rc: c_int = re.pcre2_match_8(self.re, subject.ptr, subject.len, 0, re.PCRE2_NOTEMPTY, match_data, match_ctx);
        if (rc == re.PCRE2_ERROR_JIT_STACKLIMIT) {
            // Backtracking outgrew the JIT stack; the interpreter has no such ceiling.
            rc = re.pcre2_match_8(self.re, subject.ptr, subject.len, 0, re.PCRE2_NOTEMPTY | re.PCRE2_NO_JIT, match_data, match_ctx);
        }
        // A failed allocation inside PCRE2 comes back as a negative code that
        // is easy to mistake for "did not match".
        if (context.oom) return error.OutOfMemory;
        const matched = rc > 0;

        var properties: ?Properties = null;
        if (want_properties and matched and self.properties.items.len > 0) {
            const ovector = re.pcre2_get_ovector_pointer_8(match_data);
            const ovector_count = re.pcre2_get_ovector_count_8(match_data);
            for (self.capture_indices, 0..) |group, i| {
                self.capture_values[i] = captureSlice(subject, ovector, ovector_count, group);
            }
            properties = .{ .names = self.properties.items, .values = self.capture_values };
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
        self.allocator.free(self.capture_indices);
        self.allocator.free(self.capture_values);
        self.allocator.free(self.regex);
        if (self.jit_stack) |stack| re.pcre2_jit_stack_free_8(stack);
        freeGeneralContext(self.general_context);
        self.allocator.destroy(self.boxed_context);
    }
};

/// Result of a regex match operation.
/// Contains information about whether the match was successful and any captured properties.
///
/// Nothing here owns memory. `original` is the subject the caller passed in, and
/// captured values are slices into it held by scratch storage inside `Prepared`.
/// Both stay valid only until the next call to `Prepared.match`.
pub const MatchResult = struct {
    /// Whether the pattern matched the subject text
    matched: bool,
    /// The original subject text that was matched against
    original: []const u8,
    /// Captured property names and values, or null when the caller did not ask for them
    properties: ?Properties,
};

/// Captured property names paired with their values, in the order the macro
/// declares them. A null value means the group did not participate in the match.
pub const Properties = struct {
    names: []const [:0]const u8,
    values: []const ?[]const u8,

    pub const Entry = struct {
        name: [:0]const u8,
        value: []const u8,
    };

    /// Iterates the groups that actually captured something, skipping the rest.
    pub fn iterator(self: Properties) Iterator {
        return .{ .properties = self };
    }

    pub const Iterator = struct {
        properties: Properties,
        index: usize = 0,

        pub fn next(self: *Iterator) ?Entry {
            while (self.index < self.properties.names.len) {
                const current = self.index;
                self.index += 1;
                if (self.properties.values[current]) |value| {
                    return .{ .name = self.properties.names[current], .value = value };
                }
            }
            return null;
        }
    };
};

/// `PCRE2_UNSET` is `~(PCRE2_SIZE)0`, which translate-c cannot render.
const PCRE2_UNSET: usize = std.math.maxInt(usize);

/// Marks a property whose capture group PCRE2 could not resolve by name.
const CAPTURE_UNAVAILABLE: u32 = std.math.maxInt(u32);

/// Slice `subject` down to what capture group `group` matched, or null if it did
/// not participate.
fn captureSlice(subject: []const u8, ovector: [*c]usize, ovector_count: u32, group: u32) ?[]const u8 {
    if (group == CAPTURE_UNAVAILABLE or group >= ovector_count) return null;
    const start = ovector[2 * group];
    const end = ovector[2 * group + 1];
    if (start == PCRE2_UNSET or end == PCRE2_UNSET) return null;
    if (start > end or end > subject.len) return null;
    return subject[start..end];
}

const AllocationHeader = extern struct {
    original_ptr: [*]u8,
    size: usize,
};

/// What PCRE2 carries around as opaque user data: the allocator to serve its
/// requests from, plus a note of whether one of them ever came back empty.
///
/// PCRE2 turns a failed allocation into an ordinary error code - compile error
/// 21, or a null context - which is indistinguishable from a malformed pattern,
/// so the callback has to record it here for the caller to tell the two apart.
const AllocatorContext = struct {
    gpa: std.mem.Allocator,
    oom: bool = false,
};

/// Custom allocator function for PCRE2 that ensures proper alignment.
fn pcre_alloc(size: usize, user_data: ?*anyopaque) callconv(.c) ?*anyopaque {
    const context: *AllocatorContext = @ptrCast(@alignCast(user_data.?));
    const header_size = @sizeOf(AllocationHeader);
    const total_size = header_size + size + 7;

    const raw_mem = context.gpa.alloc(u8, total_size) catch {
        context.oom = true;
        return null;
    };

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
        const context: *AllocatorContext = @ptrCast(@alignCast(user_data.?));
        const data_ptr = @as([*]u8, @ptrCast(p));
        const data_addr = @intFromPtr(data_ptr);

        const header_addr = data_addr - @sizeOf(AllocationHeader);
        const header = @as(*const AllocationHeader, @ptrFromInt(header_addr));

        const slice = header.original_ptr[0..header.size];
        context.gpa.free(slice);
    }
}

/// Create a PCRE2 general context bound to the given allocator context.
/// `context` must remain stable (same address) for the lifetime of the
/// returned context, since PCRE2 stores the pointer as opaque user data.
/// Null means the context itself could not be allocated.
fn createGeneralContext(context: *AllocatorContext) ?*re.pcre2_general_context_8 {
    return re.pcre2_general_context_create_8(&pcre_alloc, &pcre_free, context);
}

/// Free a context created by `createGeneralContext`.
fn freeGeneralContext(ctx: *re.pcre2_general_context_8) void {
    re.pcre2_general_context_free_8(ctx);
}

const StackItem = union(enum) {
    info: front.Info,
    expansion_end: []const u8,
};

/// Pick a capture group name that no group in the expansion uses yet.
///
/// The bare reference comes first, then `MACRO_reference` when the same name is
/// referenced twice, then the same with a numeric suffix. A name has to be unique
/// across the whole expansion: PCRE2 rejects a pattern holding two groups of the
/// same name unless PCRE2_DUPNAMES is set.
///
/// The returned name is owned by the caller.
fn uniqueReference(
    gpa: std.mem.Allocator,
    used_properties: *const std.StringHashMap(bool),
    macro: []const u8,
    reference: []const u8,
) ![:0]const u8 {
    if (!used_properties.contains(reference)) return gpa.dupeSentinel(u8, reference, 0);

    var name: std.ArrayList(u8) = .empty;
    errdefer name.deinit(gpa);
    try name.print(gpa, "{s}_{s}", .{ macro, reference });

    const base_len = name.items.len;
    var suffix: usize = 1;
    while (used_properties.contains(name.items)) : (suffix += 1) {
        name.shrinkRetainingCapacity(base_len);
        try name.print(gpa, "_{d}", .{suffix});
    }
    return name.toOwnedSliceSentinel(gpa, 0);
}

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
    errdefer result.deinit(gpa);
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
                        if (gop.found_existing) return error.CircularMacro;

                        const childs = try front.getPattern(current_slice);

                        if (current.reference) |current_reference| {
                            // leading (?<name> immediately into composition
                            try result.properties.ensureUnusedCapacity(gpa, 1);
                            const reference = try uniqueReference(
                                gpa,
                                &used_properties,
                                current_slice,
                                std.mem.span(current_reference),
                            );
                            // `used_properties` borrows the name, so the owner has to be
                            // recorded first: it outlives the map either way.
                            result.properties.appendAssumeCapacity(reference);
                            try used_properties.put(reference, true);

                            try composition.appendSlice(gpa, "(?<");
                            try composition.appendSlice(gpa, reference);
                            try composition.appendSlice(gpa, ">");

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

/// Render a PCRE2 error code into `buffer` and return just the written part.
/// `pcre2_get_error_message_8` reports the length but leaves the rest of the
/// buffer untouched, so the whole array must never be printed.
fn errorMessage(errornumber: c_int, buffer: []u8) []const u8 {
    const len = re.pcre2_get_error_message_8(errornumber, buffer.ptr, buffer.len);
    if (len < 0) return "unknown error";
    return buffer[0..@intCast(len)];
}

/// Starting size of the JIT stack. PCRE2 grows it on demand up to JIT_STACK_MAX_SIZE.
const JIT_STACK_START_SIZE: usize = 32 * 1024;
/// Ceiling for the JIT stack. Beyond it matching falls back to the interpreter.
const JIT_STACK_MAX_SIZE: usize = 1024 * 1024;

/// Prepare a pattern for matching by compiling it with PCRE2.
/// This function takes a Pattern and compiles it into a PCRE2 regex object
/// that can be used for matching operations.
///
/// `gpa` The allocator to use for memory allocations
/// `pattern` The Pattern to compile. `prepare` takes ownership of it on every
/// path: what it does not hand over to the returned `Prepared` it releases,
/// including when it fails, so the caller must never free it itself.
/// `jit` Whether to additionally JIT-compile the pattern. Worth roughly 10x per
/// match but costs about a millisecond up front, so it only pays off when many
/// subjects are matched. A failed JIT compilation is not fatal: PCRE2 keeps
/// matching with the interpreter.
/// @return A Prepared struct containing the compiled regex and properties, or an error
pub fn prepare(gpa: std.mem.Allocator, pattern: Pattern, jit: bool) !Prepared {
    var owned = pattern;
    errdefer owned.deinit(gpa);

    const boxed_context = try gpa.create(AllocatorContext);
    boxed_context.* = .{ .gpa = gpa };
    errdefer gpa.destroy(boxed_context);

    const general_ctx = createGeneralContext(boxed_context) orelse return error.OutOfMemory;
    errdefer freeGeneralContext(general_ctx);

    var errornumber: c_int = undefined;
    var erroroffset: re.PCRE2_SIZE = undefined;
    const compile_ctx = re.pcre2_compile_context_create_8(general_ctx) orelse return error.OutOfMemory;
    defer re.pcre2_compile_context_free_8(compile_ctx);

    const regex = re.pcre2_compile_8(owned.regex.ptr, owned.regex.len, 0, &errornumber, &erroroffset, compile_ctx) orelse {
        // PCRE2 reports a failed allocation as compile error 21, which reads
        // exactly like a malformed pattern. Only the callback knows better.
        if (boxed_context.oom) return error.OutOfMemory;

        var buffer: [256]u8 = undefined;
        const message = errorMessage(errornumber, &buffer);
        std.log.warn("PCRE2 compilation failed at offset {d}: {s}\nProblem regexp: {s}", .{ erroroffset, message, owned.regex });
        return error.InvalidRegex;
    };
    errdefer re.pcre2_code_free_8(regex);

    const capture_indices = try gpa.alloc(u32, owned.properties.items.len);
    errdefer gpa.free(capture_indices);
    const capture_values = try gpa.alloc(?[]const u8, owned.properties.items.len);
    errdefer gpa.free(capture_values);
    for (owned.properties.items, 0..) |name, i| {
        const number = re.pcre2_substring_number_from_name_8(regex, name.ptr);
        capture_indices[i] = if (number > 0) @intCast(number) else CAPTURE_UNAVAILABLE;
        capture_values[i] = null;
    }

    return .{
        .re = regex,
        .properties = owned.properties,
        .regex = owned.regex,
        .allocator = gpa,
        .boxed_context = boxed_context,
        .general_context = general_ctx,
        .jit_stack = if (jit) jitCompile(regex, general_ctx) else null,
        .capture_indices = capture_indices,
        .capture_values = capture_values,
    };
}

/// JIT-compile `regex` and return a stack for it, or null if the JIT is
/// unavailable. PCRE2 silently keeps using the interpreter in that case.
fn jitCompile(regex: *re.pcre2_code_8, general_ctx: *re.pcre2_general_context_8) ?*re.pcre2_jit_stack_8 {
    const rc = re.pcre2_jit_compile_8(regex, re.PCRE2_JIT_COMPLETE);
    if (rc != 0) {
        var buffer: [256]u8 = undefined;
        std.log.warn("PCRE2 JIT compilation failed, falling back to the interpreter: {s}", .{errorMessage(rc, &buffer)});
        return null;
    }
    return re.pcre2_jit_stack_create_8(JIT_STACK_START_SIZE, JIT_STACK_MAX_SIZE, general_ctx);
}

test "createPattern detects circular macros" {
    const gpa = std.testing.allocator;
    front.deinitLib();
    defer front.deinitLib();

    var paths_buf = [_][]const u8{"./test_assets/circular.patterns"};
    const paths: [][]const u8 = paths_buf[0..];
    try front.compileLib(gpa, std.testing.io, paths);

    try std.testing.expectError(error.CircularMacro, createPattern(gpa, "CYCLEA"));
    try std.testing.expectError(error.CircularMacro, createPattern(gpa, "CYCLEB"));
    try std.testing.expectError(error.CircularMacro, createPattern(gpa, "SELFREF"));
}

test "createPattern gives every repeated reference a unique name" {
    const gpa = std.testing.allocator;
    front.deinitLib();
    defer front.deinitLib();

    var paths_buf = [_][]const u8{"./test_assets/duplicate_reference.patterns"};
    const paths: [][]const u8 = paths_buf[0..];
    try front.compileLib(gpa, std.testing.io, paths);

    const cases = [_]struct { macro: []const u8, names: []const []const u8 }{
        .{ .macro = "DUPTWO", .names = &.{ "x", "WORDY_x" } },
        .{ .macro = "DUPTHREE", .names = &.{ "x", "WORDY_x", "WORDY_x_1" } },
        .{ .macro = "DUPCLASH", .names = &.{ "x", "WORDY_x", "WORDY_WORDY_x" } },
    };

    for (cases) |case| {
        const pattern = try createPattern(gpa, case.macro);
        // prepare() takes ownership of the pattern and would reject duplicate
        // group names with error.InvalidRegex.
        var prepared = try prepare(gpa, pattern, false);
        defer prepared.deinit();

        try std.testing.expectEqual(case.names.len, prepared.properties.items.len);
        for (case.names, prepared.properties.items, prepared.capture_indices) |expected, actual, group| {
            try std.testing.expectEqualStrings(expected, actual);
            try std.testing.expect(group != CAPTURE_UNAVAILABLE);
        }
    }
}

/// One full pattern lifecycle, for `checkAllAllocationFailures` to replay with
/// every allocation in it failing in turn.
fn preparedRoundTrip(gpa: std.mem.Allocator, macro: []const u8) !void {
    const pattern = try createPattern(gpa, macro);
    var prepared = try prepare(gpa, pattern, false);
    defer prepared.deinit();

    _ = try prepared.match(gpa, "a b c", true);
}

test "no allocation failure leaks or panics" {
    const gpa = std.testing.allocator;
    front.deinitLib();
    defer front.deinitLib();

    var paths_buf = [_][]const u8{"./test_assets/duplicate_reference.patterns"};
    const paths: [][]const u8 = paths_buf[0..];
    try front.compileLib(gpa, std.testing.io, paths);

    try std.testing.checkAllAllocationFailures(gpa, preparedRoundTrip, .{"DUPTHREE"});
}
