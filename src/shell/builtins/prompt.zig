const std = @import("std");
const posix = std.posix;
const core = @import("../../main.zig");
const shell = @import("../../shell.zig");
const time = @import("../../time.zig");
const fg = core.fg;

pub const exec_mode: core.ExecMode = .function;
pub const no_display = true;

const base_color = fg(.default);

const prompt = base_color ++ "┌┤ {s}{s} " ++
    base_color ++ "│ {s}" ++
    base_color ++ " │\n└─" ++ fg(.default) ++ " ";

pub fn main(_: []const core.Argument) core.Error {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();

    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    var link_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;

    var colorized_path = std.ArrayList(u8).init(allocator);
    defer colorized_path.deinit();

    const home = posix.getenv("HOME") orelse "";

    @memcpy(
        path_buf[0..shell.logical_path.len],
        shell.logical_path,
    );
    var path = path_buf[0..shell.logical_path.len];

    const is_link = blk: {
        _ = posix.readlink(path, &link_buf) catch |err| {
            switch (err) {
                error.NotLink => break :blk false,
                else => break :blk true,
            }
        };

        break :blk true;
    };

    var in_home = false;

    if (path.len == 1) {
        _ = colorized_path.writer().write(fg(.bright_blue)) catch unreachable;
        _ = colorized_path.writer().write("/") catch unreachable;
    }

    if (path.len >= home.len and std.mem.eql(u8, path[0..home.len], home)) {
        const is_link2 = blk: {
            _ = posix.readlink(home, &link_buf) catch |err| {
                switch (err) {
                    error.NotLink => break :blk false,
                    else => break :blk true,
                }
            };

            break :blk true;
        };

        const color = if (is_link2) fg(.cyan) else fg(.bright_blue);

        in_home = true;

        _ = colorized_path.writer().write(color) catch unreachable;
        _ = colorized_path.writer().write("~") catch unreachable;
        path = path[home.len..];
    }

    var it = std.fs.path.componentIterator(path) catch unreachable;
    while (it.next()) |name| {
        const is_link2 = blk: {
            const real = if (in_home) blk2: {
                var s: []const u8 = undefined;
                s.len = name.path.len + home.len;
                s.ptr = name.path.ptr - home.len;
                break :blk2 s;
            } else name.path;
            _ = posix.readlink(real, &link_buf) catch |err| {
                switch (err) {
                    error.NotLink => break :blk false,
                    else => break :blk true,
                }
            };

            break :blk true;
        };

        const color = if (is_link2) fg(.cyan) else fg(.bright_blue);

        _ = colorized_path.writer().write(comptime fg(.bright_blue) ++ "/") catch unreachable;
        _ = colorized_path.writer().write(color) catch unreachable;
        _ = colorized_path.writer().write(name.name) catch unreachable;
    }

    const color = if (is_link) fg(.cyan) else fg(.bright_blue);
    const exit_code = shell.variables.get("mist.exit_code") orelse unreachable;

    var code_buf: [4096]u8 = undefined;

    const previous_name = shell.variables.get("mist.exit_code_name");

    const str: []const u8 = if (previous_name) |name| blk: {
        if (false) {
            break :blk std.fmt.bufPrint(
                &code_buf,
                fg(.magenta) ++ "{s}",
                .{name},
            ) catch unreachable;
        }

        break :blk std.fmt.bufPrint(
            &code_buf,
            fg(.red) ++ "{s}",
            .{name},
        ) catch unreachable;
    } else if (std.mem.eql(u8, "0", exit_code)) blk: {
        break :blk comptime fg(.green) ++ "ok";
    } else blk: {
        break :blk std.fmt.bufPrint(
            &code_buf,
            fg(.red) ++ "error code {s}",
            .{exit_code},
        ) catch unreachable;
    };

    stdout.print(prompt, .{
        color,
        colorized_path.items,
        str,
    }) catch {};

    return .success;
}
