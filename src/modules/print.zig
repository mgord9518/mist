const std = @import("std");
const core = @import("../main.zig");
const fg = core.fg;

pub const exec_mode: core.ExecMode = .fork;

pub const help = core.Help{
    .description = "print [" ++ fg(.cyan) ++ "STRING" ++
        fg(.default) ++ "] to stdout",
    .usage = "{0s}",
    .options = &.{},
    .exit_codes = &.{},
};

const Error = enum(u8) {
    success = 0,
    unknown_error = 1,
    usage_error = 2,
    not_found = 3,
};

pub fn main(arguments: []const core.Argument) Error {
    const stdout = std.io.getStdOut().writer();

    for (arguments) |arg| {
        if (arg == .option) switch (arg.option.flag) {
            //'l' => show_hidden = true,

            else => return .usage_error,
        };

        if (arg == .positional) {
            stdout.print("{s}\n", .{arg.positional}) catch return .unknown_error;
        }

        break;
    }

    //const allocator = std.heap.page_allocator;

    return .success;
}
