const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const strip = optimize != .Debug;
    const options = b.addOptions();

    const version_opt = b.option([]const u8, "version", "The version of the app") orelse "0.3.0-dev";
    options.addOption([]const u8, "version", version_opt);

    const flex_input = "src/grok/grok.lex";
    const flex_output = "--outfile=src/grok/generated/grok.flex.c";

    var flex_args: []const []const u8 = undefined;
    const os_tag = builtin.os.tag;
    if (os_tag == .linux) {
        flex_args = &[_][]const u8{
            "flex",
            "--fast",
            flex_output,
            flex_input,
        };
    } else if (os_tag == .windows) {
        flex_args = &[_][]const u8{
            "win_flex.exe",
            "--fast",
            "--wincompat",
            flex_output,
            flex_input,
        };
    } else if (os_tag == .macos) {
        flex_args = &[_][]const u8{
            "/usr/local/opt/flex/bin/flex",
            "--fast",
            flex_output,
            flex_input,
        };
    }

    const flex_step = b.addSystemCommand(flex_args);

    const bison_input = "src/grok/grok.y";
    const bison_output = "--output=src/grok/generated/grok.tab.c";

    var bison_args: []const []const u8 = undefined;
    if (os_tag == .linux) {
        bison_args = &[_][]const u8{
            "bison",
            bison_output,
            "-dy",
            bison_input,
        };
    } else if (os_tag == .windows) {
        bison_args = &[_][]const u8{
            "win_bison.exe",
            bison_output,
            "-dy",
            bison_input,
        };
    } else if (os_tag == .macos) {
        bison_args = &[_][]const u8{
            "/usr/local/opt/flex/bin/flex",
            bison_output,
            "-dy",
            bison_input,
        };
    }

    const bison_step = b.addSystemCommand(bison_args);
    bison_step.step.dependOn(&flex_step.step);

    const pcre2_dep = b.dependency("pcre2", .{
        .target = target,
        .optimize = optimize,
    });

    const pcre = pcre2_dep.artifact("pcre2-8");

    const yazap = b.dependency("yazap", .{});

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
    exe.step.dependOn(&bison_step.step);
    const glob_dep = b.dependency("glob", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("glob", glob_dep.module("glob"));
    exe.root_module.addImport("yazap", yazap.module("yazap"));
    exe.root_module.addIncludePath(b.path("src/grok/generated"));
    exe.root_module.addIncludePath(b.path("src/srclib"));
    exe.root_module.addIncludePath(b.path("src"));
    exe.root_module.addCSourceFiles(.{ .files = &libgrok_sources, .flags = &[_][]const u8{} });
    exe.root_module.linkLibrary(pcre);
    exe.root_module.addImport("build_options", options.createModule());

    // const tst = b.addExecutable(.{
    //     .name = "_tst",
    //     .root_module = b.createModule(.{
    //         .optimize = optimize,
    //         .target = target,
    //         .strip = strip,
    //         .link_libc = true,
    //         .link_libcpp = true,
    //     }),
    // });
    // tst.root_module.addIncludePath(b.path("src/grok/generated"));
    // tst.root_module.addIncludePath(pcre.installed_headers.items[0].getSource().dirname());
    // tst.root_module.addIncludePath(b.path("src/srclib"));
    // tst.root_module.linkLibrary(lib);

    b.installArtifact(exe);

    // const run_unit_tests = b.addRunArtifact(tst);
    // run_unit_tests.step.dependOn(b.getInstallStep());
    // if (b.args) |args| {
    //     run_unit_tests.addArgs(args);
    // }

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    // const test_step = b.step("test", "Run unit tests");
    // test_step.dependOn(&run_unit_tests.step);
}

const libgrok_sources = [_][]const u8{
    "src/grok/generated/grok.flex.c",
    "src/grok/generated/grok.tab.c",
    "src/srclib/lib.c",
};
