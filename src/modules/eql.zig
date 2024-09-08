const std = @import("std");
const core = @import("../main.zig");

pub const exec_mode: core.ExecMode = .fork;

pub const help = core.Help{
    .description = "compare values",
    .usage = "<VALUE>...",
};

// TODO numeric comparison
pub fn main(arguments: []const core.Argument) core.Error {
    var current_target: ?[]const u8 = null;
    for (arguments) |arg| {
        if (arg == .option) return .usage_error;

        if (current_target != null and !std.mem.eql(
            u8,
            arg.positional,
            current_target.?,
        )) {
            return .not_equal;
        }

        current_target = arg.positional;
    }

    return .success;
}
