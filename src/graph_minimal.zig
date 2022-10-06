const std = @import("std");
const lerp = @import("envelopes.zig").lerp;

const Context = struct {
    sample_rate: usize,
    time: usize,
};

const Output = struct {
    prev: ?*Output = null,
    next: ?*Output = null,
};

const Node = struct {
    /// Head of input linked list
    input_head: Output,
    /// An item in another nodes input list
    output: Output,
    parameters: []Output,
    bus_param: [][]f32,
    bus_in: [][]f32, // used for mixing inputs
    bus_out: [][]f32, // where outputs is stored
    process: *const fn (*Node, Context) void,

    const Empty = [0][]f32{};
    const NoChannel = &Empty;
    const NoParam = &Empty;

    pub fn init(process: *const fn (*Node, Context) void, parameters: []Output, bus_param: [][]f32, bus_in: [][]f32, bus_out: [][]f32) @This() {
        return @This(){
            .input_head = Output{},
            .output = Output{},
            .parameters = parameters,
            .bus_param = bus_param,
            .bus_in = bus_in,
            .bus_out = bus_out,
            .process = process,
        };
    }

    pub fn disconnectOutput(output_node: *Node) void {
        if (output_node.output.prev) |prev| {
            prev.next = output_node.output.next;
        }
        if (output_node.output.next) |next| {
            next.prev = output_node.output.prev;
        }
        output_node.output.prev = null;
        output_node.output.next = null;
    }

    /// Adds output_node to input list of input_node
    pub fn connectToParameter(output_node: *Node, input_node: *Node, param: usize) void {
        output_node.disconnectOutput();
        output_node.output.next = input_node.parameters[param].next;
        output_node.output.prev = &input_node.parameters[param];
        input_node.parameters[param].next = &output_node.output;
    }

    /// Adds output_node to input list of input_node
    pub fn connectToInput(output_node: *Node, input_node: *Node) void {
        output_node.disconnectOutput();
        output_node.output.next = input_node.input_head.next;
        output_node.output.prev = &input_node.input_head;
        input_node.input_head.next = &output_node.output;
    }

    pub fn pullParam(node: *Node, ctx: Context) void {
        if (node.bus_param.len == 0) return;
        for (node.bus_param) |channel, c| {
            for (channel) |*sample| {
                sample.* = 0;
            }
            var next_parameter = node.parameters[c].next;
            while (next_parameter) |parameter| {
                const parameter_node = @fieldParentPtr(Node, "output", parameter);
                parameter_node.pull(ctx);
                for (channel) |*sample, s| {
                    sample.* += parameter_node.bus_out[c][s];
                }
                next_parameter = parameter.next;
            }
        }
    }

    pub fn pull(node: *Node, ctx: Context) void {
        node.pullParam(ctx);
        for (node.bus_in) |channel| {
            for (channel) |*sample| {
                sample.* = 0;
            }
        }
        var next_input = node.input_head.next;
        while (next_input) |input| {
            const input_node = @fieldParentPtr(Node, "output", input);
            input_node.pull(ctx);
            for (node.bus_in) |channel, c| {
                for (channel) |*sample, s| {
                    sample.* += input_node.bus_out[c][s];
                }
            }
            next_input = input.next;
        }
        node.process(node, ctx);
    }
};

const Parameter = struct {
    node: Node,
    bus: []f32,
    value_begin: f32 = 0,
    value_end: f32 = 0,
    begin: usize = 0,
    end: usize = 0,

    fn init(bus_out: []f32) Parameter {
        var p = Parameter{
            .bus = bus_out,
            .node = Node.init(process, &.{}, Node.NoParam, Node.NoChannel, &.{bus_out}),
        };
        p.node.bus_out = &.{p.bus};
        return p;
    }

    fn getValue(parameter: *Parameter, time: usize) f32 {
        if (time >= parameter.begin and time <= parameter.end) {
            const t = @intToFloat(f32, time - parameter.begin) / @intToFloat(f32, parameter.end - parameter.begin);
            return lerp(parameter.value_begin, parameter.value_end, t);
        } else if (time < parameter.begin) {
            return parameter.value_begin;
        } else {
            return parameter.value_end;
        }
    }

    fn linearRamp(parameter: *Parameter, begin: usize, end: usize, value_begin: f32, value_end: f32) void {
        parameter.value_begin = value_begin;
        parameter.value_end = value_end;
        parameter.begin = begin;
        parameter.end = end;
    }

    fn linearRampTo(parameter: *Parameter, now: usize, then: usize, value: f32) void {
        parameter.value_begin = parameter.getValue(now);
        parameter.value_end = value;
        parameter.begin = now;
        parameter.end = then;
    }

    fn process(node: *Node, ctx: Context) void {
        const parameter = @fieldParentPtr(Parameter, "node", node);
        for (node.bus_out) |channel| {
            for (channel) |*sample, s| {
                const value = parameter.getValue(ctx.time + s);
                sample.* = value;
            }
        }
    }
};

