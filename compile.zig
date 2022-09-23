const std = @import("std");
const pkg = @import("build.zig").pkg;
const examples = @import("build.zig").examples;
const mach = @import("zig-deps/mach/build.zig");

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const options = mach.Options{};

    inline for (examples) |example| {
        const example_app = mach.App.init(b, .{
            .name = example.name,
            .src = (comptime thisDir() ++ "/examples/" ++ example.src),
            .target = target,
            .deps = &.{pkg},
        });
        example_app.setBuildMode(mode);
        example_app.link(options);
        example_app.install();

        const example_compile_step = b.step("example-" ++ example.name, "Compile " ++ example.name ++ " example");
        example_compile_step.dependOn(&example_app.getInstallStep().?.step);

        const example_run_cmd = example_app.run();
        example_run_cmd.dependOn(&example_app.getInstallStep().?.step);

        const example_run_step = b.step("run-example-" ++ example.name, "Run " ++ example.name ++ " example");
        example_run_step.dependOn(example_run_cmd);
    }
}

fn thisDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}
