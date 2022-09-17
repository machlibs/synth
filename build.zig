const std = @import("std");
const fetch = @import("fetch.zig");

pub const pkg = std.build.Pkg{
    .name = "synth",
    .source = .{ .path = thisDir() ++ "/src/main.zig" },
    .dependencies = null,
};

const deps = [_]fetch.Dependency{
    .{ .git = .{
        .name = "mach",
        .url = "https://github.com/hexops/mach",
        .commit = "47d1544b6483ec6038fcc0eb2b90c14f8ab8d253",
    } },
};

pub fn build(b: *std.build.Builder) !void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const main_tests = b.addTest("src/main.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    ensureGit(b.allocator);
    try fetch.fetchAndBuild(b, "zig-deps", &deps, "compile.zig");
}

fn thisDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
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
