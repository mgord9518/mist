const std = @import("std");
const core = @import("../../../main.zig");
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

        stdout.print(fg(.yellow) ++ "{s}" ++
            fg(.default) ++ ": {s}\n", .{
            k,
            mod.help.?.description,
        }) catch {};
    }

    return .success;
}
