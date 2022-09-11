const std = @import("std");
const mach = @import("deps/mach/build.zig");

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const lib = b.addStaticLibrary("synth", "src/main.zig");
    lib.setBuildMode(mode);
    lib.install();

    const main_tests = b.addTest("src/main.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    const options = mach.Options{};

    const example_app = mach.App.init(b, .{
        .name = "wasm4-apu",
        .src = "examples/wasm4.zig",
        .target = target,
    });
    example_app.step.step.dependOn(&lib.step);
    example_app.setBuildMode(mode);
    example_app.link(options);
    example_app.install();

    const example_compile_step = b.step("example-wasm4-apu", "Compile wasm4-apu example");
    example_compile_step.dependOn(&example_app.getInstallStep().?.step);

    const example_run_cmd = example_app.run();
    example_run_cmd.step.dependOn(&example_app.getInstallStep().?.step);

    const example_run_step = b.step("run-example-wasm4-apu", "Run wasm4-apu example");
    example_run_step.dependOn(&example_run_cmd.step);
}
