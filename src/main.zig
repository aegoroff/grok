const std = @import("std");
const front = @import("frontend.zig");
const back = @import("backend.zig");
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

    var app = yazap.App.init(allocator, "grok", "Grok regexp macro processor\nCopyright (C) 2019-2025 Alexander Egorov. All rights reserved.");
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

    var info_cmd = app.createCommand("info", "Macro information mode");
    try info_cmd.addArg(macro_opt);

    try root_cmd.addSubcommand(str_cmd);
    try root_cmd.addSubcommand(file_cmd);
    try root_cmd.addSubcommand(stdin_cmd);
    try root_cmd.addSubcommand(info_cmd);

    try root_cmd.addArg(yazap.Arg.multiValuesOption(
        "patterns",
        'p',
        "One or more pattern files. If not set, current directory used to search all *.patterns files",
        512,
    ));

    const matches = try app.parseProcess();
    const patterns = matches.getMultiValues("patterns");

    try compile_lib(patterns, arena.allocator());

    if (matches.subcommandMatches("info")) |info_cmd_matches| {
        if (info_cmd_matches.getSingleValue("macro")) |macro| {
            try on_template(allocator, stdout, macro);
        } else {
            try on_templates(allocator, stdout);
        }
    }
    if (matches.subcommandMatches("string")) |info_cmd_matches| {
        if (info_cmd_matches.getSingleValue("macro")) |macro| {
            if (info_cmd_matches.getSingleValue("STRING")) |str| {
                const info_mode = info_cmd_matches.containsArg("info");
                try on_string(arena.allocator(), stdout, macro, str, info_mode);
            }
        }
    }
    if (matches.subcommandMatches("file")) |info_cmd_matches| {
        if (info_cmd_matches.getSingleValue("macro")) |macro| {
            if (info_cmd_matches.getSingleValue("PATH")) |path| {
                const info_mode = info_cmd_matches.containsArg("info");
                try on_file(allocator, stdout, macro, path, info_mode);
            }
        }
    }

    if (matches.subcommandMatches("stdin")) |info_cmd_matches| {
        if (info_cmd_matches.getSingleValue("macro")) |macro| {
            const info_mode = info_cmd_matches.containsArg("info");
            try on_stdin(allocator, stdout, macro, info_mode);
        }
    }
}

fn on_string(allocator: std.mem.Allocator, stdout: *std.io.Writer, macro: []const u8, subject: []const u8, info_mode: bool) !void {
    back.init(allocator);
    const pattern = (try back.create_pattern(allocator, macro)).?;
    const prepared = try back.prepare_re(allocator, pattern);
    const matched = back.match_re(&pattern, subject, &prepared);
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

const Encoding = enum {
    unknown,
    utf8,
    utf16le,
    utf16be,
    utf32be,
};

const Bom = struct {
    encoding: Encoding,
    signature: []const u8,
};

const signatures: []const Bom = &[_]Bom{
    Bom{
        .encoding = .utf8,
        .signature = &[_]u8{ 0xEF, 0xBB, 0xBF },
    },
    Bom{
        .encoding = .utf16le,
        .signature = &[_]u8{ 0xFF, 0xFE },
    },
    Bom{
        .encoding = .utf16be,
        .signature = &[_]u8{ 0xFE, 0xFF },
    },
    Bom{
        .encoding = .utf32be,
        .signature = &[_]u8{ 0x00, 0x00, 0xFE, 0xFF },
    },
    Bom{
        .encoding = .unknown,
        .signature = &[_]u8{},
    },
};

const DetectResult = struct {
    encoding: Encoding,
    offset: usize,
};

fn detect_bom_memory(buffer: []const u8) DetectResult {
    for (signatures) |bom| {
        if (bom.signature.len == 0) continue;

        if (buffer.len >= bom.signature.len and
            std.mem.startsWith(u8, buffer, bom.signature))
        {
            return .{
                .encoding = bom.encoding,
                .offset = bom.signature.len,
            };
        }
    }

    return .{ .encoding = .unknown, .offset = 0 };
}

fn char_to_wchar(
    allocator: std.mem.Allocator,
    buffer: []const u8,
    encoding: Encoding,
) ![]u16 {
    const len = buffer.len / 2;

    var wide_buffer = try allocator.alloc(u16, len);

    var i: usize = 0;
    var counter: usize = 0;
    while (i + 1 < buffer.len) : (i += 2) {
        const b1 = buffer[i];
        const b2 = buffer[i + 1];

        const val: u16 = switch (encoding) {
            .utf16le => @as(u16, b2) << 8 | b1,
            else => @as(u16, b1) << 8 | b2,
        };

        wide_buffer[counter] = val;
        counter += 1;
    }

    return wide_buffer[0..counter];
}

fn on_file(allocator: std.mem.Allocator, stdout: *std.io.Writer, macro: []const u8, path: []const u8, info_mode: bool) !void {
    var file = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });
    defer file.close();
    var file_buffer: [16384]u8 = undefined;
    var file_reader = file.reader(&file_buffer);
    const reader = &file_reader.interface;
    const encoding_buffer = try reader.take(4);
    const detection = detect_bom_memory(encoding_buffer);
    var encoding: Encoding = undefined;
    if (detection.encoding == .unknown) {
        encoding = .utf8; // set default to utf-8
    } else {
        encoding = detection.encoding;
    }
    return read_from_reader(allocator, stdout, macro, reader, info_mode, encoding);
}

