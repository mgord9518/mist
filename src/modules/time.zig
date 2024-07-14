const std = @import("std");
const core = @import("../main.zig");
const time = @import("../time.zig");
const fg = core.fg;
const builtin = @import("builtin");
const usage_print = core.usage_print;
const pipe = @import("../shell/pipe.zig");
const shell = @import("../shell.zig");

pub const exec_mode: core.ExecMode = .fork;

pub const help = core.Help{
    .description = "times a program, printing results to stderr",
    .usage = usage_print("-- <PROGRAM> [PROGRAM_ARGS]"),
};

pub fn main(arguments: []const core.Argument) core.Error {
    //const stdout = std.io.getStdOut().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    if (arguments.len < 1) return .usage_error;
    if (arguments[0] == .option) return .usage_error;

    var sys_args: ?[][]const u8 = null;

    const command_name = arguments[0].positional;
    const args = if (arguments.len > 1) arguments[1..] else null;
    var command = shell.Command{ .system = .{
        .name = command_name,
    } };

    // Convert to module command if it exists
    if (core.module_list.get(command_name)) |_| {
        command = .{ .module = .{
            .name = command.system.name,
            .arguments = args orelse &.{},
        } };
    } else {
        sys_args = allocator.alloc(
            []const u8,
            arguments.len - 1,
        ) catch unreachable;

        for (arguments[1..], 0..) |_, idx| {
            switch (arguments[1..][idx]) {
                .option => |opt| {
                    sys_args.?[idx] = std.fmt.allocPrint(
                        allocator,
                        "-{c}",
                        .{opt.flag},
                    ) catch return .out_of_memory;
                },
                .positional => |str| {
                    sys_args.?[idx] = str;
                },
            }
        }

        command.system.arguments = sys_args.?;
    }

    const begin_time = time.Timestamp.nowUtc();

    const exit_status = pipe.chainCommands(
        allocator,
        &.{command},
    ) catch unreachable;
    _ = &exit_status;

    const end_time = time.Timestamp.nowUtc();

    var ndif = @as(i31, end_time.nanoseconds) - begin_time.nanoseconds;
    var dif = end_time.seconds - begin_time.seconds;
    if (ndif < 0) {
        ndif += 1_000_000_000;
        dif -= 1;
    }

    std.debug.print("{d}.{d:0>3}\n", .{
        dif,
        @as(u30, @intCast(ndif)) / 1_000_000,
    });

    if (sys_args != null) {
        for (arguments[1..], 0..) |arg, idx| {
            if (arg == .option) {
                allocator.free(sys_args.?[idx]);
            }
        }

        allocator.free(sys_args.?);
    }

    return switch (exit_status.ret) {
        .exec_failure => .command_not_found,
        else => .success,
    };
}
