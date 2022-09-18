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
    /// How many units are allocated
    unit_count: usize = 0,
    /// Stores how units are connected
    connection: std.ArrayList(Connection),
    /// Stores all output units, used for determining the schedule
    outputs: std.ArrayList(*Unit),
    /// Schedule for running units
    schedule: std.ArrayList(*Unit),
    /// Last time the graph ran the scheduling algorithm, in terms of modification count
    last_scheduled: usize = 0,
    /// The number of modifications to the graph
    modification_count: usize = 0,
    /// If an invalid configuration is detected, this flag is set and no
    /// processing will be occur until the graph is configured correctly.
    invalid_graph: bool = false, // TODO: detect errors
    /// Memory used for temporary allocations. Defaults to 4 KiB
    scratch_buffer: []u8,
    /// Scratch allocator
    scratch_fba: std.heap.FixedBufferAllocator,
    bus_buffer: []f32,

    const Connection = struct {
        /// The unit generating a signal
        input: *Unit,
        /// The unit reading the signal
        output: *Unit,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        opt: struct {
            sample_rate: usize,
            block_size: usize = 128,
            unit_capacity: usize = 128,
            connection_capacity: usize = 256,
            max_outputs: usize = 16,
            scratch_buffer_size: usize = 1024 * 4,
            bus_capacity: usize = 64,
        },
    ) !Graph {
        const scratch_buffer = try allocator.alloc(u8, opt.scratch_buffer_size);
        return Graph{
            .sample_rate = opt.sample_rate,
            .block_size = opt.block_size,
            .allocator = allocator,
            .unit_pool = try Pool(Unit).initCapacity(allocator, opt.unit_capacity),
            .connection = try std.ArrayList(Connection).initCapacity(allocator, opt.connection_capacity),
            .outputs = try std.ArrayList(*Unit).initCapacity(allocator, opt.max_outputs),
            .schedule = try std.ArrayList(*Unit).initCapacity(allocator, opt.unit_capacity),
            .scratch_buffer = scratch_buffer,
            .scratch_fba = std.heap.FixedBufferAllocator.init(scratch_buffer),
            .bus_buffer = try allocator.alloc(f32, opt.block_size * opt.bus_capacity),
        };
    }

    pub fn deinit(graph: *Graph) void {
        graph.connection.deinit();
        graph.outputs.deinit();
        graph.unit_pool.deinit();
        graph.schedule.deinit();
        graph.allocator.free(graph.scratch_buffer);
        graph.allocator.free(graph.bus_buffer);
    }

    /// Allocate a unit from the pool.
    /// WARNING: This function will allocate if there is no room in the pool. If the code is running in a real-time context, assume
    /// allocation will cause unacceptable delays.
    pub fn add(graph: *Graph, unit: Unit) !*Unit {
        var new_unit = try graph.unit_pool.new();
        new_unit.* = unit;
        new_unit.sample_rate = graph.sample_rate;
        new_unit.block_size = graph.block_size;

        graph.modification_count +%= 1;
        graph.unit_count += 1;
        if (new_unit.is_output and graph.outputs.items.len < graph.outputs.capacity) {
            // TODO: Consider finding all outputs every time a modification occurs?
            graph.outputs.appendAssumeCapacity(new_unit);
        }

        return new_unit;
    }

    /// Allocate a unit from the pool if capacity already exists. If there are no free slots, returns error.OutOfMemory.
    /// Use this while running in real time contexts.
    pub fn addFromPool(graph: *Graph, unit: Unit) !*Unit {
        var new_unit = try graph.unit_pool.newFromPool();
        new_unit.* = unit;
        new_unit.sample_rate = graph.sample_rate;
        new_unit.block_size = graph.block_size;

        graph.modification_count +%= 1;
        graph.unit_count += 1;
        if (new_unit.is_output and graph.outputs.items.len < graph.outputs.capacity) {
            graph.outputs.appendAssumeCapacity(new_unit);
        }

        return new_unit;
    }

    /// Connect unit_output's output to unit_input's input
    pub fn connect(graph: *Graph, unit_output: *Unit, unit_input: *Unit) !void {
        if (unit_input == unit_output) return error.FeedbackLoop;
        try graph.connection.append(.{ .input = unit_input, .output = unit_output });
        graph.modification_count +%= 1;
    }

    /// Disconnect unit_output's output from unit_input's input
    pub fn disconnect(graph: *Graph, unit_output: *Unit, unit_input: *Unit) void {
        if (unit_input == unit_output) return;
        for (graph.connection.items) |item, i| {
            if (item.output == unit_output and item.input == unit_input) {
                _ = graph.connection.swapRemove(i);
                graph.modification_count +%= 1;
                return;
            }
        }
    }

    /// Removes a unit and cleans up all the connections
    pub fn remove(graph: *Graph, unit: *Unit) void {
        var connect_iter = graph.connectionIter(unit);
        while (connect_iter.next()) |_| {
            _ = graph.connection.swapRemove(connect_iter.index - 1);
            connect_iter.index -|= 1;
        }
        graph.unit_pool.delete(unit);
        graph.modification_count +%= 1;
        graph.unit_count -|= 1;
    }

    /// If the graph has been modified, generate a new schedule for the units
    pub fn reschedule(graph: *Graph) !void {
        graph.scratch_fba.reset();
        graph.schedule.shrinkRetainingCapacity(0);
        const allocator = graph.scratch_fba.allocator();

        // Skip rescheduling if the graph has not been modified
        if (graph.last_scheduled == graph.modification_count) return;

        // Create a hash map to store what items have already been seen
        var seen = std.AutoHashMap(*Unit, usize).init(allocator);
        // Ensure capacity to minimize heap fragmentation
        try seen.ensureTotalCapacity(@intCast(u32, graph.unit_count));
        // Create a queue for adding search items to
        const ConnectionQueue = std.TailQueue(*Unit);
        var connection_queue = ConnectionQueue{};

        // Start at the outputs
        for (graph.outputs.items) |out_unit| {
            seen.putAssumeCapacity(out_unit, 1);
            out_unit.bus_id = graph.schedule.items.len;
            graph.schedule.appendAssumeCapacity(out_unit);

            // Add inputs to connection queue
            var iter = graph.inputIter(out_unit);
            while (iter.next()) |input| {
                var next = try allocator.create(ConnectionQueue.Node);
                next.data = input;
                connection_queue.append(next);
            }
        }

        // Perform a breadth first search
        while (connection_queue.pop()) |unit| {
            if (seen.get(unit.data)) |_| {
                continue;
            }
            seen.putAssumeCapacity(unit.data, 1);
            unit.data.bus_id = graph.schedule.items.len;
            graph.schedule.appendAssumeCapacity(unit.data);

            // Add inputs to connection queue
            var iter = graph.inputIter(unit.data);
            while (iter.next()) |input| {
                var next = try allocator.create(ConnectionQueue.Node);
                next.data = input;
                connection_queue.append(next);
            }
        }

        std.mem.reverse(*Unit, graph.schedule.items);

        graph.last_scheduled = graph.modification_count;
    }

    pub fn getBus(graph: *Graph, bus_number: usize) []f32 {
        const start = bus_number * graph.block_size;
        const end = start + graph.block_size;
        return graph.bus_buffer[start..end];
    }

    /// Execute the graph to generate samples.
    pub fn run(graph: *Graph, time: usize, input: [][]const f32, output: [][]f32) !void {
        _ = input;
        graph.scratch_fba.reset();
        const allocator = graph.scratch_fba.allocator();
        var output_buses = try std.ArrayList([]f32).initCapacity(allocator, 16);

        // Reset buffers to 0
        for (graph.bus_buffer) |*sample| {
            sample.* = 0.0;
        }

        for (graph.schedule.items) |unit| {
            const unit_bus = graph.getBus(unit.bus_id);

            const output_channels = output_channels: {
                if (unit.is_output) break :output_channels output;
                var out_iter = graph.outputIter(unit);
                while (out_iter.next()) |out| {
                    const output_bus = graph.getBus(out.bus_id);
                    output_buses.appendAssumeCapacity(output_bus);
                }
                break :output_channels output_buses.items;
            };

            unit.run(unit, time, &.{unit_bus}, output_channels);

            output_buses.shrinkRetainingCapacity(0);
        }
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
    bus_id: usize = 0,
    /// For the given input, fill output
    run: *const fn (*Unit, time: usize, bus: [][]const f32, output: [][]f32) void,
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

const Output = struct {
    pub fn run(_: *Unit, _: usize, bus: [][]const f32, outputs: [][]f32) void {
        for (outputs) |output, i| {
            for (output) |*sample, a| {
                sample.* += bus[i][a];
            }
        }
    }

    pub fn unit() Unit {
        var obj = Unit{
            .run = run,
            .data = undefined,
            .is_output = true,
        };
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

test "audio graph connect/disconnect" {
    // Create an audio context
    var graph = try Graph.init(testing.allocator, .{
        .sample_rate = 10,
        .block_size = 20,
    });
    defer graph.deinit();

    var phasor = try graph.add(Phasor.unit());
    var output = try graph.add(Output.unit());

    try graph.connect(phasor, output);

    try testing.expectEqual(@as(usize, 1), graph.connection.items.len);

    var iter = graph.outputIter(phasor);
    try testing.expectEqual(@as(?*Unit, output), iter.next());
    try testing.expectEqual(@as(?*Unit, null), iter.next());

    graph.disconnect(phasor, output);

    iter = graph.outputIter(phasor);
    try testing.expectEqual(@as(?*Unit, null), iter.next());
}

test "audio graph removal" {
    // Create an audio context
    var graph = try Graph.init(testing.allocator, .{
        .sample_rate = 10,
        .block_size = 20,
    });
    defer graph.deinit();

    var phasor = try graph.add(Phasor.unit());
    var output = try graph.add(Output.unit());

    try graph.connect(phasor, output);

    try testing.expectEqual(@as(usize, 1), graph.connection.items.len);

    graph.remove(output);

    try testing.expectEqual(@as(usize, 0), graph.connection.items.len);

    var iter = graph.outputIter(phasor);
    try testing.expectEqual(@as(?*Unit, null), iter.next());
}

test "audio graph scheduling" {
    // Create an audio context
    var graph = try Graph.init(testing.allocator, .{
        .sample_rate = 10,
        .block_size = 20,
    });
    defer graph.deinit();

    var phasor = try graph.add(Phasor.unit());
    var output = try graph.add(Output.unit());

    try graph.connect(phasor, output);

    try graph.reschedule();

    try testing.expectEqualSlices(*Unit, &[_]*Unit{ phasor, output }, graph.schedule.items);
}

test "audio graph running" {
    // Create an audio context
    var graph = try Graph.init(testing.allocator, .{
        .sample_rate = 10,
        .block_size = 20,
    });
    defer graph.deinit();

    var phasor = try graph.add(Phasor.unit());
    var output = try graph.add(Output.unit());

    try graph.connect(phasor, output);

    try graph.reschedule();

    try testing.expectEqualSlices(*Unit, &[_]*Unit{ phasor, output }, graph.schedule.items);

    var expected = [10]f32{ 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 0.0 } ** 2;
    var input_block = [1]f32{0} ** 20;
    var output_block = [1]f32{0} ** 20;
    var input_channels = [1][]f32{&input_block};
    var output_channels = [1][]f32{&output_block};

    try graph.run(0, &input_channels, &output_channels);

    try expectSlicesApproxEqAbs(f32, &expected, &output_block, 0.01);
}
