const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const pcre2_dep = b.dependency("pcre2", .{
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addStaticLibrary(.{
        .name = "libgrok",
        .target = target,
        .optimize = optimize,
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
        .target = target,
        .optimize = optimize,
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
    });
    const catch2_lib = catch2_dep.artifact("Catch2");
    const catch2_main = catch2_dep.artifact("Catch2WithMain");

    const tst = b.addExecutable(.{
        .name = "_tst",
        .target = target,
        .optimize = optimize,
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
