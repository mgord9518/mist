const std = @import("std");
const core = @import("../main.zig");
const fg = core.fg;
const curses = @import("../shell/curses.zig");
const S = std.posix.S;

pub const exec_mode: core.ExecMode = .fork;

pub const help = core.Help{
    .description = "list files in a directory",
    .usage = "[-alUr1] [DIR]",
    .options = &.{
        .{ .flag = 'a', .description = "show hidden files" },
        .{ .flag = 'l', .description = "format in long mode" },
        .{ .flag = 'U', .description = "do not sort output" },
        .{ .flag = 'r', .description = "sort in reverse order" },
        .{ .flag = '1', .description = "force single-column output" },
    },
};

const Entry = struct {
    // The color is a compile-time string, either 5 or 6 bytes long
    color: []const u8,

    // Path is allocated, must be freed after use
    path: []const u8,

    stat: ?std.fs.File.Stat,
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
    var rev_sort = false;

    var target: ?[]const u8 = null;
    for (arguments) |arg| {
        if (arg == .option) switch (arg.option.flag) {
            'a' => show_hidden = true,
            'l' => long = true,
            'U' => sort = false,
            'r' => rev_sort = true,
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

        const stat = dir.statFile(entry.name) catch blk: {
            break :blk null;
        };

        const color = switch (entry.kind) {
            .directory => core.colors.fs.directory,

            // TODO: detect broken links
            .sym_link => core.colors.fs.sym_link,
            .character_device, .block_device => core.colors.fs.device,
            else => blk: {
                const st = stat orelse {
                    break :blk core.colors.fs.file;
                };

                const can_exec = (st.mode & S.IXUSR) |
                    (st.mode & S.IXGRP) |
                    (st.mode & S.IXOTH) > 0;
                if (can_exec) {
                    break :blk core.colors.fs.executable;
                }
                break :blk core.colors.fs.file;
            },
        };

        const file_name = allocator.dupe(u8, entry.name) catch unreachable;

        longest = @max(longest, entry.name.len);

        file_list.append(.{
            .kind = entry.kind,
            .color = color,
            .path = file_name,
            .stat = stat,
        }) catch return .unknown_error;
    }

    if (sort) {
        std.mem.sort(
            Entry,
            file_list.items,
            @as(SortContext, .{
                .order = .alphabetic,
                .reverse = rev_sort,
            }),
            sortFn,
        );
    }

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

                if (entry.stat) |stat| {
                    mode = stat.mode;
                }

                stat_blk: {
                    const stat = dir.statFile(entry.path) catch break :stat_blk;
                    //_ = stat;
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
                } else '!';

                const sz = if (entry.stat) |stat| blk: {
                    break :blk stat.size;
                } else 0;

                stdout.print(fg(.default) ++ "{s} {o:0<3} {:>8.2} ", .{
                    st_buf[0..1],
                    mode & 0o777,
                    fmtIntSizeDec(sz),
                }) catch return .unknown_error;
            }

            curses.move(.right, col * col_width);

            stdout.print("{s}{s}\n", .{
                entry.color,
                entry.path,
            }) catch return .unknown_error;

            idx += 1;
        }

        while (idx < files_per_col) : (idx += 1) {
            _ = stdout.write("\n") catch return .unknown_error;
        }

        _ = stdout.write(fg(.default)) catch return .unknown_error;
    } else {
        idx += 1;
        for (file_list.items) |entry| {
            stdout.print("{s}\n", .{entry.path}) catch return .unknown_error;
        }
    }

    return .success;
}

const SortContext = struct {
    reverse: bool = false,
    order: Order,

    const Order = enum {
        alphabetic,
        size,
    };
};

fn sortFn(ctx: SortContext, a: Entry, b: Entry) bool {
    const ret = switch (ctx.order) {
        .alphabetic => sortByAlphabet({}, a, b),
        //.alphabetic => sortByAlphabetBytes({}, a, b),
        .size => sortBySize({}, a, b),
    };

    if (ctx.reverse) return !ret;

    return ret;
}

fn sortBySize(_: void, a: Entry, b: Entry) bool {
    const sz_a = if (a.stat != null) a.stat.?.size else 0;
    const sz_b = if (b.stat != null) b.stat.?.size else 0;

    return sz_a > sz_b;
}

/// Sorts UTF-8 strings ordered by lower to higher codepoints preferring
/// shorter strings.
fn sortByAlphabet(_: void, a: Entry, b: Entry) bool {
    var utf8_view_a = std.unicode.Utf8View.init(
        a.path,
    ) catch return true;

    var utf8_view_b = std.unicode.Utf8View.init(
        b.path,
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

/// Sorts strings by byte values. This is smaller and simpler than the UTF-8
/// version but will not properly sort Unicode strings
fn sortByAlphabetBytes(_: void, a: Entry, b: Entry) bool {
    var a_idx: usize = 0;
    var b_idx: usize = 0;

    while (true) {
        const char_a = a.path[a_idx];
        const char_b = b.path[b_idx];

        if (char_a > char_b) {
            return false;
        } else if (char_a < char_b) {
            return true;
        }

        a_idx += 1;
        b_idx += 1;

        if (a_idx >= a.path.len) return true;
        if (b_idx >= b.path.len) return false;
    }

    unreachable;
}

const formatSizeDec = formatSizeImpl(1000).formatSizeImpl;
pub fn fmtIntSizeDec(value: u64) std.fmt.Formatter(formatSizeDec) {
    return .{ .data = value };
}

// Copied and modified from <https://github.com/ziglang/zig/blob/master/lib/std/fmt.zig>
fn formatSizeImpl(comptime base: comptime_int) type {
    return struct {
        fn formatSizeImpl(
            value: u64,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            if (value == 0) {
                return std.fmt.formatBuf("0B", options, writer);
            }
            // The worst case in terms of space needed is 32 bytes + 3 for the suffix.
            var buf: [std.fmt.format_float.min_buffer_size + 3]u8 = undefined;

            const mags_si = " kMGTPEZY";
            const mags_iec = " KMGTPEZY";

            const log2 = std.math.log2(value);
            const magnitude = switch (base) {
                1000 => @min(log2 / comptime std.math.log2(1000), mags_si.len - 1),
                1024 => @min(log2 / 10, mags_iec.len - 1),
                else => unreachable,
            };
            const new_value = std.math.lossyCast(f64, value) / std.math.pow(f64, std.math.lossyCast(f64, base), std.math.lossyCast(f64, magnitude));
            const suffix = switch (base) {
                1000 => mags_si[magnitude],
                1024 => mags_iec[magnitude],
                else => unreachable,
            };

            const s = switch (magnitude) {
                0 => buf[0..std.fmt.formatIntBuf(&buf, value, 10, .lower, .{})],
                else => std.fmt.formatFloat(&buf, new_value, .{ .mode = .decimal, .precision = options.precision }) catch |err| switch (err) {
                    error.BufferTooSmall => unreachable,
                },
            };

            var i: usize = s.len;
            if (suffix == ' ') {
                buf[i] = 'B';
                buf[i + 1] = ' ';
                i += 1;
            } else switch (base) {
                1000 => {
                    buf[i..][0..2].* = [_]u8{ suffix, 'B' };
                    i += 2;
                },
                1024 => {
                    buf[i..][0..3].* = [_]u8{ suffix, 'i', 'B' };
                    i += 3;
                },
                else => unreachable,
            }

            return std.fmt.formatBuf(buf[0..i], options, writer);
        }
    };
}
