const std = @import("std");
const core = @import("../main.zig");
const shell = @import("../shell.zig");
const parser = @import("../shell/parser.zig");
const pipe = @import("../shell/pipe.zig");
const builtin = @import("builtin");

pub const exec_mode: core.ExecMode = .function;

pub const help = core.Help{
    .description = "run a procedure",
    .usage = "<PROC>",
};

pub fn main(arguments: []const core.Argument) core.Error {
    //const stdout = std.io.getStdOut().writer();

    var stdin_file = std.io.getStdIn();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var target: ?[]const u8 = null;
    for (arguments) |arg| {
        if (arg == .option) switch (arg.option[1]) {
            //'a' => show_hidden = true,

            else => return .usage_error,
        };

        if (arg == .positional) {
            target = arg.positional;
            break;
        }
    }

    if (target == null) return .usage_error;

    const proc_data = shell.procedures.get(target.?).?;

    std.debug.print("PROC DAT {s}\n", .{proc_data});

    var fbs = std.io.fixedBufferStream(proc_data);

    var buf: [4096]u8 = undefined;

    //    var off: usize = 0;
    var line_num: usize = 0;

    while (fbs.reader().readUntilDelimiterOrEof(&buf, '\n') catch unreachable) |line| : (line_num += 1) {
        const exit_status = shell.runLine(
            allocator,
            stdin_file.reader(),
            line,
            true,
        ) catch unreachable;

        const previous_status_name = shell.statusName(exit_status.ret);
        const previous_status = shell.statusCode(exit_status.ret);

        if (previous_status_name) |err_name| {
            shell.printError(
                "{s}\n",
                0,
                exit_status.idx,
                .{err_name},
            );
        } else if (previous_status != 0) {
            shell.printError(
                "exit code: {d}\n",
                0,
                exit_status.idx,
                .{previous_status},
            );
        }
    }

    return .success;
}
