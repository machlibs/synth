const std = @import("std");
const testing = std.testing;
const units = @import("units.zig");

const Pool = @import("pool.zig").Pool;
const Phasor = units.Phasor;
const Output = units.Output;

pub const AudioParam = struct {
    start_value: f32,
    end_value: f32,
    start_time: usize,
    end_time: usize,
};

/// Interface for defining audio sources. Add as a field to custom nodes that define an audio source.
pub const AudioSource = struct {
    /// `run` points to a user-defined function for processing audio data.
    /// This function shoud operate in real-time, meaning it should not allocate
    /// memory, perform blocking i/o, or make syscalls.
    /// - `source` - pointer to AudioSource struct. Use `@fieldParentPtr()` on
    ///   this to get the struct it is embedded inside of.
    /// - `graph` - pointer the audio graph, to get sample_rate, max block size,
    ///   etc.
    /// - `time` - current time in samples
    /// - `channel_count` - number of audio channels to output
    /// - `output` - planar buffer for audio output. This means each channel is a
    ///   contiguous block of memory
    run: *const fn (source: *AudioSource, graph: *const Graph, time: usize, channel_count: usize, output: []f32) void,
};

/// Interface for defining audio effects. Add as a field to custom nodes that define an audio effect.
pub const AudioEffect = struct {
    /// `run` points to a user-defined function for processing audio data.
    /// This function shoud operate in real-time, meaning it should not allocate
    /// memory, perform blocking i/o, or make syscalls.
    /// - `source` - pointer to AudioSource struct. Use `@fieldParentPtr()` on
    ///   this to get the struct it is embedded inside of.
    /// - `graph` - pointer the audio graph, to get sample_rate, max block size,
    ///   etc.
    /// - `time` - current time in samples
    /// - `channel_count` - number of audio channels to output
    /// - `input` - planar buffer for audio input. This means each channel is a
    ///   contiguous block of memory
    /// - `output` - planar buffer for audio output. This means each channel is a
    ///   contiguous block of memory
    run: *const fn (effect: *AudioEffect, graph: *const Graph, time: usize, channel_count: usize, input: []const f32, output: []f32) void,
};

/// Interface for defining audio sinks. Add as a field to custom nodes that define an audio sink.
pub const AudioSink = struct {
    /// `run` points to a user-defined function for processing audio data.
    /// This function shoud operate in real-time, meaning it should not allocate
    /// memory, perform blocking i/o, or make syscalls.
    /// - `source` - pointer to AudioSource struct. Use `@fieldParentPtr()` on
    ///   this to get the struct it is embedded inside of.
    /// - `graph` - pointer the audio graph, to get sample_rate, max block size,
    ///   etc.
    /// - `time` - current time in samples
    /// - `channel_count` - number of audio channels to output
    /// - `input` - planar buffer for audio input. This means each channel is a
    ///   contiguous block of memory
    run: *const fn (sink: *AudioSink, graph: *const Graph, time: usize, channel_count: usize, input: []f32) void,
};

pub const AudioNodeInput = struct {};
pub const AudioNodeOutput = struct {};

pub const AudioNode = struct {
    inputs: []AudioNodeInput,
    outputs: []AudioNodeOutput,
    params: []AudioParam,
    settings: []AudioSetting,

    channel_count: usize,
    channel_count_mode: ChannelCountMode,
    channel_interpretation: ChannelInterpretation,

    fn input(node: *AudioNode, index: usize) *AudioNodeInput {}
    fn output(node: *AudioNode, index: usize) *AudioNodeOutput {}
};

pub const AudioNodeRef = union(enum) {
    Source: *AudioSource,
    Effect: *AudioEffect,
    Sink: *AudioSink,
};

