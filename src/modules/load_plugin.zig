const std = @import("std");
const core = @import("../main.zig");

pub const exec_mode: core.ExecMode = .function;

pub const help = core.Help{
    .description = "load a plugin file",
    .usage = "[NAME] <MIST_PLUGIN>",
};

// TODO numeric comparison

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

    var current_target: ?[]const u8 = null;
    for (arguments) |arg| {
        if (arg == .option) return error.UsageError;

        if (current_target != null and !std.mem.eql(
            u8,
            arg.positional,
            current_target.?,
        )) {
            return error.NotEqual;
        }

        current_target = arg.positional;
    }

    var dl = try std.DynLib.open(current_target.?);

    const dl_main = dl.lookup(core.PluginMain, "_MIST_PLUGIN_1_0_MAIN").?;

    try core.plugin_list.put("loaded", dl_main);

    return;
}
