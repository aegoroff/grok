const std = @import("std");
const builtin = @import("builtin");
const grok = @import("grok.zig");
const glob = @import("glob");

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

var allocator: std.mem.Allocator = undefined;
var composition: std.ArrayList(Info) = undefined;
var definitions: std.StringHashMap(std.ArrayList(Info)) = undefined;

pub fn getPattern(key: []const u8) grok.GrokError!std.ArrayList(Info) {
    return definitions.get(key) orelse grok.GrokError.UnknownMacro;
}

pub fn getPatterns() std.StringHashMap(std.ArrayList(Info)) {
    return definitions;
}

pub fn compileLib(gpa: std.mem.Allocator, paths: ?[][]const u8) !void {
    allocator = gpa;
    definitions = std.StringHashMap(std.ArrayList(Info)).init(allocator);
    if (paths) |path_arg| {
        if (path_arg.len == 0) {
            try compileDefault();
        } else {
            for (path_arg) |path| {
                compileDir(path) catch {
                    try compileFile(path.ptr);
                };
            }
        }
    } else {
        try compileDefault();
    }
}

fn compileDefault() !void {
    var lib_path: []const u8 = undefined;
    if (builtin.os.tag == .linux) {
        lib_path = "/usr/share/grok/patterns";
    } else {
        lib_path = try std.fs.selfExeDirPathAlloc(allocator);
    }

    try compileDir(lib_path);
}

fn compileDir(lib_path: []const u8) !void {
    var dir: std.fs.Dir = undefined;
    const options: std.fs.Dir.OpenOptions = .{ .iterate = true };
    if (std.fs.path.isAbsolute(lib_path)) {
        dir = try std.fs.openDirAbsolute(lib_path, options);
    } else {
        dir = try std.fs.cwd().openDir(lib_path, options);
    }
    var walker = try dir.walk(allocator);
    defer walker.deinit();
    while (true) {
        const entry_or_null = walker.next() catch {
            continue;
        };
        const entry = entry_or_null orelse {
            break;
        };
        switch (entry.kind) {
            std.fs.Dir.Entry.Kind.file => {
                const matches = glob.match("*.patterns", entry.basename);
                if (matches) {
                    const p = try entry.dir.realpathAlloc(allocator, entry.basename);
                    try compileFile(p.ptr);
                }
            },
            else => {},
        }
    }
}

fn compileFile(path: [*c]const u8) !void {
    const c_file_ptr = c.fopen(path, "r") orelse {
        // Handle error
        std.debug.print("Failed to open file: {s}\n", .{path});
        return grok.GrokError.UnknownPatternFile;
    };
    defer _ = c.fclose(c_file_ptr);

    c.yyrestart(c_file_ptr);
    if (c.yyparse() > 0) {
        std.debug.print("Failed to parse file: {s}\n", .{path});
        return grok.GrokError.InvalidPatternFile;
    }
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
