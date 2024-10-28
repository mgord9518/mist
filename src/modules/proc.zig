const std = @import("std");
const core = @import("../main.zig");
const shell = @import("../shell.zig");

pub const exec_mode: core.ExecMode = .fork;

pub const help = core.Help{
    .description = "read from STDIN, creating a procedure",
    .usage = "<PROCEDURE NAME>",
};

pub fn main(arguments: []const core.Argument) core.Error {
    realMain(arguments) catch |err| {
        return switch (err) {
            error.NoSpaceLeft => .no_space_left,
            error.UsageError => .no_space_left,
            else => .unknown_error,
        };
    };

    return .success;
}

fn realMain(arguments: []const core.Argument) !void {
    if (arguments.len != 1) return error.UsageError;

    const name = if (arguments[0] == .positional) blk: {
        break :blk arguments[0].positional;
    } else {
        return error.UsageError;
    };

    if (name.len > 255) return error.NoSpaceLeft;

    var stdin_file = std.io.getStdIn();

    var fbs = std.io.fixedBufferStream(shell.shm);

    // `P` for procedure
    _ = try fbs.write("P");

    // Name length, 1 byte
    _ = try fbs.writer().writeInt(u8, @intCast(name.len), .little);

    // Procedure size, this will be written last
    _ = try fbs.writer().writeInt(u16, 69, .little);

    _ = try fbs.write(name);

    while (true) {
        stdin_file.reader().streamUntilDelimiter(
            fbs.writer(),
            '\n',
            null,
        ) catch |err| {
            switch (err) {
                error.EndOfStream => break,
                else => return err,
            }
        };
    }

    std.debug.print("fbs {}\n", .{fbs.pos});

    const total: u16 = @intCast(fbs.pos - 4 - name.len);

    try fbs.seekableStream().seekTo(2);
    _ = try fbs.writer().writeInt(u16, total, .little);
}
