const std = @import("std");

pub const AudioSettingType = enum {
    Bool,
    Integer,
    Float,
    Enumeration,
};

pub const AudioSettingValue = union {
    Bool: bool,
    Integer: i32,
    Float: f32,
    Enumeration: u32,
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
    type: union(AudioSettingType) {
        Bool,
        Integer,
        Float,
        Enumeration: []const []const u8,
    },
    /// The default value of the audio setting. This should match the type
    /// of the setting.
    default: AudioSettingValue,
};

pub const AudioParamDefinition = struct {
    /// The name of the parameter. This should be a human-readable name. Example: "frequency"
    name: []const u8,
    /// The short name of the parameter. This should identify the parameter. Example: "FREQ"
    short_name: []const u8,
    /// The default value of the parameter. This is used if no value is explicitly set
    default: f32,
    /// The minimum value of the parameter
    minimum: f32,
    /// The maximum value of the parameter
    maximum: f32,
};

pub const SpeakerChannelLayout = enum(usize) {
    /// One channel
    Mono = 1,
    /// Two channels, Left and Right
    Stereo = 2,
    /// Four channels, Left, Right, Back Left, Back Right
    Quad = 4,
    /// Six channels, Left, Right, Front Center, Low Frequency, Back Left, Back Right
    Surround5_1 = 6,
};

pub const ChannelInterpretation = enum {
    Speakers,
    Discrete,
};

pub const ChannelCount = union(enum) {
    /// Use the largest channel count connected
    Max,
    /// Use a specific channel count
    Explicit: usize,
    /// Use the largest channel count, with a defined upper bound
    ClampedMax: usize,
};

pub const AudioChannelDefinition = struct {
    interpretation: ChannelInterpretation,
    channel_count: ChannelCount,
};

pub const AudioProcessInputs = struct {
    time: u64,
    sample_rate: u64,
    settings: []const AudioSettingValue,
    params: []const []const f32,
    signal: []const []const f32,
};

pub const AudioProcessOutput = struct {
    signal: [][]f32,
};

/// Defines a specific type of audio node
pub const AudioNodeDefinition = struct {
    process: *const fn (AudioProcessInputs, AudioProcessOutput) void,
    /// The name of the node. This should clearly describe the node
    name: []const u8,
    /// The short name of the parameter. This should clearly identify the parameter
    short_name: []const u8,
    /// Block-accurate control values
    settings: []const AudioSettingDefinition,
    /// Sample-accurate control values
    params: []const AudioParamDefinition,
    /// How the node interprets input channels.
    input: AudioChannelDefinition,
    /// How the node decides on output channels
    output: AudioChannelDefinition,
};

