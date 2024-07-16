const std = @import("std");
const core = @import("../main.zig");
const fg = core.fg;

pub const exec_mode: core.ExecMode = .fork;

pub const help = core.Help{
    .description = "print <STRING> to STDOUT",
    .usage = "<STRING>",
};

pub fn main(arguments: []const core.Argument) core.Error {
    const stdout = std.io.getStdOut().writer();

    if (arguments.len != 1) return .usage_error;
    if (arguments[0] == .option) return .usage_error;

    stdout.print(
        "{s}\n",
        .{arguments[0].positional},
    ) catch return .unknown_error;

    return .success;
}
