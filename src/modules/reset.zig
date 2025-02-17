const std = @import("std");
const core = @import("../main.zig");

pub const exec_mode: core.ExecMode = .function;

pub const help = core.Help{
    .description = "reset terminal control codes",
    .usage = "",
};

pub const main = core.genericMain(realMain);

fn realMain(_: []const []const u8) !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("{s}{s}{s}{s}{s}", .{
        "\x1bc",
        "\x1b(B",
        "\x1b[m",
        "\x1b[J",
        "\x1b[?25h",
    });

    return;
}
