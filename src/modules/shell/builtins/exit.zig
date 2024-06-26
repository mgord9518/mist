const std = @import("std");
const core = @import("../../../main.zig");
const fg = core.fg;

pub const exec_mode: core.ExecMode = .function;

pub const help = core.Help{
    .description = "quit the shell session",
    .usage = "{0s} [" ++
        fg(.cyan) ++ "EXIT_CODE" ++
        fg(.default) ++ "]",
};

// TODO: specify exit code
pub fn main(arguments: []const core.Argument) core.Error {
    _ = arguments;

    setTerminalToNormalMode() catch return .unknown_error;

    // TODO: use exit code
    std.posix.exit(0);
}

fn setTerminalToNormalMode() !void {
    var term_info = try std.posix.tcgetattr(
        std.posix.STDIN_FILENO,
    );

    term_info.lflag.ECHO = true;
    term_info.lflag.ICANON = true;

    try std.posix.tcsetattr(
        std.posix.STDIN_FILENO,
        .NOW,
        term_info,
    );
}
