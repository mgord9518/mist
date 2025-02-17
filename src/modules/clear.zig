const std = @import("std");
const core = @import("../main.zig");

pub const exec_mode: core.ExecMode = .function;

pub const help = core.Help{
    .description = "clear the screen",
    .usage = "",
};

pub fn main(_: []const []const u8) core.Error {
    const stdout = std.io.getStdOut().writer();

    stdout.print("\x1bc", .{}) catch return .unknown_error;

    return .success;
}
