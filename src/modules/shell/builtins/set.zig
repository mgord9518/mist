const std = @import("std");
const core = @import("../../../main.zig");
const shell = @import("../../shell.zig");

pub const exec_mode: core.ExecMode = .function;

pub const help = core.Help{
    .description = "create an integer variable",
    .usage = "<VARIABLE NAME> [VALUE]",
    .options = &.{},
    .exit_codes = &.{
        .{
            .code = 2,
            .name = "usage error",
        },
        .{
            .code = 3,
            .name = "already defined",
        },
    },
};

pub fn main(arguments: []const core.Argument) u8 {
    const allocator = std.heap.page_allocator;

    if (arguments.len < 1 or arguments.len > 2) return 2;

    const name = if (arguments[0] == .positional) blk: {
        //        const s = shell.variables.getKey(
        //            arguments[0].positional,
        //        ) orelse allocator.dupe(
        //            u8,
        //            arguments[0].positional,
        //        ) catch unreachable;

        break :blk arguments[0].positional;
    } else {
        return 2;
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
            return 2;
        }
    } else "";

    shell.variables.put(
        name,
        value,
    ) catch unreachable;

    return 0;
}
