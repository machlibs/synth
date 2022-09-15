const std = @import("std");
const mach = @import("libs/mach/build.zig");

pub const pkg = std.build.Pkg{
    .name = "synth",
    .source = .{ .path = thisDir() ++ "/src/main.zig" },
    .dependencies = null,
};

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const options = mach.Options{};

    const example_app = mach.App.init(b, .{
        .name = "wasm4-apu",
        .src = (comptime thisDir() ++ "/examples/wasm4.zig"),
        .target = target,
        .deps = &.{pkg},
    });
    example_app.setBuildMode(mode);
    example_app.link(options);
    example_app.install();

    const example_compile_step = b.step("example-wasm4-apu", "Compile wasm4-apu example");
    example_compile_step.dependOn(&example_app.getInstallStep().?.step);

    const example_run_cmd = example_app.run();
    example_run_cmd.dependOn(&example_app.getInstallStep().?.step);

    const example_run_step = b.step("run-example-wasm4-apu", "Run wasm4-apu example");
    example_run_step.dependOn(example_run_cmd);
}

fn thisDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}
