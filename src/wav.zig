const std = @import("std");
const testing = std.testing;

const WAV = @This();

format: Format,
samples: WavData,

/// Read wav file from given reader
pub fn read(alloc: std.mem.Allocator, reader: anytype) !WAV {
    // Read RIFF header to verify it is a WAV file
    const riff = try readHeader(reader);
    _ = riff;

    // Read format data
    const format = try readFormat(reader);

    // Read data header and allocate
    const data_header = try readDataHeader(reader);
    const data_format = try format.getDataFormat();
    const sample_num = getSampleNum(format, data_header);
    const data_buffer: WavData = switch (data_format) {
        .UInt8 => .{ .UInt8 = try alloc.alloc(u8, sample_num) },
        .SInt16 => .{ .SInt16 = try alloc.alloc(i16, sample_num) },
    };

    try readAllData(reader, format, data_header, data_buffer);

    return WAV{
        .format = format,
        .samples = data_buffer,
    };
}

/// Read a WAV file from memory
pub fn readFromBuffer(alloc: std.mem.Allocator, data: []const u8) !WAV {
    var fixed_buffer_stream = std.io.FixedBufferStream([]const u8){
        .buffer = data,
        .pos = 0,
    };

    const reader = fixed_buffer_stream.reader();

    return WAV.read(alloc, reader);
}

/// Free the wav samples
pub fn free(wav: *WAV, alloc: std.mem.Allocator) void {
    wav.samples.free(alloc);
}

/// Convert the u8 or i16 data into floating point samples
pub fn toF32(wav: *WAV, out: []f32) usize {
    switch (wav.samples) {
        .UInt8 => |slice| {
            if (out.len < slice.len) return error.OutOfMemory;
            for (slice) |sample, i| {
                out[i] = (@intToFloat(f32, sample) / @as(f32, std.math.maxInt(u8))) * 2 - 1;
            }
        },
        .SInt16 => |slice| {
            if (out.len < slice.len) return error.OutOfMemory;
            for (slice) |sample, i| {
                out[i] = @intToFloat(f32, sample) / @as(f32, std.math.maxInt(i16));
            }
        },
    }
}

/// Stores the RIFF header information for a WAV file
pub const Riff = struct {
    chunk_id: [4]u8,
    chunk_size: u32,
    format: [4]u8,
};

/// WAV file format values. Only PCM is supported at the moment.
const AudioFormat = enum(u16) { PCM = 1 };

/// WAV Foramt chunk, describes the format of the audio data
pub const Format = struct {
    subchunk_id: [4]u8,
    subchunk_size: u32,
    audio_format: AudioFormat,
    num_channels: u16,
    sample_rate: u32,
    byte_rate: u32,
    block_align: u16,
    bits_per_sample: u16,

    pub fn getDataFormat(fmt: Format) !WavDataEnum {
        if (fmt.bits_per_sample == 8) {
            return .UInt8;
        } else if (fmt.bits_per_sample == 16) {
            return .SInt16;
        }
        return error.Unsupported;
    }
};

/// Header for the audio data chunk
pub const DataHeader = struct {
    subchunk_id: [4]u8,
    subchunk_size: u32,
};

/// Possible formats for the audio stream
pub const WavDataEnum = enum {
    UInt8,
    SInt16,
};

pub const WavData = union(WavDataEnum) {
    UInt8: []u8,
    SInt16: []i16,

    pub fn free(data: WavData, alloc: std.mem.Allocator) void {
        switch (data) {
            .UInt8 => |slice| alloc.free(slice),
            .SInt16 => |slice| alloc.free(slice),
        }
    }
};

/// Read the RIFF header chunk of a WAV file.
fn readHeader(reader: anytype) !Riff {
    var riff: Riff = undefined;
    // -- Header -- //
    // Read the RIFF magic bytes
    if (try reader.read(&riff.chunk_id) != 4) return error.UnexpectedEOF;
    if (!std.mem.eql(u8, &riff.chunk_id, "RIFF")) return error.NotARiffFile;

    // Length of the file overall
    riff.chunk_size = try reader.readInt(u32, .Little);

    // Check that the file is indeed a wav file and not some other RIFF file.
    if (try reader.read(&riff.format) != 4) return error.MissingHeaderFormat;
    if (!std.mem.eql(u8, &riff.format, "WAVE")) return error.NotAWavFile;

    return riff;
}

