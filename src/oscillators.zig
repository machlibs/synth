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

// According to stb, ought to be good enough for anybody
const MAX_BLEP_LENGTH = 64;

/// Used to antialias waves
pub const HexBlep = struct {
    width: usize,
    oversample: usize,
    blep_buffer: []f32,
    blamp_buffer: []f32,

    // TODO: allow configuring / computing blep at comptime
    // fn initComptime()

    pub fn init(width_passed: usize, oversample: usize, init_buffer: []f32, store_buffer: []f32) HexBlep {
        const halfwidth = width_passed / 2;
        const half = halfwidth * oversample;
        const blep_buffer_count = width_passed * (oversample + 1);
        const n = 2 * half + 1;
        const step = init_buffer[0..n];
        const ramp = init_buffer[n..];
        const blep_buffer = store_buffer[0..blep_buffer_count];
        const blamp_buffer = store_buffer[blep_buffer_count..];
        var integrate_impulse: f64 = 0;
        var integrate_step: f64 = 0;

        // change this to a comptime variable
        const width = if (width_passed > MAX_BLEP_LENGTH) MAX_BLEP_LENGTH else width_passed;

        // compute BLEP and BLAMP by integrating windowed sinc
        {
            var i: usize = 0;
            while (i < n) : (i += 1) {
                var j: usize = 0;
                while (j < 16) : (j += 1) {
                    const sinc_t: f32 = std.math.pi * (@intToFloat(f32, i) - @intToFloat(f32, half)) / @intToFloat(f32, oversample);
                    const sinc: f32 = if (i == half) 1.0 else std.math.sin(sinc_t) / sinc_t;
                    const wt: f32 = 2.0 * std.math.pi * @intToFloat(f32, i) / @intToFloat(f32, n - 1);
                    const window: f32 = (0.355768 - 0.487396 * std.math.cos(wt) + 0.144232 * std.math.cos(2 * wt) - 0.012604 * std.math.cos(3 * wt)); // Nuttal
                    const value: f64 = @as(f64, window) * @as(f64, sinc);
                    integrate_impulse += value / 16;
                    integrate_step += integrate_impulse / 16;
                }
                step[i] = @floatCast(f32, integrate_impulse);
                ramp[i] = @floatCast(f32, integrate_step);
            }
        }

        // renormalize
        {
            var i: usize = 0;
            while (i < n) : (i += 1) {
                step[i] = step[i] * (1.0 / step[n - 1]);
                ramp[i] = ramp[i] * (@intToFloat(f32, halfwidth) / ramp[n - 1]);
            }
        }

        // deinterleave to allow efficient interpolation e.g. w/SIMD
        {
            var j: usize = 0;
            while (j <= oversample) : (j += 1) {
                var i: usize = 0;
                while (i < width) : (i += 1) {
                    blep_buffer[j * width + i] = step[j + i * oversample];
                    blamp_buffer[j * width + i] = ramp[j + i * oversample];
                }
            }
        }

        // subtract out the naive waveform; note we can't do this to the raw data
        // above because we want the discontinuity to be in a different location
        // for `j= 0` and `j=oversample` (which exists to provide something to interpolate against)
        {
            var j: usize = 0;
            while (j <= oversample) : (j += 1) {
                // subtract step
                var i: usize = halfwidth;
                while (i < width) : (i += 1) {
                    blep_buffer[j * width + i] -= 1.0;
                }

                // subtract ramp
                i = halfwidth;
                while (i < width) : (i += 1) {
                    blamp_buffer[j * width + i] -= @intToFloat(f32, j + i * oversample - half) * (1.0 / @intToFloat(f32, oversample));
                }
            }
        }

        return HexBlep{
            .width = width,
            .oversample = oversample,
            .blep_buffer = blep_buffer,
            .blamp_buffer = blamp_buffer,
        };
    }

    pub fn initAlloc(alloc: std.mem.Allocator, width: usize, oversample: usize) !HexBlep {
        const halfwidth = width / 2;
        const half = halfwidth * oversample;
        const blep_buffer_count = width * (oversample + 1);
        const n = 2 * half + 1;

        const init_buffer = try alloc.alloc(f32, n * 2);
        defer alloc.free(init_buffer);
        const store_buffer = try alloc.alloc(f32, blep_buffer_count * 2);

        return init(width, oversample, init_buffer, store_buffer);
    }

    fn compute(hex_blep: HexBlep, output: []f32, time_since_transition: f32, scale: f32, data: []f32) void {
        var slot = @floatToInt(usize, time_since_transition * @intToFloat(f32, hex_blep.oversample));
        if (slot >= hex_blep.oversample) slot = hex_blep.oversample;

        const out = output[0..hex_blep.width];
        const d1 = data[slot .. slot + hex_blep.width];
        const d2 = data[slot + 1 .. slot + 1 + hex_blep.width];

        const lerpweight = time_since_transition * @intToFloat(f32, hex_blep.oversample) - @intToFloat(f32, slot);
        for (out) |*sample, i| {
            sample.* = scale * (d1[i] + (d2[i] - d1[i]) * lerpweight);
        }
    }

    pub fn blep(hex_blep: HexBlep, output: []f32, time_since_transition: f32, scale: f32) void {
        hex_blep.compute(output, time_since_transition, scale, hex_blep.blep_buffer);
    }

    pub fn blamp(hex_blep: HexBlep, output: []f32, time_since_transition: f32, scale: f32) void {
        hex_blep.compute(output, time_since_transition, scale, hex_blep.blamp_buffer);
    }
};

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
    time: f32,
    prev_dt: f32,
    /// The current parameters
    current: Parameters,
    /// The parameters that are waiting to be applied
    pending: ?Parameters,
    /// Lookup table for the blep function
    hex_blep: HexBlep,
    /// Stores overlap between runs
    buffer: [MAX_BLEP_LENGTH]f32,

    /// Creates a hexwave oscillator
    pub fn init(hex_blep: HexBlep, parameters: Parameters) Hexwave {
        return Hexwave{
            .time = 0,
            .prev_dt = 0,
            .current = parameters,
            .pending = null,
            .hex_blep = hex_blep,
            .buffer = undefined,
        };
    }

    const HexwaveUnit = struct {
        frequency: f32,
        hexwave: Hexwave,

        pub fn run(obj: *Unit, _: usize, _: [][]const f32, outputs: [][]f32) void {
            var self = @ptrCast(*HexwaveUnit, @alignCast(@alignOf(HexwaveUnit), &obj.data));
            self.hexwave.generateSamples(outputs[0], self.frequency / @intToFloat(f32, obj.sample_rate));
        }
    };

    pub fn unit(hex_blep: HexBlep, parameters: Parameters, frequency: f32) Unit {
        var obj = Unit{
            .name = "Hexwave",
            .run = HexwaveUnit.run,
            .data = undefined,
            .inputs = 0,
            .outputs = 1,
        };
        var self = @ptrCast(*HexwaveUnit, @alignCast(@alignOf(HexwaveUnit), &obj.data));
        self.* = HexwaveUnit{
            .hexwave = Hexwave.init(hex_blep, parameters),
            .frequency = frequency,
        };
        return obj;
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

    const HexVert = struct {
        time: f32,
        value: f32,
        slope: f32,
    };

    /// 9 vertices, 4 for each side  plus 1 more for wraparound
    fn generateLineSegments(hex: *Hexwave, dt: f32) [9]HexVert {
        var vert: [9]HexVert = undefined;
        var min_len: f32 = dt / 256.0;

        vert[0].time = 0;
        vert[0].value = 0;
        vert[1].time = hex.current.zero_wait * 0.5;
        vert[1].value = 0;
        vert[2].time = 0.5 * hex.current.peak_time + vert[1].time * (1 - hex.current.peak_time);
        vert[2].value = 0;
        vert[3].time = 0.5;
        vert[3].value = hex.current.half_height;

        if (hex.current.reflect) {
            var j: usize = 4;
            while (j <= 7) : (j += 1) {
                vert[j].time = 1 - vert[7 - j].time;
                vert[j].value = -vert[7 - j].value;
            }
        } else {
            var j: usize = 4;
            while (j <= 7) : (j += 1) {
                vert[j].time = 0.5 - vert[j - 4].time;
                vert[j].value = -vert[j - 4].value;
            }
        }

        vert[8].time = 1;
        vert[8].value = 0;
        {
            var j: usize = 0;
            while (j < 8) : (j += 1) {
                if (vert[j + 1].time <= vert[j].time + min_len) {
                    // Comment transcribed from stb_hexwave
                    // If change takes place over less than a fraction of a sample treat as discountinuity
                    //
                    // Otherwise the slope computation can blow up to arbitrarily large and we
                    // try to generate a huge BLAMP and the result is wrong.
                    //
                    // Why does this happen if the math is right? I believe if done perfectly,
                    // the two BLAMPs on either side of the slope would cancel out, but our
                    // BLAMPs have only limited sub-sample precision and limited integration
                    // accuracy . Or maybe it's just the math blowing up w/ floating point precision
                    // limits as we try to make x * (1/x) cancel out
                    //
                    // min_len verified artifact-free even near nyquist with only oversample = 4
                    vert[j + 1].time = vert[j].time;
                }
            }
        }

        if (vert[8].time != 1.0) {
            // If the above fixup moved the endpoint away from 1.0, move it back,
            // along with any other vertices that got moved to the same time
            const time = vert[8].time;
            var j: usize = 0;
            while (j <= 8) : (j += 1) {
                if (vert[j].time == time) {
                    vert[j].time = 1.0;
                }
            }
        }

        {
            // Compute the exact slopes from the final fixed-up positions
            var j: usize = 0;
            while (j < 8) : (j += 1) {
                if (vert[j + 1].time == vert[j].time) {
                    vert[j].slope = 0;
                } else {
                    vert[j].slope = (vert[j + 1].value - vert[j].value) / (vert[j + 1].time - vert[j].time);
                }
            }
        }

        vert[8].time = 1;
        vert[8].value = vert[0].value;
        vert[8].slope = vert[0].slope;

        return vert;
    }

    /// Generates samples into the `out` buffer. Divide the frequency by the sample_rate before passing it in as `frequency`.
    pub fn generateSamples(hex: *Hexwave, output: []f32, frequency: f32) void {
        const hex_blep = hex.hex_blep;
        var t = hex.time;
        var temp_output_buffer: [2 * MAX_BLEP_LENGTH]f32 = undefined;
        var temp_output = &temp_output_buffer;
        const buffered_length = hex.hex_blep.width;
        const dt = @fabs(frequency);
        const recip_dt = if (dt == 0.0) 0.0 else 1.0 / dt;

        const halfw = hex.hex_blep.width / 2;
        // All sample times are biased by halfw to leave room for BLEP/BLAMP to go back in time

        // Don't try to process a zero length buffer
        if (output.len <= 0) return;

        // Convert parameters to times and slopes
        var vert = hex.generateLineSegments(dt);

        if (hex.prev_dt != dt) {
            // If frequency changes, add a fixup at the derivative discontinuity starting at now
            var j: usize = 1;
            while (j < 6) : (j += 1) {
                if (t < vert[j].time) break;
            }
            const slope = vert[j].slope;
            if (slope != 0) hex_blep.blamp(output, 0, (dt - hex.prev_dt) * slope);
            hex.prev_dt = dt;
        }

        // copy the buffered data from the last call and clear the rest of the output array
        std.mem.set(f32, output, 0);
        std.mem.set(f32, temp_output, 0);

        if (output.len >= hex_blep.width) {
            std.mem.copy(f32, output, &hex.buffer);
        } else {
            // if the output is shorter than hex_blep.width, we do all synthesis to temp_output
            std.mem.copy(f32, temp_output, &hex.buffer);
        }

        var pass: usize = 0;
        pass: while (pass < 2) : (pass += 1) {
            var i_0: usize = 0;
            var i_1: usize = 0;
            var out: []f32 = output;

            // we want to simulat having one buffer that is num_output + hex_blep.width
            // samples long, without putting that requirement on the user, and without
            // allocating a temp buffer that's as long as the whole thing. So we use two
            // overlapping buffers, one the user's buffer and one a fixed-length temp
            // buffer.
            if (pass == 0) {
                if (out.len < hex_blep.width) continue;
                // run as far as we can without overwriting the end of the user's buffer
                // TODO is this a place for slicing?
                out = output;
                i_0 = 0;
                i_1 = out.len - hex_blep.width;
            } else {
                //generate the rest into a temp buffer
                out = temp_output;
                i_0 = 0;
                if (out.len >= hex_blep.width) {
                    i_1 = hex_blep.width;
                } else {
                    i_1 = out.len;
                }
            }

            // determine current segment
            var j: usize = 0;
            while (j < 8) : (j += 1) {
                if (t < vert[j + 1].time) break;
            }

            var i = i_0;
            while (true) {
                while (t < vert[j + 1].time) : (i += 1) {
                    // TODO: decipher this loop
                    if (i == i_1) break :pass;
                    out[i + halfw] += vert[j].value + vert[j].slope * (t - vert[j].time);
                    t += dt;
                }
                // transition from lineseg starting at j to lineseg starting at j + 1

                if (vert[j].time == vert[j + 1].time) {
                    hex_blep.blep(out[i..], recip_dt * (t - vert[j + 1].time), (vert[j + 1].value - vert[j].value));
                }
                hex_blep.blamp(out[i..], recip_dt * (t - vert[j + 1].time), dt * (vert[j + 1].slope - vert[j].slope));

                j += 1;

                if (j == 8) {
                    // change to different waveform if there's a change pending
                    j = 0;
                    t -= 1.0; // t was >= 1.0 if j==8
                    if (hex.pending) |pending| {
                        const prev_slope = vert[j].slope;
                        const prev_value = vert[j].value;
                        hex.current = pending;
                        hex.pending = null;
                        vert = hex.generateLineSegments(dt);
                        // the following never occurs with this oscillator but it makes the code work in more general cases
                        if (vert[j].value != prev_value) {
                            hex_blep.blep(out[i..], recip_dt * t, (vert[j].value - prev_value));
                        }
                        if (vert[j].slope != prev_slope) {
                            hex_blep.blamp(out[i..], recip_dt * t, dt * (vert[j].slope - prev_value));
                        }
                    }
                }
            }
        }

        // at this point we've written output and temp_output
        if (output.len >= hex_blep.width) {
            // the first half of temp overlaps the end of output, the second half will be the new start overlap
            var i: usize = 0;
            while (i < hex_blep.width) : (i += 1) {
                output[output.len - hex_blep.width + i] += temp_output[i];
            }
            // copy from temp_output to buffer?
            std.mem.copy(f32, &hex.buffer, temp_output[hex_blep.width .. hex_blep.width + buffered_length]);
        } else {
            var i: usize = 0;
            while (i < output.len) : (i += 1) {
                output[i] += temp_output[i];
            }
            // copy from temp_output to buffer?
            std.mem.copy(f32, &hex.buffer, temp_output[output.len .. hex_blep.width + buffered_length]);
        }

        hex.time = t;
    }
};
