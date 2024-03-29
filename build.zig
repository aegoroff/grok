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
    lib.linkLibrary(pcre2_dep.artifact("pcre2"));
    lib.linkLibC();
    lib.addIncludePath(.{ .path = "src/srclib" });
    lib.addIncludePath(.{ .path = "src/grok" });

    lib.addCSourceFiles(&libgrok_sources, &[_][]const u8{});
    b.installArtifact(lib);
}

const libgrok_sources = [_][]const u8{
    "src/srclib/argtable3.c",
    "src/srclib/dbg_helpers.c",
    "src/srclib/encoding.c",
    "src/srclib/lib.c",
    "src/srclib/sort.c",
};
