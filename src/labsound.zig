const std = @import("std");

const Context = struct {
    id: u64,
};
const Connection = struct {
    id: u64,
};
const Pin = struct {
    id: u64,
    valid: bool,
};
const PinData = struct {
    output_index: usize,
    node_id: Node,
    setting: *AudioSetting,
    param: *AudioParam,
};
const Node = struct { id: u64, valid: bool };
const NodeData = struct {
    node: *AudioNode,
};

const NodeReverseLookup = struct {
    input_pin_map: std.AutoHashMap([]const u8, Pin),
    output_pin_map: std.AutoHashMap([]const u8, Pin),
    param_pin_map: std.AutoHashMap([]const u8, Pin),
};

pub const Provider = struct {
    audioPins: std.AutoHashMap(Pin, PinData),
    audioNodes: std.AutoHashMap(Pin, NodeData),

    pub fn createRuntimeContext(provider: *Provider, node: Node) Context {}

    // Node creation and deletion
    pub fn nodeNames(provider: *Provider) [][]const u8 {}
    pub fn nodeCreate(provider: *Provider) Node {}
    pub fn nodeDelete(provider: *Provider, node: Node) void {}

    // Node access
    pub fn nodeGetTiming(provider: *Provider, node: Node) f32 {}
    pub fn nodeGetSelfTiming(provider: *Provider, node: Node) f32 {}
    pub fn nodeStartStop(provider: *Provider, node: Node) void {}
    pub fn nodeBang(provider: *Provider, node: Node) void {}

    pub fn nodeInputWithIndex(provider: *Provider, node: Node, output: usize) Pin {}
    pub fn nodeOutputNamed(provider: *Provider, node: Node, output_name: []const u8) Pin {}
    pub fn nodeOutputWithIndex(provider: *Provider, node: Node, output: usize) Pin {}
    pub fn nodeParamNamed(provider: *Provider, node: Node, output_name: []const u8) Pin {}

    // Pins
    pub fn pinSetParamValue(provider: *Provider, node_name: []const u8, param_name: []const u8, value: f32) void {}
    pub fn pinSetSettingFloatValue(provider: *Provider, node_name: []const u8, setting_name: []const u8, value: f32) void {}
    pub fn pinSetFloatValue(provider: *Provider, pin: Pin, value: f32) void {}
    pub fn pinFloatValue(provider: *Provider, pin: Pin) f32 {}

    pub fn pinSetParamValue(provider: *Provider, node_name: []const u8, param_name: []const u8, value: i32) void {}
    pub fn pinSetSettingIntValue(provider: *Provider, node_name: []const u8, setting_name: []const u8, value: i32) void {}
    pub fn pinSetIntValue(provider: *Provider, pin: Pin, value: i32) void {}
    pub fn pinIntValue(provider: *Provider, pin: Pin) i32 {}

    pub fn pinSetParamValue(provider: *Provider, node_name: []const u8, param_name: []const u8, value: bool) void {}
    pub fn pinSetSettingBoolValue(provider: *Provider, node_name: []const u8, setting_name: []const u8, value: bool) void {}
    pub fn pinSetBoolValue(provider: *Provider, pin: Pin, value: bool) void {}
    pub fn pinBoolValue(provider: *Provider, pin: Pin) bool {}

    pub fn pinSetSettingBusValue(provider: *Provider, node_name: []const u8, setting_name: []const u8, path: []const u8) void {}
    pub fn pinSetBusFromFile(provider: *Provider, pin: Pin, path: []const u8) void {}

    pub fn pinSetSettingEnumerationValue(provider: *Provider, node_name: []const u8, setting_name: []const u8, value: []const u8) void {}
    pub fn pinSetEnumerationValue(provider: *Provider, pin: Pin, value: []const u8) void {}

    // String-based interfaces
    pub fn pinCreateOutput(provider: *Provider, node_name: []const u8, output_name: []const u8, channels: usize) void {}

    // Connections
    pub fn connectBusOutToBusIn(provider: *Provider, node_out_id: Node, output_pin_id: Pin, node_in_id: Node) void {}
    pub fn connectBusOutToParamIn(provider: *Provider, node_out_id: Node, output_pin_id: Pin, node_in_id: Node) void {}
    pub fn disconnect(provider: *Provider, connection_id: Connection) void {}
};
