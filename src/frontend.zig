const std = @import("std");
const builtin = @import("builtin");
const grok = @import("grok.zig");
const glob = @import("glob");
const c = @import("c");

const ErrorReporter = @import("fehler").ErrorReporter;
const Diagnostic = @import("fehler").Diagnostic;
const Severity = @import("fehler").Severity;
const SourceRange = @import("fehler").SourceRange;

pub const Info = struct {
    data: [*c]const u8,
    reference: [*c]const u8,
    part: Part,
};

pub const Part = enum { literal, reference };

var allocator: std.mem.Allocator = undefined;
var io: std.Io = undefined;
var composition: std.ArrayList(Info) = .empty;
var current_file: ?[]const u8 = null;
var current_source: ?[]const u8 = null;
var definitions: std.StringHashMap(std.ArrayList(Info)) = undefined;
var lib_initialized: bool = false;
var oom_jmp_buf: ?*c.jmp_buf = null;

fn noteOom() void {
    c.fend_signal_oom();
    if (oom_jmp_buf) |buf| {
        c.longjmp(&buf[0], 1);
    }
}

pub fn getPattern(key: []const u8) grok.GrokError!std.ArrayList(Info) {
    return definitions.get(key) orelse grok.GrokError.UnknownMacro;
}

pub fn getPatterns() std.StringHashMap(std.ArrayList(Info)) {
    return definitions;
}

pub fn compileLib(gpa: std.mem.Allocator, stdio: std.Io, paths: ?[][]const u8) !void {
    allocator = gpa;
    io = stdio;
    definitions = std.StringHashMap(std.ArrayList(Info)).init(allocator);
    lib_initialized = true;
    if (paths) |path_arg| {
        if (path_arg.len == 0) {
            try compileDefault();
        } else {
            for (path_arg) |path| {
                compileDir(path) catch {
                    const pathz = try allocator.dupeSentinel(u8, path, 0);
                    defer allocator.free(pathz);
                    try compileFile(pathz);
                };
            }
        }
    } else {
        try compileDefault();
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

fn compileDefault() !void {
    if (builtin.os.tag == .linux) {
        try compileDir("/usr/share/grok/patterns");
        return;
    }

    const lib_path = try std.process.executableDirPathAlloc(io, allocator);
    defer allocator.free(lib_path);
    try compileDir(lib_path);
}

fn compileDir(lib_path: []const u8) !void {
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
    current_file = path;
    defer current_file = null;

    var file_buffer: [64 * 1024]u8 = undefined;
    var file = std.Io.Dir.cwd().openFile(io, path, .{ .mode = .read_only }) catch {
        std.log.err("Failed to open file: {s}", .{path});
        return grok.GrokError.UnknownPatternFile;
    };
    defer file.close(io);

    var memory = std.Io.Writer.Allocating.init(allocator);
    defer memory.deinit();
    var file_reader = file.reader(io, &file_buffer);
    _ = try file_reader.interface.streamRemaining(&memory.writer);

    const source = try allocator.dupe(u8, memory.written());
    defer allocator.free(source);
    current_source = source;
    defer current_source = null;

    const source_z = try allocator.dupeSentinel(u8, source, 0);
    defer allocator.free(source_z);

    const scan_buf = c.yy_scan_string(source_z.ptr);
    defer c.yy_delete_buffer(scan_buf);

    // Initialize location tracking BEFORE scanning
    c.yyset_lineno(1);
    c.yycolumn = 1;
    c.yylloc.first_line = 1;
    c.yylloc.last_line = 1;
    c.yylloc.first_column = 1;
    c.yylloc.last_column = 1;
    c.yyerror_flag = 0; // Reset error flag
    c.fend_oom_flag = 0;

    var oom_jmp: c.jmp_buf = undefined;
    oom_jmp_buf = &oom_jmp;
    defer oom_jmp_buf = null;

    if (c.setjmp(&oom_jmp[0]) != 0) {
        return grok.GrokError.OutOfMemory;
    }

    const result = c.yyparse();
    if (c.fend_oom_flag != 0) {
        return grok.GrokError.OutOfMemory;
    }
    if (result != 0) {
        std.log.err("Failed to parse file: {s} at line {d}", .{ path, c.yylineno });
        return grok.GrokError.InvalidPatternFile;
    }
}

pub export fn fend_on_literal(str: [*c]const u8) void {
    composition.append(allocator, Info{
        .data = str,
        .reference = null,
        .part = .literal,
    }) catch {
        noteOom();
    };
}

pub export fn fend_on_definition() void {
    composition = .empty;
}

pub export fn fend_on_definition_end(str: [*c]const u8) void {
    const slice = std.mem.span(str);
    const len = slice.len;
    definitions.put(slice[0..len], composition) catch {
        noteOom();
    };
}

pub export fn fend_strdup(str: [*c]const u8) [*c]const u8 {
    const slice = std.mem.span(str);
    const mem = allocator.allocSentinel(u8, slice.len, 0) catch {
        noteOom();
        return null;
    };
    @memcpy(mem[0..slice.len], slice);
    return @ptrCast(mem.ptr);
}

pub export fn fend_on_macro(name: [*c]u8, property: [*c]u8) ?*c.macro_t {
    if (name == null) {
        noteOom();
        return null;
    }
    const ptr = allocator.create(c.macro_t) catch {
        noteOom();
        return null;
    };
    ptr.* = c.macro_t{
        .name = name,
        .property = property,
    };
    return ptr;
}

pub export fn fend_on_grok(m: ?*c.macro_t) void {
    const macro = m orelse {
        noteOom();
        return;
    };
    composition.append(allocator, Info{
        .data = macro.name,
        .reference = macro.property,
        .part = .reference,
    }) catch {
        noteOom();
    };
    allocator.destroy(macro);
}

export fn fend_print_error(
    first_line: c_int,
    first_column: c_int,
    last_line: c_int,
    last_column: c_int,
    message: [*:0]const u8,
) callconv(.c) void {
    if (current_file) |path| {
        var reporter = ErrorReporter.init(allocator);
        defer reporter.deinit();

        const source = current_source orelse {
            std.log.err("No source text for file: {s}", .{path});
            return;
        };

        reporter.addSource(path, source) catch |e| {
            std.log.err("Add source '{s}' failed with: {}", .{ path, e });
        };

        const diagnostic = Diagnostic.init(.err, std.mem.span(message))
            .withRange(SourceRange.span(
            path,
            @intCast(first_line),
            @intCast(first_column),
            @intCast(last_line),
            @intCast(last_column),
        ));

        reporter.report(diagnostic);
    } else {
        std.log.err("An errror occured during library compilation: {s}", .{std.mem.span(message)});
    }
}

test "fend_signal_oom sets parser flag" {
    c.fend_oom_flag = 0;
    c.fend_signal_oom();
    try std.testing.expect(c.fend_oom_flag != 0);
}
