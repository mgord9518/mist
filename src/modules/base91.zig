const std = @import("std");
const core = @import("../main.zig");
const fg = core.fg;
const base91 = @import("base91");

pub const exec_mode: core.ExecMode = .fork;

pub const help = core.Help{
    .description = core.usage_print("convert data from STDIN to base91, printing it to STDOUT"),
    .usage = "[-d]",
};

pub fn main(arguments: []const core.Argument) core.Error {
    const allocator = std.heap.page_allocator;

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
        if (arg == .option) switch (arg.option.flag) {
            'd' => decode = true,

            else => return .usage_error,
        };

        if (arg == .positional) {
            target = arg.positional;
        }
    }

    const mem = 4096;

    if (decode) {
        const buf = allocator.alloc(
            u8,
            mem,
        ) catch return .unknown_error;
        defer allocator.free(buf);

        var decoder = base91.decodeStream(
            allocator,
            buffered_stdin,
            .{
                .buf_size = base91.standard.Decoder.calcSize(mem),
            },
        ) catch return .unknown_error;

        while (true) {
            const bytes_read = decoder.read(buf) catch return .unknown_error;

            if (bytes_read == 0) break;

            _ = buffered_stdout.write(buf[0..bytes_read]) catch return .unknown_error;
        }
    } else {
        const buf = allocator.alloc(
            u8,
            base91.standard.Encoder.calcSize(mem),
        ) catch return .out_of_memory;
        defer allocator.free(buf);

        var encoder = base91.encodeStream(
            allocator,
            buffered_stdin,
            .{
                .buf_size = mem,
            },
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
