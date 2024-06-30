// Simple wrapper around `StringHashMap` to automatically manage string memory

const std = @import("std");

const VariableMap = @This();

map: std.StringHashMap([]const u8),

pub fn init(allocator: std.mem.Allocator) VariableMap {
    return .{ .map = std.StringHashMap([]const u8).init(allocator) };
}

pub fn deinit(self: *VariableMap) void {
    var it = self.map.keyIterator();

    while (it.next()) |key| {
        _ = self.remove(key.*);
    }

    self.map.deinit();
}

pub fn get(self: *VariableMap, name: []const u8) ?[]const u8 {
    return self.map.get(name);
}

pub fn put(self: *VariableMap, name: []const u8, value: []const u8) !void {
    const key = if (self.map.get(name)) |s| blk: {
        self.map.allocator.free(s);

        break :blk name;
    } else try self.map.allocator.dupe(u8, name);

    // TODO TYPE
    return try self.map.put(
        key,
        try self.map.allocator.dupe(u8, value),
    );
}

pub fn remove(self: *VariableMap, name: []const u8) bool {
    const key = self.map.getKey(name) orelse return false;
    const value = self.map.get(key) orelse unreachable;

    const ret = self.map.remove(key);
    self.map.allocator.free(key);
    self.map.allocator.free(value);

    return ret;
}