fn cosProcess(node: *Node, _: Context) void {
    for (node.bus_out) |channel| {
        for (channel) |*sample, s| {
            sample.* = @cos(@intToFloat(f32, s));
        }
    }
}

fn sineProcess(node: *Node, _: Context) void {
    for (node.bus_out) |channel| {
        for (channel) |*sample, s| {
            sample.* = @sin(@intToFloat(f32, s));
        }
    }
}

fn copyProcess(node: *Node, _: Context) void {
    for (node.bus_in) |channel, c| {
        for (channel) |sample, s| {
            node.bus_out[c][s] = sample;
        }
    }
}

const Gain = struct {
    node: Node,
    param_list: [1]Output,
    param_bus: []f32,
    in_bus: []f32,
    out_bus: []f32,
    gain: f32,

    fn init(gain: f32, bus_param: []f32, bus_in: []f32, bus_out: []f32) Gain {
        var gain_node = Gain{
            .param_list = .{Output{ .next = null, .prev = null }},
            .param_bus = bus_param,
            .in_bus = bus_in,
            .out_bus = bus_out,
            .node = undefined,
            .gain = gain,
        };
        gain_node.node = Node.init(process, gain_node.param_list[0..], &.{gain_node.param_bus}, &.{gain_node.in_bus}, &.{gain_node.out_bus});
        return gain_node;
    }

    fn process(node: *Node, _: Context) void {
        const gain_node = @fieldParentPtr(Gain, "node", node);
        var s: usize = 0;
        while (s < node.bus_in[0].len) : (s += 1) {
            const gain = if (node.parameters[0].next != null) node.bus_param[0][s] else gain_node.gain;
            for (node.bus_in) |channel, c| {
                node.bus_out[c][s] = channel[s] * gain;
            }
        }
    }
};

test "graph minimal" {
    const alloc = std.testing.allocator;
    const ctx = Context{ .sample_rate = 1, .time = 0 };

    var buffer1 = try alloc.alloc(f32, 128);
    defer alloc.free(buffer1);
    var node1 = Node.init(sineProcess, &.{}, Node.NoParam, Node.NoChannel, &.{buffer1[0..128]});

    var buffer2 = try alloc.alloc(f32, 128 * 2);
    defer alloc.free(buffer2);
    var node2 = Node.init(copyProcess, &.{}, Node.NoParam, &.{buffer2[0..128]}, &.{buffer2[128..]});

    node1.connectToInput(&node2);

    node2.pull(ctx);

    var sineBuffer: [128]f32 = undefined;
    for (sineBuffer) |*sample, s| {
        sample.* = @sin(@intToFloat(f32, s));
    }

    for (sineBuffer) |sample, s| {
        try std.testing.expectApproxEqAbs(sample, buffer2[s], 0.01);
        try std.testing.expectApproxEqAbs(sample, buffer2[s + 128], 0.01);
    }

    node1.disconnectOutput();

    var buffer3 = try alloc.alloc(f32, 128);
    defer alloc.free(buffer3);
    var node3 = Node.init(cosProcess, &.{}, Node.NoParam, Node.NoChannel, &.{buffer3[0..128]});

    node3.connectToInput(&node2);

    node2.pull(ctx);

    var cosBuffer: [128]f32 = undefined;
    for (cosBuffer) |*sample, s| {
        sample.* = @cos(@intToFloat(f32, s));
    }

    for (cosBuffer) |sample, s| {
        try std.testing.expectApproxEqAbs(sample, buffer2[s], 0.01);
        try std.testing.expectApproxEqAbs(sample, buffer2[s + 128], 0.01);
        try std.testing.expectError(error.TestExpectedApproxEqAbs, std.testing.expectApproxEqAbs(sineBuffer[s], buffer2[s], 0.01));
    }
}

test "graph minimal parameter" {
    const alloc = std.testing.allocator;
    const ctx = Context{ .sample_rate = 1, .time = 0 };

    var buffer1 = try alloc.alloc(f32, 128);
    defer alloc.free(buffer1);
    var param1 = Parameter.init(buffer1[0..128]);

    var buffer2 = try alloc.alloc(f32, 128 * 3);
    defer alloc.free(buffer2);
    var gain1 = Gain.init(0.0, buffer2[0..128], buffer2[128 .. 128 * 2], buffer2[128 * 2 .. 128 * 3]);

    param1.node.connectToParameter(&gain1.node, 0);

    param1.linearRamp(64, 128, 0.0, 1.0);

    gain1.node.pull(ctx);

    for (buffer1) |sample, s| {
        if (s <= 64) {
            try std.testing.expectApproxEqAbs(@as(f32, 0.0), sample, 0.01);
        } else {
            const t = @intToFloat(f32, s - 64) / 64;
            try std.testing.expectApproxEqAbs(lerp(0.0, 1.0, t), sample, 0.01);
        }
    }
}
