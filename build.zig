const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const strip = optimize != .Debug;

    const pcre2_dep = b.dependency("pcre2", .{
        .target = target,
        .optimize = optimize,
    });

    const pcre = pcre2_dep.artifact("pcre2-8");

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
    const clap_dep = b.dependency("clap", .{
        .optimize = optimize,
        .target = target,
    });
    const glob_dep = b.dependency("glob", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("glob", glob_dep.module("glob"));
    exe.root_module.addImport("clap", clap_dep.module("clap"));
    exe.root_module.addIncludePath(pcre.installed_headers.items[0].getSource().dirname());
    exe.root_module.addIncludePath(b.path("src/grok/generated"));
    exe.root_module.addIncludePath(b.path("src/srclib"));
    exe.root_module.addIncludePath(b.path("src"));
    exe.root_module.addCSourceFiles(.{ .files = &libgrok_sources, .flags = &[_][]const u8{} });
    exe.root_module.linkLibrary(pcre);

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
