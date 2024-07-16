const std = @import("std");
const core = @import("../main.zig");

pub const exec_mode: core.ExecMode = .fork;

pub const help = core.Help{
    .description = "compress data from STDIN with gzip, printing it to STDOUT",
    .usage = "[-d]",
};

pub fn main(arguments: []const core.Argument) core.Error {
    const stdout_file = std.io.getStdOut();
    var buf_writer = std.io.bufferedWriter(stdout_file.writer());
    const buffered_stdout = buf_writer.writer();

    const stdin_file = std.io.getStdIn();
    var buf_reader = std.io.bufferedReader(stdin_file.reader());
    const buffered_stdin = buf_reader.reader();

    var decode = false;
    for (arguments) |arg| {
        if (arg == .positional) return .usage_error;

        if (arg == .option) switch (arg.option.flag) {
            'd' => decode = true,

            else => return .usage_error,
        };
    }

    if (decode) {
        std.compress.gzip.decompress(
            buffered_stdin,
            buffered_stdout,
        ) catch |err| {
            return switch (err) {
                error.InvalidCode,
                error.InvalidMatch,
                error.InvalidBlockType,
                error.WrongStoredBlockNlen,
                error.InvalidDynamicBlockHeader,
                => .corrupt_input,

                else => .unknown_error,
            };
        };
    } else {
        std.compress.gzip.compress(
            buffered_stdin,
            buffered_stdout,
            .{},
        ) catch |err| {
            return switch (err) {
                else => .unknown_error,
            };
        };
    }

    buf_writer.flush() catch return .unknown_error;

    return .success;
}
