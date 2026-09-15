pub const Config = @This();

const std = @import("std");
const yazap = @import("yazap");
const builtin = @import("builtin");
const build_options = @import("build_options");
const front = @import("frontend.zig");
const printer = @import("printer.zig");

const PATTERNS_NAME: []const u8 = "patterns";
const COUNT_NAME: []const u8 = "count";
const LINE_NAME: []const u8 = "line-number";
const INFO_NAME: []const u8 = "info";
const JSON_NAME: []const u8 = "jsonl";
const INVERT_NAME: []const u8 = "invert-match";
const PATH_NAME: []const u8 = "PATH";
const STRING_NAME: []const u8 = "STRING";
const MACRO_ARG_NAME: []const u8 = "MACRO";

pub const MACRO_NAME: []const u8 = "macro";
pub const STRING_COMMAND_NAME: []const u8 = "string";
pub const FILE_COMMAND_NAME: []const u8 = "file";
pub const STDIN_COMMAND_NAME: []const u8 = "stdin";

matches: yazap.ArgMatches,
allocator: std.mem.Allocator,
app: *yazap.App,
io: std.Io,
app_descr: []const u8,

pub fn init(gpa: std.mem.Allocator, io: std.Io, argv: []const [:0]const u8) !Config {
    const app_descr_template =
        \\Grok regexp macro processor {s} {s}
        \\Copyright (C) 2018-2026 Alexander Egorov. All rights reserved.
    ;
    const query = std.Target.Query.fromTarget(&builtin.target);
    const app_descr = try std.fmt.allocPrint(
        gpa,
        app_descr_template,
        .{ build_options.version, @tagName(query.cpu_arch.?) },
    );
    errdefer gpa.free(app_descr);

    const app = try gpa.create(yazap.App);
    errdefer gpa.destroy(app);
    app.* = yazap.App.init(gpa, "grok", app_descr);

    var root_cmd = app.rootCommand();
    root_cmd.setProperty(.help_on_empty_args);
    root_cmd.setProperty(.subcommand_required);

    const patterns_opt = yazap.Arg.multiValuesOption(
        PATTERNS_NAME,
        'p',
        "One or more pattern files. If not set, current directory used to search all *.patterns files",
        1,
    );

    var macro_opt = yazap.Arg.singleValueOption(MACRO_NAME, 'm', "Pattern macros to build regexp");
    macro_opt.setValuePlaceholder("STRING");
    macro_opt.setProperty(.takes_value);
    const info_opt = yazap.Arg.booleanOption(INFO_NAME, 'i', "Dont work like grep i.e. output matched string with additional info");
    const json_opt = yazap.Arg.booleanOption(JSON_NAME, 'j', "Output matched strings in JSONL (Newline delimited JSON) format");
    const count_opt = yazap.Arg.booleanOption(COUNT_NAME, 'c', "Print only matched strings count");
    const line_num_opt = yazap.Arg.booleanOption(LINE_NAME, 'n', "Print line number along with output lines");
    const invert_opt = yazap.Arg.booleanOption(INVERT_NAME, 'v', "Select non-matching lines");

    var str_cmd = app.createCommand(STRING_COMMAND_NAME, "Single string matching mode");
    str_cmd.setProperty(.help_on_empty_args);
    str_cmd.setProperty(.positional_arg_required);
    const string_arg = yazap.Arg.positional(STRING_NAME, "String to match", null);
    try str_cmd.addArg(patterns_opt);
    try str_cmd.addArg(macro_opt);
    try str_cmd.addArg(info_opt);
    try str_cmd.addArg(json_opt);
    try str_cmd.addArg(invert_opt);
    try str_cmd.addArg(string_arg);

    var file_cmd = app.createCommand(FILE_COMMAND_NAME, "File matching mode");
    file_cmd.setProperty(.help_on_empty_args);
    file_cmd.setProperty(.positional_arg_required);
    const file_arg = yazap.Arg.positional(PATH_NAME, "Full path to file to read data from", null);

    try file_cmd.addArg(patterns_opt);
    try file_cmd.addArg(macro_opt);
    try file_cmd.addArg(info_opt);
    try file_cmd.addArg(json_opt);
    try file_cmd.addArg(count_opt);
    try file_cmd.addArg(line_num_opt);
    try file_cmd.addArg(invert_opt);
    try file_cmd.addArg(file_arg);

    var stdin_cmd = app.createCommand(STDIN_COMMAND_NAME, "Standard input (stdin) matching mode");
    stdin_cmd.setProperty(.help_on_empty_args);
    try stdin_cmd.addArg(patterns_opt);
    try stdin_cmd.addArg(macro_opt);
    try stdin_cmd.addArg(info_opt);
    try stdin_cmd.addArg(json_opt);
    try stdin_cmd.addArg(count_opt);
    try stdin_cmd.addArg(line_num_opt);
    try stdin_cmd.addArg(invert_opt);

    var macro_cmd = app.createCommand(
        MACRO_NAME,
        "Macro information mode where a macro real regexp can be displayed or to get all supported macroses",
    );
    const macro_name_opt = yazap.Arg.positional(
        MACRO_ARG_NAME,
        "Macro name to expand real regular expression",
        null,
    );
    try macro_cmd.addArg(patterns_opt);
    try macro_cmd.addArg(macro_name_opt);

    try root_cmd.addSubcommand(str_cmd);
    try root_cmd.addSubcommand(file_cmd);
    try root_cmd.addSubcommand(stdin_cmd);
    try root_cmd.addSubcommand(macro_cmd);

    const matches = try app.parseFrom(io, argv);

    return .{
        .matches = matches,
        .allocator = gpa,
        .app = app,
        .io = io,
        .app_descr = app_descr,
    };
}

