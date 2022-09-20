const std = @import("std");
const testing = std.testing;

const Riff = struct {
    chunk_id: [4]u8,
    chunk_size: u32,
    format: [4]u8,
};

const AudioFormat = enum(u16) { PCM = 1 };

const Format = struct {
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
            if (fmt.num_channels == 1) return .Mono8Bit;
            if (fmt.num_channels == 2) return .Stereo8Bit;
            return error.Unsupported;
        } else if (fmt.bits_per_sample == 16) {
            if (fmt.num_channels == 1) return .Mono16Bit;
            if (fmt.num_channels == 2) return .Stereo16Bit;
            return error.Unsupported;
        }
        return error.Unsupported;
    }
};

const DataHeader = struct {
    subchunk_id: [4]u8,
    subchunk_size: u32,
};

const WavDataEnum = enum {
    Mono8Bit,
    Stereo8Bit,
    Mono16Bit,
    Stereo16Bit,
};

const WavData = union(WavDataEnum) {
    Mono8Bit: []u8,
    Stereo8Bit: []u8,
    Mono16Bit: []u16,
    Stereo16Bit: []u16,

    pub fn free(data: WavData, alloc: std.mem.Allocator) void {
        switch (data) {
            .Mono8Bit => |slice| alloc.free(slice),
            .Stereo8Bit => |slice| alloc.free(slice),
            .Mono16Bit => |slice| alloc.free(slice),
            .Stereo16Bit => |slice| alloc.free(slice),
        }
    }
};

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

fn readDataHeader(reader: anytype) !DataHeader {
    var data_header: DataHeader = undefined;
    // -- Sub-chunk 2 -- //
    // Ensure the next chunk is a data chunk
    if (try reader.read(&data_header.subchunk_id) != 4) return error.UnexpectedEOF;
    if (!std.mem.eql(u8, &data_header.subchunk_id, "data")) return error.InvalidDataHeader;
    data_header.subchunk_size = try reader.readInt(u32, .Little);

    return data_header;
}

fn readAllData(reader: anytype, format: Format, data_header: DataHeader, data: WavData) !void {
    const sample_num = getSampleNum(format, data_header);
    switch (data) {
        .Mono8Bit => |slice| {
            const num_samples = data_header.subchunk_size / (format.num_channels * format.bits_per_sample / 8);
            if (slice.len < num_samples) return error.InsufficientBuffer;
            var i: usize = 0;
            while (i < sample_num) : (i += 1) {
                slice[i] = try reader.readInt(u8, .Little);
            }
        },
        .Stereo8Bit => |slice| {
            const num_samples = data_header.subchunk_size / (format.num_channels * format.bits_per_sample / 8);
            if (slice.len < num_samples) return error.InsufficientBuffer;
            // return try reader.readAll(@ptrCast([]u8, slice));
            // try reader.readAll(slice);
            var i: usize = 0;
            while (i < sample_num) : (i += 1) {
                slice[i] = try reader.readInt(u8, .Little);
            }
        },
        .Mono16Bit => |slice| {
            const num_samples = data_header.subchunk_size / (format.num_channels * format.bits_per_sample / 8);
            if (slice.len < num_samples) return error.InsufficientBuffer;
            // return try reader.readAll(@ptrCast([]u8, slice));
            // try reader.readAll(slice);
            var i: usize = 0;
            while (i < sample_num) : (i += 1) {
                slice[i] = try reader.readInt(u16, .Little);
            }
        },
        .Stereo16Bit => |slice| {
            const num_samples = data_header.subchunk_size / (format.num_channels * format.bits_per_sample / 8);
            if (slice.len < num_samples) return error.InsufficientBuffer;
            // return try reader.readAll(@ptrCast([]u8, slice));
            // try reader.readAll(slice);
            var i: usize = 0;
            while (i < sample_num) : (i += 1) {
                slice[i] = try reader.readInt(u16, .Little);
            }
        },
    }
}

fn getSampleNum(format: Format, data_header: DataHeader) usize {
    return data_header.subchunk_size / (format.num_channels * format.bits_per_sample / 8);
}

test "ambience.wav" {
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
        .Mono8Bit => .{ .Mono8Bit = try alloc.alloc(u8, sample_num) },
        .Stereo8Bit => .{ .Stereo8Bit = try alloc.alloc(u8, sample_num) },
        .Mono16Bit => .{ .Mono16Bit = try alloc.alloc(u16, sample_num) },
        .Stereo16Bit => .{ .Stereo16Bit = try alloc.alloc(u16, sample_num) },
    };
    defer data_buffer.free(alloc);

    try readAllData(reader, format, data_header, data_buffer);
}
