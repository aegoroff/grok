const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const strip = optimize != .Debug;
    const options = b.addOptions();

    const version_opt = b.option([]const u8, "version", "The version of the app") orelse "0.3.0-dev";
    options.addOption([]const u8, "version", version_opt);

    const generated_path = "src/grok/generated";

    ensureDirExists(b, generated_path) catch unreachable;

    const flex_input = "src/grok/grok.lex";
    const flex_output = std.fmt.allocPrint(b.allocator, "{s}/grok.flex.c", .{generated_path}) catch "";
    const flex_out_opt = std.fmt.allocPrint(b.allocator, "--outfile={s}", .{flex_output}) catch "";

    const bison_input = "src/grok/grok.y";
    const bison_output = std.fmt.allocPrint(b.allocator, "{s}/grok.tab.c", .{generated_path}) catch "";
    const bison_out_opt = std.fmt.allocPrint(b.allocator, "--output={s}", .{bison_output}) catch "";

    const libgrok_sources = [_][]const u8{
        flex_output,
        bison_output,
        "src/lib.c",
    };

    var flex_args: []const []const u8 = undefined;
    var bison_args: []const []const u8 = undefined;

    switch (builtin.os.tag) {
        .linux => {
            flex_args = &[_][]const u8{ "flex", "--fast", flex_out_opt, flex_input };
            bison_args = &[_][]const u8{ "bison", bison_out_opt, "-dy", bison_input };
        },
        .windows => {
            flex_args = &[_][]const u8{ "win_flex.exe", "--fast", "--wincompat", flex_out_opt, flex_input };
            bison_args = &[_][]const u8{ "win_bison.exe", bison_out_opt, "-dy", bison_input };
        },
        .macos => {
            flex_args = &[_][]const u8{ "/usr/local/opt/flex/bin/flex", "--fast", flex_out_opt, flex_input };
            bison_args = &[_][]const u8{ "/usr/local/opt/bison/bin/bison", bison_out_opt, "-dy", bison_input };
        },
        else => @compileError("Unsupported OS: " ++ @tagName(builtin.os.tag)),
    }

    const flex = b.addSystemCommand(flex_args);
    const bison = b.addSystemCommand(bison_args);

    const yazap = b.dependency("yazap", .{});
    const glob_dep = b.dependency("glob", .{ .target = target, .optimize = optimize });
    const pcre2_dep = b.dependency("pcre2", .{ .target = target, .optimize = optimize });

    const exe = b.addExecutable(.{
        .name = "grok",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .optimize = optimize,
            .target = target,
            .strip = strip,
            .link_libc = true,
        }),
    });

    bison.step.dependOn(&flex.step);
    exe.step.dependOn(&bison.step);

    exe.root_module.addImport("glob", glob_dep.module("glob"));
    exe.root_module.addImport("yazap", yazap.module("yazap"));
    exe.root_module.addIncludePath(b.path(generated_path));
    exe.root_module.addIncludePath(b.path("src"));
    exe.root_module.addCSourceFiles(.{ .files = &libgrok_sources, .flags = &[_][]const u8{} });
    exe.root_module.linkLibrary(pcre2_dep.artifact("pcre2-8"));
    exe.root_module.addImport("build_options", options.createModule());

    b.installArtifact(exe);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .optimize = optimize,
            .target = target,
            .link_libc = true,
        }),
    });
    unit_tests.root_module.addImport("glob", glob_dep.module("glob"));
    unit_tests.root_module.addImport("yazap", yazap.module("yazap"));
    unit_tests.root_module.addIncludePath(b.path(generated_path));
    unit_tests.root_module.addIncludePath(b.path("src"));
    unit_tests.root_module.addCSourceFiles(.{ .files = &libgrok_sources, .flags = &[_][]const u8{} });
    unit_tests.root_module.linkLibrary(pcre2_dep.artifact("pcre2-8"));
    unit_tests.root_module.addImport("build_options", options.createModule());

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const tr = target.result;
    const tar_file = std.fmt.allocPrint(b.allocator, "{s}/grok-{s}-{s}-{s}-{s}.tar", .{
        b.install_prefix,
        version_opt,
        @tagName(tr.cpu.arch),
        @tagName(tr.os.tag),
        @tagName(tr.abi),
    }) catch "";

    const binary_step = b.addSystemCommand(&.{
        "tar",
        "-cvf", // c - create, f - file
        tar_file,
        "-C",
        b.exe_dir,
        ".",
    });
    const license_step = b.addSystemCommand(&.{
        "tar",
        "-rvf", // r - append, f - file
        tar_file,
        "-C",
        ".",
        "LICENSE.txt",
    });
    const patterns_step = b.addSystemCommand(&.{
        "tar",
        "-rvf", // r - append, f - file
        tar_file,
        "-C",
        "patterns/",
        ".",
    });
    const gzip_step = b.addSystemCommand(&.{
        "gzip",
        tar_file,
    });

    binary_step.step.dependOn(b.getInstallStep());
    license_step.step.dependOn(&binary_step.step);
    patterns_step.step.dependOn(&license_step.step);
    gzip_step.step.dependOn(&patterns_step.step);

    const archive_step = b.step("archive", "Create a tar.gz archive of the build");
    archive_step.dependOn(&gzip_step.step);
}

fn ensureDirExists(b: *std.Build, dir_path: []const u8) !void {
    const full_path = b.pathFromRoot(dir_path);
    std.fs.cwd().makePath(full_path) catch |err| {
        std.debug.print("Failed to create directory '{s}': {s}\n", .{ full_path, @errorName(err) });
        return err;
    };
}
