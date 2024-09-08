const std = @import("std");
const core = @import("../main.zig");
const pipe = @import("../shell/pipe.zig");
const shell = @import("../shell.zig");

pub const exec_mode: core.ExecMode = .fork;

pub const help = core.Help{
    .description = "times a program, printing results to STDERR",
    .usage = "-- <PROGRAM> [PROGRAM_ARGS]",
};

pub fn main(arguments: []const core.Argument) core.Error {
    const stderr = std.io.getStdErr().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    if (arguments.len < 1) return .usage_error;
    if (arguments[0] == .option) return .usage_error;

    const sys_args = allocator.alloc(
        []const u8,
        arguments.len,
    ) catch unreachable;
    defer allocator.free(sys_args);

    for (arguments, 0..) |arg, idx| {
        switch (arg) {
            .option => |opt| sys_args[idx] = opt,
            .positional => |str| sys_args[idx] = str,
        }
    }

    const begin_time = std.time.nanoTimestamp();

    const exit_status = shell.runLine(
        allocator,
        sys_args[0],
        true,
    ) catch unreachable;

    const end_time = std.time.nanoTimestamp();

    const dif = end_time - begin_time;

    const rem: u30 = @intCast(@mod(dif, std.time.ns_per_s));

    stderr.print("{d}.{d:0>3}\n", .{
        @divTrunc(dif, std.time.ns_per_s),
        rem / std.time.ns_per_ms,
    }) catch unreachable;

    return switch (exit_status.ret) {
        .exec_failure => .command_not_found,
        else => .success,
    };
}
