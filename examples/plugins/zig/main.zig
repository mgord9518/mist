const std = @import("std");

export fn _MIST_PLUGIN_1_0_MAIN(
    arg_count: usize,
    arg_pointers: [*][*:0]const u8,
    arg_pointer_sizes: [*:0]usize,
) u8 {
    std.debug.print("Hello from Zig!\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var arguments = allocator.alloc([]const u8, arg_count) catch unreachable;
    defer allocator.free(arguments);

    for (arg_pointers[0..arg_count], 0..) |arg, idx| {
        arguments[idx] = arg[0..arg_pointer_sizes[idx]];
    }

    std.debug.print("My arguments are: ", .{});

    for (arguments) |arg| {
        std.debug.print("{s}, ", .{arg});
    }

    std.debug.print("\n", .{});

    return 0;
}
