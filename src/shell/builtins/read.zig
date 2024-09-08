const std = @import("std");
const core = @import("../../main.zig");
const shell = @import("../../shell.zig");

pub const exec_mode: core.ExecMode = .fork;

pub const help = core.Help{
    .description = "read one line from STDIN, set <VAR_NAME> to it",
    .usage = "<VAR_NAME>",
};

pub fn main(arguments: []const core.Argument) core.Error {
    const stdin_file = std.io.getStdIn();
    var buf_reader = std.io.bufferedReader(stdin_file.reader());
    const buffered_stdin = buf_reader.reader();

    const varout_file = std.fs.File{ .handle = 4 };

    const varout = varout_file.writer();
    var buf_writer = std.io.bufferedWriter(varout);
    const buffered_varout = buf_writer.writer();

    if (arguments.len != 1) return .usage_error;

    const name = if (arguments[0] == .positional) blk: {
        break :blk arguments[0].positional;
    } else {
        return .usage_error;
    };

    if (name.len > 255) return .no_space_left;

    buffered_varout.print("V{c}{s}", .{
        @as(u8, @intCast(name.len)),
        name,
    }) catch return .unknown_error;

    //_ = std.posix.write(4, name) catch unreachable;

    buffered_stdin.streamUntilDelimiter(
        buffered_varout,
        '\n',
        null,
    ) catch return .unknown_error;

    buf_writer.flush() catch return .unknown_error;

    return .success;
}
