const std = @import("std");
const core = @import("../../../main.zig");
const shell = @import("../../shell.zig");
const Int = std.math.big.int.Managed;

pub const exec_mode: core.ExecMode = .function;

pub const help = core.Help{
    .description = "create an integer variable",
    .usage = "[VARIABLE NAME] [VALUE]",
    .options = &.{},
    .exit_codes = &.{
        .{
            .code = 2,
            .name = "invalid character",
            .description = "",
        },
        .{
            .code = 3,
            .name = "already defined",
            .description = "",
        },
    },
};

pub fn main(arguments: []const core.Argument) u8 {
    // If an existing variable under the same name exists, ensure it's the
    // correct type
    if (shell.variables.get(arguments[0].positional)) |entry| {
        if (entry != .Int) return 3;
    }

    var i = Int.init(shell.variables.map.allocator) catch unreachable;
    i.setString(
        10,
        arguments[1].positional,
    ) catch return 2;

    shell.variables.put(
        arguments[0].positional,
        .{ .Int = i },
    ) catch unreachable;

    return 0;
}
