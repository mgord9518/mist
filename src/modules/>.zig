const std = @import("std");
const core = @import("../main.zig");
const fg = core.fg;

pub const exec_mode: core.ExecMode = .fork;

pub const help = core.Help{
    .description = core.usage_print("read STDIN into <FILE>"),
    .usage = "<FILE>",
};

pub fn main(arguments: []const core.Argument) core.Error {
    const stdin = std.io.getStdIn().reader();

    var buf: [4096]u8 = undefined;

    const cwd = std.fs.cwd();

    if (arguments.len != 1) return .usage_error;
    if (arguments[0] == .option) return .usage_error;

    var out_file = cwd.createFile(
        arguments[0].positional,
        .{},
    ) catch return .unknown_error;

    while (true) {
        const bytes_read = stdin.read(&buf) catch return .unknown_error;

        if (bytes_read == 0) break;

        _ = out_file.write(buf[0..bytes_read]) catch return .unknown_error;
    }

    return .success;
}
