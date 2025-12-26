const std = @import("std");
const front = @import("frontend.zig");
const back = @import("backend.zig");
const clap = @import("clap");
const glob = @import("glob");

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

    var iter = try std.process.ArgIterator.initWithAllocator(allocator);
    defer iter.deinit();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help                 Display this help and exit.
        \\-i, --info                 Dont work like grep i.e. output matched string with additional info
        \\-f, --file     <str>       Full path to file to read data from.
        \\-m, --macro    <str>       Pattern macros to build regexp.
        \\-s, --string   <str>       String to match.
        \\-p, --patterns <str>...    One or more pattern files. You can also use
        \\                           wildcards like path/*.patterns. If not set, current
        \\                           directory used to search all *.patterns files
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = arena.allocator(),
    }) catch |err| {
        // Report useful error and exit
        diag.report(stdout, err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        return clap.help(stdout, clap.Help, &params, .{});
    }
    const info_mode = res.args.info != 0;

    try compile_lib(res.args.patterns, arena.allocator());

    const macro = res.args.macro orelse {
        return;
    };

    if (res.args.string != null) {
        try on_string(arena.allocator(), stdout, macro, res.args.string.?, info_mode);
    }

    if (res.args.file != null) {
        try on_file(allocator, stdout, macro, res.args.file.?, info_mode);
    }
}

fn on_string(allocator: std.mem.Allocator, stdout: *std.io.Writer, macro: []const u8, subject: []const u8, info_mode: bool) !void {
    back.init(allocator);
    const pattern = (try back.create_pattern(allocator, macro)).?;
    const prepared = try back.prepare_re(pattern);
    const matched = back.match_re(&pattern, subject, &prepared);
    if (info_mode) {
        if (matched.matched) {
            std.debug.print("Match found\n", .{});
            if (matched.properties != null) {
                var it = matched.properties.?.iterator();
                while (it.next()) |entry| {
                    const key = entry.key_ptr.*;
                    const val = entry.value_ptr.*;
                    std.debug.print("\t{s}: {s}\n", .{ key, val });
                }
            }
        } else {
            std.debug.print("No match found\n", .{});
        }
    } else if (matched.matched) {
        try stdout.print("{s}", .{subject});
    }
}

fn on_file(allocator: std.mem.Allocator, stdout: *std.io.Writer, macro: []const u8, path: []const u8, info_mode: bool) !void {
    back.init(allocator);
    const pattern = (try back.create_pattern(allocator, macro)).?;
    const prepared = try back.prepare_re(pattern);
    var file = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });
    defer file.close();

    var file_buffer: [4096]u8 = undefined;
    var file_reader = file.reader(&file_buffer);
    var reader = &file_reader.interface;

    var line_no: usize = 1;

    while (true) {
        var aw = std.Io.Writer.Allocating.init(allocator);
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

        const line = aw.written();
        const matched = back.match_re(&pattern, line, &prepared);
        if (info_mode) {
            try stdout.print("line: {d} match: {} | pattern: {s}\n", .{ line_no, matched.matched, macro });
            if (matched.properties != null) {
                try stdout.print("\n  Meta properties found:\n", .{});
                var it = matched.properties.?.iterator();
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

fn compile_lib(files: []const []const u8, allocator: std.mem.Allocator) !void {
    front.init(allocator);
    const patterns = files;
    if (patterns.len == 0) {
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
        for (patterns) |pattern| {
            try front.compile_file(pattern.ptr);
        }
    }
}
