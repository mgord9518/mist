const std = @import("std");
const core = @import("../main.zig");
const sort = @import("sort.zig");
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
        //.{ .flag = 'R', .description = "list files recursively" },
        .{ .flag = '1', .description = "force single-column output" },
    },
};

const Entry = struct {
    // Path is allocated, must be freed after use
    name: []const u8,

    kind: std.fs.File.Kind,
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

    var long = false;
    var single_column = false;
    var show_hidden = false;
    var do_sort = true;
    var rev_sort = false;

    var targets = std.ArrayList([]const u8).init(allocator);
    defer targets.deinit();

    for (arguments) |arg| {
        if (arg == .option) switch (arg.option) {
            'a' => show_hidden = true,
            'l' => long = true,
            'U' => do_sort = false,
            'r' => rev_sort = true,
            '1' => single_column = true,

            else => return error.UsageError,
        };

        if (arg == .positional) {
            try targets.append(arg.positional);
        }
    }

    if (targets.items.len == 0) {
        try targets.append(".");
    }

    for (targets.items) |target| {
        const cwd = std.fs.cwd();
        const dir = cwd.openDir(
            target,
            .{ .iterate = true },
        ) catch |err| {
            switch (err) {
                error.NotDir => {
                    const file = try cwd.openFile(target, .{});
                    defer file.close();

                    const stat = try file.stat();

                    try stdout.print(
                        "{}{s} {o:0>4} {:>.2}\n",
                        .{
                            core.ColorName.default,
                            target,
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
                allocator.free(entry.name);
            }

            file_list.deinit();
        }

        var longest: usize = 0;
        var dir_it = dir.iterate();
        while (try dir_it.next()) |entry| {
            if (!show_hidden and entry.name[0] == '.') continue;

            const file_name = try allocator.dupe(u8, entry.name);

            longest = @max(longest, entry.name.len);

            try file_list.append(.{
                .kind = entry.kind,
                .name = file_name,
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

        if (!stdout_file.isTty()) {
            for (file_list.items) |entry| {
                try stdout.print("{s}\n", .{entry.name});
            }

            return;
        }

        if (long) {
            try prettyListLong(
                dir,
                target,
                file_list.items,
            );
        } else {
            try prettyList(
                dir,
                longest,
                file_list.items,
                single_column,
            );
        }
    }
}

fn colorFromKind(dir: std.fs.Dir, entry: Entry) !core.ColorName {
    return switch (entry.kind) {
        .directory => core.colors.fs.directory,

        // TODO: detect broken links
        .sym_link => blk: {
            var buf: [std.fs.max_path_bytes]u8 = undefined;
            const link_target = try dir.readLink(entry.name, &buf);

            dir.access(link_target, .{}) catch |err| {
                break :blk switch (err) {
                    error.FileNotFound => core.colors.fs.broken_sym_link,
                    else => core.colors.fs.sym_link,
                };
            };

            break :blk core.colors.fs.sym_link;
        },
        .character_device, .block_device => core.colors.fs.device,
        else => blk: {
            const st = dir.statFile(entry.name) catch {
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
}

fn prettyListLong(dir: std.fs.Dir, target: []const u8, items: []const Entry) !void {
    const stdout_file = std.io.getStdOut();
    const stdout = stdout_file.writer();

    try stdout.print(
        "{}{s}\n",
        .{ core.ColorName.default, target },
    );

    for (items, 0..) |entry, i| {
        const stat = dir.statFile(entry.name) catch null;

        const color = try colorFromKind(dir, entry);

        const branch_symbol: []const u8 = if (i == items.len - 1) "└" else "├";

        var mode: std.posix.mode_t = 0;

        if (stat) |st| {
            mode = st.mode;
        }

        const sz = if (stat) |st| blk: {
            break :blk st.size;
        } else 0;

        try stdout.print(
            "{}{s}─ {c} {o:0>4} {:>8.2} ",

            .{
                core.ColorName.default,
                branch_symbol,
                inodeSymbol(entry.kind),
                mode & 0o7777,
                fmtIntSizeDec(sz),
            },
        );

        try stdout.print("{}{s}\n", .{
            color,
            entry.name,
        });
    }

    _ = try stdout.print("{}", .{core.ColorName.default});
}

fn prettyList(dir: std.fs.Dir, longest: usize, items: []const Entry, single_column: bool) !void {
    const stdout_file = std.io.getStdOut();
    const stdout = stdout_file.writer();

    const size = curses.terminalSize();

    const col_width = longest + 2;
    var col_num = if (!single_column) blk: {
        break :blk (size.w / col_width);
    } else 1;

    if (col_num < 1) col_num = 1;

    var files_per_col = (items.len / (col_num));
    if (items.len % col_num != 0) files_per_col += 1;

    var idx: usize = 0;
    var col: usize = 0;

    for (items) |entry| {
        const color = try colorFromKind(dir, entry);

        if (idx >= files_per_col) {
            col += 1;
            idx = 0;
            _ = try stdout.write("\r");
            curses.move(.up, files_per_col);
        }

        curses.move(.right, col * col_width);

        try stdout.print("{}{s}\n", .{
            color,
            entry.name,
        });

        idx += 1;
    }

    while (idx < files_per_col) : (idx += 1) {
        _ = try stdout.write("\n");
    }

    _ = try stdout.print("{}", .{core.ColorName.default});
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
        //.alphabetic => sort.sortByAlphabet({}, a.name, b.name),
        .alphabetic => sort.sortByAlphabetBytes({}, a.name, b.name),
        //        .size => blk: {
        //            const sz_a = if (a.stat != null) a.stat.?.size else 0;
        //            const sz_b = if (b.stat != null) b.stat.?.size else 0;
        //
        //            break :blk sz_a > sz_b;
        //        },
        .size => unreachable,
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
