const std = @import("std");
const re = @cImport({
    @cDefine("PCRE2_CODE_UNIT_WIDTH", "8");
    @cInclude("pcre2.h");
});
const front = @import("frontend.zig");
const clap = @import("clap");
const glob = @import("glob");

const PCRE2_ZERO_TERMINATED = ~@as(re.PCRE2_SIZE, 0);

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
        \\-p, --patterns <str>...    One or more pattern files. You can also use
        \\                           wildcards like path\*.patterns. If not set, current
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

/// Compiles a regex pattern string and returns a pattern code you can use
/// to match subjects. Returns `null` if something is wrong with the pattern
fn compile(needle: []const u8) ?*re.pcre2_code_8 {
    const pattern: re.PCRE2_SPTR8 = &needle[0];
    var errornumber: c_int = undefined;
    var erroroffset: re.PCRE2_SIZE = undefined;

    const regex: ?*re.pcre2_code_8 = re.pcre2_compile_8(pattern, PCRE2_ZERO_TERMINATED, 0, &errornumber, &erroroffset, null);
    return regex;
}

/// Takes in a compiled regexp pattern from `compile` and a string of test which is the haystack
/// and returns the first match from the haystack.
fn find(regexp: *re.pcre2_code_8, haystack: []const u8) ?[]const u8 {
    const subject: re.PCRE2_SPTR8 = &haystack[0];
    const subjLen: re.PCRE2_SIZE = haystack.len;

    const matchData: ?*re.pcre2_match_data_8 = re.pcre2_match_data_create_from_pattern_8(regexp, null);
    const rc: c_int = re.pcre2_match_8(regexp, subject, subjLen, 0, 0, matchData.?, null);

    if (rc < 0) {
        return null;
    }

    const ovector = re.pcre2_get_ovector_pointer_8(matchData);
    if (rc == 0) {
        std.debug.print("ovector was not big enough for all the captured substrings\n", .{});
        return null;
    }

    if (ovector[0] > ovector[1]) {
        std.debug.print("error with ovector\n", .{});
        re.pcre2_match_data_free_8(matchData);
        re.pcre2_code_free_8(regexp);
        return null;
    }
    const match = haystack[ovector[0]..ovector[1]]; // First match only
    return match;
}
