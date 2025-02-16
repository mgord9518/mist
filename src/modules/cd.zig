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

fn realMain(arguments: []const core.Argument) !void {

    //pub fn main(arguments: []const core.Argument) core.Error {
    const cwd = std.fs.cwd();

    const home = std.posix.getenv("HOME") orelse "";

    if (arguments.len == 0) {
        previous_dir = try std.fmt.bufPrint(&previous_dir_buf, "{s}", .{home}); //catch return .unknown_error;

        @memcpy(previous_dir_buf[0..shell.logical_path.len], shell.logical_path);
        previous_dir = previous_dir_buf[0..shell.logical_path.len];

        try std.posix.chdir(home); //catch |err| {
        //            return switch (err) {
        //                error.FileNotFound => .file_not_found,
        //                else => return .unknown_error,
        //            };
        //        };

        return;
    }

    if (std.mem.eql(u8, arguments[0].positional, "-")) {
        if (previous_dir) |pdir| {
            const temp = pdir;

            @memcpy(previous_dir_buf[0..shell.logical_path.len], shell.logical_path);
            previous_dir = previous_dir_buf[0..shell.logical_path.len];

            @memcpy(shell.logical_path_buf[0..temp.len], temp);
            shell.logical_path = shell.logical_path_buf[0..temp.len];

            try std.posix.chdir(temp); // catch |err| {
            //                return switch (err) {
            //                    error.FileNotFound => .file_not_found,
            //                    else => unreachable,
            //                };
            //            };
        }

        return;
    }

    const sub_dir = arguments[0].positional;

    var dir = try cwd.openDir(sub_dir, .{}); // catch {
    //        return .unknown_error;
    //    };

    @memcpy(previous_dir_buf[0..shell.logical_path.len], shell.logical_path);
    previous_dir = previous_dir_buf[0..shell.logical_path.len];

    resolveLogicalPath(sub_dir) catch unreachable;

    try dir.setAsCwd(); //catch |err| {
    //        switch (err) {
    //            error.NotDir => return .not_dir,
    //            error.AccessDenied => return .access_denied,
    //            else => return .unknown_error,
    //        }
    //    };

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
