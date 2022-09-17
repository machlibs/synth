const std = @import("std");
const testing = std.testing;

const Pool = @import("pool.zig").Pool;

const Graph = struct {
    sample_rate: usize,
    block_size: usize,
    allocator: std.mem.Allocator,
    unit_pool: Pool(Unit),
    connection: std.ArrayList(Connection),

    const Connection = struct {
        input: *Unit,
        output: *Unit,
    };

    pub fn init(allocator: std.mem.Allocator, opt: struct {
        sample_rate: usize,
        block_size: usize,
    }) Graph {
        return Graph{
            .sample_rate = opt.sample_rate,
            .block_size = opt.block_size,
            .allocator = allocator,
            .unit_pool = Pool(Unit).init(allocator),
            .connection = std.ArrayList(Connection).init(allocator),
        };
    }

    pub fn deinit(graph: *Graph) void {
        graph.unit_pool.deinit();
    }

    /// Allocate a unit from the pool
    pub fn add(graph: *Graph, unit: Unit) !*Unit {
        var new_unit = try graph.unit_pool.new();
        new_unit.* = unit;
        new_unit.sample_rate = graph.sample_rate;
        new_unit.block_size = graph.block_size;
        return new_unit;
    }

    /// Connect unit_output's output to unit_input's input
    pub fn connect(graph: *Graph, unit_output: *Unit, unit_input: *Unit) !void {
        if (unit_input == unit_output) return error.FeedbackLoop;
        try graph.connection.push(.{ .input = unit_input, .output = unit_output });
    }

    const ConnectionIter = struct {
        graph: *Graph,
        index: usize,
        unit: *Unit,
        finding: enum { Inputs, Outputs },

        pub fn next(iter: *ConnectionIter) ?*Unit {
            switch (iter.finding) {
                .Inputs => {
                    while (iter.index < iter.graph.connection.items.len) {
                        defer iter.index += 1;
                        if (iter.graph.connections.items[iter.index].output == iter.unit) {
                            return iter.graph.connections.items[iter.index].input;
                        }
                    }
                },
                .Outputs => {
                    while (iter.index < iter.graph.connection.items.len) {
                        defer iter.index += 1;
                        if (iter.graph.connections.items[iter.index].input == iter.unit) {
                            return iter.graph.connections.items[iter.index].output;
                        }
                    }
                },
            }
        }
    };

    pub fn outputIter(graph: *Graph, unit: *Unit) ConnectionIter {
        return ConnectionIter{
            .graph = graph,
            .index = 0,
            .unit = unit,
            .finding = .Outputs,
        };
    }

    pub fn inputIter(graph: *Graph, unit: *Unit) ConnectionIter {
        return ConnectionIter{
            .graph = graph,
            .index = 0,
            .unit = unit,
            .finding = .Inputs,
        };
    }
};

/// An interface for units
pub const Unit = struct {
    is_output: bool = false,
    sample_rate: usize = 0,
    block_size: usize = 0,
    /// For the given input, fill output
    run: *const fn (*Unit, time: usize, input: [][]const f32, output: [][]f32) void,
    /// Fields to store custom properties in
    data: [16]usize,

    pub fn reset(unit: *Unit) void {
        unit.is_idempotent = false;
        unit.is_output = false;
    }
};

const Phasor = struct {
    frequency: f32 = 1,
    phase: f32 = 0,

    pub fn run(obj: *Unit, _: usize, _: [][]const f32, outputs: [][]f32) void {
        var self = @ptrCast(*Phasor, @alignCast(@alignOf(Phasor), &obj.data));
        const phase_increase = self.frequency / @intToFloat(f32, obj.sample_rate);
        var i: usize = 0;
        while (i < obj.block_size) : (i += 1) {
            self.phase += phase_increase;
            if (self.phase >= 1.0) self.phase = 0;
            for (outputs) |output| {
                output[i] = self.phase;
            }
        }
    }

    pub fn unit() Unit {
        var obj = Unit{
            .run = run,
            .data = undefined,
        };
        var self = @ptrCast(*Phasor, @alignCast(@alignOf(Phasor), &obj.data));
        self.* = Phasor{};
        return obj;
    }
};

test "audio graph simple phasor" {
    // Create an audio context
    var graph = Graph.init(testing.allocator, .{
        .sample_rate = 10,
        .block_size = 1,
    });
    defer graph.deinit();

    var phasor = try graph.add(Phasor.unit());
    var time: usize = 0;
    var input_block = [1]f32{0};
    var output_block = [1]f32{0};
    var input_channels = [1][]f32{&input_block};
    var output_channels = [1][]f32{&output_block};

    phasor.run(phasor, time, &input_channels, &output_channels);
    try testing.expectApproxEqAbs(@as(f32, 0.1), output_channels[0][0], 0.01);
    phasor.run(phasor, time, &input_channels, &output_channels);
    try testing.expectApproxEqAbs(@as(f32, 0.2), output_channels[0][0], 0.01);
    phasor.run(phasor, time, &input_channels, &output_channels);
    try testing.expectApproxEqAbs(@as(f32, 0.3), output_channels[0][0], 0.01);
}

/// Tests that two slices are approximately equal. Tolerance is checked per sample.
fn expectSlicesApproxEqAbs(comptime T: type, expected: []T, actual: []T, tolerance: T) !void {
    if (expected.len != actual.len) {
        std.debug.print("slice lengths differ. expected {d}, found {d}\n", .{ expected.len, actual.len });
        return error.TestExpectedEqual;
    }
    for (expected) |_, i| {
        if (!std.math.approxEqAbs(T, expected[i], actual[i], tolerance)) {
            std.debug.print("index {} incorrect. expected {any}, found {any}\n", .{ i, expected[i], actual[i] });
            return error.TextExpectedEqual;
        }
    }
}

test "audio graph phasor" {
    // Create an audio context
    var graph = Graph.init(testing.allocator, .{
        .sample_rate = 10,
        .block_size = 20,
    });
    defer graph.deinit();

    var phasor = try graph.add(Phasor.unit());
    var time: usize = 0;
    var input_block = [1]f32{0} ** 20;
    var output_block = [1]f32{0} ** 20;
    var input_channels = [1][]f32{&input_block};
    var output_channels = [1][]f32{&output_block};

    var expected = [10]f32{ 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 0.0 } ** 2;

    phasor.run(phasor, time, &input_channels, &output_channels);
    try expectSlicesApproxEqAbs(f32, &expected, output_channels[0], 0.01);
}

test "audio graph connections" {
    // Create an audio context
    var graph = Graph.init(testing.allocator, .{
        .sample_rate = 10,
        .block_size = 20,
    });
    defer graph.deinit();

    var phasor = try graph.add(Phasor.unit());
    var output = try graph.add(Unit{});

    try graph.connect(phasor, output);

    try testing.expectEqual(@as(usize, 1), graph.connection.items.len);
}