pub fn deinit(self: *Config) void {
    front.deinitLib();
    self.app.deinit();
    self.allocator.destroy(self.app);
    self.allocator.free(self.app_descr);
}

pub const Command = enum { string, file, stdin, macro };

pub const Selected = struct {
    cmd: Command,
    matches: yazap.ArgMatches,
};

pub fn selected(self: *const Config) ?Selected {
    if (self.matches.subcommandMatches(STRING_COMMAND_NAME)) |m| return .{ .cmd = .string, .matches = m };
    if (self.matches.subcommandMatches(FILE_COMMAND_NAME)) |m| return .{ .cmd = .file, .matches = m };
    if (self.matches.subcommandMatches(STDIN_COMMAND_NAME)) |m| return .{ .cmd = .stdin, .matches = m };
    if (self.matches.subcommandMatches(MACRO_NAME)) |m| return .{ .cmd = .macro, .matches = m };
    return null;
}

pub fn loadPatterns(self: *const Config, writer: *std.Io.Writer, cmd: yazap.ArgMatches) !void {
    const patterns = cmd.getMultiValues(PATTERNS_NAME);
    front.compileLib(self.allocator, self.io, patterns) catch |e| {
        try writer.print("Failed to compile lib: {}\n", .{e});
        return e;
    };
}

pub fn getMacro(match: yazap.ArgMatches) error{MacroNotProvided}![]const u8 {
    return match.getSingleValue(MACRO_NAME) orelse return error.MacroNotProvided;
}

pub fn getStringArgValue(match: yazap.ArgMatches) ?[]const u8 {
    return match.getSingleValue(STRING_NAME);
}

pub fn getPathArgValue(match: yazap.ArgMatches) ?[]const u8 {
    return match.getSingleValue(PATH_NAME);
}

pub fn getMacroArgValue(match: yazap.ArgMatches) ?[]const u8 {
    return match.getSingleValue(MACRO_ARG_NAME);
}

pub fn isInfoMode(match: yazap.ArgMatches) bool {
    return match.containsArg(INFO_NAME);
}

pub fn isJsonMode(match: yazap.ArgMatches) bool {
    return match.containsArg(JSON_NAME);
}

pub fn isCountMode(match: yazap.ArgMatches) bool {
    return match.containsArg(COUNT_NAME);
}

pub fn printLineNumber(match: yazap.ArgMatches) bool {
    return match.containsArg(LINE_NAME);
}

pub fn isInvertMatch(match: yazap.ArgMatches) bool {
    return match.containsArg(INVERT_NAME);
}

/// Builds output flags from parsed CLI args. Stream commands (file, stdin) expose count and line-number options.
pub fn outputFlags(match: yazap.ArgMatches, stream: bool) printer.OutputFlags {
    return .{
        .info = isInfoMode(match),
        .json = isJsonMode(match),
        .count = stream and isCountMode(match),
        .print_line_num = stream and printLineNumber(match),
        .invert_match = isInvertMatch(match),
    };
}

test "correct string parsing and run integration test" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const command_line: []const [:0]const u8 = &[_][:0]const u8{ "string", "-p", "./patterns/", "-m", "YEAR", "2000" };
    var config = try Config.init(arena.allocator(), std.testing.io, command_line);
    defer config.deinit();

    const sel = config.selected() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(.string, sel.cmd);

    var writer = std.Io.Writer.Allocating.init(arena.allocator());
    try config.loadPatterns(&writer.writer, sel.matches);
}

test "incorrect string parsing no positional parameter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const command_line: []const [:0]const u8 = &[_][:0]const u8{ "string", "-m", "YEAR" };
    const err = Config.init(arena.allocator(), std.testing.io, command_line);
    try std.testing.expectError(yazap.yazap_error.ParseError.PositionalArgumentNotProvided, err);
}

test "incorrect file parsing no positional parameter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const command_line: []const [:0]const u8 = &[_][:0]const u8{ "file", "-m", "YEAR" };

    const err = Config.init(arena.allocator(), std.testing.io, command_line);
    try std.testing.expectError(yazap.yazap_error.ParseError.PositionalArgumentNotProvided, err);
}

test "missing macro option" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const command_line: []const [:0]const u8 = &[_][:0]const u8{ "file", "-p", "./patterns/", "log.txt" };
    var config = try Config.init(arena.allocator(), std.testing.io, command_line);
    defer config.deinit();

    const sel = config.selected() orelse return error.TestUnexpectedResult;
    try std.testing.expectError(error.MacroNotProvided, getMacro(sel.matches));
}
