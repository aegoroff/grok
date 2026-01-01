pub const Grok = @This();

const std = @import("std");
const yazap = @import("yazap");
const builtin = @import("builtin");
const build_options = @import("build_options");
const glob = @import("glob");
const front = @import("frontend.zig");
const patterns_name: []const u8 = "patterns";
pub const macro_name: []const u8 = "macro";
pub const string_command_name: []const u8 = "string";
pub const file_command_name: []const u8 = "file";
pub const stdin_command_name: []const u8 = "stdin";

matches: yazap.ArgMatches,
allocator: std.mem.Allocator,
app: yazap.App,

pub fn init(allocator: std.mem.Allocator, argv: []const [:0]const u8) !Grok {
    const app_descr_template =
        \\Grok regexp macro processor {s} {s}
        \\Copyright (C) 2018-2026 Alexander Egorov. All rights reserved.
    ;
    const query = std.Target.Query.fromTarget(&builtin.target);
    const app_descr = try std.fmt.allocPrint(
        allocator,
        app_descr_template,
        .{ build_options.version, @tagName(query.cpu_arch.?) },
    );

    var app = yazap.App.init(allocator, "grok", app_descr);

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
    try file_cmd.addArg(file_opt);

    var stdin_cmd = app.createCommand(stdin_command_name, "Standard input (stdin) matching mode");
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

    const matches = try app.parseFrom(argv);

    return Grok{
        .matches = matches,
        .allocator = allocator,
        .app = app,
    };
}

pub fn deinit(self: *Grok) void {
    self.app.deinit();
}

pub fn run(self: *Grok, command: []const u8, handler: *const fn (std.mem.Allocator, yazap.ArgMatches) void) bool {
    if (self.matches.subcommandMatches(command)) |cmd_matches| {
        const patterns = cmd_matches.getMultiValues(patterns_name);
        self.compileLib(patterns) catch |e| {
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

fn compileLib(self: *Grok, paths: ?[][]const u8) !void {
    front.init(self.allocator);
    if (paths == null or paths.?.len == 0) {
        // Use default
        var lib_path: []const u8 = undefined;
        const os_tag = builtin.os.tag;
        if (os_tag == .linux) {
            lib_path = "/usr/share/grok/patterns";
        } else {
            lib_path = try std.fs.selfExeDirPathAlloc(self.allocator);
        }

        try self.compileDir(lib_path);
    } else {
        for (paths.?) |path| {
            self.compileDir(path) catch {
                try front.compileFile(path.ptr);
            };
        }
    }
}

fn compileDir(self: *Grok, lib_path: []const u8) !void {
    var dir: std.fs.Dir = undefined;
    const options: std.fs.Dir.OpenOptions = .{ .iterate = true };
    if (std.fs.path.isAbsolute(lib_path)) {
        dir = try std.fs.openDirAbsolute(lib_path, options);
    } else {
        dir = try std.fs.cwd().openDir(lib_path, options);
    }
    var walker = try dir.walk(self.allocator);
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
                    const p = try entry.dir.realpathAlloc(self.allocator, entry.basename);
                    try front.compileFile(p.ptr);
                }
            },
            else => {},
        }
    }
}

test "correct string parsing and run integration test" {
    const allocator = std.heap.c_allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const command_line: []const [:0]const u8 = &[_][:0]const u8{ "string", "-m", "YEAR", "2000" };
    var grok = try Grok.init(arena.allocator(), command_line);
    defer grok.deinit();
    const run_result = grok.run("string", &testAction);
    try std.testing.expect(run_result);
}

test "incorrect string parsing no positional parameter" {
    const allocator = std.heap.c_allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const command_line: []const [:0]const u8 = &[_][:0]const u8{ "string", "-m", "YEAR" };
    const err = Grok.init(arena.allocator(), command_line);
    try std.testing.expectError(yazap.yazap_error.ParseError.PositionalArgumentNotProvided, err);
}

test "incorrect file parsing no positional parameter" {
    const allocator = std.heap.c_allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const command_line: []const [:0]const u8 = &[_][:0]const u8{ "file", "-m", "YEAR" };
    const err = Grok.init(arena.allocator(), command_line);
    try std.testing.expectError(yazap.yazap_error.ParseError.PositionalArgumentNotProvided, err);
}

fn testAction(_: std.mem.Allocator, _: yazap.ArgMatches) void {}
