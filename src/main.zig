const std = @import("std");
const builtin = @import("builtin");
const front = @import("frontend.zig");
const back = @import("backend.zig");
const encoding = @import("encoding.zig");
const glob = @import("glob");
const yazap = @import("yazap");

pub fn main() !void {
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

    const appDescr = try std.fmt.allocPrint(
        allocator,
        "Grok regexp macro processor. {s}\nCopyright (C) 2019-2025 Alexander Egorov. All rights reserved.",
        .{@tagName(query.cpu_arch.?)},
    );

    var app = yazap.App.init(allocator, "grok", appDescr);
    defer app.deinit();

    var root_cmd = app.rootCommand();
    root_cmd.setProperty(.help_on_empty_args);
    root_cmd.setProperty(.subcommand_required);

    var macro_opt = yazap.Arg.singleValueOption("macro", 'm', "Pattern macros to build regexp");
    macro_opt.setValuePlaceholder("STRING");
    macro_opt.setProperty(.takes_value);
    const info_opt = yazap.Arg.booleanOption("info", 'i', "Dont work like grep i.e. output matched string with additional info");

    var str_cmd = app.createCommand("string", "Single string matching mode");
    str_cmd.setProperty(.help_on_empty_args);
    str_cmd.setProperty(.positional_arg_required);
    const string_opt = yazap.Arg.positional("STRING", "String to match", null);
    try str_cmd.addArg(macro_opt);
    try str_cmd.addArg(info_opt);
    try str_cmd.addArg(string_opt);

    var file_cmd = app.createCommand("file", "File matching mode");
    file_cmd.setProperty(.help_on_empty_args);
    file_cmd.setProperty(.positional_arg_required);
    const file_opt = yazap.Arg.positional("PATH", "Full path to file to read data from", null);

    try file_cmd.addArg(macro_opt);
    try file_cmd.addArg(info_opt);
    try file_cmd.addArg(file_opt);

    var stdin_cmd = app.createCommand("stdin", "Standard input (stdin) matching mode");
    stdin_cmd.setProperty(.help_on_empty_args);
    try stdin_cmd.addArg(macro_opt);
    try stdin_cmd.addArg(info_opt);

    var macro_cmd = app.createCommand("macro", "Macro information mode where a macro real regexp can be displayed or to get all supported macroses");
    const macro_name_opt = yazap.Arg.positional("MACRO", "Macro name to expand real regular expression", null);
    try macro_cmd.addArg(macro_name_opt);

    try root_cmd.addSubcommand(str_cmd);
    try root_cmd.addSubcommand(file_cmd);
    try root_cmd.addSubcommand(stdin_cmd);
    try root_cmd.addSubcommand(macro_cmd);

    try root_cmd.addArg(yazap.Arg.multiValuesOption(
        "patterns",
        'p',
        "One or more pattern files. If not set, current directory used to search all *.patterns files",
        512,
    ));

    const matches = try app.parseProcess();
    const patterns = matches.getMultiValues("patterns");

    try compileLib(patterns, arena.allocator());

    if (matches.subcommandMatches("macro")) |info_cmd_matches| {
        if (info_cmd_matches.getSingleValue("MACRO")) |macro| {
            try onTemplate(allocator, stdout, macro);
        } else {
            try onTemplates(allocator, stdout);
        }
    }
    if (matches.subcommandMatches("string")) |info_cmd_matches| {
        if (info_cmd_matches.getSingleValue("macro")) |macro| {
            if (info_cmd_matches.getSingleValue("STRING")) |str| {
                const info_mode = info_cmd_matches.containsArg("info");
                try onString(arena.allocator(), stdout, macro, str, info_mode);
            }
        }
    }
    if (matches.subcommandMatches("file")) |info_cmd_matches| {
        if (info_cmd_matches.getSingleValue("macro")) |macro| {
            if (info_cmd_matches.getSingleValue("PATH")) |path| {
                const info_mode = info_cmd_matches.containsArg("info");
                try onFile(allocator, stdout, macro, path, info_mode);
            }
        }
    }

    if (matches.subcommandMatches("stdin")) |info_cmd_matches| {
        if (info_cmd_matches.getSingleValue("macro")) |macro| {
            const info_mode = info_cmd_matches.containsArg("info");
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
    const pattern = (try back.createPattern(allocator, macro)).?;
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
    const pattern = (try back.createPattern(allocator, macro)).?;
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
    const pattern = (try back.createPattern(allocator, macro)).?;
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

fn compileLib(files: ?[][]const u8, allocator: std.mem.Allocator) !void {
    front.init(allocator);
    if (files == null or files.?.len == 0) {
        // Use default
        const lib_path = "/usr/share/grok/patterns";
        var dir = try std.fs.openDirAbsolute(lib_path, .{ .iterate = true });
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
    } else {
        for (files.?) |file| {
            try front.compileFile(file.ptr);
        }
    }
}
