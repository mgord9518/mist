const std = @import("std");
const core = @import("../main.zig");
const fg = core.fg;

pub const exec_mode: core.ExecMode = .fork;
pub const no_display = true;

pub const help = core.Help{
    .description = "read STDIN into <FILE>",
    .usage = "<FILE>",
};

pub fn main(arguments: []const core.Argument) core.Error {
    const stdin_file = std.io.getStdIn();
    var buf_reader = std.io.bufferedReader(stdin_file.reader());
    const buffered_stdin = buf_reader.reader();

    var buf: [4096]u8 = undefined;

    const cwd = std.fs.cwd();

    if (arguments.len != 1) return .usage_error;
    if (arguments[0] == .option) return .usage_error;

    var out_file = cwd.createFile(
        arguments[0].positional,
        .{},
    ) catch return .unknown_error;

    var buf_writer = std.io.bufferedWriter(out_file.writer());
    const buffered_out_file = buf_writer.writer();

    while (true) {
        const bytes_read = buffered_stdin.read(&buf) catch return .unknown_error;

        if (bytes_read == 0) break;

        _ = buffered_out_file.write(buf[0..bytes_read]) catch return .unknown_error;
    }

    buf_writer.flush() catch return .unknown_error;

    return .success;
}
