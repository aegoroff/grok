const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const strip = optimize != .Debug;

    const pcre2_dep = b.dependency("pcre2", .{
        .target = target,
        .optimize = optimize,
        .strip = strip,
    });

    const lib = b.addLibrary(.{
        .name = "libgrok",
        .root_module = b.createModule(.{
            .optimize = optimize,
            .target = target,
            .strip = strip,
        }),
    });
    lib.linkage = .static;

    const pcre = pcre2_dep.artifact("pcre2-8");
    lib.linkLibrary(pcre);
    lib.linkLibC();
    lib.addObjectFile(b.path("external_lib/lib/apr/lib/libapr-1.a"));
    lib.addObjectFile(b.path("external_lib/lib/apr/lib/libaprutil-1.a"));
    lib.addIncludePath(b.path("src/srclib"));
    lib.addIncludePath(b.path("src/grok"));
    lib.addIncludePath(b.path("src/grok/generated"));
    lib.addIncludePath(b.path("external_lib/lib/apr/include/apr-1"));

    lib.addCSourceFiles(.{ .files = &libgrok_sources, .flags = &[_][]const u8{} });

    const exe = b.addExecutable(.{
        .name = "grok",
        .root_module = b.createModule(.{
            .optimize = optimize,
            .target = target,
            .strip = strip,
        }),
    });
    exe.addCSourceFiles(.{ .files = &grok_sources, .flags = &[_][]const u8{} });
    exe.addIncludePath(b.path("src/srclib"));
    exe.addIncludePath(b.path("src/grok"));
    exe.addIncludePath(b.path("src/grok/generated"));
    exe.addIncludePath(b.path("external_lib/lib/apr/include/apr-1"));
    exe.addIncludePath(b.path("external_lib/lib/argtable3"));
    exe.addIncludePath(pcre.installed_headers.items[0].getSource().dirname());

    exe.addObjectFile(b.path("external_lib/lib/apr/lib/libapr-1.a"));
    exe.addObjectFile(b.path("external_lib/lib/apr/lib/libaprutil-1.a"));
    exe.linkLibrary(lib);
    exe.linkLibC();

    const catch2_dep = b.dependency("catch2", .{
        .target = target,
        .optimize = optimize,
        .strip = strip,
    });
    const catch2_lib = catch2_dep.artifact("Catch2");
    const catch2_main = catch2_dep.artifact("Catch2WithMain");

    const tst = b.addExecutable(.{
        .name = "_tst",
        .root_module = b.createModule(.{
            .optimize = optimize,
            .target = target,
            .strip = strip,
        }),
    });
    tst.addCSourceFiles(.{ .files = &tst_sources, .flags = &[_][]const u8{} });
    tst.addIncludePath(b.path("src/srclib"));
    tst.addIncludePath(b.path("src/grok"));
    tst.addIncludePath(b.path("src/grok/generated"));
    tst.addIncludePath(b.path("external_lib/lib/apr/include/apr-1"));
    tst.addIncludePath(pcre.installed_headers.items[0].getSource().dirname());
    tst.addIncludePath(b.path("src/srclib"));

    tst.addObjectFile(b.path("external_lib/lib/apr/lib/libapr-1.a"));
    tst.addObjectFile(b.path("external_lib/lib/apr/lib/libaprutil-1.a"));
    tst.linkLibrary(lib);
    tst.linkLibrary(catch2_lib);
    tst.linkLibrary(catch2_main);
    tst.linkLibC();
    tst.linkLibCpp();

    b.installArtifact(lib);
    b.installArtifact(exe);
    b.installArtifact(tst);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const run_unit_tests = b.addRunArtifact(tst);
    run_unit_tests.step.dependOn(b.getInstallStep());

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}

const libgrok_sources = [_][]const u8{
    "src/srclib/dbg_helpers.c",
    "src/srclib/encoding.c",
    "src/srclib/lib.c",
    "src/srclib/sort.c",
    "src/grok/generated/grok.flex.c",
    "src/grok/generated/grok.tab.c",
};

const grok_sources = [_][]const u8{
    "src/grok/backend.c",
    "src/grok/configuration.c",
    "src/grok/frontend.c",
    "src/grok/grok.c",
    "src/grok/pattern.c",
    "external_lib/lib/argtable3/argtable3.c",
};

const tst_sources = [_][]const u8{
    "src/_tst/encoding.cpp",
    "src/_tst/lib_test.cpp",
    "src/_tst/size_to_string.cpp",
    "src/_tst/time_to_string.cpp",
    "src/_tst/trim_tests.cpp",
};
