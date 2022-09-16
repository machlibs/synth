const std = @import("std");
const testing = std.testing;

comptime {
    _ = osc;
}

pub const osc = @import("oscillators.zig");

/// Oscillators are waveform generators
pub const Oscillator = union(enum) {
    Noise: osc.Noise,
    Square: osc.Square,
    Triangle: osc.Triangle,
};

/// An APDHSR envelope for modulating the volume of a signal over time.
/// This is a variant on ADSR that requires the length of the note to be
/// known in advance, and allows specifying the peak amplitude.
pub const APDHSR = struct {
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

    /// Start the envelope at the given time
    pub fn start(env: *APDHSR, time: usize) void {
        env.startTime = time;
        env.attackTime = time + env.attack;
        env.decayTime = env.attackTime + env.decay;
        env.holdTime = env.decayTime + env.hold;
        env.releaseTime = env.holdTime + env.release;
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
                .startValue = env.sustain,
                .endValue = 0,
                .start = env.holdTime,
                .end = env.releaseTime,
            }, time);
        } else if (time >= env.decayTime) {
            // Sustain
            return env.sustain;
        } else if (time >= env.attackTime) {
            // Decay
            return Ramp.sample(.{
                .startValue = env.peak,
                .endValue = env.sustain,
                .start = env.attackTime,
                .end = env.decayTime,
            }, time);
        } else {
            // Attack
            return Ramp.sample(.{
                .startValue = 0,
                .endValue = env.peak,
                .start = env.startTime,
                .end = env.attackTime,
            }, time);
        }
    }
};

test "envelope usage" {
    var time: usize = 0;
    var env = APDHSR{
        .attack = 2,
        .peak = 1,
        .decay = 2,
        .hold = 2,
        .sustain = 0.5,
        .release = 2,
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

pub const Synth = struct {};
