//! Example showing how to build a synth like the WASM4 APU
const std = @import("std");
const mach = @import("mach");
const gpu = @import("gpu");
const synth = @import("synth");
const sysaudio = mach.sysaudio;
const js = mach.sysjs;
const builtin = @import("builtin");

pub const App = @This();

audio: sysaudio,
device: *sysaudio.Device,
tone_engine: ToneEngine = undefined,
channel: usize = 0,

pub fn init(app: *App, core: *mach.Core) !void {
    const audio = try sysaudio.init();
    errdefer audio.deinit();

    var device = try audio.requestDevice(core.allocator, .{ .mode = .output, .channels = 2 });
    errdefer device.deinit(core.allocator);

    device.setCallback(callback, app);
    try device.start();

    app.audio = audio;
    app.device = device;
    app.tone_engine = .{};
}

fn callback(device: *sysaudio.Device, user_data: ?*anyopaque, buffer: []u8) void {
    // TODO(sysaudio): should make user_data pointer type-safe
    const app: *App = @ptrCast(*App, @alignCast(@alignOf(App), user_data));

    // Where the magic happens: fill our audio buffer with PCM dat.
    app.tone_engine.render(device.properties, buffer);
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

const Command = union(enum) {
    SetOut: usize,
    SetIn: usize,
    RunOsc: usize,
    RunEnv: usize,
    Gain: f32,
    Output: usize,
};

const Runner = struct {
    out: usize = 0,
    in: usize = 0,
    osc: [4]synth.Oscillator,
    env: [4]synth.APDHSR,
    bus: [6][128]f32 = std.mem.zeroes([6][128]f32),

    pub fn run(runner: *Runner, time: usize, sample_rate: usize, program: []const Command) []f32 {
        // Reset buffer
        for (runner.bus) |*bus| {
            for (bus) |*sample| {
                sample.* = 0;
            }
        }
        // Run program
        for (program) |command| {
            switch (command) {
                .SetOut => |out| runner.out = out,
                .SetIn => |in| runner.in = in,
                .RunEnv => |env| {
                    var i: usize = 0;
                    while (i < 128) : (i += 1) {
                        runner.bus[runner.out][i] += runner.bus[runner.in][i] * runner.env[env].sample(time + i);
                    }
                },
                .RunOsc => |osc| {
                    var i: usize = 0;
                    while (i < 128) : (i += 1) {
                        switch (runner.osc[osc]) {
                            .Noise => |*noise| {
                                runner.bus[runner.out][i] += runner.bus[runner.in][i] * noise.sample(sample_rate);
                            },
                            .Square => |*square| {
                                runner.bus[runner.out][i] += runner.bus[runner.in][i] * square.sample(sample_rate);
                            },
                            .Triangle => |*triangle| {
                                runner.bus[runner.out][i] += runner.bus[runner.in][i] * triangle.sample(sample_rate);
                            },
                        }
                    }
                },
                .Gain => |gain| {
                    var i: usize = 0;
                    while (i < 128) : (i += 1) {
                        runner.bus[runner.out][i] += runner.bus[runner.in][i] * gain;
                    }
                },
                .Output => |bus| {
                    return &runner.bus[bus];
                },
            }
        }
        return &runner.bus[runner.out];
    }
};

// A simple synthesizer emulating the WASM4 APU.
pub const ToneEngine = struct {
    /// The time in samples
    time: usize = 0,
    program: []const Command = &[_]Command{
        .{ .SetOut = 0 },
        .{ .RunOsc = 0 },
        .{ .SetOut = 1 },
        .{ .RunOsc = 1 },
        .{ .SetOut = 2 },
        .{ .RunOsc = 2 },
        .{ .SetOut = 3 },
        .{ .RunOsc = 3 },
        .{ .SetOut = 4 },
        .{ .SetIn = 0 },
        .{ .RunEnv = 0 },
        .{ .SetIn = 1 },
        .{ .RunEnv = 1 },
        .{ .SetIn = 2 },
        .{ .RunEnv = 2 },
        .{ .SetIn = 3 },
        .{ .RunEnv = 3 },
        .{ .SetOut = 5 },
        .{ .SetIn = 4 },
        .{ .Gain = 0.1 },
        .{ .Output = 5 },
    },
    outbuffer: [128]f32 = [_]f32{0} ** 128,
    outlen: usize = 0,
    /// Wasm4 has 4 channels with predefined waveforms
    runner: Runner = Runner{
        .osc = .{
            .{ .Square = .{ .dutyCycle = 0.5 } },
            .{ .Square = .{ .dutyCycle = 0.5 } },
            .{ .Triangle = .{} },
            .{ .Noise = .{ .seed = 0x01 } },
        },
        .env = std.mem.zeroes([4]synth.APDHSR),
    },

    /// Controls overall volume
    volume: f32 = 0x1333.0 / 0xFFFF.0,
    // volume_triangle: f32 = 0x2000.0 / 0xFFFF.0,

    min_count: usize = std.math.maxInt(usize),
    max_count: usize = 0,

    pub fn render(engine: *ToneEngine, properties: sysaudio.Device.Properties, buffer: []u8) void {
        engine.min_count = @minimum(engine.min_count, buffer.len / properties.channels);
        engine.max_count = @maximum(engine.max_count, buffer.len / properties.channels);
        // Ignore everything but f32 for now
        if (properties.format != .F32) return;
        const buf = @ptrCast([*]f32, @alignCast(@alignOf(f32), buffer.ptr))[0 .. buffer.len / @sizeOf(f32)];
        renderWithType(f32, engine, properties, buf);
    }

    pub fn renderWithType(comptime T: type, engine: *ToneEngine, properties: sysaudio.Device.Properties, buffer: []T) void {
        const frames = buffer.len / properties.channels;

        var frame: usize = 0;
        if (engine.outlen != 0) {
            var channel: usize = 0;
            while (channel < properties.channels) : (channel += 1) {
                for (engine.outbuffer[0..engine.outlen]) |sample, i| {
                    var channel_buffer = buffer[channel * frames .. (channel + 1) * frames];
                    channel_buffer[frame + i] = sample;
                }
            }
            engine.outlen = 0;
        }

        const remainder = frames % 128;
        while (frame < frames) {
            var samples = engine.runner.run(engine.time + frame, properties.sample_rate, engine.program);

            const send = if (frame + samples.len > frames) remainder else 128;

            // Emit the sample on all channels.
            var channel: usize = 0;
            while (channel < properties.channels) : (channel += 1) {
                for (samples[0..send]) |sample, i| {
                    var channel_buffer = buffer[channel * frames .. (channel + 1) * frames];
                    channel_buffer[frame + i] = sample;
                }
            }
            if (send != 128) {
                for (samples[send..]) |sample, i| {
                    engine.outbuffer[i] = sample;
                }
                engine.outlen = 128 - send;
            }
            frame += samples.len;
        }
        engine.time += frames;
    }

    pub fn play(engine: *ToneEngine, properties: sysaudio.Device.Properties, channel: usize, frequency: f32) void {
        _ = engine;
        _ = properties;
        _ = channel;
        _ = frequency;
        // switch (engine.channels[channel]) {
        //     .Square => |*square| square.frequency = frequency,
        //     .Triangle => |*triangle| triangle.frequency = frequency,
        //     .Noise => |*noise| noise.frequency = frequency,
        // }
        // const sample_rate = @intToFloat(f32, properties.sample_rate);
        // engine.envelopes[channel].attack = @floatToInt(usize, sample_rate * 0.1);
        // engine.envelopes[channel].peak = 1;
        // engine.envelopes[channel].decay = @floatToInt(usize, sample_rate * 0.1);
        // engine.envelopes[channel].hold = @floatToInt(usize, sample_rate * 0.1);
        // engine.envelopes[channel].sustain = 0.5;
        // engine.envelopes[channel].release = @floatToInt(usize, sample_rate * 0.1);
        // engine.envelopes[channel].start(engine.time);
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
