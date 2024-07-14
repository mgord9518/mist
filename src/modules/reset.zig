const std = @import("std");
const core = @import("../main.zig");

pub const exec_mode: core.ExecMode = .function;

pub const help = core.Help{
    .description = "reset terminal control codes",
    .usage = "",
};

pub fn main(_: []const core.Argument) core.Error {
    const stdout = std.io.getStdOut().writer();

    stdout.print("{s}{s}{s}{s}{s}", .{
        "\x1bc",
        "\x1b(B",
        "\x1b[m",
        "\x1b[J",
        "\x1b[?25h",
    }) catch {};

    return .success;
}
