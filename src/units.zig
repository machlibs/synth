const std = @import("std");
const graph = @import("graph.zig");

const Unit = graph.Unit;

pub fn phasor(sample_rate: usize, time: usize, frequency: f32, phase: f32) f32 {
    const increase = frequency / @intToFloat(f32, sample_rate);
    const value = @intToFloat(f32, time) * increase + phase;
    return value - std.math.floor(value);
}

/// A simple unit that goes from 0 to 1 every period. Useful for implementing
/// other waves.
pub const Phasor = struct {
    frequency: f32 = 1,
    phase: f32 = 0,

    pub fn run(obj: *Unit, time: usize, _: [][]const f32, outputs: [][]f32) void {
        var self = @ptrCast(*Phasor, @alignCast(@alignOf(Phasor), &obj.data));
        var phase = phasor(obj.sample_rate, time, self.frequency, self.phase);
        const phase_increase = self.frequency / @intToFloat(f32, obj.sample_rate);
        var i: usize = 0;
        while (i < outputs.len) : (i += 1) {
            phase += phase_increase;
            if (phase >= 1.0) phase = 0;
            for (outputs) |output| {
                output[i] += phase;
            }
        }
    }

    pub fn unit() Unit {
        var obj = Unit{
            .name = "Phasor",
            .run = run,
            .data = undefined,
            .inputs = 0,
            .outputs = 1,
        };
        var self = @ptrCast(*Phasor, @alignCast(@alignOf(Phasor), &obj.data));
        self.* = Phasor{};
        return obj;
    }
};

pub const Output = struct {
    pub fn run(_: *Unit, _: usize, bus: [][]const f32, outputs: [][]f32) void {
        for (outputs) |output, i| {
            for (output) |*sample, a| {
                sample.* += bus[i][a];
            }
        }
    }

    pub fn unit() Unit {
        var obj = Unit{
            .name = "Output",
            .run = run,
            .data = undefined,
            .is_output = true,
            .inputs = 16,
            .outputs = 0,
        };
        return obj;
    }
};

pub const Gain = struct {
    level: f32,

    pub fn run(obj: *Unit, _: usize, bus: [][]const f32, outputs: [][]f32) void {
        var self = @ptrCast(*Gain, @alignCast(@alignOf(Gain), &obj.data));
        for (outputs) |output, i| {
            for (output) |*sample, a| {
                sample.* += self.level * bus[i][a];
            }
        }
    }

    pub fn unit(level: f32) Unit {
        var obj = Unit{
            .name = "Gain",
            .run = run,
            .data = undefined,
            .inputs = 16,
            .outputs = 0,
        };
        var self = @ptrCast(*Gain, @alignCast(@alignOf(Gain), &obj.data));
        self.* = Gain{ .level = level };
        return obj;
    }
};
