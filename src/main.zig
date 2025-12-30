const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const front = @import("frontend.zig");
const back = @import("backend.zig");
const encoding = @import("encoding.zig");
const glob = @import("glob");
const yazap = @import("yazap");

pub fn main() !void {
    if (builtin.os.tag == .windows) {
        // Windows-specific UTF-8 setup
        const kernel32 = std.os.windows.kernel32;
        _ = kernel32.SetConsoleOutputCP(65001);
    }
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    defer {
        stdout.flush() catch {};
    }

    const allocator = std.heap.c_allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const query = std.Target.Query.fromTarget(&builtin.target);

    const app_descr_template =
        \\Grok regexp macro processor {s} {s}
        \\Copyright (C) 2019-2025 Alexander Egorov. All rights reserved.
    ;
    const app_descr = try std.fmt.allocPrint(
        allocator,
        app_descr_template,
        .{ build_options.version, @tagName(query.cpu_arch.?) },
    );

    var app = yazap.App.init(allocator, "grok", app_descr);
    defer app.deinit();

    var root_cmd = app.rootCommand();
    root_cmd.setProperty(.help_on_empty_args);
    root_cmd.setProperty(.subcommand_required);

    const patterns_name: []const u8 = "patterns";
    const patterns_opt = yazap.Arg.multiValuesOption(
        patterns_name,
        'p',
        "One or more pattern files. If not set, current directory used to search all *.patterns files",
        512,
    );
    const macro_name: []const u8 = "macro";
    var macro_opt = yazap.Arg.singleValueOption(macro_name, 'm', "Pattern macros to build regexp");
    macro_opt.setValuePlaceholder("STRING");
    macro_opt.setProperty(.takes_value);
    const info_opt = yazap.Arg.booleanOption("info", 'i', "Dont work like grep i.e. output matched string with additional info");

    var str_cmd = app.createCommand("string", "Single string matching mode");
    str_cmd.setProperty(.help_on_empty_args);
    str_cmd.setProperty(.positional_arg_required);
    const string_opt = yazap.Arg.positional("STRING", "String to match", null);
    try str_cmd.addArg(patterns_opt);
    try str_cmd.addArg(macro_opt);
    try str_cmd.addArg(info_opt);
    try str_cmd.addArg(string_opt);

    var file_cmd = app.createCommand("file", "File matching mode");
    file_cmd.setProperty(.help_on_empty_args);
    file_cmd.setProperty(.positional_arg_required);
    const file_opt = yazap.Arg.positional("PATH", "Full path to file to read data from", null);

    try file_cmd.addArg(patterns_opt);
    try file_cmd.addArg(macro_opt);
    try file_cmd.addArg(info_opt);
    try file_cmd.addArg(file_opt);

    var stdin_cmd = app.createCommand("stdin", "Standard input (stdin) matching mode");
    stdin_cmd.setProperty(.help_on_empty_args);
    try stdin_cmd.addArg(patterns_opt);
    try stdin_cmd.addArg(macro_opt);
    try stdin_cmd.addArg(info_opt);

    var macro_cmd = app.createCommand(macro_name, "Macro information mode where a macro real regexp can be displayed or to get all supported macroses");
    const macro_name_opt = yazap.Arg.positional("MACRO", "Macro name to expand real regular expression", null);
    try macro_cmd.addArg(patterns_opt);
    try macro_cmd.addArg(macro_name_opt);

    try root_cmd.addSubcommand(str_cmd);
    try root_cmd.addSubcommand(file_cmd);
    try root_cmd.addSubcommand(stdin_cmd);
    try root_cmd.addSubcommand(macro_cmd);

    const matches = try app.parseProcess();

    if (matches.subcommandMatches(macro_name)) |cmd_matches| {
        const patterns = cmd_matches.getMultiValues(patterns_name);
        try compileLib(patterns, arena.allocator());
        if (cmd_matches.getSingleValue("MACRO")) |macro| {
            try onTemplate(allocator, stdout, macro);
        } else {
            try onTemplates(allocator, stdout);
        }
    } else if (matches.subcommandMatches("string")) |cmd_matches| {
        const patterns = cmd_matches.getMultiValues(patterns_name);
        try compileLib(patterns, arena.allocator());
        if (cmd_matches.getSingleValue(macro_name)) |macro| {
            if (cmd_matches.getSingleValue("STRING")) |str| {
                const info_mode = cmd_matches.containsArg("info");
                try onString(arena.allocator(), stdout, macro, str, info_mode);
            }
        }
    } else if (matches.subcommandMatches("file")) |cmd_matches| {
        const patterns = cmd_matches.getMultiValues(patterns_name);
        try compileLib(patterns, arena.allocator());
        if (cmd_matches.getSingleValue(macro_name)) |macro| {
            if (cmd_matches.getSingleValue("PATH")) |path| {
                const info_mode = cmd_matches.containsArg("info");
                try onFile(allocator, stdout, macro, path, info_mode);
            }
        }
    } else if (matches.subcommandMatches("stdin")) |cmd_matches| {
        const patterns = cmd_matches.getMultiValues(patterns_name);
        try compileLib(patterns, arena.allocator());
        if (cmd_matches.getSingleValue(macro_name)) |macro| {
            const info_mode = cmd_matches.containsArg("info");
            try onStdin(allocator, stdout, macro, info_mode);
        }
    }
}

