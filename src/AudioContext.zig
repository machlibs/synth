const std = @import("std");

pub const AudioParamType = union(enum) {
    Float,
    // FloatRange: []const f32,
    Int,
    // IntRange: []const i32,
    Enum: [][]const u8,
    Bool,
};

/// Processing rate of an AudioParam
pub const AudioParamRate = enum {
    /// Params with a rate of Sample can update at any point in a block
    Sample,
    /// Params with a rate of Block can update once per block
    Block,
};

/// The definition of a single parameter on an AudioNode
pub const AudioParamDefinition = struct {
    /// The name of the parameter. This should clearly describe the parameter
    name: []const u8,
    /// The short name of the parameter. This should clearly identify the parameter
    short_name: []const u8,
    /// The type of the AudioParam.
    /// - Float: a 32-bit floating point number
    /// - Int: a signed 32-bit integer
    /// - Enum: a set of named constants
    /// - Bool: true or false
    type: AudioParamType,
    /// How quickly the AudioParam can change value
    /// - Sample: changes to the AudioParam value are take effect at a per-sample rate
    /// - Block: changes to the AudioParam value are take effect at the beginning of a block (128 samples)
    rate: AudioParamRate,
};

/// Defines a specific type of audio node
pub const AudioNodeDefinition = struct {
    /// The name of the node. This should clearly describe the node
    name: []const u8,
    /// The short name of the parameter. This should clearly identify the parameter
    short_name: []const u8,
    params: []AudioParamDefinition,
    inputCount: usize,
    outputCount: usize,
};

pub const AudioParamValue = union {
    Float: f32,
    Int: i32,
    Enum: u32,
    Bool: bool,
};

pub const AudioParam = struct {
    value: AudioParamType,
};

pub const AudioNode = struct {
    definition: usize, // 8
    params_start: usize, // 8
    inputs_start: usize, // 8
    outputs_start: usize, // 8
};

pub const AudioContext = struct {
    definitions: []AudioNodeDefinition,

    params: []AudioParam,
    /// Index of first param that is free. A value of std.math.maxInt(usize) indicates no params are free
    param_free: usize = std.math.maxInt(usize),

    inputs: []usize,
    /// Index of first input that is free. A value of std.math.maxInt(usize) indicates no inputs are free
    input_free: usize = std.math.maxInt(usize),

    outputs: []usize,
    /// Index of first output that is free. A value of std.math.maxInt(usize) indicates no outputs are free
    output_free: usize = std.math.maxInt(usize),

    nodes: []NodeOrIndex,
    /// Index of first node that is free. A value of std.math.maxInt(usize) indicates no nodes are free
    node_free: usize = std.math.maxInt(usize),

    const NodeOrIndex = union { node: AudioNode, offset: usize };
};
