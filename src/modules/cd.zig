const std = @import("std");
const posix = std.posix;
const core = @import("../main.zig");
const shell = @import("../shell.zig");
const fg = core.fg;

pub const exec_mode: core.ExecMode = .function;

pub const help = core.Help{
    .description = "change working directory",
    .usage = "[DIR]",
};

var previous_dir: ?[]const u8 = null;
var previous_dir_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;

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

    const cwd = std.fs.cwd();

    const home = std.posix.getenv("HOME") orelse "";

    if (arguments.len == 0) {
        previous_dir = try std.fmt.bufPrint(&previous_dir_buf, "{s}", .{home});

        @memcpy(previous_dir_buf[0..shell.logical_path.len], shell.logical_path);
        previous_dir = previous_dir_buf[0..shell.logical_path.len];

        try std.posix.chdir(home);

        return;
    }

    if (std.mem.eql(u8, arguments[0].positional, "-")) {
        if (previous_dir) |pdir| {
            const temp = pdir;

            @memcpy(previous_dir_buf[0..shell.logical_path.len], shell.logical_path);
            previous_dir = previous_dir_buf[0..shell.logical_path.len];

            @memcpy(shell.logical_path_buf[0..temp.len], temp);
            shell.logical_path = shell.logical_path_buf[0..temp.len];

            try std.posix.chdir(temp);
        }

        return;
    }

    const sub_dir = arguments[0].positional;

    var dir = try cwd.openDir(sub_dir, .{});

    @memcpy(previous_dir_buf[0..shell.logical_path.len], shell.logical_path);
    previous_dir = previous_dir_buf[0..shell.logical_path.len];

    resolveLogicalPath(sub_dir) catch unreachable;

    try dir.setAsCwd();

    return;
}

fn resolveLogicalPath(sub_dir: []const u8) !void {
    var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const allocator = fba.allocator();

    const temp = std.fs.path.resolve(
        allocator,
        &.{
            shell.logical_path,
            sub_dir,
        },
    ) catch unreachable;

    @memcpy(shell.logical_path_buf[0..temp.len], temp);
    shell.logical_path = shell.logical_path_buf[0..temp.len];

    allocator.free(temp);
}
