const std = @import("std");

const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("grok.h");
    @cInclude("grok.tab.h");
});

pub const Info = struct {
    data: [*c]const u8,
    reference: [*c]const u8,
    part: Part,
};

pub const Part = enum { literal, reference };

pub fn compile_file(path: [*c]const u8) !void {
    const c_file_ptr = c.fopen(path, "r");

    if (c_file_ptr == null) {
        // Handle error
        std.debug.print("Failed to open file: {s}\n", .{path});
        return;
    }

    c.yyrestart(c_file_ptr);
    if (c.yyparse() > 0) {
        std.debug.print("Failed to parse file: {s}\n", .{path});
    }
}

var allocator: std.mem.Allocator = undefined;
var composition: std.ArrayList(Info) = undefined;

pub fn init(a: std.mem.Allocator) void {
    allocator = a;
}

pub export fn fend_on_literal(str: [*c]const u8) void {
    composition.append(allocator, .{ .data = str, .reference = null, .part = .literal }) catch |e| {
        std.debug.print("Error: {t}\n", .{e});
    };
}

pub export fn fend_on_definition() void {
    composition = std.ArrayList(Info){};
}

pub export fn fend_on_definition_end(str: [*c]const u8) void {
    std.debug.print("Definition end: {s}\n", .{str});
}

pub export fn fend_strdup(str: [*c]const u8) [*c]const u8 {
    const slice = std.mem.span(str);

    // Allocate memory for string + null terminator
    const mem = allocator.alloc(u8, slice.len + 1) catch return null;
    @memcpy(mem[0..slice.len], slice);
    mem[slice.len] = 0; // Null terminator
    return @ptrCast(mem.ptr);
}

pub export fn fend_on_macro(name: [*c]u8, property: [*c]u8) *c.macro_t {
    var m = c.macro_t{ .name = name, .property = property };
    return &m;
}

pub export fn fend_on_grok(m: *c.macro_t) void {
    composition.append(allocator, .{ .data = m.name, .reference = m.property, .part = .reference }) catch |e| {
        std.debug.print("Error: {t}\n", .{e});
    };
}
