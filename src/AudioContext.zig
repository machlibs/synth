const std = @import("std");

pub const AudioSettingType = union(enum) {
    None,
    Bool,
    Integer,
    Float,
    Enumeration: [][]const u8,
};

/// The definition of a single parameter on an AudioNode
pub const AudioSettingDefinition = struct {
    /// The name of the setting. This should be a human-readble name. Example: "distanceModel"
    name: []const u8,
    /// The short name of the setting. This should identify the setting. Example: "DSTM"
    short_name: []const u8,
    /// The type of the AudioSetting.
    /// - Float: a 32-bit floating point number
    /// - Int: a signed 32-bit integer
    /// - Enum: a set of named constants
    /// - Bool: true or false
    type: AudioSettingType,
};

pub const AudioParamDefinition = struct {
    /// The name of the parameter. This should be a human-readable name. Example: "frequency"
    name: []const u8,
    /// The short name of the parameter. This should identify the parameter. Example: "FREQ"
    short_name: []const u8,
    ///  The unit of the parameter.
    unit: ?[]const u8 = null,
    /// The default value of the parameter. This is used if no value is explicitly set
    default: f32,
    /// The minimum value of the parameter
    minimum: f32,
    /// The maximum value of the parameter
    maximum: f32,
};

pub const AudioNodeInput = struct {
    channel_count: usize,
};

pub const AudioNodeOutput = struct {
    channel_count: usize,
};

/// Defines a specific type of audio node
pub const AudioNodeDefinition = struct {
    /// The name of the node. This should clearly describe the node
    name: []const u8,
    /// The short name of the parameter. This should clearly identify the parameter
    short_name: []const u8,
    /// Block-accurate control values
    settings: []AudioSettingDefinition,
    /// Sample-accurate control values
    params: []AudioParamDefinition,
    /// Inputs to the node. Multiple outputs can connect to one input.
    inputs: []AudioNodeInput,
    /// Outputs of the node. Outputs can be connected to multiple inputs.
    outputs: []AudioNodeOutput,
};

pub const AudioContext = struct {
    block_size: usize,

    definitions: std.ArrayList(AudioNodeDefinition),

    settings: std.ArrayList(SettingValue),
    pins: std.AutoHashMap(PinID, Pin),
    nodes: std.AutoHashMap(NodeID, Node),

    const NodeType = struct {
        id: usize,
    };

    pub const SettingValue = union {
        Bool: bool,
        Integer: i32,
        Float: f32,
        Enumeration: u32,
    };

    pub const Setting = union(AudioSettingType) {
        Bool: bool,
        Integer: i32,
        Float: f32,
        Enumeration: u32,
    };

    const NodeID = struct {
        id: usize,
    };

    pub const Node = struct {
        type_id: usize, // 8
        settings_start: usize, // 8
        inputs_start: usize, // 8
        outputs_start: usize, // 8
    };

    const PinID = struct {
        id: usize,
    };

    pub const Pin = struct {
        data: union(enum) { output: usize, setting: usize, param: usize },
        node_id: NodeID,
    };

    /// Initialize the AudioContext.
    pub fn init(allocator: std.mem.Allocator, options: struct {
        block_size: usize = 128,
    }) AudioContext {
        return AudioContext{
            .block_size = options.block_size,
            .settings = std.ArrayList(AudioNodeDefinition).init(allocator),
            .inputs = std.ArrayList(usize).init(allocator),
            .outputs = std.ArrayList(usize).init(allocator),
            .nodes = std.ArrayList(AudioNodeDefinition).init(allocator),
        };
    }

    /// Adds a node definition to the audio context. The slices for `settings`, `params`, `inputs`, and `outputs`
    /// should either be const or somewhere else in memory that will live for the same length as the AudioContext.
    /// Returns a definition id for the node definition.
    pub fn addNodeDefinition(ctx: *AudioContext, definition: AudioNodeDefinition) !NodeType {
        try ctx.definitions.append(definition);
        return ctx.definitions.len - 1;
    }

    pub fn createNode(ctx: *AudioContext, node_type: NodeType) !NodeID {
        if (node_type.id > ctx.definitions.items.len) return error.InvalidNodeType;
        const node_def = ctx.definitions.items[node_type.id];
        const settings_start = if (node_def.settings.len == 0) std.math.maxInt(usize) else ctx.definitions.items.len;
        const pin_index = ctx.pins.items.len;
    }

    pub fn setSetting(ctx: *AudioContext, node_id: NodeID, setting: usize, value: Setting) !void {
        const node = ctx.nodes.get(node_id) orelse return error.NoSuchNode;
        const node_def = ctx.definitions.items[node.type_id];
        if (setting >= node_def.settings.len) return error.NoSuchSetting;
        if (@as(AudioSettingType, value) != node_def.settings[setting].type) return error.IncorrectType;
        ctx.settings.items[node.settings_start + setting] = value;
    }

    pub fn getSetting(ctx: *AudioContext, node_id: NodeID, setting: usize) !Setting {
        const node = ctx.nodes.get(node_id) orelse return error.NoSuchNode;
        const node_def = ctx.definitions.items[node.type_id];
        if (setting >= node_def.settings.len) return error.NoSuchSetting;
        const value = ctx.settings.items[node.settings_start + setting];
        return switch (node_def.settings[setting].type) {
            .Bool => .{ .Bool = value.Bool },
            .Integer => .{ .Integer = value.Integer },
            .Float => .{ .Float = value.Float },
            .Enumeration => .{ .Enumeration = value.Enumeration },
        };
    }
};

test "AudioContext add node definition" {
    var ctx = try AudioContext.init(std.testing.allocator, .{});
    defer ctx.deinit(std.testing.allocator);

    const Oscillator = try ctx.addNodeDefinition(.{
        .name = "oscillator",
        .short_name = "OSC",
        .settings = &.{
            .{
                .name = "type",
                .short_name = "TYPE",
                .type = .{ .Enumeration = &.{
                    "None",
                    "Sine",
                    "FastSine",
                    "Square",
                    "Sawtooth",
                    "Triangle",
                    "Custom",
                } },
            },
        },
        .params = &.{
            .{
                .name = "frequency",
                .short_name = "FREQ",
                .default = 440,
                .minimum = 0,
                .maximum = 100_000,
            },
            .{
                .name = "detune",
                .short_name = "DTUN",
                .default = 0,
                .minimum = -4800,
                .maximum = 4800,
            },
            .{
                .name = "amplitude",
                .short_name = "AMPL",
                .default = 1,
                .minimum = 0,
                .maximum = 100_000,
            },
            .{
                .name = "bias",
                .short_name = "BIAS",
                .default = 0,
                .minimum = -1_000_000,
                .maximum = 100_000,
            },
        },
        .inputs = &.{},
        .outputs = &.{.{ .channel_count = 1 }},
    });

    const osc = ctx.createNode(Oscillator);
}
