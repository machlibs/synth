const std = @import("std");

const Context = struct {
    sample_rate: usize,
};

const Output = struct {
    prev: ?*Output,
    next: ?*Output,
};

const Node = struct {
    input_list: Output,
    bus_in: [][]f32, // used for mixing inputs
    bus_out: [][]f32, // where outputs is stored
    process: *const fn (*Node, Context) void,

    const NoChannel = &[0][]f32{};

    pub fn init(process: *const fn (*Node, Context) void, bus_in: [][]f32, bus_out: [][]f32) @This() {
        return @This(){
            .input_list = .{ .next = null, .prev = null },
            .bus_in = bus_in,
            .bus_out = bus_out,
            .process = process,
        };
    }

    pub fn disconnectOutput(output_node: *Node) void {
        if (output_node.input_list.prev) |prev| {
            prev.next = output_node.input_list.next;
        }
        if (output_node.input_list.next) |next| {
            next.prev = output_node.input_list.prev;
        }
    }

    /// Adds output_node to input list of input_node
    pub fn connectOutputTo(output_node: *Node, input_node: *Node) void {
        output_node.disconnectOutput();
        output_node.input_list.next = input_node.input_list.next;
        output_node.input_list.prev = &input_node.input_list;
        input_node.input_list.next = &output_node.input_list;
    }

    pub fn pull(node: *Node, ctx: Context) void {
        for (node.bus_in) |channel| {
            for (channel) |*sample| {
                sample.* = 0;
            }
        }
        var next_input = node.input_list.next;
        while (next_input) |input| {
            const input_node = @fieldParentPtr(Node, "input_list", input);
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

fn testProcess(node: *Node, _: Context) void {
    for (node.bus_in) |channel, c| {
        for (channel) |sample, s| {
            node.bus_out[c][s] = sample;
        }
    }
    return;
}

test "graph minimal" {
    const alloc = std.testing.allocator;
    const ctx = Context{ .sample_rate = 1 };

    var buffer1 = try alloc.alloc(f32, 128);
    defer alloc.free(buffer1);
    var node1 = Node.init(sineProcess, Node.NoChannel, &.{buffer1[0..128]});

    var buffer2 = try alloc.alloc(f32, 128 * 2);
    defer alloc.free(buffer2);
    var node2 = Node.init(testProcess, &.{buffer2[0..128]}, &.{buffer2[128..]});

    node1.connectOutputTo(&node2);

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
    var node3 = Node.init(cosProcess, Node.NoChannel, &.{buffer3[0..128]});

    node3.connectOutputTo(&node2);

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
