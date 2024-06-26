const std = @import("std");
const core = @import("../main.zig");
const builtin = @import("builtin");

pub const exec_mode: core.ExecMode = .function;

pub const help = core.Help{
    .description = "print an environment variable to stdout",
    .usage = "{0s}",
    .options = &.{},
    .exit_codes = &.{},
};

pub fn main(arguments: []const core.Argument) core.Error {
    const stdout = std.io.getStdOut().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var target: ?[]const u8 = null;
    for (arguments) |arg| {
        if (arg == .option) switch (arg.option.flag) {
            //'a' => show_hidden = true,

            else => return .usage_error,
        };

        if (arg == .positional) {
            target = arg.positional;
            break;
        }
    }

    const v = target orelse return .unknown_error;

    // Only allocate if needed
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi) {
        const var_string = std.process.getEnvVarOwned(
            allocator,
            v,
        ) catch |err| {
            return switch (err) {
                error.EnvironmentVariableNotFound => .invalid_env_variable,
                error.OutOfMemory => .out_of_memory,

                else => .unknown_error,
            };
        };

        defer allocator.free(var_string);
        stdout.print("{s}\n", .{var_string}) catch unreachable;
    } else {
        const var_string = std.posix.getenv(
            v,
        ) orelse return .invalid_env_variable;

        stdout.print("{s}\n", .{var_string}) catch unreachable;
    }

    return .success;
}