fn on_stdin(allocator: std.mem.Allocator, stdout: *std.io.Writer, macro: []const u8, info_mode: bool) !void {
    var file_buffer: [16384]u8 = undefined;
    var file_reader = std.fs.File.stdin().reader(&file_buffer);
    const reader = &file_reader.interface;
    return read_from_reader(allocator, stdout, macro, reader, info_mode, null);
}

fn on_template(allocator: std.mem.Allocator, stdout: *std.io.Writer, macro: []const u8) !void {
    const pattern = (try back.create_pattern(allocator, macro)).?;
    return stdout.print("{s}\n", .{pattern.regex});
}

fn on_templates(allocator: std.mem.Allocator, stdout: *std.io.Writer) !void {
    var it = front.get_patterns().keyIterator();
    var macroses = std.ArrayList([]const u8){};
    while (it.next()) |item| {
        try macroses.append(allocator, item.*);
    }
    std.mem.sort([]const u8, macroses.items, {}, string_less_than);
    for (macroses.items) |item| {
        try stdout.print("{s}\n", .{item});
    }
}

fn string_less_than(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}

fn read_from_reader(
    allocator: std.mem.Allocator,
    stdout: *std.io.Writer,
    macro: []const u8,
    reader: *std.Io.Reader,
    info_mode: bool,
    encoding: ?Encoding, // null means reading from stdin
) !void {
    const pattern = (try back.create_pattern(allocator, macro)).?;
    const prepared = try back.prepare_re(allocator, pattern);

    var line_no: usize = 1;

    var arena = std.heap.ArenaAllocator.init(allocator);
    var current_encoding: Encoding = undefined;

    while (true) {
        defer _ = arena.reset(.retain_capacity);
        back.init(arena.allocator());
        var aw = std.Io.Writer.Allocating.init(arena.allocator());
        defer aw.deinit();
        _ = reader.streamDelimiter(&aw.writer, '\n') catch |err| switch (err) {
            error.EndOfStream => {
                if (aw.written().len == 0) break;
                // Process the very last line if it doesn't end with \n
                break;
            },
            else => return err,
        };

        reader.toss(1);

        var line = aw.written();

        if (encoding) |e| {
            current_encoding = e;
        } else {
            // stdin case. Detect encoding on each line because stdin can be
            // concatenated from several files using cat
            const detected = detect_bom_memory(line);
            if (detected.encoding != .unknown) {
                current_encoding = detected.encoding;
            }
        }

        if (current_encoding == .utf16be or current_encoding == .utf16le) {
            const wide = try char_to_wchar(arena.allocator(), line, current_encoding);
            //std.debug.print("Encoding {}: {any}\n", .{ current_encoding, wide });
            const converted: []u8 = undefined;
            _ = try std.unicode.utf16LeToUtf8(converted, wide);
            line = converted;
        }

        const matched = back.match_re(&pattern, line, &prepared);
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

fn compile_lib(files: ?[][]const u8, allocator: std.mem.Allocator) !void {
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
                        try front.compile_file(p.ptr);
                    }
                },
                else => {},
            }
        }
    } else {
        for (files.?) |file| {
            try front.compile_file(file.ptr);
        }
    }
}
