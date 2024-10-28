const std = @import("std");
const core = @import("../main.zig");
const shell = @import("../shell.zig");

pub const exec_mode: core.ExecMode = .fork;

pub const help = core.Help{
    .description = "set a variable from STDIN",
    .usage = "<VARIABLE NAME>",
};

pub fn main(arguments: []const core.Argument) core.Error {
    if (arguments.len != 1) return .usage_error;

    const name = if (arguments[0] == .positional) blk: {
        break :blk arguments[0].positional;
    } else {
        return .usage_error;
    };

    if (name.len > 255) return .no_space_left;

    // `V` for variable
    _ = std.posix.write(4, "V") catch unreachable;

    _ = std.posix.write(
        4,
        &.{@as(u8, @intCast(name.len))},
    ) catch unreachable;

    _ = std.posix.write(4, name) catch unreachable;

    var buf: [4096]u8 = undefined;
    while (true) {
        const read_amount = std.posix.read(
            std.posix.STDIN_FILENO,
            &buf,
        ) catch unreachable;

        if (read_amount == 0) break;

        _ = std.posix.write(
            4,
            buf[0..read_amount],
        ) catch unreachable;
    }

    return .success;
}
