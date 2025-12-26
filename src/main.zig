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

    const params = comptime clap.parseParamsComptime(
        \\-h, --help                 Display this help and exit.
        \\-f, --file     <str>       Full path to file to read data from.
        \\-m, --macro    <str>       Pattern macros to build regexp.
        \\-s, --string   <str>       String to match.
        \\-p, --patterns <str>...    One or more pattern files. You can also use
        \\                           wildcards like path/*.patterns. If not set, current
        \\                           directory used to search all *.patterns files
    );

    const allocator = std.heap.c_allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

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

    try compile_lib(res.args.patterns, arena.allocator());

    const macro = res.args.macro orelse {
        return;
    };
    const haystack = res.args.string orelse {
        return;
    };
    back.init(arena.allocator());
    const pattern = (try back.create_pattern(arena.allocator(), macro)).?;
    const prepared = try back.prepare_re(pattern);
    const matched = back.match_re(&pattern, haystack, &prepared);
    if (matched.matched) {
        std.debug.print("Match found\n", .{});
    } else {
        std.debug.print("No match found\n", .{});
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
