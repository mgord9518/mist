const std = @import("std");
const core = @import("../main.zig");
const base91 = @import("base91");

pub const exec_mode: core.ExecMode = .fork;

pub const help = core.Help{
    .description = "convert data from STDIN to base91, printing it to STDOUT",
    .usage = "[-d]",
    .options = &.{
        .{ .flag = 'd', .description = "decode" },
    },
};

pub fn main(arguments: []const core.Argument) core.Error {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const stdout_file = std.io.getStdOut();
    const stdout = stdout_file.writer();
    var buf_writer = std.io.bufferedWriter(stdout);
    const buffered_stdout = buf_writer.writer();

    const stdin = std.io.getStdIn().reader();
    var buf_reader = std.io.bufferedReader(stdin);
    const buffered_stdin = buf_reader.reader();

    var decode = false;
    var target: ?[]const u8 = null;
    for (arguments) |arg| {
        if (arg == .option) switch (arg.option[1]) {
            'd' => decode = true,

            else => return .usage_error,
        };

        if (arg == .positional) {
            target = arg.positional;
        }
    }

    const mem = 4096;

    const buf = allocator.alloc(
        u8,
        base91.standard.Encoder.calcSize(mem),
    ) catch return .unknown_error;
    defer allocator.free(buf);

    if (decode) {
        var decoder = base91.decodeStream(
            allocator,
            buffered_stdin,
            .{},
        ) catch return .unknown_error;

        while (true) {
            const bytes_read = decoder.read(buf) catch return .unknown_error;

            if (bytes_read == 0) break;

            _ = buffered_stdout.write(buf[0..bytes_read]) catch return .unknown_error;
        }
    } else {
        var encoder = base91.encodeStream(
            allocator,
            buffered_stdin,
            .{},
        ) catch return .unknown_error;

        while (true) {
            const bytes_read = encoder.read(buf) catch return .unknown_error;

            if (bytes_read == 0) break;

            _ = buffered_stdout.write(buf[0..bytes_read]) catch return .unknown_error;
        }

        if (stdout_file.isTty()) {
            _ = buffered_stdout.write("\n") catch return .unknown_error;
        }
    }

    buf_writer.flush() catch return .unknown_error;

    return .success;
}
