const std = @import("std");
const posix = std.posix;
const core = @import("../../../main.zig");
const shell = @import("../../shell.zig");
const time = @import("../../../time.zig");
const fg = core.fg;

pub const exec_mode: core.ExecMode = .function;

pub const help = core.Help{
    .description = "print command prompt",
    .usage = "",
    .options = &.{},
    .exit_codes = &.{},
};

//const prompt = fg(.cyan) ++ "┃" ++ fg(.bright_blue) ++ " {s} " ++ fg(.cyan) ++ "┃ {s} " ++ fg(.cyan) ++ "┠╼" ++ fg(.default) ++ " ";
//const prompt = fg(.cyan) ++ "╭┨ {s}{s} " ++ fg(.cyan) ++ "┃ {s} " ++ fg(.cyan) ++ "┃\n╰╼" ++ fg(.default) ++ " ";
const prompt = fg(.default) ++ "┌┤ {s}{s} " ++ fg(.default) ++ "│ {d:0<2}:{d:0<2}:{d:0<2} " ++ fg(.default) ++ "│ {s}" ++ fg(.default) ++ " │\n└─" ++ fg(.default) ++ " ";
//const prompt = fg(.default) ++ "╭┨ {s}{s} " ++ fg(.default) ++ "┃ {s} " ++ fg(.default) ++ "┠────────────────────────────────────────┨\n╰╼" ++ fg(.default) ++ " ";

//const prompt = fg(.cyan) ++ "┌[" ++ fg(.bright_blue) ++ " {s} " ++ fg(.cyan) ++ "]─[ CODE ]\n└╼" ++ fg(.default) ++ " ";

pub fn main(_: []const core.Argument) u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();

    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    var link_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;

    var colorized_path = std.ArrayList(u8).init(allocator);
    defer colorized_path.deinit();

    const home = std.posix.getenv("HOME") orelse "";
    //var path = std.fs.cwd().realpath(".", path_buf[6..]) catch return 1;
    //var path = std.posix.getcwd(path_buf[6..]) catch return 1;

    @memcpy(path_buf[0..shell.logical_path.len], shell.logical_path);
    var path = path_buf[0..shell.logical_path.len];

    const is_link = blk: {
        _ = std.posix.readlink(path, &link_buf) catch |err| {
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
            _ = std.posix.readlink(home, &link_buf) catch |err| {
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
            _ = std.posix.readlink(real, &link_buf) catch |err| {
                switch (err) {
                    error.NotLink => break :blk false,
                    else => break :blk true,
                }
            };

            break :blk true;
        };

        const color = if (is_link2) fg(.cyan) else fg(.bright_blue);

        //        _ = colorized_path.writer().write(fg(.white)) catch unreachable;
        _ = colorized_path.writer().write(comptime fg(.bright_blue) ++ "/") catch unreachable;
        //_ = colorized_path.writer().write("/") catch unreachable;
        _ = colorized_path.writer().write(color) catch unreachable;
        _ = colorized_path.writer().write(name.name) catch unreachable;

        //std.debug.print("name {s}{s}\n", .{ color, name.path });
    }

    const color = if (is_link) fg(.cyan) else fg(.bright_blue);
    //@memcpy(path_buf[0..6], color);

    const exit_code = shell.variables.get("mash::exit_code") orelse unreachable;

    var code_buf: [4096]u8 = undefined;

    const previous_name = shell.variables.get("mash::exit_code_name");

    const str: []const u8 = if (previous_name) |name| blk: {
        if (shell.child_error.* != 0) {
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

    const date = time.Date.fromUnix(std.time.timestamp());

    stdout.print(prompt, .{
        color,
        //path,
        colorized_path.items,
        date.hours,
        date.minutes,
        date.seconds,
        str,
    }) catch {};

    return 0;
}
