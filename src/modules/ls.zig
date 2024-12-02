const std = @import("std");
const core = @import("../main.zig");
const sort = @import("sort.zig");
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

pub const main = core.genericMain(realMain);

fn realMain(arguments: []const core.Argument) !void {
    const stdout_file = std.io.getStdOut();
    const stdout = stdout_file.writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var long = false;
    var single_column = false;
    var show_hidden = false;
    var do_sort = true;
    var rev_sort = false;

    var target: ?[]const u8 = null;
    for (arguments) |arg| {
        if (arg == .option) switch (arg.option[1]) {
            'a' => show_hidden = true,
            'l' => long = true,
            'U' => do_sort = false,
            'r' => rev_sort = true,
            '1' => single_column = true,

            else => return error.UsageError,
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
        switch (err) {
            error.NotDir => {
                const file = try cwd.openFile(target.?, .{});
                defer file.close();

                const stat = try file.stat();

                try stdout.print(
                    //fg(.default) ++ "{c} {o:0>4} {:>8.2} ",
                    fg(.default) ++ "{s} {o:0>4} {:>.2}\n",
                    .{
                        target.?,
                        stat.mode & 0o7777,
                        fmtIntSizeDec(stat.size),
                    },
                );

                return;
            },

            else => return err,
        }
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
    while (try it.next()) |entry| {
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

        const file_name = try allocator.dupe(u8, entry.name);

        longest = @max(longest, entry.name.len);

        try file_list.append(.{
            .kind = entry.kind,
            .color = color,
            .path = file_name,
            .stat = stat,
        });
    }

    if (do_sort) {
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
    var col_num = if (!long and !single_column) blk: {
        break :blk (size.w / col_width);
    } else 1;

    if (col_num < 1) col_num = 1;

    var files_per_col = (file_list.items.len / (col_num));
    if (file_list.items.len % col_num != 0) files_per_col += 1;

    var idx: usize = 0;
    var col: usize = 0;

    if (stdout_file.isTty()) {
        for (file_list.items) |entry| {
            if (idx >= files_per_col) {
                col += 1;
                idx = 0;
                _ = try stdout.write("\r");
                curses.move(.up, files_per_col);
            }

            if (long) {
                var mode: std.posix.mode_t = 0;

                if (entry.stat) |stat| {
                    mode = stat.mode;
                }

                if (false) {
                    stat_blk: {
                        const stat = dir.statFile(entry.path) catch break :stat_blk;
                        //_ = stat;
                        mode = stat.mode;
                    }
                }

                const sz = if (entry.stat) |stat| blk: {
                    break :blk stat.size;
                } else 0;

                try stdout.print(
                    fg(.default) ++ "{c} {o:0>4} {:>8.2} ",
                    .{
                        inodeSymbol(entry.kind),
                        mode & 0o7777,
                        fmtIntSizeDec(sz),
                    },
                );
            }

            curses.move(.right, col * col_width);

            try stdout.print("{s}{s}\n", .{
                entry.color,
                entry.path,
            });

            idx += 1;
        }

        while (idx < files_per_col) : (idx += 1) {
            _ = try stdout.write("\n");
        }

        _ = try stdout.write(fg(.default));
    } else {
        idx += 1;
        for (file_list.items) |entry| {
            try stdout.print("{s}\n", .{entry.path});
        }
    }
}

fn inodeSymbol(kind: std.fs.File.Kind) u8 {
    return switch (kind) {
        .file => '-',
        .directory => 'd',
        .character_device => 'c',
        .block_device => 'b',
        .named_pipe => 'p',
        .sym_link => 'l',
        .unix_domain_socket => 's',
        else => '?',
    };
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
        //.alphabetic => sort.sortByAlphabet({}, a.path, b.path),
        .alphabetic => sort.sortByAlphabetBytes({}, a.path, b.path),
        .size => blk: {
            const sz_a = if (a.stat != null) a.stat.?.size else 0;
            const sz_b = if (b.stat != null) b.stat.?.size else 0;

            break :blk sz_a > sz_b;
        },
    };

    if (ctx.reverse) return !ret;

    return ret;
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
