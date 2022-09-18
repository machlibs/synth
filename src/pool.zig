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

        /// Initialize pool with the specified `capacity`. This immediately allocates
        /// `capacity` items and adds them all to the free list.
        pub fn initCapacity(allocator: std.mem.Allocator, capacity: usize) !@This() {
            var pool = @This().init(allocator);
            var free = try pool.arena.allocator().alloc(List.Node, capacity);
            for (free) |*node| {
                pool.free.append(node);
            }
            return pool;
        }

        pub fn deinit(self: *@This()) void {
            self.arena.deinit();
        }

        /// Take an item from the pool if a slot is free. If there is no free slot, return an error.
        pub fn newFromPool(self: *@This()) !*Unit {
            const obj = if (self.free.popFirst()) |item|
                item
            else
                return error.OutOfMemory;
            return &obj.data;
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
