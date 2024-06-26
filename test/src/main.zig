const std = @import("std");

fn noop(_: i32) callconv(.C) void {
    std.debug.print("I won't die that easy!\n", .{});
}

pub fn main() !void {
    var action = std.posix.Sigaction{
        .handler = .{ .handler = &noop },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };

    try std.posix.sigaction(std.posix.SIG.INT, &action, null);

    // try disableSigint();
    var i: usize = 0;
    while (i < 60) : (i += 1) {
        std.debug.print("sleep {d}\n", .{i});
        std.time.sleep(1_000_000_000);
    }
}
