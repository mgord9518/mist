const std = @import("std");
const core = @import("../../main.zig");
const curses = @import("../../shell/curses.zig");
const fg = core.fg;

pub const exec_mode: core.ExecMode = .function;

pub const help = core.Help{
    .description = "quit the current shell session",
    .usage = "[EXIT_CODE]",
};

// TODO: specify exit code
pub fn main(arguments: []const core.Argument) core.Error {
    curses.setTerminalMode(.normal) catch return .unknown_error;

    if (arguments.len == 0) std.posix.exit(0);

    if (arguments.len != 1) return .usage_error;
    if (arguments[0] == .option) return .usage_error;

    const target = std.fmt.parseInt(
        u8,
        arguments[0].positional,
        10,
    ) catch 255;

    std.posix.exit(target);
}
