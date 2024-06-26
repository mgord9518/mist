const std = @import("std");
const core = @import("../main.zig");

pub const exec_mode: core.ExecMode = .function;

pub const help = core.Help{
    .description = "clear the screen",
    .usage = "{0s}",
    .options = &.{},
    .exit_codes = &.{},
};

pub fn main(_: []const core.Argument) u8 {
    const stdout = std.io.getStdOut().writer();

    stdout.print("\x1bc", .{}) catch {};

    return 0;
}
