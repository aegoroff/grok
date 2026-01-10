pub const Config = @This();

const std = @import("std");
const yazap = @import("yazap");
const builtin = @import("builtin");
const build_options = @import("build_options");
const front = @import("frontend.zig");

const patterns_name: []const u8 = "patterns";
const count_name: []const u8 = "count";
const line_name: []const u8 = "line-number";

pub const macro_name: []const u8 = "macro";
pub const string_command_name: []const u8 = "string";
pub const file_command_name: []const u8 = "file";
pub const stdin_command_name: []const u8 = "stdin";

matches: yazap.ArgMatches,
allocator: std.mem.Allocator,
app: yazap.App,

pub fn init(gpa: std.mem.Allocator, argv: []const [:0]const u8) !Config {
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

    var app = yazap.App.init(gpa, "grok", app_descr);

    var root_cmd = app.rootCommand();
    root_cmd.setProperty(.help_on_empty_args);
    root_cmd.setProperty(.subcommand_required);

    const patterns_opt = yazap.Arg.multiValuesOption(
        patterns_name,
        'p',
        "One or more pattern files. If not set, current directory used to search all *.patterns files",
        512,
    );

    var macro_opt = yazap.Arg.singleValueOption(macro_name, 'm', "Pattern macros to build regexp");
    macro_opt.setValuePlaceholder("STRING");
    macro_opt.setProperty(.takes_value);
    const info_opt = yazap.Arg.booleanOption("info", 'i', "Dont work like grep i.e. output matched string with additional info");
    const count_opt = yazap.Arg.booleanOption(count_name, 'c', "Print only matched strings count");
    const line_num_opt = yazap.Arg.booleanOption(line_name, 'n', "Print line number along with output lines");

    var str_cmd = app.createCommand(string_command_name, "Single string matching mode");
    str_cmd.setProperty(.help_on_empty_args);
    str_cmd.setProperty(.positional_arg_required);
    const string_opt = yazap.Arg.positional("STRING", "String to match", null);
    try str_cmd.addArg(patterns_opt);
    try str_cmd.addArg(macro_opt);
    try str_cmd.addArg(info_opt);
    try str_cmd.addArg(string_opt);

    var file_cmd = app.createCommand(file_command_name, "File matching mode");
    file_cmd.setProperty(.help_on_empty_args);
    file_cmd.setProperty(.positional_arg_required);
    const file_opt = yazap.Arg.positional("PATH", "Full path to file to read data from", null);

    try file_cmd.addArg(patterns_opt);
    try file_cmd.addArg(macro_opt);
    try file_cmd.addArg(info_opt);
    try file_cmd.addArg(count_opt);
    try file_cmd.addArg(line_num_opt);
    try file_cmd.addArg(file_opt);

    var stdin_cmd = app.createCommand(stdin_command_name, "Standard input (stdin) matching mode");
    stdin_cmd.setProperty(.help_on_empty_args);
    try stdin_cmd.addArg(patterns_opt);
    try stdin_cmd.addArg(macro_opt);
    try stdin_cmd.addArg(info_opt);
    try stdin_cmd.addArg(count_opt);
    try stdin_cmd.addArg(line_num_opt);

    var macro_cmd = app.createCommand(macro_name, "Macro information mode where a macro real regexp can be displayed or to get all supported macroses");
    const macro_name_opt = yazap.Arg.positional("MACRO", "Macro name to expand real regular expression", null);
    try macro_cmd.addArg(patterns_opt);
    try macro_cmd.addArg(macro_name_opt);

    try root_cmd.addSubcommand(str_cmd);
    try root_cmd.addSubcommand(file_cmd);
    try root_cmd.addSubcommand(stdin_cmd);
    try root_cmd.addSubcommand(macro_cmd);

    const matches = try app.parseFrom(argv);

    return Config{
        .matches = matches,
        .allocator = gpa,
        .app = app,
    };
}

pub fn deinit(self: *Config) void {
    self.app.deinit();
}

pub fn run(self: *Config, command: []const u8, handler: *const fn (std.mem.Allocator, yazap.ArgMatches) void) bool {
    if (self.matches.subcommandMatches(command)) |cmd_matches| {
        const patterns = cmd_matches.getMultiValues(patterns_name);
        front.compileLib(self.allocator, patterns) catch |e| {
            std.debug.print("Failed to compile lib: {}\n", .{e});
            return true;
        };

        handler(self.allocator, cmd_matches);
        return true;
    }
    return false;
}

pub fn getMacro(match: yazap.ArgMatches) ?[]const u8 {
    return match.getSingleValue(macro_name);
}

pub fn isInfoMode(match: yazap.ArgMatches) bool {
    return match.containsArg("info");
}

pub fn isCountMode(match: yazap.ArgMatches) bool {
    return match.containsArg(count_name);
}

pub fn printLineNumber(match: yazap.ArgMatches) bool {
    return match.containsArg(line_name);
}

test "correct string parsing and run integration test" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const command_line: []const [:0]const u8 = &[_][:0]const u8{ "string", "-m", "YEAR", "2000" };
    var config = try Config.init(arena.allocator(), command_line);
    defer config.deinit();
    const run_result = config.run("string", &testStringAction);
    try std.testing.expect(run_result);
}

test "incorrect string parsing no positional parameter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const command_line: []const [:0]const u8 = &[_][:0]const u8{ "string", "-m", "YEAR" };
    const err = Config.init(arena.allocator(), command_line);
    try std.testing.expectError(yazap.yazap_error.ParseError.PositionalArgumentNotProvided, err);
}

test "incorrect file parsing no positional parameter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const command_line: []const [:0]const u8 = &[_][:0]const u8{ "file", "-m", "YEAR" };
    const err = Config.init(arena.allocator(), command_line);
    try std.testing.expectError(yazap.yazap_error.ParseError.PositionalArgumentNotProvided, err);
}

fn testStringAction(_: std.mem.Allocator, _: yazap.ArgMatches) void {
    if (!builtin.is_test) {
        @compileError("This function is only available in test builds");
    }
}
