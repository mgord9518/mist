const std = @import("std");
const core = @import("../main.zig");

pub const exec_mode: core.ExecMode = .function;

pub const help = core.Help{
    .description = "clear the screen",
    .usage = "{0s}",
};

pub fn main(_: []const core.Argument) core.Error {
    const stdout = std.io.getStdOut().writer();

    stdout.print("\x1bc", .{}) catch {};

    return .success;
}
