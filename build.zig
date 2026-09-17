const std = @import("std");
const fuzz_wire = @import("src/fuzz_encoding.zig");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = resolveTarget(b);
    const optimize = b.standardOptimizeOption(.{});
    const strip = optimize != .debug;
    const options = b.addOptions();

    const version_opt = b.option([]const u8, "version", "The version of the app") orelse "0.6.0-dev";
    options.addOption([]const u8, "version", version_opt);

    const c_code_path = "src/grok";
    const generated_path = b.fmt("{s}/generated", .{c_code_path});

    ensureDirExists(b, generated_path);

    const flex_input = b.fmt("{s}/grok.lex", .{c_code_path});
    const flex_src = b.fmt("{s}/grok.flex.c", .{generated_path});
    const flex_hdr = b.fmt("{s}/grok.flex.h", .{generated_path});
    const flex_opt = b.fmt("--outfile={s}", .{flex_src});
    const flex_hdr_opt = b.fmt("--header-file={s}", .{flex_hdr});

    const bison_input = b.fmt("{s}/grok.y", .{c_code_path});
    const bison_src = b.fmt("{s}/grok.tab.c", .{generated_path});
    const bison_opt = b.fmt("--output={s}", .{bison_src});

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

    const pcre2_dep = b.dependency("pcre2", .{
        .target = target,
        .optimize = optimize,
        .support_jit = true,
    });

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

    if (optimize == .fast and target.result.os.tag != .macos and target.result.os.tag != .windows) {
        exe.lto = .full;
        exe.link_gc_sections = true;
    }

    b.installArtifact(exe);

    // Unit tests
    const unit_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

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

    const write_fuzz_macros = b.addWriteFiles();
    const fuzz_macros_path = write_fuzz_macros.add("fuzz_macros.zig", generateFuzzMacros(b));
    const fuzz_corpus_path = write_fuzz_macros.add("fuzz_corpus.zig", generateFuzzCorpus(b));
    const fuzz_macros_mod = b.createModule(.{
        .root_source_file = fuzz_macros_path,
        .optimize = optimize,
        .target = target,
    });
    const fuzz_corpus_mod = b.createModule(.{
        .root_source_file = fuzz_corpus_path,
        .optimize = optimize,
        .target = target,
    });
    fuzzing.root_module.addImport("fuzz_macros", fuzz_macros_mod);
    fuzzing.root_module.addImport("fuzz_corpus", fuzz_corpus_mod);
    fuzzing.step.dependOn(&write_fuzz_macros.step);

    const run_fuzzing = b.addRunArtifact(fuzzing);
    const fuzz_string_step = b.step("fuzzing", "Fuzzing");
    fuzz_string_step.dependOn(&run_fuzzing.step);

    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_fuzzing.step);

    // Packaging — install paths are LazyPath-only since Zig 0.17 (configure/make split).
    const tr = target.result;
    const gz_basename = b.fmt("grok-{s}-{s}-{s}-{s}.tar.gz", .{
        version_opt,
        @tagName(tr.cpu.arch),
        @tagName(tr.os.tag),
        @tagName(tr.abi),
    });

    const pack = b.addSystemCommand(&.{ "tar", "-czvf" });
    const gz_file = pack.addOutputFileArg(gz_basename);
    pack.addArg("-C");
    pack.addDirectoryArg2(.{ .relative = .{ .base = .install_bin } }, .{ .make_absolute = true });
    pack.addArg(".");
    pack.addArg("-C");
    pack.addDirectoryArg2(b.path(""), .{ .make_absolute = true });
    pack.addArg("LICENSE.txt");
    pack.addArg("-C");
    pack.addDirectoryArg2(b.path("patterns"), .{ .make_absolute = true });
    pack.addArg(".");
    pack.step.dependOn(b.getInstallStep());

    // Keep the tarball off the default install step to avoid a cycle with getInstallStep().
    const install_tarball = b.addInstallFile(gz_file, gz_basename);
    const archive_step = b.step("archive", "Create a tar.gz archive of the build");
    archive_step.dependOn(&install_tarball.step);
}

