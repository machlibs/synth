const std = @import("std");
const pkg = @import("build.zig").pkg;
const mach = @import("zig-deps/mach/build.zig");

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

    // TODO: de-duplicate
    const example_wav_app = mach.App.init(b, .{
        .name = "wav",
        .src = (comptime thisDir() ++ "/examples/wav.zig"),
        .target = target,
        .deps = &.{pkg},
    });
    example_wav_app.setBuildMode(mode);
    example_wav_app.link(options);
    example_wav_app.install();

    const example_wav_compile_step = b.step("example-wav", "Compile wav example");
    example_wav_compile_step.dependOn(&example_wav_app.getInstallStep().?.step);

    const example_wav_run_cmd = example_wav_app.run();
    example_wav_run_cmd.dependOn(&example_wav_app.getInstallStep().?.step);

    const example_wav_run_step = b.step("run-example-wav", "Run wav example");
    example_wav_run_step.dependOn(example_wav_run_cmd);
}

fn thisDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}
