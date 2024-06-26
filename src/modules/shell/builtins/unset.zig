const std = @import("std");
const core = @import("../../../main.zig");
const shell = @import("../../shell.zig");

pub const exec_mode: core.ExecMode = .function;

pub const help = core.Help{
    .description = "un-define a variable",
    .usage = "<VARIABLE NAME>",
    .options = &.{},
    .exit_codes = &.{
        .{
            .code = 2,
            .name = "usage error",
        },
    },
};

pub fn main(arguments: []const core.Argument) u8 {
    if (arguments.len < 1) return 2;

    const name = if (arguments[0] == .positional) blk: {
        break :blk arguments[0].positional;
    } else {
        return 2;
    };

    _ = shell.variables.remove(
        name,
    );

    return 0;
}
