const std = @import("std");
const core = @import("../../main.zig");
const shell = @import("../../shell.zig");

pub const exec_mode: core.ExecMode = .fork;

pub const help = core.Help{
    .description = "set a variable from STDIN",
    .usage = "<VARIABLE NAME>",
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

    _ = try fbs.write("P");
    _ = try fbs.writer().writeInt(u8, @intCast(name.len), .little);

    _ = try fbs.write(name);
    _ = try fbs.writer().writeInt(u16, 10, .little);

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
}
