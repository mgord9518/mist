const std = @import("std");
const posix = std.posix;
const core = @import("../../main.zig");
const shell = @import("../../shell.zig");
const fg = core.fg;

pub const exec_mode: core.ExecMode = .function;

pub const help = core.Help{
    .description = "change working directory",
    .usage = "[DIR]",
};

var previous_dir: ?[]const u8 = null;
var previous_dir_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;

pub fn main(arguments: []const core.Argument) core.Error {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const cwd = std.fs.cwd();

    if (arguments.len == 0) {
        const home = std.posix.getenv("HOME") orelse "";

        previous_dir = std.fmt.bufPrint(&previous_dir_buf, "{s}", .{home}) catch return .unknown_error;

        std.posix.chdir(home) catch |err| {
            return switch (err) {
                error.FileNotFound => .file_not_found,
                else => return .unknown_error,
            };
        };

        return .success;
    }

    if (std.mem.eql(u8, arguments[0].positional, "-")) {
        if (previous_dir) |pdir| {
            _ = pdir;
            // TODO
            //            defer previous_dir = std.fmt.bufPrint(&previous_dir_buf, "{s}", .{home});
            //
            //            const temp = pdir;
            //            previous_dir = temp;
            //            std.debug.print("{?s}\n", .{previous_dir});
            //
            //            std.posix.chdir(temp) catch |err| {
            //                return switch (err) {
            //                    error.FileNotFound => 3,
            //                    else => return 1,
            //                };
            //            };
        }

        return .unknown_error;
    }

    const p = arguments[0].positional;

    const tmp = std.fs.path.resolve(
        allocator,
        &.{
            shell.logical_path,
            p,
        },
    ) catch unreachable;

    var dir = cwd.openDir(tmp, .{}) catch {
        allocator.free(tmp);
        return .unknown_error;
    };

    @memcpy(shell.logical_path_buf[0..tmp.len], tmp);
    shell.logical_path = shell.logical_path_buf[0..tmp.len];

    allocator.free(tmp);

    dir.setAsCwd() catch |err| {
        switch (err) {
            error.NotDir => return .unknown_error,
            else => return .unknown_error,
        }
    };

    previous_dir = arguments[0].positional;
    //    std.posix.chdir(arguments[0].positional) catch |err| {
    //        return switch (err) {
    //            error.FileNotFound => 3,
    //            else => return 1,
    //        };
    //    };

    return .success;
}
