const std = @import("std");

/// A simple memory pool. Orignally authored by MasterQ32
pub fn Pool(comptime Unit: type) type {
    return struct {
        const List = std.TailQueue(Unit);

        arena: std.heap.ArenaAllocator,
        free: List = .{},

        pub fn init(allocator: std.mem.Allocator) @This() {
            return .{ .arena = std.heap.ArenaAllocator.init(allocator) };
        }

        pub fn deinit(self: *@This()) void {
            self.arena.deinit();
        }

        pub fn new(self: *@This()) !*Unit {
            const obj = if (self.free.popFirst()) |item|
                item
            else
                try self.arena.allocator().create(List.Node);
            return &obj.data;
        }

        pub fn delete(self: *@This(), obj: *Unit) void {
            const node = @fieldParentPtr(List.Node, "data", obj);
            self.free.append(node);
        }
    };
}
