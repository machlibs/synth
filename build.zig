const std = @import("std");
const fetch = @import("fetch.zig");

pub const pkg = std.build.Pkg{
    .name = "synth",
    .source = .{ .path = thisDir() ++ "/src/main.zig" },
    .dependencies = null,
};

const Example = struct { name: []const u8, src: []const u8 };
pub const examples = [_]Example{
    .{ .name = "wasm4-apu", .src = "wasm4.zig" },
    .{ .name = "wav", .src = "wav.zig" },
    .{ .name = "hexwave", .src = "hexwave.zig" },
};

const deps = [_]fetch.Dependency{
    .{ .git = .{
        .name = "mach",
        .url = "https://github.com/hexops/mach",
        .commit = "02ab8f964aa217a87b21d5b3f92f21b03c4a36d4",
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

    inline for (examples) |example| {
        fetch.addStep(b, "example-" ++ example.name, "Builds the " ++ example.name ++ " example");
        fetch.addStep(b, "run-example-" ++ example.name, "Runs the " ++ example.name ++ " example");
    }

    try fetch.fetchAndBuild(b, "zig-deps", &deps, "compile.zig");
}

fn thisDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}