/// An interface for units
pub const Unit = struct {
    name: []const u8,
    is_output: bool = false,
    sample_rate: usize = 0,
    max_block_size: usize = 0,
    bus_ids: [16]usize = .{0} ** 16, // TODO: figure out long-term plan for multi-channel units
    inputs: usize = 0,
    inputs_connected: usize = 0,
    outputs: usize = 0,
    outputs_connected: usize = 0,
    /// For the given inputs, fill the output
    run: *const fn (*Unit, time: usize, bus: [][]const f32, output: [][]f32) void,
    /// Fields to store custom properties in
    data: [16]usize,

    pub fn reset(unit: *Unit) void {
        unit.is_idempotent = false;
        unit.is_output = false;
    }
};

pub const Graph = struct {
    /// The audio sample_rate
    sample_rate: usize,
    /// How many audio frames are processed at a time
    max_block_size: usize,
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
        /// Which channels are connected
        channel: usize,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        opt: struct {
            sample_rate: usize,
            max_block_size: usize = 128,
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
            .max_block_size = opt.max_block_size,
            .allocator = allocator,
            .unit_pool = try Pool(Unit).initCapacity(allocator, opt.unit_capacity),
            .connection = try std.ArrayList(Connection).initCapacity(allocator, opt.connection_capacity),
            .outputs = try std.ArrayList(*Unit).initCapacity(allocator, opt.max_outputs),
            .schedule = try std.ArrayList(*Unit).initCapacity(allocator, opt.unit_capacity),
            .scratch_buffer = scratch_buffer,
            .scratch_fba = std.heap.FixedBufferAllocator.init(scratch_buffer),
            .bus_buffer = try allocator.alloc(f32, opt.max_block_size * opt.bus_capacity),
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
        new_unit.max_block_size = graph.max_block_size;

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
        new_unit.max_block_size = graph.max_block_size;

        graph.modification_count +%= 1;
        graph.unit_count += 1;
        if (new_unit.is_output and graph.outputs.items.len < graph.outputs.capacity) {
            graph.outputs.appendAssumeCapacity(new_unit);
        }

        return new_unit;
    }

    /// Connect unit_output's output to unit_input's input
    pub fn connect(graph: *Graph, unit_output: *Unit, unit_input: *Unit, channel: usize) !void {
        if (unit_input == unit_output) return error.FeedbackLoop;
        try graph.connection.append(.{ .input = unit_input, .output = unit_output, .channel = channel });
        unit_input.inputs_connected += 1;
        unit_output.outputs_connected += 1;
        graph.modification_count +%= 1;
    }

    /// Disconnect unit_output's output from unit_input's input
    pub fn disconnect(graph: *Graph, unit_output: *Unit, unit_input: *Unit, channel: usize) void {
        if (unit_input == unit_output) return;
        for (graph.connection.items) |item, i| {
            if (item.output == unit_output and item.input == unit_input and item.channel == channel) {
                _ = graph.connection.swapRemove(i);
                unit_input.inputs_connected -= 1;
                unit_output.outputs_connected -= 1;
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
        var seen = std.AutoHashMap(*Unit, [16]bool).init(allocator);
        // Ensure capacity to minimize heap fragmentation
        try seen.ensureTotalCapacity(@intCast(u32, graph.unit_count));
        // Create a queue for adding search items to
        const ConnectionQueue = std.TailQueue(Channel);
        var connection_queue = ConnectionQueue{};

        var bus_count: usize = 0;

        // Start at the outputs
        for (graph.outputs.items) |out_unit| {
            var seen_res = seen.getOrPutAssumeCapacity(out_unit);
            if (!seen_res.found_existing) {
                seen_res.value_ptr.* = [_]bool{false} ** 16;
                var i: usize = 0;
                while (i < out_unit.inputs_connected) : (i += 1) {
                    var next = try allocator.create(ConnectionQueue.Node);
                    next.data = .{ .unit = out_unit, .channel = i };
                    connection_queue.append(next);
                }
            } else {
                std.log.warn("duplicate output", .{});
            }
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
            var seen_res = seen.getOrPutAssumeCapacity(unit.data.unit);
            if (seen_res.found_existing and seen_res.value_ptr.*[unit.data.channel]) {
                continue;
            } else if (!seen_res.found_existing) {
                seen_res.value_ptr.* = [_]bool{false} ** 16;
                graph.schedule.appendAssumeCapacity(unit.data.unit);
            }
            seen_res.value_ptr.*[unit.data.channel] = true;
            unit.data.unit.bus_ids[unit.data.channel] = bus_count;
            bus_count += 1;

            // Add inputs to connection queue
            var iter = graph.inputIter(unit.data.unit);
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
        const start = bus_number * graph.max_block_size;
        const end = start + graph.max_block_size;
        return graph.bus_buffer[start..end];
    }

    /// Execute the graph to generate samples.
    pub fn run(graph: *Graph, time: usize, input: [][]const f32, output: [][]f32) !void {
        _ = input;
        graph.scratch_fba.reset();
        const allocator = graph.scratch_fba.allocator();
        var output_buses = try std.ArrayList([]f32).initCapacity(allocator, 16);
        var input_buses = try std.ArrayList([]f32).initCapacity(allocator, 16);

        // Reset buffers to 0
        for (graph.bus_buffer) |*sample| {
            sample.* = 0.0;
        }

        for (graph.schedule.items) |unit| {
            const input_channels = input_channels: {
                // TODO: microphone/line in input
                var i: usize = 0;
                while (i < unit.inputs_connected) : (i += 1) {
                    const unit_bus = graph.getBus(unit.bus_ids[i]);
                    input_buses.appendAssumeCapacity(unit_bus);
                }
                break :input_channels input_buses.items;
            };

            const output_channels = output_channels: {
                if (unit.is_output) break :output_channels output;
                var out_iter = graph.outputIter(unit);
                while (out_iter.next()) |out| {
                    const output_bus = graph.getBus(out.unit.bus_ids[out.channel]);
                    output_buses.appendAssumeCapacity(output_bus);
                }
                break :output_channels output_buses.items;
            };

            unit.run(unit, time, input_channels, output_channels);
            // std.log.warn("{s} bus input ids: {any}", .{ unit.name, unit.bus_ids[0..unit.inputs_connected] });

            output_buses.shrinkRetainingCapacity(0);
            input_buses.shrinkRetainingCapacity(0);
        }
    }

    const Channel = struct { unit: *Unit, channel: usize };

    /// Struct for iterating over unit connections
    const ConnectionIter = struct {
        graph: *Graph,
        index: usize,
        unit: *Unit,
        finding: enum { Inputs, Outputs, Both },

        pub fn next(iter: *ConnectionIter) ?Channel {
            const connection = iter.graph.connection;
            switch (iter.finding) {
                .Outputs => {
                    while (iter.index < connection.items.len) {
                        defer iter.index += 1;
                        if (connection.items[iter.index].output == iter.unit) {
                            return .{
                                .unit = connection.items[iter.index].input,
                                .channel = connection.items[iter.index].channel,
                            };
                        }
                    }
                },
                .Inputs => {
                    while (iter.index < connection.items.len) {
                        defer iter.index += 1;
                        if (connection.items[iter.index].input == iter.unit) {
                            return .{
                                .unit = connection.items[iter.index].output,
                                .channel = connection.items[iter.index].channel,
                            };
                        }
                    }
                },
                .Both => {
                    while (iter.index < connection.items.len) {
                        defer iter.index += 1;
                        if (connection.items[iter.index].input == iter.unit) {
                            return .{
                                .unit = connection.items[iter.index].output,
                                .channel = connection.items[iter.index].channel,
                            };
                        } else if (connection.items[iter.index].output == iter.unit) {
                            return .{
                                .unit = connection.items[iter.index].input,
                                .channel = connection.items[iter.index].channel,
                            };
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

test "audio graph simple phasor" {
    // Create an audio context
    var graph = try Graph.init(testing.allocator, .{
        .sample_rate = 10,
        .max_block_size = 1,
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
    time += 1;

    // The buffer must be zeroed before running again
    output_block[0] = 0;
    phasor.run(phasor, time, &input_channels, &output_channels);
    try testing.expectApproxEqAbs(@as(f32, 0.2), output_channels[0][0], 0.01);
    time += 1;

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
        .max_block_size = 20,
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
        .max_block_size = 20,
    });
    defer graph.deinit();

    var phasor = try graph.add(Phasor.unit());
    var output = try graph.add(Output.unit());

    try graph.connect(phasor, output, 0);

    try testing.expectEqual(@as(usize, 1), graph.connection.items.len);

    var iter = graph.outputIter(phasor);
    try testing.expectEqual(@as(?Graph.Channel, .{ .unit = output, .channel = 0 }), iter.next());
    try testing.expectEqual(@as(?Graph.Channel, null), iter.next());

    graph.disconnect(phasor, output, 0);

    iter = graph.outputIter(phasor);
    try testing.expectEqual(@as(?Graph.Channel, null), iter.next());
}

test "audio graph removal" {
    // Create an audio context
    var graph = try Graph.init(testing.allocator, .{
        .sample_rate = 10,
        .max_block_size = 20,
    });
    defer graph.deinit();

    var phasor = try graph.add(Phasor.unit());
    var output = try graph.add(Output.unit());

    try graph.connect(phasor, output, 0);

    try testing.expectEqual(@as(usize, 1), graph.connection.items.len);

    graph.remove(output);

    try testing.expectEqual(@as(usize, 0), graph.connection.items.len);

    var iter = graph.outputIter(phasor);
    try testing.expectEqual(@as(?Graph.Channel, null), iter.next());
}

test "audio graph scheduling" {
    // Create an audio context
    var graph = try Graph.init(testing.allocator, .{
        .sample_rate = 10,
        .max_block_size = 20,
    });
    defer graph.deinit();

    var phasor = try graph.add(Phasor.unit());
    var output = try graph.add(Output.unit());

    try graph.connect(phasor, output, 0);

    try graph.reschedule();

    try testing.expectEqualSlices(*Unit, &[_]*Unit{ phasor, output }, graph.schedule.items);
}

test "audio graph run" {
    // Create an audio context
    var graph = try Graph.init(testing.allocator, .{
        .sample_rate = 10,
        .max_block_size = 20,
    });
    defer graph.deinit();

    var phasor = try graph.add(Phasor.unit());
    var output = try graph.add(Output.unit());

    Phasor.setUnitFrequency(phasor, 1);

    try graph.connect(phasor, output, 0);

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

test "audio graph run stereo" {
    // Create an audio context
    var graph = try Graph.init(testing.allocator, .{
        .sample_rate = 10,
        .max_block_size = 20,
    });
    defer graph.deinit();

    var phasor = try graph.add(Phasor.unit());
    var output = try graph.add(Output.unit());

    try graph.connect(phasor, output, 0);
    try graph.connect(phasor, output, 1);

    try graph.reschedule();

    try testing.expectEqualSlices(*Unit, &[_]*Unit{ phasor, output }, graph.schedule.items);

    var expected = [10]f32{ 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 0.0 } ** 2;
    var input_block_0 = [1]f32{0} ** 20;
    var input_block_1 = [1]f32{0} ** 20;
    var output_block_0 = [1]f32{0} ** 20;
    var output_block_1 = [1]f32{0} ** 20;
    var input_channels = [2][]f32{ &input_block_0, &input_block_1 };
    var output_channels = [2][]f32{ &output_block_0, &output_block_1 };

    try graph.run(0, &input_channels, &output_channels);

    try expectSlicesApproxEqAbs(f32, &expected, &output_block_0, 0.01);
    try expectSlicesApproxEqAbs(f32, &expected, &output_block_1, 0.01);
}
