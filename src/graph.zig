const std = @import("std");
const testing = std.testing;

const Pool = @import("pool.zig").Pool;

const Graph = struct {
    /// The audio sample_rate
    sample_rate: usize,
    /// How many audio frames are processed at a time
    block_size: usize,
    allocator: std.mem.Allocator,
    /// Unit pool
    unit_pool: Pool(Unit),
    /// Stores how units are connected
    connection: std.ArrayList(Connection),
    /// Memory used for temporary allocations. Defaults to 4 KiB
    // scratch_buffer: []u8,
    /// Scratch allocator
    // scratch_fba: std.heap.FixedBufferAllocator,

    const Connection = struct {
        input: *Unit,
        output: *Unit,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        opt: struct {
            sample_rate: usize,
            block_size: usize,
            unit_capacity: usize = 128,
            connection_capacity: usize = 256,
            // scratch_buffer_size: usize = 1024 * 4,
        },
    ) !Graph {
        // const scratch_buffer = try allocator.alloc(u8, opt.scratch_buffer_size);
        return Graph{
            .sample_rate = opt.sample_rate,
            .block_size = opt.block_size,
            .allocator = allocator,
            .unit_pool = try Pool(Unit).initCapacity(allocator, opt.unit_capacity),
            .connection = try std.ArrayList(Connection).initCapacity(allocator, opt.connection_capacity),
            // .scratch_buffer = scratch_buffer,
            // .scratch_fba = std.heap.FixedBufferAllocator.init(scratch_buffer),
        };
    }

    pub fn deinit(graph: *Graph) void {
        graph.unit_pool.deinit();
        graph.connection.deinit();
    }

    /// Allocate a unit from the pool.
    /// WARNING: This function will allocate if there is no room in the pool. If the code is running in a real-time context, assume
    /// allocation will cause unacceptable delays.
    pub fn add(graph: *Graph, unit: Unit) !*Unit {
        var new_unit = try graph.unit_pool.new();
        new_unit.* = unit;
        new_unit.sample_rate = graph.sample_rate;
        new_unit.block_size = graph.block_size;
        return new_unit;
    }

    /// Allocate a unit from the pool if capacity already exists. If there are no free slots, returns error.OutOfMemory.
    /// Use this while running in real time contexts.
    pub fn addFromPool(graph: *Graph, unit: Unit) !*Unit {
        var new_unit = try graph.unit_pool.newFromPool();
        new_unit.* = unit;
        new_unit.sample_rate = graph.sample_rate;
        new_unit.block_size = graph.block_size;
        return new_unit;
    }

    /// Connect unit_output's output to unit_input's input
    pub fn connect(graph: *Graph, unit_output: *Unit, unit_input: *Unit) !void {
        if (unit_input == unit_output) return error.FeedbackLoop;
        try graph.connection.append(.{ .input = unit_input, .output = unit_output });
    }

    /// Removes a unit and cleans up all the connections
    pub fn remove(graph: *Graph, unit: *Unit) void {
        // graph.scratch_fba.reset();
        // var remove = std.ArrayList(usize).init(graph.scratch_fba.allocator());
        var connect_iter = graph.connectionIter(unit);
        while (connect_iter.next()) |_| {
            _ = graph.connection.swapRemove(connect_iter.index - 1);
            connect_iter.index -|= 1;
        }
        graph.unit_pool.delete(unit);
    }

    /// Struct for iterating over unit connections
    const ConnectionIter = struct {
        graph: *Graph,
        index: usize,
        unit: *Unit,
        finding: enum { Inputs, Outputs, Both },

        pub fn next(iter: *ConnectionIter) ?*Unit {
            const connection = iter.graph.connection;
            switch (iter.finding) {
                .Outputs => {
                    while (iter.index < connection.items.len) {
                        defer iter.index += 1;
                        if (connection.items[iter.index].output == iter.unit) {
                            return connection.items[iter.index].input;
                        }
                    }
                },
                .Inputs => {
                    while (iter.index < connection.items.len) {
                        defer iter.index += 1;
                        if (connection.items[iter.index].input == iter.unit) {
                            return connection.items[iter.index].output;
                        }
                    }
                },
                .Both => {
                    while (iter.index < connection.items.len) {
                        defer iter.index += 1;
                        if (connection.items[iter.index].input == iter.unit or
                            connection.items[iter.index].output == iter.unit)
                        {
                            return connection.items[iter.index].output;
                        }
                    }
                },
            }
            return null;
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

    pub fn connectionIter(graph: *Graph, unit: *Unit) ConnectionIter {
        return ConnectionIter{
            .graph = graph,
            .index = 0,
            .unit = unit,
            .finding = .Both,
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

/// A simple unit that goes from 0 to 1 every period. Useful for implementing
/// other waves.
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
                output[i] += self.phase;
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

/// Writes samples to out_buffer until it reaches the end.
const Output = struct {
    out_buffer: [][]f32,

    pub fn run(obj: *Unit, _: usize, inputs: [][]const f32, _: [][]f32) void {
        var self = @ptrCast(*Output, @alignCast(@alignOf(Output), &obj.data));
        for (self.out_buffer) |output, i| {
            for (output) |*sample, a| {
                sample.* += inputs[i][a];
            }
        }
    }

    pub fn unit(out_buffer: [][]f32) Unit {
        var obj = Unit{
            .run = run,
            .data = undefined,
        };
        var self = @ptrCast(*Output, @alignCast(@alignOf(Output), &obj.data));
        self.* = Output{ .out_buffer = out_buffer };
        return obj;
    }
};

test "audio graph simple phasor" {
    // Create an audio context
    var graph = try Graph.init(testing.allocator, .{
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

    // The buffer must be zeroed before running again
    output_block[0] = 0;
    phasor.run(phasor, time, &input_channels, &output_channels);
    try testing.expectApproxEqAbs(@as(f32, 0.2), output_channels[0][0], 0.01);

    output_block[0] = 0;
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
    var graph = try Graph.init(testing.allocator, .{
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
    var graph = try Graph.init(testing.allocator, .{
        .sample_rate = 10,
        .block_size = 20,
    });
    defer graph.deinit();

    // To create an Output unit we need a buffer to write to
    var buffer = [_]f32{0} ** 10;
    var out_buf = buffer[0..10];

    var phasor = try graph.add(Phasor.unit());
    var output = try graph.add(Output.unit(&.{out_buf}));

    try graph.connect(phasor, output);

    try testing.expectEqual(@as(usize, 1), graph.connection.items.len);

    var iter = graph.outputIter(phasor);
    try testing.expectEqual(@as(?*Unit, output), iter.next());
    try testing.expectEqual(@as(?*Unit, null), iter.next());

    graph.remove(output);
}
