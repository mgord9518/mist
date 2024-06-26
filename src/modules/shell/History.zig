const std = @import("std");
const History = @This();

allocator: std.mem.Allocator,
list: std.ArrayList([]const u8),
cursor: usize,

pub fn init(allocator: std.mem.Allocator) History {
    return .{
        .allocator = allocator,
        .list = std.ArrayList([]const u8).init(allocator),
        .cursor = 0,
    };
}

pub fn deinit(hist: *History) void {
    hist.list.deinit();
}

pub fn append(hist: *History, line: []const u8) !void {
    try hist.list.append(line);
}

pub fn pop(hist: *History, line: []const u8) []const u8 {
    return hist.list.pop(line);
}

pub fn last(hist: *const History) ?[]const u8 {
    if (hist.list.items.len == 0) return null;
    return hist.list.items[hist.list.items.len - 1];
}

pub fn cursorAtEnd(hist: *const History) bool {
    return hist.cursor == hist.list.items.len;
}
