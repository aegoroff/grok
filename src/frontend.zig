const std = @import("std");

const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("grok.h");
    @cInclude("grok.tab.h");
});

pub fn compile_file(path: [*c]const u8) !void {
    const c_file_ptr = c.fopen(path, "r");

    if (c_file_ptr == null) {
        // Handle error
        std.debug.print("Failed to open file: {s}\n", .{path});
    }

    c.yyrestart(c_file_ptr);
    if (c.yyparse() > 0) {
        std.debug.print("Failed to parse file: {s}\n", .{path});
    }
}

pub export fn fend_on_literal(str: [*c]const u8) void {
    std.debug.print("Literal: {s}\n", .{str});
}

pub export fn fend_on_definition() void {
    std.debug.print("Definition\n", .{});
}

pub export fn fend_on_definition_end(str: [*c]const u8) void {
    std.debug.print("Definition end: {s}\n", .{str});
}

pub export fn fend_strdup(str: [*c]const u8) [*c]const u8 {
    std.debug.print("fend_strdup: {s}\n", .{str});
    return str;
}

pub export fn fend_on_macro(name: [*c]u8, property: [*c]u8) *c.macro_t {
    std.debug.print("Macro name: {s}", .{name});
    if (property != null) {
        std.debug.print(" Macro property: {s}\n", .{property});
    } else {
        std.debug.print("\n", .{});
    }
    var m = c.macro_t{ .name = name, .property = property };
    return &m;
}

pub export fn fend_on_grok(m: *c.macro_t) void {
    std.debug.print("On grok: {s}\n", .{m.name});
}
