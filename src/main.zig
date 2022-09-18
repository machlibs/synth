comptime {
    _ = osc;
    _ = env;
    _ = graph;
}

pub const osc = @import("oscillators.zig");
pub const env = @import("envelopes.zig");
pub const units = @import("units.zig");
pub const graph = @import("graph.zig");
