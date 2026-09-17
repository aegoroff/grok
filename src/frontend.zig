const std = @import("std");
const builtin = @import("builtin");
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
var lib_mutex: std.Io.Mutex = .init;
threadlocal var oom_jmp_buf: ?*c.jmp_buf = null;

fn noteOom() void {
    c.fend_signal_oom();
    if (oom_jmp_buf) |buf| {
        c.longjmp(&buf[0], 1);
    }
}

fn freeInfo(info: Info) void {
    allocator.free(std.mem.span(info.data));
    if (info.reference) |r| {
        allocator.free(std.mem.span(r));
    }
}

fn freeMacro(macro: *c.macro_t) void {
    allocator.free(std.mem.span(macro.name));
    if (macro.property != null) {
        allocator.free(std.mem.span(macro.property));
    }
    allocator.destroy(macro);
}

fn freeMacroDefinition(list: *std.ArrayList(Info)) void {
    for (list.items) |info| {
        freeInfo(info);
    }
    list.deinit(allocator);
}

fn clearComposition() void {
    for (composition.items) |info| {
        freeInfo(info);
    }
    composition.clearRetainingCapacity();
}

pub fn getPattern(key: []const u8) error{UnknownMacro}!std.ArrayList(Info) {
    return definitions.get(key) orelse error.UnknownMacro;
}

pub fn getPatterns() std.StringHashMap(std.ArrayList(Info)) {
    return definitions;
}

pub fn compileLib(gpa: std.mem.Allocator, stdio: std.Io, paths: ?[][]const u8) !void {
    try lib_mutex.lock(stdio);
    defer lib_mutex.unlock(stdio);

    if (lib_initialized) deinitLibUnlocked();
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
    lib_mutex.lock(io) catch return;
    defer lib_mutex.unlock(io);
    deinitLibUnlocked();
}

