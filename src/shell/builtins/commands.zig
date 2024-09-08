const std = @import("std");
const core = @import("../../main.zig");
const fg = core.fg;

pub const exec_mode: core.ExecMode = .fork;

pub const help = core.Help{
    .description = "list available modules",
    .usage = "",
};

pub fn main(_: []const core.Argument) core.Error {
    const stdout = std.io.getStdOut().writer();

    for (core.module_list.keys()) |k| {
        const mod = core.module_list.get(k) orelse unreachable;

        if (mod.no_display) continue;

        //stdout.print(core.colors.module ++ "{s:>8}" ++
        stdout.print(core.colors.module ++ "{s}" ++
            fg(.default) ++ ": \n  ", .{
            k,
            //mod.help.?.description,
        }) catch {};

        core.usagePrint(stdout, mod.help.?.description) catch {};

        stdout.print("\n\n", .{}) catch {};
    }

    return .success;
}
