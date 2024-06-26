const std = @import("std");
const core = @import("../main.zig");
const fg = core.fg;

pub const exec_mode: core.ExecMode = .fork;

pub const help = core.Help{
    .description = "repeat [" ++ fg(.cyan) ++ "STRING" ++
        fg(.default) ++ "], or `yes` if unspecified",
    .usage = "{0s}",
    .options = &.{},
    .exit_codes = &.{},
};

pub fn main(arguments: []const core.Argument) u8 {
    _ = arguments;
    //const allocator = std.heap.page_allocator;
    const stdout = std.io.getStdOut().writer();

    while (true) {
        _ = stdout.write("y\n") catch break;
    }

    return 0;
}
