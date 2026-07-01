const std = @import("std");
const builtin = @import("builtin");
const grok = @import("grok.zig");
const glob = @import("glob");
const c = @import("c");

pub const Info = struct {
    data: [*c]const u8,
    reference: [*c]const u8,
    part: Part,
};

pub const Part = enum { literal, reference };

var allocator: std.mem.Allocator = undefined;
var composition: std.ArrayList(Info) = .empty;
var definitions: std.StringHashMap(std.ArrayList(Info)) = undefined;
var lib_initialized: bool = false;

pub fn getPattern(key: []const u8) grok.GrokError!std.ArrayList(Info) {
    return definitions.get(key) orelse grok.GrokError.UnknownMacro;
}

pub fn getPatterns() std.StringHashMap(std.ArrayList(Info)) {
    return definitions;
}

pub fn compileLib(gpa: std.mem.Allocator, io: std.Io, paths: ?[][]const u8) !void {
    allocator = gpa;
    definitions = std.StringHashMap(std.ArrayList(Info)).init(allocator);
    lib_initialized = true;
    if (paths) |path_arg| {
        if (path_arg.len == 0) {
            try compileDefault(io);
        } else {
            for (path_arg) |path| {
                compileDir(io, path) catch {
                    const pathz = try allocator.dupeSentinel(u8, path, 0);
                    defer allocator.free(pathz);
                    try compileFile(pathz);
                };
            }
        }
    } else {
        try compileDefault(io);
    }
}

/// Releases everything compileLib accumulated in the global pattern table.
/// Safe to call even if compileLib was never invoked (e.g. bad-args test path).
pub fn deinitLib() void {
    if (!lib_initialized) return;

    var it = definitions.iterator();
    while (it.next()) |entry| {
        for (entry.value_ptr.items) |info| {
            allocator.free(std.mem.span(info.data));
            if (info.reference) |r| {
                allocator.free(std.mem.span(r));
            }
        }
        entry.value_ptr.deinit(allocator);

        const key = entry.key_ptr.*;
        allocator.free(key.ptr[0 .. key.len + 1]); // +1: compensate sentinel byte, lost under `slice[0..len]` in fend_on_definition_end
    }
    definitions.deinit();
    composition = .empty;
    lib_initialized = false;
}

fn compileDefault(io: std.Io) !void {
    var lib_path: []const u8 = undefined;
    if (builtin.os.tag == .linux) {
        lib_path = "/usr/share/grok/patterns";
    } else {
        lib_path = try std.process.executableDirPathAlloc(io, allocator);
    }

    try compileDir(io, lib_path);
}

fn compileDir(io: std.Io, lib_path: []const u8) !void {
    var dir: std.Io.Dir = undefined;
    const options: std.Io.Dir.OpenOptions = .{ .iterate = true };
    if (std.fs.path.isAbsolute(lib_path)) {
        dir = try std.Io.Dir.openDirAbsolute(io, lib_path, options);
    } else {
        dir = try std.Io.Dir.cwd().openDir(io, lib_path, options);
    }
    var walker = try dir.walk(allocator);
    defer walker.deinit();
    while (true) {
        const entry_or_null = walker.next(io) catch |walk_err| {
            std.log.err("{}", .{walk_err});
            continue;
        };
        const entry = entry_or_null orelse {
            break;
        };
        switch (entry.kind) {
            std.Io.File.Kind.file => {
                const matches = glob.match("*.patterns", entry.basename);
                if (matches) {
                    const p = try entry.dir.realPathFileAlloc(io, entry.basename, allocator);
                    defer allocator.free(p);
                    const pz = try allocator.dupeSentinel(u8, p, 0);
                    defer allocator.free(pz);
                    try compileFile(pz);
                }
            },
            else => {},
        }
    }
}

fn compileFile(path: []const u8) !void {
    const c_file_ptr = c.fopen(path.ptr, "r") orelse {
        std.log.err("Failed to open file: {s}", .{path});
        return grok.GrokError.UnknownPatternFile;
    };
    defer _ = c.fclose(c_file_ptr);

    c.yyrestart(c_file_ptr);
    if (c.yyparse() > 0) {
        std.log.err("Failed to parse file: {s}", .{path});
        return grok.GrokError.InvalidPatternFile;
    }
}

pub export fn fend_on_literal(str: [*c]const u8) void {
    composition.append(allocator, Info{
        .data = str,
        .reference = null,
        .part = .literal,
    }) catch |e| {
        std.log.err("{}", .{e});
    };
}

pub export fn fend_on_definition() void {
    composition = .empty;
}

pub export fn fend_on_definition_end(str: [*c]const u8) void {
    const slice = std.mem.span(str);
    const len = slice.len;
    definitions.put(slice[0..len], composition) catch |e| {
        std.log.err("{}", .{e});
    };
}

pub export fn fend_strdup(str: [*c]const u8) [*c]const u8 {
    const slice = std.mem.span(str);
    // Allocate memory for string + null terminator
    const mem = allocator.allocSentinel(u8, slice.len, 0) catch |e| {
        std.log.err("{}", .{e});
        return null;
    };
    @memcpy(mem[0..slice.len], slice);
    return @ptrCast(mem.ptr);
}

pub export fn fend_on_macro(name: [*c]u8, property: [*c]u8) ?*c.macro_t {
    const ptr = allocator.create(c.macro_t) catch |e| {
        std.log.err("{}", .{e});
        return null;
    };
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
        std.log.err("{}", .{e});
    };
    allocator.destroy(m);
}

export fn fend_print_error(first_line: c_int, first_column: c_int, last_line: c_int, last_column: c_int, message: [*:0]const u8) callconv(.c) void {
    std.log.err("{d}.{d}-{d}.{d}: error: {s}", .{
        first_line,
        first_column,
        last_line,
        last_column,
        message,
    });
}