fn deinitLibUnlocked() void {
    if (!lib_initialized) return;

    var it = definitions.iterator();
    while (it.next()) |entry| {
        freeMacroDefinition(entry.value_ptr);

        const key = entry.key_ptr.*;
        allocator.free(key.ptr[0 .. key.len + 1]); // +1: compensate sentinel byte, lost under `slice[0..len]` in fend_on_definition_end
    }
    definitions.deinit();
    composition = .empty;
    _ = c.yylex_destroy();
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
    defer dir.close(io);
    var walker = try dir.walk(allocator);
    defer walker.deinit();
    while (true) {
        const entry_or_null = walker.next(io) catch |walk_err| {
            std.log.warn("{}", .{walk_err});
            continue;
        };
        const entry = entry_or_null orelse {
            break;
        };
        switch (entry.kind) {
            std.Io.File.Kind.file => {
                if (std.mem.endsWith(u8, entry.basename, ".patterns")) {
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
        std.log.warn("Failed to open file: {s}", .{path});
        return error.UnknownPatternFile;
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

    _ = c.yy_scan_string(source_z.ptr);
    defer _ = c.yypop_buffer_state();

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
        clearComposition();
        return error.OutOfMemory;
    }

    const result = c.yyparse();
    if (c.fend_oom_flag != 0) {
        clearComposition();
        return error.OutOfMemory;
    }
    if (result != 0) {
        clearComposition();
        std.log.warn("Failed to parse file: {s} at line {d}", .{ path, c.yylineno });
        return error.InvalidPatternFile;
    }
}

pub export fn fend_on_literal(str: [*c]const u8) void {
    composition.append(allocator, Info{
        .data = str,
        .reference = null,
        .part = .literal,
    }) catch {
        allocator.free(std.mem.span(str)); // ownership never reached composition
        noteOom();
    };
}

pub export fn fend_on_definition() void {
    composition = .empty;
}

pub export fn fend_on_definition_end(str: [*c]const u8) void {
    const slice = std.mem.span(str);
    const len = slice.len;
    const key = slice[0..len];

    if (definitions.getPtr(key)) |old| {
        freeMacroDefinition(old);
        old.* = composition;
        composition = .empty;
        allocator.free(slice.ptr[0 .. len + 1]);
        return;
    }

    definitions.put(key, composition) catch {
        // Neither the key nor the composition reached the table.
        clearComposition();
        composition.deinit(allocator);
        composition = .empty;
        allocator.free(slice.ptr[0 .. len + 1]); // +1: sentinel, as on the replace path above
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
        freeMacro(macro); // frees name, property and the macro itself
        noteOom(); // returns here when no OOM jump buffer is armed
        return;
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
            std.log.warn("No source text for file: {s}", .{path});
            return;
        };

        reporter.addSource(path, source) catch |e| {
            std.log.warn("Add source '{s}' failed with: {}", .{ path, e });
            return;
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
        std.log.warn("An errror occured during library compilation: {s}", .{std.mem.span(message)});
    }
}

test "fend_signal_oom sets parser flag" {
    c.fend_oom_flag = 0;
    c.fend_signal_oom();
    try std.testing.expect(c.fend_oom_flag != 0);
}

test "compileLib/deinitLib loop has no GPA leak" {
    var gpa_state = std.heap.DebugAllocator(.{}){};
    const gpa = gpa_state.allocator();
    var paths_buf = [_][]const u8{"./patterns/"};
    const paths: [][]const u8 = paths_buf[0..];

    for (0..5) |_| {
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        try compileLib(arena.allocator(), std.testing.io, paths);
        deinitLib();
    }

    try std.testing.expectEqual(std.heap.Check.ok, gpa_state.deinit());
}

test "duplicate macro definition has no GPA leak" {
    var gpa_state = std.heap.DebugAllocator(.{}){};
    const gpa = gpa_state.allocator();
    var paths_buf = [_][]const u8{"./test_assets/duplicate_macro.patterns"};
    const paths: [][]const u8 = paths_buf[0..];

    try compileLib(gpa, std.testing.io, paths);
    const pattern = try getPattern("DUP");
    try std.testing.expectEqualStrings("literal-only", std.mem.span(pattern.items[0].data));
    deinitLib();

    try std.testing.expectEqual(std.heap.Check.ok, gpa_state.deinit());
}

test "fend_on_grok frees the macro once when composition append fails" {
    var gpa_state = std.heap.DebugAllocator(.{}){};
    const gpa = gpa_state.allocator();

    allocator = gpa;
    composition = .empty;
    c.fend_oom_flag = 0;
    oom_jmp_buf = null; // force noteOom to return instead of longjmp

    const name = fend_strdup("NAME");
    const macro = fend_on_macro(@constCast(name), null).?;

    var failing = std.testing.FailingAllocator.init(gpa, .{ .fail_index = 0 });
    allocator = failing.allocator();
    fend_on_grok(macro);
    allocator = gpa;

    try std.testing.expect(c.fend_oom_flag != 0);
    try std.testing.expectEqual(std.heap.Check.ok, gpa_state.deinit());
}

test "fend_on_literal frees the literal when composition append fails" {
    var gpa_state = std.heap.DebugAllocator(.{}){};
    const gpa = gpa_state.allocator();

    allocator = gpa;
    composition = .empty;
    c.fend_oom_flag = 0;
    oom_jmp_buf = null; // force noteOom to return instead of longjmp

    const str = fend_strdup("LITERAL");

    var failing = std.testing.FailingAllocator.init(gpa, .{ .fail_index = 0 });
    allocator = failing.allocator();
    fend_on_literal(str);
    allocator = gpa;

    try std.testing.expect(c.fend_oom_flag != 0);
    try std.testing.expectEqual(std.heap.Check.ok, gpa_state.deinit());
}

test "fend_on_definition_end frees key and composition when put fails" {
    var gpa_state = std.heap.DebugAllocator(.{}){};
    const gpa = gpa_state.allocator();

    allocator = gpa;
    composition = .empty;
    c.fend_oom_flag = 0;
    oom_jmp_buf = null;

    // A definition that carries one literal, so the list buffer is in play too.
    fend_on_literal(fend_strdup("BODY"));
    const key = fend_strdup("SOMEMACRO");

    // StringHashMap captures its allocator at init, so the table must be built
    // on the failing one for put() to fail.
    var failing = std.testing.FailingAllocator.init(gpa, .{ .fail_index = 0 });
    definitions = std.StringHashMap(std.ArrayList(Info)).init(failing.allocator());
    allocator = failing.allocator();
    fend_on_definition_end(key);
    allocator = gpa;
    definitions.deinit();

    try std.testing.expect(c.fend_oom_flag != 0);
    try std.testing.expectEqual(@as(usize, 0), composition.items.len);
    try std.testing.expectEqual(std.heap.Check.ok, gpa_state.deinit());
}