/// Read the format sub-chunk of a WAV file.
fn readFormat(reader: anytype) !Format {
    var format: Format = undefined;

    // -- Sub-chunk 1 -- //
    // Read the fmt sub-chunk. This chunk describes the format of the audio.
    if (try reader.read(&format.subchunk_id) != 4) return error.UnexpectedEOF;
    if (!std.mem.eql(u8, &format.subchunk_id, "fmt ")) return error.InvalidFormatHeader;

    // Read the length of the format chunk
    format.subchunk_size = try reader.readInt(u32, .Little);
    if (format.subchunk_size != 16) return error.UnsupportedFormatLength;

    // Read the audio format of the data. This function only implements support for uncompressed wav files.
    format.audio_format = try reader.readEnum(AudioFormat, .Little);
    if (format.audio_format != .PCM) return error.CompressedWavFile;

    format.num_channels = try reader.readInt(u16, .Little);
    format.sample_rate = try reader.readInt(u32, .Little);
    format.byte_rate = try reader.readInt(u32, .Little);
    format.block_align = try reader.readInt(u16, .Little);
    format.bits_per_sample = try reader.readInt(u16, .Little);

    // Format consistency checks
    if ((format.sample_rate * format.num_channels * format.bits_per_sample) / 8 != format.byte_rate) return error.MismatchedByteRate;
    if ((format.num_channels * format.bits_per_sample) / 8 != format.block_align) return error.MismatchedBlockAlign;

    return format;
}

/// Read the data header to check validity and find the data length
fn readDataHeader(reader: anytype) !DataHeader {
    var data_header: DataHeader = undefined;
    // -- Sub-chunk 2 -- //
    // Ensure the next chunk is a data chunk
    if (try reader.read(&data_header.subchunk_id) != 4) return error.UnexpectedEOF;
    if (!std.mem.eql(u8, &data_header.subchunk_id, "data")) return error.InvalidDataHeader;
    data_header.subchunk_size = try reader.readInt(u32, .Little);

    return data_header;
}

/// Read all the data from the WAV data section
fn readAllData(reader: anytype, format: Format, data_header: DataHeader, data: WavData) !void {
    const num_samples = getSampleNum(format, data_header);
    switch (data) {
        .UInt8 => |slice| {
            if (slice.len < num_samples) return error.InsufficientBuffer;
            var i: usize = 0;
            while (i < num_samples) : (i += 1) {
                slice[i] = try reader.readInt(u8, .Little);
            }
        },
        .SInt16 => |slice| {
            if (slice.len < num_samples) return error.InsufficientBuffer;
            var i: usize = 0;
            while (i < num_samples) : (i += 1) {
                slice[i] = try reader.readInt(i16, .Little);
            }
        },
    }
}

fn getSampleNum(format: Format, data_header: DataHeader) usize {
    return data_header.subchunk_size / (format.num_channels * format.bits_per_sample / 8);
}

test "manual read ambience.wav" {
    const file = @embedFile("ambience.wav");
    var fixed_buffer_stream = std.io.FixedBufferStream([]const u8){
        .buffer = file,
        .pos = 0,
    };

    const reader = fixed_buffer_stream.reader();

    const riff = try readHeader(reader);
    try testing.expectEqualSlices(u8, "RIFF", &riff.chunk_id);
    try testing.expectEqual(@as(u32, 82472), riff.chunk_size);
    try testing.expectEqualSlices(u8, "WAVE", &riff.format);

    const format = try readFormat(reader);
    try testing.expectEqualSlices(u8, "fmt ", &format.subchunk_id);
    try testing.expectEqual(@as(u32, 16), format.subchunk_size);
    try testing.expectEqual(AudioFormat.PCM, format.audio_format);
    try testing.expectEqual(@as(u16, 2), format.num_channels);
    try testing.expectEqual(@as(u32, 44100), format.sample_rate);
    try testing.expectEqual(@as(u32, 176400), format.byte_rate);
    try testing.expectEqual(@as(u32, 4), format.block_align);
    try testing.expectEqual(@as(u16, 16), format.bits_per_sample);

    const data_header = try readDataHeader(reader);
    const data_format = try format.getDataFormat();
    const sample_num = getSampleNum(format, data_header);
    const alloc = testing.allocator;
    const data_buffer: WavData = switch (data_format) {
        .UInt8 => .{ .UInt8 = try alloc.alloc(u8, sample_num) },
        .SInt16 => .{ .SInt16 = try alloc.alloc(i16, sample_num) },
    };
    defer data_buffer.free(alloc);

    try readAllData(reader, format, data_header, data_buffer);
}

test "read ambience.wav" {
    const file = @embedFile("ambience.wav");
    var wav = try WAV.readFromBuffer(testing.allocator, file);
    defer wav.free(testing.allocator);

    const format = wav.format;
    try testing.expectEqualSlices(u8, "fmt ", &format.subchunk_id);
    try testing.expectEqual(@as(u32, 16), format.subchunk_size);
    try testing.expectEqual(AudioFormat.PCM, format.audio_format);
    try testing.expectEqual(@as(u16, 2), format.num_channels);
    try testing.expectEqual(@as(u32, 44100), format.sample_rate);
    try testing.expectEqual(@as(u32, 176400), format.byte_rate);
    try testing.expectEqual(@as(u32, 4), format.block_align);
    try testing.expectEqual(@as(u16, 16), format.bits_per_sample);
}
