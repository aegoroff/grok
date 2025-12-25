const std = @import("std");
const re = @cImport({
    @cDefine("PCRE2_CODE_UNIT_WIDTH", "8");
    @cInclude("pcre2.h");
});
const front = @import("frontend.zig");

const PCRE2_ZERO_TERMINATED = ~@as(re.PCRE2_SIZE, 0);

pub fn main() void {
    const pattern = "your\\s(.*)\\s";
    const subject = "all of your codebase are belong to us!";
    const rxp = compile(pattern);
    const match = find(rxp.?, subject);
    std.debug.print("Pattern is: {s}\n", .{pattern});
    std.debug.print("Haystack is: {s}\n", .{subject});
    std.debug.print("Match is: {?s}\n", .{match});

    fend_on_literal("Hello, World!");
    try front.compile_file("path/to/file");
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

pub fn fend_on_literal(_: []const u8) void {
    // Implementation of fend_on_literal function
}
