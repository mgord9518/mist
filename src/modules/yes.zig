const std = @import("std");
const core = @import("../main.zig");
const fg = core.fg;

pub const exec_mode: core.ExecMode = .fork;

pub const help = core.Help{
    .description = "repeat [STRING] or `y` if unspecified",
    .usage = "[STRING]",
};

pub const main = core.genericMain(realMain);

fn realMain(argv: []const []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var argument_list = std.ArrayList(core.Argument).init(allocator);
    defer argument_list.deinit();

    var it = core.ArgumentParser.init(argv);
    while (it.next()) |entry| {
        try argument_list.append(entry);
    }
    const arguments = argument_list.items;

    const stdout_file = std.io.getStdOut();
    const stdout = stdout_file.writer();
    var buf_writer = std.io.bufferedWriter(stdout);
    const buffered_stdout = buf_writer.writer();

    var target: ?[]const u8 = null;
    for (arguments) |arg| {
        if (arg == .option) return error.UsageError;

        if (arg == .positional) {
            if (target != null) return error.UsageError;

            target = arg.positional;
        }
    }

    while (true) {
        buffered_stdout.print(
            "{s}\n",
            .{target orelse "y"},
        ) catch break;
    }

    try buf_writer.flush();

    return;
}
