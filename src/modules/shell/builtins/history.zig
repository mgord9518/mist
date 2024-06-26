const std = @import("std");
const core = @import("../../../main.zig");
const fg = core.fg;
const shell = @import("../../shell.zig");
const posix = std.posix;

pub const exec_mode: core.ExecMode = .fork;

pub const help = core.Help{
    .description = "list previously used commands",
    .usage = "{0s}",
    .options = &.{},
    .exit_codes = &.{},
};

pub fn main(_: []const core.Argument) u8 {
    const stdout_file = std.io.getStdOut();
    const stdout = stdout_file.writer();

    if (stdout_file.isTty()) {
        for (shell.history.list.items, 0..) |item, idx| {
            stdout.print(fg(.cyan) ++ "{d} " ++ fg(.default) ++ "{s}\n", .{ idx, item }) catch return 1;
        }
    } else {
        for (shell.history.list.items, 0..) |item, idx| {
            stdout.print("{d} {s}\n", .{ idx, item }) catch return 1;
        }
    }

    return 0;
}
