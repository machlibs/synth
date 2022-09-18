//! Example showing how to build a synth like the WASM4 APU
const std = @import("std");
const mach = @import("mach");
const gpu = @import("gpu");
const synth = @import("synth");
const sysaudio = mach.sysaudio;
const js = mach.sysjs;
const builtin = @import("builtin");

const Graph = synth.graph.Graph;
const Unit = synth.graph.Unit;

pub const App = @This();

audio: sysaudio,
device: *sysaudio.Device,
tone_engine: ToneEngine = undefined,
channel: usize = 0,
gpa: std.heap.GeneralPurposeAllocator(.{}),

pub fn init(app: *App, core: *mach.Core) !void {
    const audio = try sysaudio.init();
    errdefer audio.deinit();

    var device = try audio.requestDevice(core.allocator, .{ .mode = .output, .channels = 2 });
    errdefer device.deinit(core.allocator);

    app.audio = audio;
    app.device = device;
    app.gpa = std.heap.GeneralPurposeAllocator(.{}){};
    app.tone_engine = try ToneEngine.init(app.gpa.allocator(), app.device.properties);

    device.setCallback(callback, app);
    try device.start();
}

fn callback(device: *sysaudio.Device, user_data: ?*anyopaque, buffer: []u8) void {
    // TODO(sysaudio): should make user_data pointer type-safe
    const app: *App = @ptrCast(*App, @alignCast(@alignOf(App), user_data));

    // Where the magic happens: fill our audio buffer with PCM data.
    app.tone_engine.render(device.properties, buffer);
}

pub fn deinit(app: *App, core: *mach.Core) void {
    app.device.deinit(core.allocator);
    app.audio.deinit();
    app.tone_engine.deinit();
}

