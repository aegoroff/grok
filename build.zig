const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const strip = optimize != .Debug;
    const options = b.addOptions();

    const version_opt = b.option([]const u8, "version", "The version of the app") orelse "0.3.0-dev";
    options.addOption([]const u8, "version", version_opt);

    const c_code_path = "src/grok";
    const generated_path = std.fmt.allocPrint(b.allocator, "{s}/generated", .{c_code_path}) catch "";

    ensureDirExists(b, generated_path) catch unreachable;

    const flex_input = std.fmt.allocPrint(b.allocator, "{s}/grok.lex", .{c_code_path}) catch "";
    const flex_src = std.fmt.allocPrint(b.allocator, "{s}/grok.flex.c", .{generated_path}) catch "";
    const flex_opt = std.fmt.allocPrint(b.allocator, "--outfile={s}", .{flex_src}) catch "";

    const bison_input = std.fmt.allocPrint(b.allocator, "{s}/grok.y", .{c_code_path}) catch "";
    const bison_src = std.fmt.allocPrint(b.allocator, "{s}/grok.tab.c", .{generated_path}) catch "";
    const bison_opt = std.fmt.allocPrint(b.allocator, "--output={s}", .{bison_src}) catch "";

    const c_sources = [_][]const u8{
        flex_src,
        bison_src,
        std.fmt.allocPrint(b.allocator, "{s}/lib.c", .{c_code_path}) catch "",
    };

    var flex_args: []const []const u8 = undefined;
    var bison_args: []const []const u8 = undefined;

    switch (builtin.os.tag) {
        .linux => {
            flex_args = &[_][]const u8{ "flex", "--fast", flex_opt, flex_input };
            bison_args = &[_][]const u8{ "bison", bison_opt, "-dy", bison_input };
        },
        .windows => {
            flex_args = &[_][]const u8{ "win_flex.exe", "--fast", "--wincompat", flex_opt, flex_input };
            bison_args = &[_][]const u8{ "win_bison.exe", bison_opt, "-dy", bison_input };
        },
        .macos => {
            flex_args = &[_][]const u8{ "/usr/local/opt/flex/bin/flex", "--fast", flex_opt, flex_input };
            bison_args = &[_][]const u8{ "/usr/local/opt/bison/bin/bison", bison_opt, "-dy", bison_input };
        },
        else => @compileError("Unsupported OS: " ++ @tagName(builtin.os.tag)),
    }

    const flex = b.addSystemCommand(flex_args);
    const bison = b.addSystemCommand(bison_args);
    bison.step.dependOn(&flex.step);

    const yazap = b.dependency("yazap", .{});
    const glob_dep = b.dependency("glob", .{ .target = target, .optimize = optimize });
    const pcre2_dep = b.dependency("pcre2", .{ .target = target, .optimize = optimize });

    const deps = ModuleDeps{
        .b = b,
        .yazap = yazap,
        .glob_dep = glob_dep,
        .pcre2_dep = pcre2_dep,
        .c_sources = &c_sources,
        .c_code_path = c_code_path,
        .generated_path = generated_path,
        .options = options,
    };

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
    exe.step.dependOn(&bison.step);
    deps.applyTo(exe.root_module);

    if (optimize == .ReleaseFast and target.result.os.tag != .macos) {
        exe.lto = .full;
        exe.link_gc_sections = true;
    }

    b.installArtifact(exe);

    // Unit tests
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .optimize = optimize,
            .target = target,
            .link_libc = true,
        }),
    });
    unit_tests.step.dependOn(&bison.step);
    deps.applyTo(unit_tests.root_module);

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Packaging
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

const ModuleDeps = struct {
    b: *std.Build,
    yazap: *std.Build.Dependency,
    glob_dep: *std.Build.Dependency,
    pcre2_dep: *std.Build.Dependency,
    c_sources: []const []const u8,
    c_code_path: []const u8,
    generated_path: []const u8,
    options: *std.Build.Step.Options,

    fn applyTo(self: ModuleDeps, mod: *std.Build.Module) void {
        mod.addImport("glob", self.glob_dep.module("glob"));
        mod.addImport("yazap", self.yazap.module("yazap"));
        mod.addIncludePath(self.b.path(self.generated_path));
        mod.addIncludePath(self.b.path(self.c_code_path));
        mod.addCSourceFiles(.{ .files = self.c_sources, .flags = &[_][]const u8{} });
        mod.linkLibrary(self.pcre2_dep.artifact("pcre2-8"));
        mod.addImport("build_options", self.options.createModule());
    }
};

fn ensureDirExists(b: *std.Build, dir_path: []const u8) !void {
    const full_path = b.pathFromRoot(dir_path);
    std.fs.cwd().makePath(full_path) catch |err| {
        std.debug.print("Failed to create directory '{s}': {s}\n", .{ full_path, @errorName(err) });
        return err;
    };
}