fn onString(
    allocator: std.mem.Allocator,
    stdout: *std.io.Writer,
    macro: []const u8,
    subject: []const u8,
    info_mode: bool,
) !void {
    back.init(allocator);
    const pattern = try back.createPattern(allocator, macro);
    const prepared = try back.prepareRegex(pattern);
    const matched = back.matchRegex(allocator, &pattern, subject, &prepared);
    if (info_mode) {
        if (matched.matched) {
            try stdout.print("Match found\n", .{});
            if (matched.properties) |properties| {
                var it = properties.iterator();
                while (it.next()) |entry| {
                    const key = entry.key_ptr.*;
                    const val = entry.value_ptr.*;
                    try stdout.print("\t{s}: {s}\n", .{ key, val });
                }
            }
        } else {
            try stdout.print("No match found\n", .{});
        }
    } else if (matched.matched) {
        try stdout.print("{s}\n", .{subject});
    }
}

fn onFile(
    allocator: std.mem.Allocator,
    stdout: *std.io.Writer,
    macro: []const u8,
    path: []const u8,
    info_mode: bool,
) !void {
    var file = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });
    defer file.close();
    var file_buffer: [16384]u8 = undefined;
    var file_reader = file.reader(&file_buffer);
    const reader = &file_reader.interface;
    const encoding_buffer = try reader.take(4);
    const detection = encoding.detectBomMemory(encoding_buffer);
    try file_reader.seekTo(detection.offset);
    var file_encoding: encoding.Encoding = undefined;
    if (detection.encoding == .unknown) {
        file_encoding = .utf8; // set default to utf-8
    } else {
        file_encoding = detection.encoding;
    }
    return readFromReader(allocator, stdout, macro, reader, info_mode, file_encoding);
}

fn onStdin(
    allocator: std.mem.Allocator,
    stdout: *std.io.Writer,
    macro: []const u8,
    info_mode: bool,
) !void {
    var file_buffer: [16384]u8 = undefined;
    var file_reader = std.fs.File.stdin().reader(&file_buffer);
    const reader = &file_reader.interface;
    return readFromReader(allocator, stdout, macro, reader, info_mode, null);
}

fn onTemplate(allocator: std.mem.Allocator, stdout: *std.io.Writer, macro: []const u8) !void {
    const pattern = try back.createPattern(allocator, macro);
    return stdout.print("{s}\n", .{pattern.regex});
}

