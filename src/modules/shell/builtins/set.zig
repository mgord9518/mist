const std = @import("std");
const core = @import("../../../main.zig");
const shell = @import("../../shell.zig");

pub const exec_mode: core.ExecMode = .function;

pub const help = core.Help{
    .description = "create an integer variable",
    .usage = "<VARIABLE NAME> [VALUE]",
};

pub fn main(arguments: []const core.Argument) core.Error {
    const allocator = std.heap.page_allocator;

    if (arguments.len < 1 or arguments.len > 2) return .usage_error;

    const name = if (arguments[0] == .positional) blk: {
        //        const s = shell.variables.getKey(
        //            arguments[0].positional,
        //        ) orelse allocator.dupe(
        //            u8,
        //            arguments[0].positional,
        //        ) catch unreachable;

        break :blk arguments[0].positional;
    } else {
        return .usage_error;
    };

    // If an existing variable under the same name exists, ensure it's the
    // correct type
    if (shell.variables.get(name)) |entry| {
        allocator.free(entry);
    }

    const value = if (arguments.len == 2) blk: {
        if (arguments[1] == .positional) {
            //            const s = allocator.dupe(
            //                u8,
            //                arguments[1].positional,
            //            ) catch unreachable;
            //
            //            break :blk s;
            break :blk arguments[1].positional;
        } else {
            return .usage_error;
        }
    } else "";

    shell.variables.put(
        name,
        value,
    ) catch unreachable;

    return .success;
}
