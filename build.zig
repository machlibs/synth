const std = @import("std");

pub const pkg = std.build.Pkg{
    .name = "synth",
    .source = .{ .path = thisDir() ++ "/src/main.zig" },
    .dependencies = null,
};

pub fn build(b: *std.build.Builder) !void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const main_tests = b.addTest("src/main.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    const mach_path_opt = b.option([]const u8, "mach-path", "Uses the given path for mach instead of cloning the repository (requires symlinks)");
    const example_opt = b.option([]const u8, "example", "Build an example (wasm4-apu)");
    const run_opt = b.option(bool, "run", "If example should be run");

    if (run_opt != null and example_opt == null) {
        std.log.err("Please specify an example to run with -Dexample=[example]", .{});
        return error.NoExampleSpecified;
    }

    // The example code depends on mach, but tests can be run without it
    if (example_opt) |example| {
        var arglist = std.ArrayList([]const u8).init(b.allocator);
        try arglist.appendSlice(&.{ "zig", "build", "--build-file", "compile.zig" });

        if (run_opt) |_| {
            const run_cmd = b.fmt("run-example-{s}", .{example});
            try arglist.append(run_cmd);
        } else {
            const run_cmd = b.fmt("example-{s}", .{example});
            try arglist.append(run_cmd);
        }

        if (mach_path_opt) |mach_path| {
            std.os.symlink(mach_path, "libs/mach") catch |e| switch (e) {
                error.PathAlreadyExists => {},
                else => return e,
            };
        } else {
            ensureGit(b.allocator);
            ensureDependencySubmodule(b.allocator, "libs/mach") catch unreachable;
        }

        // Now that the dependencies are installed, run the compile step
        var child = std.ChildProcess.init(arglist.items, b.allocator);
        child.cwd = (comptime thisDir());
        child.stderr = std.io.getStdErr();
        child.stdout = std.io.getStdOut();

        _ = try child.spawnAndWait();
    }
}

fn thisDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

fn ensureDependencySubmodule(allocator: std.mem.Allocator, path: []const u8) !void {
    if (std.process.getEnvVarOwned(allocator, "NO_ENSURE_SUBMODULES")) |no_ensure_submodules| {
        defer allocator.free(no_ensure_submodules);
        if (std.mem.eql(u8, no_ensure_submodules, "true")) return;
    } else |_| {}
    var child = std.ChildProcess.init(&.{ "git", "submodule", "update", "--init", path }, allocator);
    child.cwd = (comptime thisDir());
    child.stderr = std.io.getStdErr();
    child.stdout = std.io.getStdOut();

    _ = try child.spawnAndWait();
}

fn ensureGit(allocator: std.mem.Allocator) void {
    const argv = &[_][]const u8{ "git", "--version" };
    const result = std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = argv,
        .cwd = ".",
    }) catch { // e.g. FileNotFound
        std.log.err("mach: error: 'git --version' failed. Is git not installed?", .{});
        std.process.exit(1);
    };
    defer {
        allocator.free(result.stderr);
        allocator.free(result.stdout);
    }
    if (result.term.Exited != 0) {
        std.log.err("mach: error: 'git --version' failed. Is git not installed?", .{});
        std.process.exit(1);
    }
}
