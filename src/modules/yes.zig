const std = @import("std");
const core = @import("../main.zig");
const fg = core.fg;

pub const exec_mode: core.ExecMode = .fork;

pub const help = core.Help{
    .description = "repeat [STRING] or `y` if unspecified",
    .usage = "[STRING]",
};

pub fn main(arguments: []const core.Argument) core.Error {
    const stdout_file = std.io.getStdOut();
    const stdout = stdout_file.writer();
    var buf_writer = std.io.bufferedWriter(stdout);
    const buffered_stdout = buf_writer.writer();

    var target: ?[]const u8 = null;
    for (arguments) |arg| {
        if (arg == .option) return .usage_error;

        if (arg == .positional) {
            if (target != null) return .usage_error;

            target = arg.positional;
        }
    }

    while (true) {
        buffered_stdout.print(
            "{s}\n",
            .{target orelse "y"},
        ) catch break;
    }

    buf_writer.flush() catch unreachable;

    return .success;
}
