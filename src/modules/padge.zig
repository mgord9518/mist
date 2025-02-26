const std = @import("std");
const shell = @import("../shell.zig");
const core = @import("../main.zig");

pub const exec_mode: core.ExecMode = .function;

pub const help = core.Help{
    .description = "manage MIST plugins",
    .usage = "<-liu> <PLUGIN_FILE>",
    .options = &.{
        .{ .flag = 'l', .description = "load plugin without installing" },
        .{ .flag = 'i', .description = "install and enable plugin" },
        .{ .flag = 'u', .description = "disable and uninstall plugin" },
    },
};

const State = enum {
    load,
    install,
    uninstall,
};

pub const main = core.genericMain(realMain);

fn realMain(argv: []const []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var maybe_state: ?State = null;

    var argument_list = std.ArrayList(core.Argument).init(allocator);
    defer argument_list.deinit();

    var it = core.ArgumentParser.init(argv);
    while (it.next()) |entry| {
        try argument_list.append(entry);
    }
    const arguments = argument_list.items;

    var targets = std.ArrayList([]const u8).init(allocator);
    defer targets.deinit();

    for (arguments) |arg| {
        if (arg == .option) {
            if (maybe_state) |_| return error.UsageError;

            switch (arg.option) {
                'l' => maybe_state = .load,
                'i' => maybe_state = .install,
                'u' => maybe_state = .uninstall,

                else => return error.UsageError,
            }
        }

        if (arg == .positional) {
            try targets.append(arg.positional);
        }
    }

    const state = maybe_state orelse return error.UsageError;

    for (targets.items) |target| {
        switch (state) {
            .load => {
                shell.debug(3, "loading plugin");

                const plugin = try core.Plugin.init(target);

                try core.plugin_list.put("loaded", plugin);

                shell.debug(3, "plugin loaded correctly");
            },
            .install => {
                var data_dir_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
                var mist_dir_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;

                const data_dir = std.posix.getenv("XDG_DATA_HOME") orelse blk: {
                    const home = std.posix.getenv("HOME") orelse return error.FileNotFound;
                    break :blk try std.fmt.bufPrint(&data_dir_buf, "{s}/.local/share", .{home});
                };

                const mist_dir = try std.fmt.bufPrint(&mist_dir_buf, "{s}/mist/plugins", .{data_dir});

                std.debug.print("dir: {s}\n", .{mist_dir});

                const cwd = std.fs.cwd();

                try cwd.makePath(mist_dir);

                var plugin_name_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
                const plugin_name = try std.fmt.bufPrint(
                    &plugin_name_buf,
                    "{s}/{s}",
                    .{ mist_dir, std.fs.path.basename(target) },
                );

                try cwd.rename(target, plugin_name);

                shell.debug(3, "installing plugin");
            },
            else => {},
        }
    }
}
