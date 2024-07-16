const std = @import("std");
const core = @import("../main.zig");

pub const exec_mode: core.ExecMode = .function;

pub const help = core.Help{
    .description = "do nothing, return successful",
    .usage = "",
};

pub fn main(_: []const core.Argument) core.Error {
    return .success;
}
