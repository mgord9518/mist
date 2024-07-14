const std = @import("std");
const core = @import("../../main.zig");
const shell = @import("../../shell.zig");

pub const exec_mode: core.ExecMode = .function;

pub const help = core.Help{
    .description = "un-define a variable",
    .usage = "<VARIABLE NAME>",
};

pub fn main(arguments: []const core.Argument) core.Error {
    if (arguments.len < 1) return .usage_error;

    const name = if (arguments[0] == .positional) blk: {
        break :blk arguments[0].positional;
    } else {
        return .usage_error;
    };

    const was_present = shell.variables.remove(
        name,
    );

    if (!was_present) {
        return .invalid_variable;
    }

    return .success;
}
