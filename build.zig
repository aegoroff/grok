const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // const libapr_dep = b.dependency("libapr", .{
    //     .target = target,
    //     .optimize = optimize,
    // });

    // const libaprutil_dep = b.dependency("libapr", .{
    //     .target = target,
    //     .optimize = optimize,
    // });

    const lib = b.addStaticLibrary(.{
        .name = "libgrok",
        .target = target,
        .optimize = optimize,
    });
    // lib.linkLibrary(libapr_dep.artifact("apr-1"));
    // lib.linkLibrary(libaprutil_dep.artifact("aprutil-1"));
    lib.linkLibC();
    lib.addIncludePath(.{ .path = "src/srclib" });

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
