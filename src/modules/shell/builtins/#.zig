// no-op for comments

const core = @import("../../../main.zig");

pub const exec_mode: core.ExecMode = .function;
pub const no_display = true;

pub fn main(_: []const core.Argument) core.Error {
    return .success;
}
