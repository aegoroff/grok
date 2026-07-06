const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const strip = optimize != .Debug;
    const options = b.addOptions();

    const version_opt = b.option([]const u8, "version", "The version of the app") orelse "0.5.0-dev";
    options.addOption([]const u8, "version", version_opt);

    const c_code_path = "src/grok";
    const generated_path = std.fmt.allocPrint(b.allocator, "{s}/generated", .{c_code_path}) catch "";

    ensureDirExists(b, generated_path);

    const flex_input = std.fmt.allocPrint(b.allocator, "{s}/grok.lex", .{c_code_path}) catch "";
    const flex_src = std.fmt.allocPrint(b.allocator, "{s}/grok.flex.c", .{generated_path}) catch "";
    const flex_hdr = std.fmt.allocPrint(b.allocator, "{s}/grok.flex.h", .{generated_path}) catch "";
    const flex_opt = std.fmt.allocPrint(b.allocator, "--outfile={s}", .{flex_src}) catch "";
    const flex_hdr_opt = std.fmt.allocPrint(b.allocator, "--header-file={s}", .{flex_hdr}) catch "";

    const bison_input = std.fmt.allocPrint(b.allocator, "{s}/grok.y", .{c_code_path}) catch "";
    const bison_src = std.fmt.allocPrint(b.allocator, "{s}/grok.tab.c", .{generated_path}) catch "";
    const bison_opt = std.fmt.allocPrint(b.allocator, "--output={s}", .{bison_src}) catch "";

    const c_sources = [_][]const u8{
        flex_src,
        bison_src,
    };

    var flex_args: []const []const u8 = undefined;
    var bison_args: []const []const u8 = undefined;

    switch (builtin.os.tag) {
        .linux => {
            flex_args = &[_][]const u8{ "flex", "--fast", flex_opt, flex_hdr_opt, flex_input };
            bison_args = &[_][]const u8{ "bison", bison_opt, "-dy", "-Wno-yacc", "-Wno-other", bison_input };
        },
        .windows => {
            flex_args = &[_][]const u8{ "win_flex.exe", "--fast", "--wincompat", flex_opt, flex_hdr_opt, flex_input };
            bison_args = &[_][]const u8{ "win_bison.exe", bison_opt, "-dy", "-Wno-yacc", "-Wno-other", bison_input };
        },
        .macos => {
            flex_args = &[_][]const u8{ "/usr/local/opt/flex/bin/flex", "--fast", flex_opt, flex_hdr_opt, flex_input };
            bison_args = &[_][]const u8{ "/usr/local/opt/bison/bin/bison", bison_opt, "-dy", "-Wno-yacc", "-Wno-other", bison_input };
        },
        else => @compileError("Unsupported OS: " ++ @tagName(builtin.os.tag)),
    }

    const flex = b.addSystemCommand(flex_args);
    const bison = b.addSystemCommand(bison_args);
    bison.step.dependOn(&flex.step);

    const yazap = b.dependency("yazap", .{});
    const fehler = b.dependency("fehler", .{});

    const glob_dep = b.dependency("glob", .{ .target = target, .optimize = optimize });
    const pcre2_dep = b.dependency("pcre2", .{ .target = target, .optimize = optimize });

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("src/grok/c.h"),
        .target = target,
        .optimize = optimize,
    });
    translate_c.addIncludePath(b.path(c_code_path));
    translate_c.addIncludePath(b.path(generated_path));
    translate_c.step.dependOn(&bison.step);

    const translate_pcre = b.addTranslateC(.{
        .root_source_file = pcre2_dep.namedLazyPath("pcre2.h"),
        .target = target,
        .optimize = optimize,
    });
    translate_pcre.defineCMacro("PCRE2_CODE_UNIT_WIDTH", "8");
    translate_pcre.step.dependOn(&pcre2_dep.artifact("pcre2-8").step);

    const c_lib = b.addLibrary(.{
        .name = "grok-c",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    c_lib.root_module.addIncludePath(b.path(c_code_path));
    c_lib.root_module.addIncludePath(b.path(generated_path));
    c_lib.root_module.addCSourceFiles(.{ .files = &c_sources, .flags = &[_][]const u8{} });
    c_lib.step.dependOn(&bison.step);

    const deps = ModuleDeps{
        .b = b,
        .yazap = yazap,
        .fehler = fehler,
        .glob_dep = glob_dep,
        .pcre2_dep = pcre2_dep,
        .c_lib = c_lib,
        .options = options,
        .translate_c = translate_c,
        .translate_pcre = translate_pcre,
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
    deps.applyTo(exe.root_module);

    if (optimize == .ReleaseFast and target.result.os.tag != .macos and target.result.os.tag != .windows) {
        exe.lto = .full;
        exe.link_gc_sections = true;
    }

    b.installArtifact(exe);

    // Unit tests
    const unit_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    deps.applyTo(unit_tests.root_module);

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");

    // Fuzzing
    const fuzzing = b.addTest(.{
        .name = "fuzzing",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/fuzz.zig"),
            .optimize = optimize,
            .target = target,
            .link_libc = true,
        }),
    });
    deps.applyTo(fuzzing.root_module);

    const run_fuzzing = b.addRunArtifact(fuzzing);
    const fuzz_string_step = b.step("fuzzing", "Fuzzing");
    fuzz_string_step.dependOn(&run_fuzzing.step);

    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_fuzzing.step);

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
    fehler: *std.Build.Dependency,
    glob_dep: *std.Build.Dependency,
    pcre2_dep: *std.Build.Dependency,
    c_lib: *std.Build.Step.Compile,
    options: *std.Build.Step.Options,
    translate_c: *std.Build.Step.TranslateC,
    translate_pcre: *std.Build.Step.TranslateC,

    fn applyTo(self: ModuleDeps, mod: *std.Build.Module) void {
        mod.addImport("glob", self.glob_dep.module("glob"));
        mod.addImport("yazap", self.yazap.module("yazap"));
        mod.addImport("fehler", self.fehler.module("fehler"));
        mod.linkLibrary(self.c_lib);
        mod.linkLibrary(self.pcre2_dep.artifact("pcre2-8"));
        mod.addImport("build_options", self.options.createModule());
        mod.addImport("c", self.translate_c.createModule());
        mod.addImport("re", self.translate_pcre.createModule());
    }
};

fn ensureDirExists(b: *std.Build, dir_path: []const u8) void {
    const full_path = b.pathFromRoot(dir_path);
    var dir = std.Io.Dir.cwd().openDir(b.graph.io, full_path, .{}) catch {
        std.Io.Dir.cwd().createDir(b.graph.io, full_path, .default_dir) catch |err| {
            std.debug.print("Failed to create directory '{s}': {s}\n", .{ full_path, @errorName(err) });
        };
        return;
    };
    dir.close(b.graph.io);
}
