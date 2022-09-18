const std = @import("std");
const testing = std.testing;
const Unit = @import("graph.zig").Unit;

/// An APDHSR envelope for modulating the volume of a signal over time.
/// This is a variant on ADSR that requires the length of the note to be
/// known in advance, and allows specifying the peak amplitude.
pub const APDHSR = struct {
    /// Stores the APDHSR values
    params: Params,
    /// Internal variable. The time, in samples, when the attack ends
    startTime: usize = 0,
    /// Internal variable. The time, in samples, when the attack ends
    attackTime: usize = 0,
    /// Internal variable. The time, in samples, when the decay ends
    decayTime: usize = 0,
    /// Internal variable. The time, in samples, when the sustain ends
    holdTime: usize = 0,
    /// Internal variable. The time, in samples, when the release ends
    releaseTime: usize = 0,

    pub const Params = struct {
        /// Time for the initial run-up of level from nil to to peak, in samples
        attack: usize,
        /// Level for peak of attack, from 0 to 1
        peak: f32,
        /// Time for run down to sustain from peak, in samples
        decay: usize,
        /// Time
        hold: usize,
        /// Level for sustain, from 0 to 1
        sustain: f32,
        /// Time for gain to decay to 0, in samples
        release: usize,
    };

    /// Start the envelope at the given time
    pub fn start(env: *APDHSR, time: usize) void {
        env.startTime = time;
        env.attackTime = time + env.params.attack;
        env.decayTime = env.attackTime + env.params.decay;
        env.holdTime = env.decayTime + env.params.hold;
        env.releaseTime = env.holdTime + env.params.release;
    }

    /// Returns the amplitude of the envelope for the time given
    pub fn sample(env: *APDHSR, time: usize) f32 {
        if (time == 0) return 0;
        if (time > env.releaseTime) {
            // Finished
            return 0;
        } else if (time >= env.holdTime) {
            // Release
            return Ramp.sample(.{
                .startValue = env.params.sustain,
                .endValue = 0,
                .start = env.holdTime,
                .end = env.releaseTime,
            }, time);
        } else if (time >= env.decayTime) {
            // Sustain
            return env.params.sustain;
        } else if (time >= env.attackTime) {
            // Decay
            return Ramp.sample(.{
                .startValue = env.params.peak,
                .endValue = env.params.sustain,
                .start = env.attackTime,
                .end = env.decayTime,
            }, time);
        } else {
            // Attack
            return Ramp.sample(.{
                .startValue = 0,
                .endValue = env.params.peak,
                .start = env.startTime,
                .end = env.attackTime,
            }, time);
        }
    }

    pub fn run(obj: *Unit, time: usize, inputs: [][]const f32, outputs: [][]f32) void {
        var self = @ptrCast(*APDHSR, @alignCast(@alignOf(APDHSR), &obj.data));
        var i: usize = 0;
        while (i < outputs[0].len) : (i += 1) {
            var _sample = self.sample(time);
            for (inputs) |input, a| {
                var output = outputs[a];
                output[i] += input[i] * _sample;
            }
        }
    }

    pub fn unit() Unit {
        var obj = Unit{
            .name = "APDHSR",
            .run = run,
            .data = undefined,
            .inputs = 1,
            .outputs = 1,
        };
        var self = @ptrCast(*APDHSR, @alignCast(@alignOf(APDHSR), &obj.data));
        self.* = APDHSR{ .params = .{
            .attack = 0,
            .peak = 0,
            .decay = 0,
            .hold = 0,
            .sustain = 0,
            .release = 0,
        } };
        return obj;
    }

    pub fn setUnitParams(obj: *Unit, params: Params) void {
        var self = @ptrCast(*APDHSR, @alignCast(@alignOf(APDHSR), &obj.data));
        self.params = params;
    }

    pub fn startUnit(obj: *Unit, time: usize) void {
        var self = @ptrCast(*APDHSR, @alignCast(@alignOf(APDHSR), &obj.data));
        self.start(time);
    }
};

test "envelope usage" {
    var time: usize = 0;
    var env = APDHSR{
        .params = .{
            .attack = 2,
            .peak = 1,
            .decay = 2,
            .hold = 2,
            .sustain = 0.5,
            .release = 2,
        },
    };
    env.start(time);
    // Attack
    try testing.expectApproxEqAbs(@as(f32, 0), env.sample(time), 0.01);
    time += 1;
    try testing.expectApproxEqAbs(@as(f32, 0.5), env.sample(time), 0.01);
    time += 1;
    // Peak
    try testing.expectApproxEqAbs(@as(f32, 1), env.sample(time), 0.01);
    time += 1;
    // Decay
    try testing.expectApproxEqAbs(@as(f32, 0.75), env.sample(time), 0.01);
    time += 1;
    try testing.expectApproxEqAbs(@as(f32, 0.5), env.sample(time), 0.01);
    time += 1;
    // Hold
    try testing.expectApproxEqAbs(@as(f32, 0.5), env.sample(time), 0.01);
    time += 1;
    try testing.expectApproxEqAbs(@as(f32, 0.5), env.sample(time), 0.01);
    time += 1;
    // Release
    try testing.expectApproxEqAbs(@as(f32, 0.25), env.sample(time), 0.01);
    time += 1;
    try testing.expectApproxEqAbs(@as(f32, 0.0), env.sample(time), 0.01);
    time += 1;
}

/// Moves from startValue to endValue over the period from start to end
pub const Ramp = struct {
    /// The starting value of the ramp
    startValue: f32,
    /// The final value of the ramp
    endValue: f32,
    /// Time, in samples, that the ramp started
    start: usize,
    /// Time, in samples, that the ramp ends
    end: usize,

    /// Returns value of ramp at given time
    pub fn sample(ramp: Ramp, time: usize) f32 {
        const t = @intToFloat(f32, (time - ramp.start)) / @intToFloat(f32, (ramp.end - ramp.start));
        return lerp(ramp.startValue, ramp.endValue, t);
    }
};

/// Returns a value linearly interpolated between value1 and value2.
/// - `t` is a value from 0 to 1
pub fn lerp(value1: f32, value2: f32, t: f32) f32 {
    return value1 + t * (value2 - value1);
}
