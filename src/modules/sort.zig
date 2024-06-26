const std = @import("std");
const core = @import("../main.zig");
const fg = core.fg;
const cursor = @import("shell/curses.zig");
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

pub fn main(arguments: []const core.Argument) core.Error {
    const stdout_file = std.io.getStdOut();
    const stdout = stdout_file.writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var long = false;
    var show_hidden = false;
    var sort = true;

    var target: []const u8 = ".";
    for (arguments) |arg| {
        if (arg == .option) switch (arg.option.flag) {
            'a' => show_hidden = true,
            'l' => long = true,
            'U' => sort = false,

            else => return .usage_error,
        };

        if (arg == .positional) {
            target = arg.positional;
        }
    }

    const cwd = std.fs.cwd();
    const dir = cwd.openDir(
        target,
        .{ .iterate = true },
    ) catch |err| {
        return switch (err) {
            error.FileNotFound => .file_not_found,
            error.AccessDenied => .access_denied,

            else => .unknown_error,
        };
    };

    var file_list = std.ArrayList([]const u8).init(allocator);
    defer {
        for (file_list.items) |file_name| {
            allocator.free(file_name);
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
                    var file = cwd.openFile(entry.name, .{}) catch {
                        break :blk fg(.default);
                    };
                    defer file.close();
                    const stat = file.stat() catch {
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

        file_list.append(file_name) catch return .unknown_error;
    }

    if (sort) {
        std.mem.sort(
            []const u8,
            file_list.items,
            @as(usize, 6),
            asc,
        );
    }

    // TODO: MOVE TO CURSES
    var ioctl: std.posix.system.winsize = undefined;
    _ = std.posix.system.ioctl(
        std.posix.STDOUT_FILENO,
        std.posix.T.IOCGWINSZ,
        @intFromPtr(&ioctl),
    );

    const col_width = longest + 2;
    const col_num = if (!long) (ioctl.ws_col / col_width) else 1;

    var files_per_col = (file_list.items.len / (col_num));
    if (file_list.items.len % col_num != 0) files_per_col += 1;

    var idx: usize = 0;
    var col: usize = 0;

    var st_buf: [10]u8 = undefined;

    if (long) {
        stdout.print(" UGO\n", .{}) catch unreachable;
    }

    if (stdout_file.isTty()) {
        for (file_list.items) |file_name| {
            if (idx >= files_per_col) {
                col += 1;
                idx = 0;
                _ = stdout.write("\r") catch return .unknown_error;
                cursor.move(.up, files_per_col);
            }

            if (long) if_blk: {
                var file = cwd.openFile(file_name[6..], .{}) catch break :if_blk;
                defer file.close();

                const stat = file.stat() catch break :if_blk;

                st_buf[0] = if (S.ISREG(stat.mode)) blk: {
                    break :blk '-';
                } else '.';

                st_buf[1] = if (stat.mode & S.IRUSR != 0) 'r' else '-';
                st_buf[2] = if (stat.mode & S.IWUSR != 0) 'w' else '-';
                st_buf[3] = if (stat.mode & S.IXUSR != 0) 'x' else '-';

                st_buf[4] = if (stat.mode & S.IRGRP != 0) 'r' else '-';
                st_buf[5] = if (stat.mode & S.IWGRP != 0) 'w' else '-';
                st_buf[6] = if (stat.mode & S.IXGRP != 0) 'x' else '-';

                st_buf[7] = if (stat.mode & S.IROTH != 0) 'r' else '-';
                st_buf[8] = if (stat.mode & S.IWOTH != 0) 'w' else '-';
                st_buf[9] = if (stat.mode & S.IXOTH != 0) 'x' else '-';

                stdout.print(fg(.default) ++ "{s}{o} ", .{
                    st_buf[0..1],
                    stat.mode & 0o777,
                }) catch return .unknown_error;
            }

            cursor.move(.right, col * col_width);

            stdout.print("{s}\n", .{file_name}) catch return .unknown_error;

            idx += 1;
        }

        while (idx < files_per_col) : (idx += 1) {
            _ = stdout.write("\n") catch return .unknown_error;
        }

        _ = stdout.write(fg(.default)) catch return .unknown_error;
    } else {
        idx += 1;
        for (file_list.items) |file_name| {
            stdout.print("{s}\n", .{file_name[6..]}) catch return .unknown_error;
        }
    }

    //std.debug.print("longest {d} {d} {d} {d}\n", .{ files_per_col, ioctl.ws_col, col_num, col_width });

    return .success;
}

/// Sorts UTF-8 strings ordered by lower to higher codepoints, preferring shorter strings.
fn asc(offset: usize, a: []const u8, b: []const u8) bool {
    // Start at offset 6 to skip the ANSI color code,
    // which is something like `\x1b[;31m`.
    // We can use offset 6 because we ensure only 2-digit codes are ever used
    var utf8_view_a = std.unicode.Utf8View.init(
        a[offset..],
    ) catch return true;

    var utf8_view_b = std.unicode.Utf8View.init(
        b[offset..],
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

fn dec(offset: usize, a: []const u8, b: []const u8) bool {
    return !asc(offset, a, b);
}
