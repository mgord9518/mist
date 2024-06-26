const std = @import("std");
const core = @import("../main.zig");
const fg = core.fg;
const curses = @import("shell/curses.zig");
const S = std.posix.S;

pub const exec_mode: core.ExecMode = .fork;

pub const help = core.Help{
    .description =
    \\list files in a directory
    \\
    \\if no [DIRECTORY] is specified, list the working directory
    ,
    .usage = "[" ++
        fg(.cyan) ++ "-aU" ++
        fg(.default) ++ "] [" ++
        fg(.cyan) ++ "DIRECTORY" ++
        fg(.default) ++ "]",
    .options = &.{
        .{ .flag = 'a', .description = "show hidden files" },
        .{ .flag = 'l', .description = "format in long mode" },
        .{ .flag = 'U', .description = "do not sort output" },
        .{ .flag = '1', .description = "force single-column output" },
    },
    .exit_codes = &.{},
};

const Entry = struct {
    path: []const u8,
    stat: std.posix.Stat,
    kind: std.fs.File.Kind,
};

pub fn main(arguments: []const core.Argument) core.Error {
    const stdout_file = std.io.getStdOut();
    const stdout = stdout_file.writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var long = false;
    var single_column = false;
    var show_hidden = false;
    var sort = true;

    var target: ?[]const u8 = null;
    for (arguments) |arg| {
        if (arg == .option) switch (arg.option.flag) {
            'a' => show_hidden = true,
            'l' => long = true,
            'U' => sort = false,
            '1' => single_column = true,

            else => return .usage_error,
        };

        if (arg == .positional) {
            target = arg.positional;
        }
    }

    const cwd = std.fs.cwd();
    const dir = cwd.openDir(
        target orelse ".",
        .{ .iterate = true },
    ) catch |err| {
        return switch (err) {
            error.FileNotFound => .file_not_found,
            error.AccessDenied => .access_denied,

            else => .unknown_error,
        };
    };

    var file_list = std.ArrayList(Entry).init(allocator);
    defer {
        for (file_list.items) |entry| {
            allocator.free(entry.path);
        }

        file_list.deinit();
    }

    var longest: usize = 0;
    var it = dir.iterate();
    while (it.next() catch return .unknown_error) |entry| {
        if (!show_hidden and entry.name[0] == '.') continue;
        const file_name = std.fmt.allocPrint(allocator, "{s}{s}", .{
            switch (entry.kind) {
                .directory => fg(.bright_blue),
                // TODO: detect broken links
                .sym_link => fg(.cyan),
                .character_device, .block_device => fg(.yellow),
                else => blk: {
                    const stat = cwd.statFile(entry.name) catch {
                        break :blk fg(.default);
                    };
                    const can_exec = (stat.mode & S.IXUSR) |
                        (stat.mode & S.IXGRP) |
                        (stat.mode & S.IXOTH) > 0;
                    if (can_exec) {
                        break :blk fg(.bright_green);
                    }
                    break :blk fg(.default);
                },
            },
            entry.name,
        }) catch return .unknown_error;

        longest = @max(longest, entry.name.len);

        file_list.append(.{
            .kind = entry.kind,
            .path = file_name,
            .stat = undefined,
        }) catch return .unknown_error;
    }

    if (sort) {
        std.mem.sort(
            Entry,
            file_list.items,
            @as(usize, 6),
            asc,
        );
    }

    // TODO: MOVE TO CURSES
    //    var ioctl: std.posix.system.winsize = undefined;
    //    _ = std.posix.system.ioctl(
    //        std.posix.STDOUT_FILENO,
    //        std.posix.T.IOCGWINSZ,
    //        @intFromPtr(&ioctl),
    //    );
    const size = curses.terminalSize();

    const col_width = longest + 2;
    const col_num = if (!long and !single_column) blk: {
        break :blk (size.w / col_width);
    } else 1;

    var files_per_col = (file_list.items.len / (col_num));
    if (file_list.items.len % col_num != 0) files_per_col += 1;

    var idx: usize = 0;
    var col: usize = 0;

    var st_buf: [1]u8 = undefined;

    if (stdout_file.isTty()) {
        for (file_list.items) |entry| {
            if (idx >= files_per_col) {
                col += 1;
                idx = 0;
                _ = stdout.write("\r") catch return .unknown_error;
                curses.move(.up, files_per_col);
            }

            if (long) {
                var mode: std.posix.mode_t = 0;

                stat_blk: {
                    const stat = cwd.statFile(entry.path[6..]) catch break :stat_blk;
                    mode = stat.mode;
                }

                st_buf[0] = if (S.ISREG(mode)) blk: {
                    break :blk '-';
                } else if (S.ISDIR(mode)) blk: {
                    break :blk 'd';
                } else if (S.ISCHR(mode)) blk: {
                    break :blk 'c';
                } else if (S.ISBLK(mode)) blk: {
                    break :blk 'b';
                } else if (S.ISFIFO(mode)) blk: {
                    break :blk 'p';
                } else if (S.ISFIFO(mode)) blk: {
                    break :blk 'p';
                } else if (S.ISLNK(mode)) blk: {
                    break :blk 'l';
                } else if (S.ISSOCK(mode)) blk: {
                    break :blk 's';
                } else '.';

                stdout.print(fg(.default) ++ "{s}{o:0<3} ", .{
                    st_buf[0..1],
                    mode & 0o777,
                }) catch return .unknown_error;
            }

            curses.move(.right, col * col_width);

            stdout.print("{s}\n", .{entry.path}) catch return .unknown_error;

            idx += 1;
        }

        while (idx < files_per_col) : (idx += 1) {
            _ = stdout.write("\n") catch return .unknown_error;
        }

        _ = stdout.write(fg(.default)) catch return .unknown_error;
    } else {
        idx += 1;
        for (file_list.items) |entry| {
            stdout.print("{s}\n", .{entry.path[6..]}) catch return .unknown_error;
        }
    }

    return .success;
}

/// Sorts UTF-8 strings ordered by lower to higher codepoints preferring
/// shorter strings.
fn asc(offset: usize, a: Entry, b: Entry) bool {
    // Start at offset 6 to skip the ANSI color code,
    // which is something like `\x1b[;31m`.
    // We can use offset 6 because we ensure only 2-digit codes are ever used
    var utf8_view_a = std.unicode.Utf8View.init(
        a.path[offset..],
    ) catch return true;

    var utf8_view_b = std.unicode.Utf8View.init(
        b.path[offset..],
    ) catch return false;

    var it_a = utf8_view_a.iterator();
    var it_b = utf8_view_b.iterator();

    while (true) {
        const codepoint_a = it_a.nextCodepoint() orelse return true;
        const codepoint_b = it_b.nextCodepoint() orelse return false;

        if (codepoint_a > codepoint_b) {
            return false;
        } else if (codepoint_a < codepoint_b) {
            return true;
        }
    }

    unreachable;
}
