const std = @import("std");

pub fn main() !void {
    return;
}

export fn _MIST_PLUGIN_1_0_MAIN(argc: usize, argv: [*][*:0]const u8, argvc: [*:0]usize) u8 {
    std.debug.print("Hello from Zig!\n", .{});

    std.debug.print("My parsed arguments are: ", .{});

    for (argv[0..argc], 0..) |arg, idx| {
        std.debug.print("{s},", .{arg[0..argvc[idx]]});
    }

    return 69;
}
