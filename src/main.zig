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
        pub fn sample(noise: *Noise, sample_rate: f32) i16 {
            noise.phase += noise.frequency * noise.frequency / (1_000_000.0 / 44100.0 * @as(f32, sample_rate));
            std.log.warn("{}", .{noise.phase});
            while (noise.phase > 0) {
                noise.phase -= 1;
                noise.xorshift();
                noise.lastRandom = @bitCast(i16, 2 *% (noise.seed & 0x1) -% 1);
            }
            std.log.warn("{}, {}", .{noise.phase, noise.lastRandom});
            return noise.lastRandom;
        }
    };

    test "noise" {
        const sample_rate = 44100;
        var noise = Noise.init(.{.seed = 0x001});
        noise.setFrequency(440);
        try testing.expectEqual(@as(i16, 1), noise.sample(sample_rate));
    }
};

pub const Envelope = struct {};

pub const Synth = struct {};
