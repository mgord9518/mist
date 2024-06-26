const std = @import("std");
const core = @import("../../../main.zig");
const fg = core.fg;

pub const exec_mode: core.ExecMode = .fork;

pub const help = core.Help{
    .description = "list available modules",
    .usage = "",
    .options = &.{},
    .exit_codes = &.{},
};

pub fn main(_: []const core.Argument) u8 {
    const stdout = std.io.getStdOut().writer();

    stdout.print(fg(.yellow) ++ "modules:\n", .{}) catch {};

    for (core.module_list.keys()) |k| {
        stdout.print(fg(.yellow) ++ "  {s}" ++
            fg(.default) ++ ": {s}\n", .{
            k,
            core.module_list.get(k).?.help.description,
        }) catch {};
    }

    return 0;
}
