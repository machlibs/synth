//! Example showing the use of the hexwave unit
const std = @import("std");
const mach = @import("mach");
const gpu = @import("gpu");
const synth = @import("synth");
const sysaudio = mach.sysaudio;
const js = mach.sysjs;
const builtin = @import("builtin");

const Graph = synth.graph.Graph;
const Unit = synth.graph.Unit;
const WavUnit = synth.wav.WavUnit;

pub const App = @This();

audio: sysaudio,
device: *sysaudio.Device,
channel: usize = 0,
gpa: std.heap.GeneralPurposeAllocator(.{}),

graph: Graph,
/// The time in samples
time: usize = 0,
hex_blep: synth.osc.HexBlep,
hexwave_unit: *Unit,
gain_unit: *Unit,
output_unit: *Unit,

pub fn init(app: *App, core: *mach.Core) !void {
    const audio = try sysaudio.init();
    errdefer audio.deinit();

    var device = try audio.requestDevice(core.allocator, .{ .mode = .output, .channels = 2 });
    errdefer device.deinit(core.allocator);

    app.audio = audio;
    app.device = device;
    app.gpa = std.heap.GeneralPurposeAllocator(.{}){};

    app.graph = try Graph.init(app.gpa.allocator(), .{
        .sample_rate = app.device.properties.sample_rate,
    });

    const sawtooth = synth.osc.Hexwave.Parameters{ .reflect = true, .peak_time = 0, .half_height = 0, .zero_wait = 0 };

    app.hex_blep = try synth.osc.HexBlep.initAlloc(app.gpa.allocator(), 32, 16);
    app.hexwave_unit = try app.graph.add(synth.osc.Hexwave.unit(app.hex_blep, sawtooth, 440));
    app.gain_unit = try app.graph.add(synth.units.Gain.unit(0.1));
    app.output_unit = try app.graph.add(synth.units.Output.unit());

    // Connect unit generators
    try app.graph.connect(app.hexwave_unit, app.gain_unit, 0);

    try app.graph.connect(app.gain_unit, app.output_unit, 0);

    // TODO: multiple channels
    try app.graph.reschedule();

    device.setCallback(callback, app);
    try device.start();
}

fn callback(_: *sysaudio.Device, user_data: ?*anyopaque, buffer_u8: []u8) void {
    // TODO(sysaudio): should make user_data pointer type-safe
    const app: *App = @ptrCast(*App, @alignCast(@alignOf(App), user_data));

    const properties = app.device.properties;

    if (properties.format != .F32) return;
    const buffer = @ptrCast([*]f32, @alignCast(@alignOf(f32), buffer_u8.ptr))[0 .. buffer_u8.len / @sizeOf(f32)];

    const frames = buffer.len / properties.channels;

    for (buffer) |*sample| {
        sample.* = 0.0;
    }

    const remainder = frames % app.graph.max_block_size;
    var frame: usize = 0;
    while (frame < frames) {
        var inputs_buf = [_][]const f32{&.{}} ** 16;
        const inputs = inputs_buf[0..1];

        var outputs_buf = [_][]f32{&.{}} ** 16;
        const outputs = outputs_buf[0..properties.channels];

        var channel: usize = 0;
        const length = if (frame + app.graph.max_block_size > frames) remainder else app.graph.max_block_size;
        while (channel < properties.channels) : (channel += 1) {
            const start = channel * frames + frame;
            outputs_buf[channel] = buffer[start .. start + length];
        }

        app.graph.run(app.time + frame, inputs, outputs) catch return;

        frame += length;
    }
    app.time += frames;
}

pub fn deinit(app: *App, core: *mach.Core) void {
    app.device.deinit(core.allocator);
    app.audio.deinit();
}

pub fn update(app: *App, engine: *mach.Core) !void {
    while (engine.pollEvent()) |event| {
        switch (event) {
            .key_press => |ev| {
                try app.device.start();
                _ = ev;
            },
            else => {},
        }
    }

    if (builtin.cpu.arch != .wasm32) {
        const back_buffer_view = engine.swap_chain.?.getCurrentTextureView();

        engine.swap_chain.?.present();
        back_buffer_view.release();
    }
}
