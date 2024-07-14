const std = @import("std");
const core = @import("../../main.zig");
const fg = core.fg;
const shell = @import("../../shell.zig");
const posix = std.posix;

pub const exec_mode: core.ExecMode = .fork;

pub const help = core.Help{
    .description = "list previously used commands",
    .usage = "{0s}",
};

pub fn main(_: []const core.Argument) core.Error {
    const stdout_file = std.io.getStdOut();
    const stdout = stdout_file.writer();

    if (stdout_file.isTty()) {
        for (shell.history.list.items, 0..) |item, idx| {
            stdout.print(
                fg(.cyan) ++ "{d} " ++
                    fg(.default) ++ "{s}\n",
                .{ idx, item },
            ) catch return .unknown_error;
        }
    } else {
        for (shell.history.list.items, 0..) |item, idx| {
            stdout.print(
                "{d} {s}\n",
                .{ idx, item },
            ) catch return .unknown_error;
        }
    }

    return .success;
}
