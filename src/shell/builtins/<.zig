const std = @import("std");
const core = @import("../../main.zig");

pub const exec_mode: core.ExecMode = .fork;
pub const no_display = true;

pub const help = core.Help{
    .description = "write <FILE> to STDOUT",
    .usage = "<FILE>",
};

pub fn main(arguments: []const core.Argument) core.Error {
    const stdout_file = std.io.getStdOut();
    var buf_writer = std.io.bufferedWriter(stdout_file.writer());
    const buffered_stdout = buf_writer.writer();

    var buf: [4096]u8 = undefined;

    const cwd = std.fs.cwd();

    if (arguments.len != 1) return .usage_error;
    if (arguments[0] == .option) return .usage_error;

    var in_file = cwd.openFile(
        arguments[0].positional,
        .{},
    ) catch |err| {
        return switch (err) {
            error.FileNotFound => .file_not_found,
            error.AccessDenied => .access_denied,
            else => .unknown_error,
        };
    };

    var buf_reader = std.io.bufferedReader(in_file.reader());
    const buffered_in_file = buf_reader.reader();

    while (true) {
        const bytes_read = buffered_in_file.read(&buf) catch return .unknown_error;

        if (bytes_read == 0) break;

        _ = buffered_stdout.write(buf[0..bytes_read]) catch return .unknown_error;
    }

    buf_writer.flush() catch return .unknown_error;

    return .success;
}
