const std = @import("std");
const testing = std.testing;
const Unit = @import("graph.zig").Unit;

/// A psuedo-random noise generator using a Linear feedback shift register (LFSR).
/// https://en.wikipedia.org/wiki/Linear-feedback_shift_register#Xorshift_LFSRs
pub const Noise = struct {
    seed: u16,
    phase: f32 = 0,
    lastRandom: i16 = 0,
    frequency: f32 = 0,

    /// 16-bit xorshift PRNG implementing lfsr.
    /// http://www.retroprogramming.com/2017/07/xorshift-pseudorandom-numbers-in-z80.html
    fn xorshift(noise: *Noise) void {
        noise.seed ^= noise.seed >> 7;
        noise.seed ^= noise.seed << 9;
        noise.seed ^= noise.seed >> 13;
    }

    /// Returns 0 or 1 psuedo-randomly
    pub fn sample(noise: *Noise, sample_rate: usize) f32 {
        const sample_rate_float = @intToFloat(f32, sample_rate);
        noise.phase += noise.frequency * noise.frequency / (1_000_000.0 / sample_rate_float * sample_rate_float);
        while (noise.phase > 0) {
            noise.phase -= 1;
            noise.xorshift();
            noise.lastRandom = @bitCast(i16, 2 *% (noise.seed & 0x1) -% 1);
        }
        return @intToFloat(f32, noise.lastRandom);
    }

    pub fn run(obj: *Unit, _: usize, _: [][]const f32, outputs: [][]f32) void {
        var self = @ptrCast(*Noise, @alignCast(@alignOf(Noise), &obj.data));
        var i: usize = 0;
        while (i < outputs[0].len) : (i += 1) {
            var _sample = self.sample(obj.sample_rate);
            for (outputs) |output| {
                output[i] += _sample;
            }
        }
    }

    pub fn unit(seed: u16) Unit {
        var obj = Unit{
            .name = "Noise",
            .run = run,
            .data = undefined,
            .inputs = 0,
            .outputs = 1,
        };
        var self = @ptrCast(*Noise, @alignCast(@alignOf(Noise), &obj.data));
        self.* = Noise{ .seed = seed };
        return obj;
    }

    pub fn setUnitFrequency(obj: *Unit, frequency: f32) void {
        var self = @ptrCast(*Noise, @alignCast(@alignOf(Noise), &obj.data));
        self.frequency = frequency;
    }
};

test "noise usage example" {
    const sample_rate = 44100;
    var noise = Noise{ .seed = 0x001 };
    noise.frequency = 440;
    try testing.expectEqual(@as(f32, 1), noise.sample(sample_rate));
}

/// A square wave oscillator
pub const Square = struct {
    /// Internal variable for tracking time
    phase: f32 = 0,
    /// The length of the pulse relative to the period of the wave
    dutyCycle: f32 = 0.5,
    /// The frequency of the wave
    frequency: f32 = 0,

    fn polyblep(phase: f32, phaseInc: f32) f32 {
        if (phase < phaseInc) {
            var t = phase / phaseInc;
            return (t + t) - (t * t);
        } else if (phase > 1.0 - phaseInc) {
            var t = (phase - (1.0 - phaseInc)) / phaseInc;
            return 1.0 - ((t + t) - (t * t));
        } else {
            return 1.0;
        }
    }

    /// Returns the next value of the square wave for the given sample rate
    pub fn sample(square: *Square, sample_rate: usize) f32 {
        if (square.frequency == 0) return 0;
        const phaseInc = (square.frequency) / @intToFloat(f32, sample_rate);
        square.phase += phaseInc;

        if (square.phase >= 1) {
            square.phase -= 1;
        }

        const phase = square.phase;
        var dutyPhase: f32 = 0;
        var dutyPhaseInc: f32 = 0;
        var multiplier: f32 = 1;
        if (phase < square.dutyCycle) {
            dutyPhase = phase / square.dutyCycle;
            dutyPhaseInc = phaseInc / square.dutyCycle;
            multiplier = 1;
        } else {
            dutyPhase = (phase - square.dutyCycle) / (1.0 - square.dutyCycle);
            dutyPhaseInc = phaseInc / (1.0 - square.dutyCycle);
            multiplier = -1;
        }
        return multiplier * polyblep(dutyPhase, dutyPhaseInc);
    }

    pub fn run(obj: *Unit, _: usize, _: [][]const f32, outputs: [][]f32) void {
        var self = @ptrCast(*Square, @alignCast(@alignOf(Square), &obj.data));
        var i: usize = 0;
        while (i < outputs[0].len) : (i += 1) {
            var _sample = self.sample(obj.sample_rate);
            for (outputs) |output| {
                output[i] += _sample;
            }
        }
    }

    pub fn unit() Unit {
        var obj = Unit{
            .name = "Square",
            .run = run,
            .data = undefined,
            .inputs = 0,
            .outputs = 1,
        };
        var self = @ptrCast(*Square, @alignCast(@alignOf(Square), &obj.data));
        self.* = Square{};
        return obj;
    }

    pub fn setUnitFrequency(obj: *Unit, frequency: f32) void {
        var self = @ptrCast(*Square, @alignCast(@alignOf(Square), &obj.data));
        self.frequency = frequency;
    }

    pub fn setUnitDuty(obj: *Unit, duty: f32) void {
        var self = @ptrCast(*Square, @alignCast(@alignOf(Square), &obj.data));
        self.dutyCycle = duty;
    }
};

test "square wave usage example" {
    const sample_rate = 44100;
    var square = Square{};
    square.frequency = 440;
    try testing.expectApproxEqAbs(@as(f32, 1), square.sample(sample_rate), 0.01);
}

/// A triangle wave oscillator
pub const Triangle = struct {
    phase: f32 = 0,
    frequency: f32 = 0,

    pub fn sample(triangle: *Triangle, sample_rate: usize) f32 {
        if (triangle.frequency == 0) return 0;
        triangle.phase += (triangle.frequency) / @intToFloat(f32, sample_rate);
        if (triangle.phase >= 1) {
            triangle.phase -= 1;
        }
        return (2 * @fabs(2 * triangle.phase - 1) - 1);
    }

    pub fn run(obj: *Unit, _: usize, _: [][]const f32, outputs: [][]f32) void {
        var self = @ptrCast(*Triangle, @alignCast(@alignOf(Triangle), &obj.data));
        var i: usize = 0;
        while (i < outputs[0].len) : (i += 1) {
            var _sample = self.sample(obj.sample_rate);
            for (outputs) |output| {
                output[i] += _sample;
            }
        }
    }

    pub fn unit() Unit {
        var obj = Unit{
            .name = "Triangle",
            .run = run,
            .data = undefined,
            .inputs = 0,
            .outputs = 1,
        };
        var self = @ptrCast(*Triangle, @alignCast(@alignOf(Triangle), &obj.data));
        self.* = Triangle{};
        return obj;
    }

    pub fn setUnitFrequency(obj: *Unit, frequency: f32) void {
        var self = @ptrCast(*Triangle, @alignCast(@alignOf(Triangle), &obj.data));
        self.frequency = frequency;
    }
};

test "triangle usage example" {
    const sample_rate = 44100;
    var triangle = Triangle{};
    triangle.frequency = 440;
    try testing.expectApproxEqAbs(@as(f32, 1), triangle.sample(sample_rate), 0.1);
}
