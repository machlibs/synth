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

fn clamp(v: anytype, a: @TypeOf(v), b: @TypeOf(v)) @TypeOf(v) {
    return @minimum(a, @maximum(v, b));
}

/// A port of stb_hexwave v0.5. The following text is paraphrased from
/// the original file.
///
/// A flexible anit-aliased (bandlimited) digital audio oscillator.
///
/// Hexwave attempts to solve the problem of generating artifact-free
/// morphable digital waveforms with a variety of spectra.
///
/// ## Waveform Shapes
/// All waveforms generated by hexwave are constructed from six line segments
/// characterized by 3 parameters.
pub const Hexwave = struct {
    /// Stores the parameters for a hexwave oscillator.
    pub const Parameters = struct {
        /// Whether the wave is reflected horizontally or not. The reflection occurs on the time-domain.
        reflect: bool = false,
        /// How long the line segment stays at the peak.
        /// peak_time is clamped to the range 0..1
        peak_time: f32 = 0,
        /// The height of the end of the peak.
        /// half_height is not clamped
        half_height: f32 = 0,
        /// Time to wait between the beginning of a cycle and starting the line.
        /// zero_wait is clamped to 0..1
        zero_wait: f32 = 0,
    };

    /// Time
    t: f32,
    prev_dt: f32,
    /// The current parameters
    current: Parameters,
    /// The parameters that are waiting to be applied
    pending: ?Parameters,
    width: usize,
    oversample: usize,
    user_buffer: []f32,
    /// Lookup table for the blep function
    blep: *OversampledBlepLike,

    /// A convenience function wrapping `init()` that will allocate `user_buffer` for you
    pub fn initAlloc(alloc: std.mem.Allocator, width: usize, oversample: usize, parameters: Parameters) !Hexwave {
        const blep_buffer_count = width * (oversample + 1);
        const user_buffer = try alloc.alloc(f32, blep_buffer_count);
        const blep_ = try alloc.create(blep);
        // blep
        blep_.* = OversampledBlepLike{
            .width = width,
            .oversample = oversample,
            .blep = user_buffer[0..oversample],
            .blamp = user_buffer[oversample..],
        };
        return init(blep_, parameters);
    }

    /// Creates a hexwave oscillator. The `user_buffer` is a temporary buffer.
    pub fn init(blep_: *OversampledBlepLike, parameters: Parameters) Hexwave {
        // TODO: compute BLEP and BLAMP by integrating windowed sinc

        // TODO: renormalize

        // TODO: deinterleave to allow efficient interpolation e.g. w/SIMD

        // TODO: subtract out the naive waveform; note we can't do this to the raw data
        // above because we want the discontinuity to be in a different location
        // for `j= 0` and `j=oversample` (which exists to provide something to interpolate against)
        // loop
        //     subtract step
        //     subtract ramp

        // TODO
        // hexblep.blep = blep_buffer;
        // hexblep.blamp = blamp_buffer;
        // hexblep.width = width;
        // hexblep.oversample = oversample;

        return Hexwave{
            .t = 0,
            .prev_dt = 0,
            .current = parameters,
            .pending = null,
            .blep = blep_,
        };
    }

    /// Schedules a parameter change to occur on the next wave boundary to prevent aliasing.
    pub fn change(hex: *Hexwave, into: Parameters) void {
        hex.pending = Parameters{
            .reflect = into.reflect,
            .peak_time = into.peak_time,
            .half_height = into.half_height,
            .zero_wait = into.zero_wait,
        };
    }

    // TODO: make it better?
    const OversampledBlepLike = struct {
        width: usize,
        oversample: usize,
        blep: []f32,
        blamp: []f32,

        fn oversample(blep: OversampledBlepLike, output: []f32, time_since_transition: f32, scale: f32, data: []f32) void {
            const slot = @floatToInt(i32, time_since_transition * blep.oversample);
            if (slot >= blep.oversample) slot = blep.oversample;

            const out = output[0..blep.width];
            const d1 = data[slot .. slot + blep.width];
            const d2 = data[slot - 1 .. slot - 1 + blep.width];

            const lerpweight = time_since_transition * blep.oversample - slot;
            for (out) |*sample, i| {
                sample.* = scale * (d1[i] + (d2[i] - d1[i]) * lerpweight);
            }
        }

        fn oversampleBlep(blep: OversampledBlepLike, output: []f32, time_since_transition: f32, scale: f32) void {
            blep.oversample(output, time_since_transition, scale, blep.blep);
        }

        fn oversampleBlamp(blep: OversampledBlepLike, output: []f32, time_since_transition: f32, scale: f32) void {
            blep.oversample(output, time_since_transition, scale, blep.blamp);
        }
    };

    const HexVert = struct {
        time: f32,
        value: f32,
        slope: f32,
    };

    /// 9 vertices, 4 for each side  plus 1 more for wraparound
    fn generateLineSegments(hex: *Hexwave, dt: f32) [9]HexVert {
        _ = hex;
        _ = dt;
        // TODO: Generate line segments
    }

    /// Generates samples into the `out` buffer. Divide the frequency by the sample_rate before passing it in as `frequency`.
    pub fn generateSamples(hex: *Hexwave, out: []f32, frequency: f32) void {
        // TODO: finish writing this part
        var t = hex.time;
        var temp_output: [2 * MAX_BLEP_LENGTH]f32 = undefined;
        const buffered_length = @sizeOf(f32) * hexblep.width;
        const dt = @fabs(frequency);
        const recip_dt = if (dt == 0.0) 0.0 else 1.0 / dt;

        const halfw = hexblep.width / 2;
        // all sample times are biased by halfw to leave room for BLEP/BLAMP to go back in time

        // Don't try to process a zero length buffer
        if (num_samples <= 0) return;

        // convert parameters to times and slopes
        var vert = hex.generateLineSegments(dt);

        if (hex.prev_dt != dt) {
            // if frequency changes, add afixup at the derivative discontinuity starting at now
            var j: usize = 1;
            while (j < 6) : (j += 1) {
                if (t < vert[j].time) break;
            }
            const slope = vert[j].slope;
            if (slope != 0) hex.blep.oversampleBlamp(); // TODO
            hex.prev_dt = dt;
        }

        // copy the buffered dat afrom the last call and clear the rest of the output array
        // TODO memset output 0 (sizeof f32 * num_samples)
        // TODO memset temp_output 0 (2 * hexblep.width * sizeof f32)

        if (num_samples >= hexblep.width) {
            // if the output is shorter than hexblep.width, we do all synthesis to temp_output
            // TODO memcpy output hex.buffer buffered_length
        } else {
            // TODO memcpy temp_output hex.buffer buffered_length
        }

        var pass: usize = 0;
        pass: while (pass < 2) : (pass += 1) {
            var i0: usize = undefined;
            var i1: usize = undefined;
            var out: *f32 = undefined;

            // we want to simulat having one buffer that is num_output + hexblep.width
            // samples long, without putting that requirement on the user, and without
            // allocating a temp buffer that's as long as the whole thing. So we use two
            // overlapping buffers, one the user's buffer and one a fixed-length temp
            // buffer.
            if (pass == 0) {
                if (num_samples < hexblep.width) continue;
                // run as far as we can without overwriting the end of the user's buffer
                // TODO is this a place for slicing?
                out = output;
                i0 = 0;
                i1 = num_samples - hexblep.width;
            } else {
                //generate the rest into a temp buffer
                out = temp_output;
                i0 = 0;
                if (num_samples >= hexblep.width) {
                    i1 = hexblep.width;
                } else {
                    i1 = num_samples;
                }
            }

            // determine current segment
            var j: usize = 0;
            while (j < 8) : (j += 1) {
                if (t < vert[j + 1].t) break;
            }

            i = i0;
            while (true) {
                while (t < vert[j + 1].t) : (i += 1) {
                    // TODO: decipher this loop
                    if (i == i1) break :pass;
                    out[i + halfw] += vert[j].value + vert[j].slope * (t - vert[j].time);
                    t += dt;
                }
                // transition from lineseg starting at j to lineseg starting at j + 1

                if (vert[j].time == vert[j + 1].time) {
                    hex.blep.oversampleBlep(); // TODO
                }
                hex.blep.oversampleBlamp(); // TODO

                j += 1;

                if (j == 8) {
                    // change to different waveform if there's a change pending
                    j = 0;
                    t -= 1.0; // t was >= 1.0 if j==8
                    if (hex.pending) |pending| {
                        const prev_slope = vert[j].slope;
                        const prev_v0 = vert[j].value;
                        hex.current = pending;
                        hex.pending = null;
                        vert = hex.generateLineSegments(dt);
                        // the following never occurs with this oscillator but it makes the code work in more general cases
                        if (vert[j].value != prev_value) {
                            hex.blep.oversampleBlep(); // TODO
                        }
                        if (vert[j].slope != prev_slope) {
                            hex.blep.oversampleBlamp(); // TODO
                        }
                    }
                }
            }
        }

        // at this point we've written output and temp_output
        if (num_samples >= hexblep.width) {
            // the first half of temp overlaps the end of output, the second half will be the new start overlap
            var i: usize = 0;
            while (i < hexblep.width) : (i += 1) {
                output[num_samples - hexblep.width + i] += temp_output[i];
            }
            // copy from temp_output to buffer?
        } else {
            var i: usize = 0;
            while (i < num_samples) : (i += 1) {
                output[i] += temp_output[i];
            }
            // copy from temp_output to buffer?
        }

        hex.time = t;
    }
};
