const std = @import("std");
const testing = std.testing;

test "oscillator" {
    _ = Oscillator;
}

pub const Oscillator = struct {
    /// A psuedo-random noise generator using a Linear feedback shift register (LFSR).
    /// https://en.wikipedia.org/wiki/Linear-feedback_shift_register#Xorshift_LFSRs
    pub const Noise = struct {
        seed: u16,
        phase: f32,
        lastRandom: i16,
        frequency: f32,

        pub const Options = struct {
            seed: u16,
        };

        pub fn init(options: Options) Noise {
            return Noise{
                .seed = options.seed,
                .phase = 0,
                .lastRandom = 0,
                .frequency = 0,
            };
        }

        pub fn setFrequency(noise: *Noise, frequency: u16) void {
            noise.frequency = @intToFloat(f32, frequency);
        }

        /// 16-bit xorshift PRNG implementing lfsr.
        /// http://www.retroprogramming.com/2017/07/xorshift-pseudorandom-numbers-in-z80.html
        fn xorshift(noise: *Noise) void {
            noise.seed ^= noise.seed >> 7;
            noise.seed ^= noise.seed << 9;
            noise.seed ^= noise.seed >> 13;
        }

        /// Returns 0 or 1 psuedo-randomly
        pub fn sample(noise: *Noise, sample_rate: f32) f32 {
            noise.phase += noise.frequency * noise.frequency / (1_000_000.0 / 44100.0 * @as(f32, sample_rate));
            while (noise.phase > 0) {
                noise.phase -= 1;
                noise.xorshift();
                noise.lastRandom = @bitCast(i16, 2 *% (noise.seed & 0x1) -% 1);
            }
            return @intToFloat(f32, noise.lastRandom);
        }
    };

    test "noise" {
        const sample_rate = 44100;
        var noise = Noise.init(.{.seed = 0x001});
        noise.setFrequency(440);
        try testing.expectEqual(@as(f32, 1), noise.sample(sample_rate));
    }

    pub const Square = struct {
        phase: f32 = 0,
        dutyCycle: f32 = 0.5,
        frequency: f32 = 0,

        fn polyblep(phase: f32, phaseInc: f32) f32 {
            if (phase < phaseInc) {
                var t = phase / phaseInc;
                return t + t - t * t;
            } else if (phase > 1.0 - phaseInc) {
                var t = (phase - (1.0 - phaseInc)) / phaseInc;
                return 1.0 - (t + t - t * t);
            } else {
                return 1.0;
            }
        }

        pub fn sample(square: *Square, sample_rate: f32) f32 {
            const phaseInc = (square.frequency) / sample_rate;
            square.phase += phaseInc;

            var dutyPhase: f32 = 0;
            var dutyPhaseInc: f32 = 0;
            var multiplier = 1;
            if (square.phase < square.dutyCycle) {
                dutyPhase = square.phase / square.dutyCycle;
                dutyPhaseInc = square.phase / square.dutyCycle;
                multiplier = 1;
            } else {
                dutyPhase = (square.phase - square.dutyCycle) / (1.0 - square.dutyCycle);
                dutyPhaseInc = phaseInc / (1.0 - square.dutyCycle);
                multiplier = -1;
            }
            return polyblep(dutyPhase, dutyPhaseInc);
        }
    };

    pub const Triangle = struct {
        phase: f32 = 0,
        frequency: f32 = 0,

        pub fn sample(triangle: *Triangle, sample_rate: f32) f32 {
            triangle.phase += (triangle.frequency) / sample_rate;
            return (2 * @fabs(2 * triangle.phase - 1) - 1);
        }
    };
};

pub const Envelope = struct {
    /// Time for the initial run-up of level from nil to to peak
    attack: f32,
    /// Time for run down to sustain from peak
    decay: f32,
    /// Level for sustain
    sustain: f32,
    release: f32,
};

pub const Synth = struct {};