pub fn update(app: *App, engine: *mach.Core) !void {
    while (engine.pollEvent()) |event| {
        switch (event) {
            .key_press => |ev| {
                try app.device.start();
                if (ev.key == .tab) {
                    app.channel += 1;
                    app.channel %= 4;
                }
                app.tone_engine.play(app.device.properties, app.channel, ToneEngine.keyToFrequency(ev.key));
                std.debug.print("channel: {}, max samples: {}, min_samples: {}\n", .{ app.channel, app.tone_engine.max_count, app.tone_engine.min_count });
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

// A simple synthesizer emulating the WASM4 APU.
pub const ToneEngine = struct {
    /// The time in samples
    time: usize = 0,

    /// Wasm4 has 4 channels with predefined waveforms
    graph: Graph,
    osc_units: [4]*Unit,
    env_units: [4]*Unit,
    output_unit: *Unit,
    gain_unit: *Unit,
    triangle_gain_unit: *Unit,

    /// Controls overall volume
    volume: f32 = 0x1333.0 / 0xFFFF.0,
    volume_triangle: f32 = 0x2000.0 / 0xFFFF.0,

    min_count: usize = std.math.maxInt(usize),
    max_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator, properties: sysaudio.Device.Properties) !ToneEngine {
        var engine = ToneEngine{
            .graph = try Graph.init(allocator, .{
                .sample_rate = properties.sample_rate,
            }),
            .osc_units = undefined,
            .env_units = undefined,
            .output_unit = undefined,
            .gain_unit = undefined,
            .triangle_gain_unit = undefined,
        };

        // Create unit generators
        engine.osc_units = .{
            try engine.graph.add(synth.osc.Square.unit()),
            try engine.graph.add(synth.osc.Square.unit()),
            try engine.graph.add(synth.osc.Triangle.unit()),
            try engine.graph.add(synth.osc.Noise.unit(0x01)),
        };
        engine.env_units = .{
            try engine.graph.add(synth.env.APDHSR.unit()),
            try engine.graph.add(synth.env.APDHSR.unit()),
            try engine.graph.add(synth.env.APDHSR.unit()),
            try engine.graph.add(synth.env.APDHSR.unit()),
        };
        engine.output_unit = try engine.graph.add(synth.units.Output.unit());
        engine.gain_unit = try engine.graph.add(synth.units.Gain.unit(engine.volume));
        engine.triangle_gain_unit = try engine.graph.add(synth.units.Gain.unit(engine.volume_triangle));

        // Connect unit generators
        try engine.graph.connect(engine.osc_units[0], engine.env_units[0], 0);
        try engine.graph.connect(engine.osc_units[1], engine.env_units[1], 0);
        try engine.graph.connect(engine.osc_units[2], engine.env_units[2], 0);
        try engine.graph.connect(engine.osc_units[3], engine.env_units[3], 0);

        try engine.graph.connect(engine.env_units[0], engine.gain_unit, 0);
        try engine.graph.connect(engine.env_units[1], engine.gain_unit, 0);
        try engine.graph.connect(engine.env_units[2], engine.triangle_gain_unit, 0);
        try engine.graph.connect(engine.env_units[3], engine.gain_unit, 0);

        try engine.graph.connect(engine.gain_unit, engine.output_unit, 0);
        try engine.graph.connect(engine.triangle_gain_unit, engine.output_unit, 0);

        // TODO: multiple channels

        try engine.graph.reschedule();

        return engine;
    }

    pub fn deinit(engine: *ToneEngine) void {
        engine.graph.deinit();
    }

    pub fn render(engine: *ToneEngine, properties: sysaudio.Device.Properties, buffer: []u8) void {
        engine.min_count = @minimum(engine.min_count, buffer.len / properties.channels);
        engine.max_count = @maximum(engine.max_count, buffer.len / properties.channels);
        // TODO: add support for other types again
        if (properties.format != .F32) return;
        const buf = @ptrCast([*]f32, @alignCast(@alignOf(f32), buffer.ptr))[0 .. buffer.len / @sizeOf(f32)];
        renderWithType(f32, engine, properties, buf);
    }

    pub fn renderWithType(comptime T: type, engine: *ToneEngine, properties: sysaudio.Device.Properties, buffer: []T) void {
        const frames = buffer.len / properties.channels;

        for (buffer) |*sample| {
            sample.* = 0.0;
        }

        const remainder = frames % engine.graph.max_block_size;
        var frame: usize = 0;
        while (frame < frames) {
            var inputs_buf = [_][]const f32{&.{}} ** 16;
            const inputs = inputs_buf[0..1];

            var outputs_buf = [_][]f32{&.{}} ** 16;
            const outputs = outputs_buf[0..properties.channels];

            var channel: usize = 0;
            const length = if (frame + engine.graph.max_block_size > frames) remainder else engine.graph.max_block_size;
            while (channel < properties.channels) : (channel += 1) {
                const start = channel * frames + frame;
                outputs_buf[channel] = buffer[start .. start + length];
            }

            engine.graph.run(engine.time + frame, inputs, outputs) catch return;

            frame += length;
        }
        engine.time += frames;
    }

    pub fn play(engine: *ToneEngine, properties: sysaudio.Device.Properties, channel: usize, frequency: f32) void {
        switch (channel) {
            0, 1 => synth.osc.Square.setUnitFrequency(engine.osc_units[channel], frequency),
            2 => synth.osc.Triangle.setUnitFrequency(engine.osc_units[channel], frequency),
            3 => synth.osc.Noise.setUnitFrequency(engine.osc_units[channel], frequency),
            else => return,
        }
        const sample_rate = @intToFloat(f32, properties.sample_rate);
        const params = synth.env.APDHSR.Params{
            .attack = @floatToInt(usize, sample_rate * 0.1),
            .peak = 1,
            .decay = @floatToInt(usize, sample_rate * 0.1),
            .hold = @floatToInt(usize, sample_rate * 0.1),
            .sustain = 0.5,
            .release = @floatToInt(usize, sample_rate * 0.1),
        };
        synth.env.APDHSR.setUnitParams(engine.env_units[channel], params);
        synth.env.APDHSR.startUnit(engine.env_units[channel], engine.time);
    }

    pub fn keyToFrequency(key: mach.Key) f32 {
        // The frequencies here just come from a piano frequencies chart. You can google for them.
        return switch (key) {
            // First row of piano keys, the highest.
            .q => 523.25, // C5
            .w => 587.33, // D5
            .e => 659.26, // E5
            .r => 698.46, // F5
            .t => 783.99, // G5
            .y => 880.0, // A5
            .u => 987.77, // B5
            .i => 1046.5, // C6
            .o => 1174.7, // D6
            .p => 1318.5, // E6
            .left_bracket => 1396.9, // F6
            .right_bracket => 1568.0, // G6

            // Second row of piano keys, the middle.
            .a => 261.63, // C4
            .s => 293.67, // D4
            .d => 329.63, // E4
            .f => 349.23, // F4
            .g => 392.0, // G4
            .h => 440.0, // A4
            .j => 493.88, // B4
            .k => 523.25, // C5
            .l => 587.33, // D5
            .semicolon => 659.26, // E5
            .apostrophe => 698.46, // F5

            // Third row of piano keys, the lowest.
            .z => 130.81, // C3
            .x => 146.83, // D3
            .c => 164.81, // E3
            .v => 174.61, // F3
            .b => 196.00, // G3
            .n => 220.0, // A3
            .m => 246.94, // B3
            .comma => 261.63, // C4
            .period => 293.67, // D4
            .slash => 329.63, // E5
            else => 0.0,
        };
    }
};