const ModuleDeps = struct {
    b: *std.Build,
    yazap: *std.Build.Dependency,
    fehler: *std.Build.Dependency,
    pcre2_dep: *std.Build.Dependency,
    c_lib: *std.Build.Step.Compile,
    options: *std.Build.Step.Options,
    translate_c: *std.Build.Step.TranslateC,
    translate_pcre: *std.Build.Step.TranslateC,

    fn applyTo(self: ModuleDeps, mod: *std.Build.Module) void {
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
    b.root.createDirPath(b.graph.io, dir_path) catch |err| {
        std.debug.print("Failed to create directory '{s}': {s}\n", .{ dir_path, @errorName(err) });
    };
}

/// Scans `patterns/*.patterns` and returns Zig source for the `fuzz_macros` module.
///
/// Each non-comment line `NAME pattern...` contributes `NAME` to the list.
/// Names are deduplicated, sorted, and emitted as `pub const names = [_][]const u8{...}`.
///
/// The fuzz test (`src/fuzz.zig`) imports this module so its macro picker and
/// corpus stay in sync with the pattern library without maintaining a hand-written list.
fn generateFuzzMacros(b: *std.Build) []const u8 {
    var names = collectPatternMacroNames(b);
    defer {
        for (names.items) |name| b.allocator.free(name);
        names.deinit(b.allocator);
    }

    var out: std.ArrayList(u8) = .empty;
    out.appendSlice(b.allocator, "// Generated by build.zig; do not edit.\n\n" ++
        "pub const names = [_][]const u8{\n") catch @panic("OOM");
    for (names.items) |name| {
        var line_buf: [256]u8 = undefined;
        const line = std.fmt.bufPrint(&line_buf, "    \"{s}\",\n", .{name}) catch @panic("macro name too long");
        out.appendSlice(b.allocator, line) catch @panic("OOM");
    }
    out.appendSlice(b.allocator, "};\n") catch @panic("OOM");
    return out.toOwnedSlice(b.allocator) catch @panic("OOM");
}

/// Reads the first line of `test_assets/logUTF8.log` for the fuzz corpus NLOG seed.
fn readNlogUtf8Line(b: *std.Build) []const u8 {
    const io = b.graph.io;
    const file = b.root.openFile(io, "test_assets/logUTF8.log", .{}) catch |err| {
        std.debug.panic("failed to open test_assets/logUTF8.log: {s}", .{@errorName(err)});
    };
    defer file.close(io);

    var reader_buf: [4096]u8 = undefined;
    var file_reader = file.reader(io, &reader_buf);
    var out: std.Io.Writer.Allocating = .init(b.allocator);
    defer out.deinit();
    _ = file_reader.interface.streamRemaining(&out.writer) catch |err| {
        std.debug.panic("failed to read test_assets/logUTF8.log: {s}", .{@errorName(err)});
    };
    const content = out.written();
    const end = std.mem.indexOfScalar(u8, content, '\n') orelse content.len;
    return b.dupe(content[0..end]);
}

fn macroNameIndex(names: []const []const u8, name: []const u8) u8 {
    for (names, 0..) |entry, i| {
        if (std.mem.eql(u8, entry, name)) return @intCast(i);
    }
    std.debug.panic("unknown fuzz macro: {s}", .{name});
}

fn repeatByte(b: *std.Build, byte: u8, count: usize) []const u8 {
    const subject = b.allocator.alloc(u8, count) catch @panic("OOM");
    @memset(subject, byte);
    return subject;
}

/// Smith-wire fuzz corpus: focused seeds plus one `"x"` entry per macro.
fn generateFuzzCorpus(b: *std.Build) []const u8 {
    var names = collectPatternMacroNames(b);
    defer {
        for (names.items) |name| b.allocator.free(name);
        names.deinit(b.allocator);
    }

    const nlog_line = readNlogUtf8Line(b);
    defer b.allocator.free(nlog_line);
    const nlog_multiline = std.fmt.allocPrint(b.allocator, "{s}\nplain line", .{nlog_line}) catch @panic("OOM");
    defer b.allocator.free(nlog_multiline);
    const notspace_512 = repeatByte(b, 'a', 512);
    defer b.allocator.free(notspace_512);
    const space_512 = repeatByte(b, ' ', 512);
    defer b.allocator.free(space_512);
    const greedy_1024 = repeatByte(b, 'x', 1024);
    defer b.allocator.free(greedy_1024);

    var out: std.ArrayList(u8) = .empty;
    out.appendSlice(b.allocator, "// Generated by build.zig; do not edit.\n" ++
        "pub const all = [_][]const u8{\n") catch @panic("OOM");

    const focused = [_]struct { name: []const u8, flags: u8, subject: []const u8 }{
        .{ .name = "NLOG", .flags = 0, .subject = nlog_line },
        .{ .name = "SYSLOGLINE", .flags = 0, .subject = "Jan  1 00:00:01 localhost sshd[1234]: Accepted password for user from 127.0.0.1 port 22 ssh2" },
        .{ .name = "COMBINEDAPACHELOG", .flags = 0, .subject = "127.0.0.1 - frank [11/Jul/2026:09:00:00 +0300] \"GET /apache_pb.gif HTTP/1.0\" 200 2326 \"http://www.example.com/\" \"Mozilla/5.0\"" },
        .{ .name = "NGINXACCESS", .flags = 0, .subject = "192.168.1.1 - - [11/Jul/2026:09:00:00 +0300] \"GET /index.html HTTP/1.1\" 200 612 \"-\" \"Mozilla/5.0\" \"-\" example.com 0.123" },
        .{ .name = "UUID", .flags = 0, .subject = "550e8400-e29b-41d4-a716-446655440000" },
        .{ .name = "YEAR", .flags = 0b00011, .subject = "2024" },
        .{ .name = "NLOG", .flags = 0b00011, .subject = nlog_line },
        .{ .name = "YEAR", .flags = 0b10011, .subject = "2024\nnot-a-year" },
        .{ .name = "GREEDYDATA", .flags = 0b11000, .subject = "2024\nline2\nline3" },
        .{ .name = "YEAR", .flags = 0b11111, .subject = "2024" },
        .{ .name = "YEAR", .flags = 0, .subject = "2024" },
        .{ .name = "YEAR", .flags = 0b10, .subject = "2024" },
        .{ .name = "YEAR", .flags = 0b01, .subject = "2024" },
        .{ .name = "YEAR", .flags = 0, .subject = "not-a-year" },
        .{ .name = "YEAR", .flags = 0b100, .subject = "not-a-year" },
        .{ .name = "NUMBER", .flags = 0, .subject = "12345" },
        .{ .name = "NUMBER", .flags = 0, .subject = "-3.14" },
        .{ .name = "NUMBER", .flags = 0b01, .subject = "not-a-number" },
        .{ .name = "NUMBER", .flags = 0b100, .subject = "no-match" },
        .{ .name = "IP", .flags = 0, .subject = "192.168.1.1" },
        .{ .name = "IP", .flags = 0, .subject = "999.999.999.999" },
        .{ .name = "IP", .flags = 0b10, .subject = "10.0.0.1" },
        .{ .name = "EMAILADDRESS", .flags = 0b10, .subject = "user@example.com" },
        .{ .name = "NLOG", .flags = 0b01, .subject = nlog_line },
        .{ .name = "NLOG", .flags = 0b1000, .subject = nlog_multiline },
        .{ .name = "NLOG", .flags = 0b10000, .subject = nlog_line },
        .{ .name = "NLOG", .flags = 1 << 5, .subject = nlog_line },
        .{ .name = "NLOG", .flags = 2 << 5, .subject = nlog_line },
        .{ .name = "NLOG", .flags = 3 << 5, .subject = nlog_line },
        .{ .name = "NLOG", .flags = 4 << 5, .subject = nlog_line },
        .{ .name = "NLOG", .flags = fuzz_wire.flagsByte(.{}, .utf32be), .subject = nlog_line },
        .{ .name = "NLOG", .flags = fuzz_wire.flagsByte(.{ .count = true, .line_number = true }, .utf16le), .subject = nlog_multiline },
        .{ .name = "YEAR", .flags = fuzz_wire.flagsByte(.{}, .utf16le), .subject = "2024" },
        .{ .name = "YEAR", .flags = fuzz_wire.flagsByte(.{}, .utf16le), .subject = "" },
        .{ .name = "YEAR", .flags = fuzz_wire.flagsByte(.{}, .utf16le), .subject = "\n\r\t" },
        .{ .name = "YEAR", .flags = fuzz_wire.flagsByte(.{}, .raw), .subject = "" },
        .{ .name = "GREEDYDATA", .flags = fuzz_wire.flagsByte(.{}, .raw), .subject = "" },
        .{ .name = "YEAR", .flags = fuzz_wire.flagsByte(.{}, .raw), .subject = "\n\r\t" },
        .{ .name = "YEAR", .flags = fuzz_wire.flagsByte(.{}, .raw), .subject = "\xd0\xb3\xd1\x80\xd0\xbe\xd0\xba" },
        .{ .name = "NOTSPACE", .flags = fuzz_wire.flagsByte(.{}, .raw), .subject = notspace_512 },
        .{ .name = "SPACE", .flags = fuzz_wire.flagsByte(.{}, .raw), .subject = space_512 },
        .{ .name = "GREEDYDATA", .flags = fuzz_wire.flagsByte(.{}, .raw), .subject = greedy_1024 },
        .{ .name = "YEAR", .flags = fuzz_wire.flagsByte(.{}, .raw), .subject = "20\x0024" },
        .{ .name = "YEAR", .flags = fuzz_wire.flagsByte(.{}, .raw), .subject = "2024\nnot-a-year\n2025" },
    };
    for (focused) |entry| {
        appendSmithCorpusEntry(&out, b, macroNameIndex(names.items, entry.name), entry.flags, entry.subject);
    }
    const binary_subject = [_]u8{ 0x00, 0xff, 0xfe };
    appendSmithCorpusEntry(&out, b, macroNameIndex(names.items, "YEAR"), fuzz_wire.flagsByte(.{}, .raw), &binary_subject);

    for (names.items, 0..) |_, i| {
        appendSmithCorpusEntry(&out, b, @intCast(i), fuzz_wire.flagsByte(.{}, .raw), "x");
    }

    out.appendSlice(b.allocator, "};\n") catch @panic("OOM");
    return out.toOwnedSlice(b.allocator) catch @panic("OOM");
}

fn appendSmithU64(out: *std.ArrayList(u8), b: *std.Build, value: u64) void {
    var buf: [8]u8 = undefined;
    std.mem.writeInt(u64, &buf, value, .little);
    for (buf) |byte| {
        var elem_buf: [8]u8 = undefined;
        const elem = std.fmt.bufPrint(&elem_buf, "{d}, ", .{byte}) catch @panic("OOM");
        out.appendSlice(b.allocator, elem) catch @panic("OOM");
    }
}

fn appendSmithCorpusEntry(
    out: *std.ArrayList(u8),
    b: *std.Build,
    macro_idx: u8,
    flags: u8,
    subject: []const u8,
) void {
    out.appendSlice(b.allocator, "    &[_]u8{ ") catch @panic("OOM");
    appendSmithU64(out, b, macro_idx);
    appendSmithU64(out, b, flags);
    if (subject.len == 0) {
        out.appendSlice(b.allocator, "1, ") catch @panic("OOM");
    } else {
        var offset: usize = 0;
        while (offset < subject.len) {
            const chunk_len = @min(subject.len - offset, 255);
            out.appendSlice(b.allocator, "0, ") catch @panic("OOM");
            appendSmithU64(out, b, chunk_len);
            for (subject[offset .. offset + chunk_len]) |byte| {
                var elem_buf: [8]u8 = undefined;
                const elem = std.fmt.bufPrint(&elem_buf, "{d}, ", .{byte}) catch @panic("OOM");
                out.appendSlice(b.allocator, elem) catch @panic("OOM");
            }
            offset += chunk_len;
        }
        out.appendSlice(b.allocator, "1, ") catch @panic("OOM");
    }
    out.appendSlice(b.allocator, "},\n") catch @panic("OOM");
}

fn collectPatternMacroNames(b: *std.Build) std.ArrayList([]const u8) {
    var names: std.ArrayList([]const u8) = .empty;

    const io = b.graph.io;
    var patterns_dir = b.root.openDir(io, "patterns", .{ .iterate = true }) catch |err| {
        std.debug.panic("failed to open patterns/: {s}", .{@errorName(err)});
    };
    defer patterns_dir.close(io);

    var it = patterns_dir.iterate();
    while (it.next(io) catch |err| {
        std.debug.panic("failed to iterate patterns/: {s}", .{@errorName(err)});
    }) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".patterns")) continue;

        const content = patterns_dir.readFileAlloc(io, entry.name, b.allocator, .unlimited) catch |err| {
            std.debug.panic("failed to read patterns/{s}: {s}", .{ entry.name, @errorName(err) });
        };
        defer b.allocator.free(content);

        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '#') continue;
            const end = std.mem.indexOfScalar(u8, trimmed, ' ') orelse continue;
            if (end == 0) continue;
            const name = b.dupe(trimmed[0..end]);

            var duplicate = false;
            for (names.items) |existing| {
                if (std.mem.eql(u8, existing, name)) {
                    duplicate = true;
                    break;
                }
            }
            if (duplicate) {
                b.allocator.free(name);
            } else {
                names.append(b.allocator, name) catch @panic("OOM");
            }
        }
    }

    std.mem.sort([]const u8, names.items, {}, struct {
        fn lessThan(_: void, a: []const u8, rhs: []const u8) bool {
            return std.mem.lessThan(u8, a, rhs);
        }
    }.lessThan);

    return names;
}

