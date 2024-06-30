const std = @import("std");
const core = @import("../main.zig");
const fg = core.fg;

pub const exec_mode: core.ExecMode = .fork;

pub const help = core.Help{
    .description = "repeat [" ++ fg(.cyan) ++ "STRING" ++
        fg(.default) ++ "], or `y` if unspecified",

    .usage = "[" ++ fg(.cyan) ++ "STRING" ++
        fg(.default) ++ "]",
};

pub fn main(arguments: []const core.Argument) core.Error {
    const stdout = std.io.getStdOut().writer();

    var target: ?[]const u8 = null;
    for (arguments) |arg| {
        if (arg == .option) return .usage_error;

        if (arg == .positional) {
            if (target != null) return .usage_error;

            target = arg.positional;
        }
    }

    while (true) {
        stdout.print(
            "{s}\n",
            .{target orelse "y"},
        ) catch break;
    }

    return .success;
}
