const std = @import("std");
const core = @import("../main.zig");
const fg = core.fg;

pub const exec_mode: core.ExecMode = .fork;

pub const help = core.Help{
    .description = "print information about [USER] or the current user",
    .usage = "[-ugGnr] [USER]",
    .options = &.{
        .{ .flag = 'u', .description = "print UID" },
        .{ .flag = 'g', .description = "print GID" },
        .{ .flag = 'G', .description = "print all GIDs" },
    },
};

const IdType = enum {
    none,
    uid,
    gid,
    gids,
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

    const stdout = std.io.getStdOut().writer();

    var id_type: IdType = .none;

    var print_names = false;
    var username: ?[]const u8 = null;

    for (arguments) |arg| {
        if (arg == .positional) {
            // TODO error handling
            if (username != null) return error.UsageError;

            username = arg.positional;

            continue;
        }

        switch (arg.option) {
            'u' => id_type = .uid,
            'g' => id_type = .gid,
            'G' => id_type = .gids,
            'n' => print_names = true,

            else => return error.UsageError,
        }
    }

    if (id_type == .none) return error.UsageError;

    const idt = id_type;

    var uid: std.posix.uid_t = 0;
    var gid: std.posix.gid_t = 0;
    if (username == null) {
        uid = std.os.linux.geteuid();
        gid = std.os.linux.getegid();
    } else {
        var passwd_it = try PasswdIterator.init(allocator);
        defer passwd_it.deinit();

        var found = false;

        while (try passwd_it.next()) |entry| {
            if (std.mem.eql(u8, entry.username, username.?)) {
                uid = entry.uid;
                found = true;
                break;
            }
        }

        if (!found) {
            unreachable;
        }
    }

    if (idt == .gids) {
        var gids: [64]std.posix.gid_t = undefined;

        const gid_count = std.os.linux.getgroups(
            gids.len,
            @ptrCast(&gids),
        );

        stdout.print("{d}", .{
            gid,
        }) catch unreachable;

        for (gids[0..gid_count], 0..) |current_gid, idx| {
            if (gid_count != idx) {
                stdout.print(" ", .{}) catch {};
            }

            stdout.print("{d}", .{
                current_gid,
            }) catch {};
        }

        stdout.print("\n", .{}) catch {};

        return;
    }

    if (print_names) {
        var passwd_it = try PasswdIterator.init(allocator);
        defer passwd_it.deinit();

        while (try passwd_it.next()) |entry| {
            const id = uid;

            if (entry.uid != id) continue;

            try stdout.print("{s}\n", .{switch (idt) {
                .uid => entry.username,

                // TODO
                .gid => entry.username,
                else => unreachable,
            }});

            break;
        }

        return;
    }

    try stdout.print("{d}\n", .{switch (idt) {
        .uid => uid,
        .gid => gid,
        else => unreachable,
    }});

    return;
}

const PasswdIterator = struct {
    list: std.ArrayList(u8),
    file: std.fs.File,

    const Error = error{
        UnexpectedEndOfLine,
    };

    const PasswdEntry = struct {
        username: []const u8,
        password: []const u8,
        uid: std.posix.uid_t,
        gid: std.posix.gid_t,
        gecos: []const u8,
        home: []const u8,
        shell: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator) !PasswdIterator {
        return .{
            .list = std.ArrayList(u8).init(allocator),
            .file = try std.fs.cwd().openFile("/etc/passwd", .{}),
        };
    }

    pub fn deinit(it: *PasswdIterator) void {
        it.list.deinit();
        it.file.close();
    }

    pub fn next(it: *PasswdIterator) !?PasswdEntry {
        it.list.shrinkRetainingCapacity(0);
        const eol = Error.UnexpectedEndOfLine;

        try it.file.reader().streamUntilDelimiter(
            it.list.writer(),
            '\n',
            null,
        );

        var split = std.mem.splitScalar(u8, it.list.items, ':');

        return .{
            .username = split.next() orelse return eol,
            .password = split.next() orelse return eol,
            .uid = try std.fmt.parseInt(
                std.posix.uid_t,
                split.next() orelse return eol,
                10,
            ),
            .gid = try std.fmt.parseInt(
                std.posix.gid_t,
                split.next() orelse return eol,
                10,
            ),
            .gecos = split.next() orelse return eol,
            .home = split.next() orelse return eol,
            .shell = split.next() orelse return eol,
        };
    }
};

const GroupIterator = struct {
    list: std.ArrayList(u8),
    file: std.fs.File,

    const Error = error{
        UnexpectedEndOfLine,
    };

    const GroupEntry = struct {
        groupname: []const u8,
        password: []const u8,
        gid: u16,
        members: []const []const u8,
    };

    pub fn init(allocator: std.mem.Allocator) !GroupIterator {
        return .{
            .list = std.ArrayList(u8).init(allocator),
            .file = try std.fs.cwd().openFile("/etc/group", .{}),
        };
    }

    pub fn deinit(it: *GroupIterator) void {
        it.list.deinit();
        it.file.close();
    }

    pub fn next(it: *GroupIterator) !?GroupEntry {
        it.list.shrinkRetainingCapacity(0);
        const eol = Error.UnexpectedEndOfLine;

        var entry = GroupEntry{
            .groupname = undefined,
            .password = "",
            .gid = 69,
            .members = &.{},
        };

        try it.file.reader().streamUntilDelimiter(
            it.list.writer(),
            '\n',
            null,
        );

        var split = std.mem.split(u8, it.list.items, ":");

        entry.groupname = split.next() orelse return eol;
        entry.password = split.next() orelse return eol;
        entry.gid = try std.fmt.parseInt(
            u16,
            split.next() orelse return eol,
            10,
        );

        return entry;
    }
};