// Pin glibc on the default Linux-gnu target so Zig links against its
// bundled CRT instead of the system crt1.o. GCC >= 15 emits a .sframe
// section there that Zig 0.16's linker cannot handle.
const pinned_glibc: std.Target.Query.SemanticVersion = .{
    .major = 2,
    .minor = 38,
    .patch = 0,
};

fn materializeHostTriple(query: *std.Target.Query) void {
    if (query.cpu_arch == null) query.cpu_arch = builtin.cpu.arch;
    if (query.os_tag == null) query.os_tag = builtin.target.os.tag;
    if (query.abi == null) query.abi = builtin.target.abi;
}

fn needsHostTripleMaterialization(query: std.Target.Query) bool {
    if (query.cpu_arch != null or query.os_tag != null) return false;
    return switch (query.cpu_model) {
        .native, .explicit => true,
        .baseline, .determined_by_arch_os => false,
    };
}

fn resolveTarget(b: *std.Build) std.Build.ResolvedTarget {
    const default_target: std.Target.Query = .{
        .abi = .gnu,
        .glibc_version = pinned_glibc,
    };

    var query = b.standardTargetOptionsQueryOnly(.{
        .default_target = default_target,
    });

    // `-Dcpu=...` without `-Dtarget` parses arch/os as "native"; use the host triple.
    if (needsHostTripleMaterialization(query)) {
        materializeHostTriple(&query);
    }

    // `-Dcpu=native` parses "native" without inheriting `default_target.glibc_version`.
    if (query.glibc_version == null) {
        const os = query.os_tag orelse builtin.target.os.tag;
        if (os == .linux) {
            const abi = query.abi orelse builtin.target.abi;
            if (abi.isGnu()) {
                query.glibc_version = pinned_glibc;
            }
        }
    }

    return b.resolveTargetQuery(query);
}