pub const AudioContext = struct {
    block_size: usize,
    node_count: usize = 0,
    current_time: usize = 0,
    definitions: std.ArrayList(AudioNodeDefinition),
    pins: std.AutoHashMap(PinID, Pin),
    nodes: std.AutoHashMap(NodeID, Node),
    auto_nodes: std.ArrayList(NodeID),

    const NodeType = struct {
        id: usize,
    };

    const NodeID = struct {
        id: usize,
    };

    pub const Node = struct {
        type_id: usize, // 8
    };

    const PinID = struct {
        node_id: usize,
        pin: usize,
    };

    pub const Pin = union(enum) {
        setting: AudioSettingValue,
        param: usize,
    };

    /// Initialize the AudioContext.
    pub fn init(allocator: std.mem.Allocator, options: struct {
        block_size: usize = 128,
    }) AudioContext {
        return AudioContext{
            .block_size = options.block_size,
            .definitions = std.ArrayList(AudioNodeDefinition).init(allocator),
            .pins = std.AutoHashMap(PinID, Pin).init(allocator),
            .nodes = std.AutoHashMap(NodeID, Node).init(allocator),
            .auto_nodes = std.ArrayList(PinID).init(allocator),
        };
    }

    /// Deinitialize the AudioContext. This frees the list of definitions and the pin and node hashmaps.
    pub fn deinit(ctx: *AudioContext) void {
        ctx.definitions.deinit();
        ctx.pins.deinit();
        ctx.nodes.deinit();
    }

    const AudioInput = struct {
        sample_rate: usize,
        channels: [][]const f32,
    };

    const AudioOutput = struct {
        channels: [][]f32,
    };

    pub fn process(ctx: *AudioContext, input: AudioInput, output: AudioOutput) void {
        for (ctx.auto_nodes.items) |auto_node| {
            // TODO: do a breadth first search
        }
    }

    /// Adds a node definition to the audio context. The slices for `settings`, `params`, `inputs`, and `outputs`
    /// should either be const or somewhere else in memory that will live for the same length as the AudioContext.
    /// Returns a definition id for the node definition.
    pub fn addNodeDefinition(ctx: *AudioContext, definition: AudioNodeDefinition) !NodeType {
        try ctx.definitions.append(definition);
        return .{ .id = ctx.definitions.items.len - 1 };
    }

    /// Create a node based on a previously defined NodeType.
    pub fn createNode(ctx: *AudioContext, node_type: NodeType) !NodeID {
        if (node_type.id > ctx.definitions.items.len) return error.InvalidNodeType;
        const node_def = ctx.definitions.items[node_type.id];
        const node_index = ctx.node_count;
        ctx.node_count += 1;
        for (node_def.settings) |setting, i| {
            try ctx.pins.put(
                PinID{ .node_id = node_index, .pin = i },
                Pin{ .setting = setting.default },
            );
        }
        const node_id = NodeID{ .id = node_index };
        try ctx.nodes.put(node_id, Node{
            .type_id = node_type.id,
        });
        return node_id;
    }

    pub fn setSetting(ctx: *AudioContext, node_id: NodeID, setting: usize, value: AudioSettingValue) !void {
        const node = ctx.nodes.get(node_id) orelse return error.NoSuchNode;
        const node_def = ctx.definitions.items[node.type_id];
        if (setting >= node_def.settings.len) return error.NoSuchSetting;
        if (@as(AudioSettingType, value) != node_def.settings[setting].type) return error.IncorrectType;
        ctx.settings.items[node.settings_start + setting] = value;
    }

    pub fn setEnumByName(ctx: *AudioContext, node_id: NodeID, setting: usize, tag: []const u8) !void {
        const node = ctx.nodes.get(node_id) orelse return error.NoSuchNode;
        const node_def = ctx.definitions.items[node.type_id];
        if (setting >= node_def.settings.len) return error.NoSuchSetting;
        if (node_def.settings[setting].type != .Enumeration) return error.IncorrectType;
        for (node_def.settings[setting].type.Enumeration) |enum_tag, i| {
            if (std.mem.eql(u8, enum_tag, tag)) {
                const pin = ctx.pins.getPtr(.{ .node_id = node_id.id, .pin = setting }) orelse return error.NoSuchPin;
                pin.*.setting.Enumeration = @intCast(u32, i);
                return;
            }
        }
        return error.UnknownEnumeration;
    }

    pub fn getSetting(ctx: *AudioContext, node_id: NodeID, setting: usize) ?AudioSettingValue {
        const node = ctx.nodes.get(node_id) orelse return null;
        const node_def = ctx.definitions.items[node.type_id];
        if (setting >= node_def.settings.len) return null;
        const pin = ctx.pins.getPtr(.{ .node_id = node_id.id, .pin = setting }) orelse return null;
        switch (pin.*) {
            .setting => |set| return set,
            else => return null,
        }
    }
};

fn oscillator_process(inputs: AudioProcessInputs, output: AudioProcessOutput) void {
    const waveform = inputs.settings[0].Enumeration;
    const sample_rate = @intToFloat(f32, inputs.sample_rate);
    for (output.signal) |channel| {
        for (channel) |*sample, i| {
            sample.* = switch (waveform) {
                1 => sine: {
                    // TODO: bias and detune
                    const time = @intToFloat(f32, inputs.time + i);
                    const frequency = inputs.params[0][i];
                    const gain = inputs.params[2][i];
                    break :sine std.math.sin(frequency * 2.0 * std.math.pi * time / sample_rate) * gain;
                },
                else => 0,
            };
        }
    }
}

test "AudioContext add node definition" {
    var ctx = AudioContext.init(std.testing.allocator, .{});
    defer ctx.deinit();

    const Oscillator = try ctx.addNodeDefinition(.{
        .process = oscillator_process,
        .name = "oscillator",
        .short_name = "OSC",
        .settings = &[_]AudioSettingDefinition{
            .{
                .name = "type",
                .short_name = "TYPE",
                .type = .{ .Enumeration = &[_][]const u8{
                    "None",
                    "Sine",
                    "FastSine",
                    "Square",
                    "Sawtooth",
                    "Triangle",
                    "Custom",
                } },
                .default = .{ .Enumeration = 0 },
            },
        },
        .params = &[_]AudioParamDefinition{
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

    const osc = try ctx.createNode(Oscillator);
    try ctx.setEnumByName(osc, 0, "Sine");
    const enum_value = ctx.getSetting(osc, 0) orelse return error.MissingSetting;
    try std.testing.expectEqual(.{ .Enumeration = 1 }, enum_value);
}
