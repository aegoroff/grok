const std = @import("std");
const grok = @import("grok.zig");

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

pub fn compileFile(path: [*c]const u8) !void {
    const c_file_ptr = c.fopen(path, "r") orelse {
        // Handle error
        std.debug.print("Failed to open file: {s}\n", .{path});
        return grok.GrokError.UnknownPatternFile;
    };

    c.yyrestart(c_file_ptr);
    if (c.yyparse() > 0) {
        std.debug.print("Failed to parse file: {s}\n", .{path});
        return grok.GrokError.InvalidPatternFile;
    }
}

var allocator: std.mem.Allocator = undefined;
var composition: std.ArrayList(Info) = undefined;
var definitions: std.StringHashMap(std.ArrayList(Info)) = undefined;

pub fn init(a: std.mem.Allocator) void {
    allocator = a;
    definitions = std.StringHashMap(std.ArrayList(Info)).init(allocator);
}

pub export fn fend_on_literal(str: [*c]const u8) void {
    composition.append(allocator, Info{
        .data = str,
        .reference = null,
        .part = .literal,
    }) catch |e| {
        std.debug.print("Error: {t}\n", .{e});
    };
}

pub export fn fend_on_definition() void {
    composition = std.ArrayList(Info){};
}

pub export fn fend_on_definition_end(str: [*c]const u8) void {
    const slice = std.mem.span(str);
    const len = slice.len;
    definitions.put(slice[0..len], composition) catch |e| {
        std.debug.print("Error: {t}\n", .{e});
    };
}

pub export fn fend_strdup(str: [*c]const u8) [*c]const u8 {
    const slice = std.mem.span(str);

    // Allocate memory for string + null terminator
    const mem = allocator.alloc(u8, slice.len + 1) catch return null;
    @memcpy(mem[0..slice.len], slice);
    mem[slice.len] = 0; // Null terminator
    return @ptrCast(mem.ptr);
}

pub export fn fend_on_macro(name: [*c]u8, property: [*c]u8) ?*c.macro_t {
    const ptr = allocator.create(c.macro_t) catch return null;
    ptr.* = c.macro_t{
        .name = name,
        .property = property,
    };
    return ptr;
}

pub export fn fend_on_grok(m: *c.macro_t) void {
    composition.append(allocator, Info{
        .data = m.name,
        .reference = m.property,
        .part = .reference,
    }) catch |e| {
        std.debug.print("Error: {t}\n", .{e});
    };
}

pub fn getPattern(key: []const u8) grok.GrokError!std.ArrayList(Info) {
    return definitions.get(key) orelse grok.GrokError.UnknownMacro;
}

pub fn getPatterns() std.StringHashMap(std.ArrayList(Info)) {
    return definitions;
}