fn onTemplates(allocator: std.mem.Allocator, stdout: *std.io.Writer) !void {
    var it = front.getPatterns().keyIterator();
    var macroses = std.ArrayList([]const u8){};
    while (it.next()) |item| {
        try macroses.append(allocator, item.*);
    }
    std.mem.sort([]const u8, macroses.items, {}, stringLessThan);
    for (macroses.items) |item| {
        try stdout.print("{s}\n", .{item});
    }
}

fn stringLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}

fn readFromReader(
    allocator: std.mem.Allocator,
    stdout: *std.io.Writer,
    macro: []const u8,
    reader: *std.Io.Reader,
    info_mode: bool,
    file_encoding: ?encoding.Encoding, // null means reading from stdin
) !void {
    back.init(allocator);
    const pattern = try back.createPattern(allocator, macro);
    const prepared = try back.prepareRegex(pattern);

    var line_no: usize = 1;

    var arena = std.heap.ArenaAllocator.init(allocator);
    var current_encoding: encoding.Encoding = undefined;

    while (true) {
        defer _ = arena.reset(.retain_capacity);
        const loop_allocator = arena.allocator();
        var aw = std.Io.Writer.Allocating.init(loop_allocator);
        defer aw.deinit();
        _ = reader.streamDelimiter(&aw.writer, '\n') catch |err| switch (err) {
            error.EndOfStream => {
                if (aw.written().len == 0) break;
                // Process the very last line if it doesn't end with \n
                break;
            },
            else => return err,
        };

        var line = aw.written();

        if (file_encoding) |e| {
            current_encoding = e;
        } else {
            // stdin case. Detect encoding on each line because stdin can be
            // concatenated from several files using cat
            const detected = encoding.detectBomMemory(line);
            if (detected.encoding != .unknown) {
                current_encoding = detected.encoding;
            }
        }

        if (current_encoding == .utf16be or current_encoding == .utf16le) {
            reader.toss(2); // IMPORTANT: or we damage lines after the first one
            line = try encoding.convertRawUtf16ToUtf8(loop_allocator, line, current_encoding);
        } else {
            reader.toss(1);
        }

        const matched = back.matchRegex(loop_allocator, &pattern, line, &prepared);
        if (info_mode) {
            try stdout.print("line: {d} match: {} | pattern: {s}\n", .{ line_no, matched.matched, macro });
            if (matched.properties) |properties| {
                try stdout.print("\n  Meta properties found:\n", .{});
                var it = properties.iterator();
                while (it.next()) |entry| {
                    const key = entry.key_ptr.*;
                    const val = entry.value_ptr.*;
                    try stdout.print("\t{s}: {s}\n", .{ key, val });
                }
                try stdout.print("\n\n", .{});
            }
        } else {
            if (matched.matched) {
                try stdout.print("{s}\n", .{line});
            }
        }
        line_no += 1;
    }
}

fn compileLib(paths: ?[][]const u8, allocator: std.mem.Allocator) !void {
    front.init(allocator);
    if (paths == null or paths.?.len == 0) {
        // Use default
        var lib_path: []const u8 = undefined;
        const os_tag = builtin.os.tag;
        if (os_tag == .linux) {
            lib_path = "/usr/share/grok/patterns";
        } else {
            lib_path = try std.fs.selfExeDirPathAlloc(allocator);
        }

        try compileDir(lib_path, allocator);
    } else {
        for (paths.?) |path| {
            var d = std.fs.cwd().openDir(path, .{}) catch {
                try front.compileFile(path.ptr);
                continue;
            };
            d.close();
            try compileDir(path, allocator);
        }
    }
}

fn compileDir(lib_path: []const u8, allocator: std.mem.Allocator) !void {
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
                    try front.compileFile(p.ptr);
                }
            },
            else => {},
        }
    }
}

test {
    @import("std").testing.refAllDecls(@This());
}
