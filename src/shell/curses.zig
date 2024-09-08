const std = @import("std");
const core = @import("../../main.zig");

pub const modules = core.modules;
const fg = core.fg;

pub const Direction = enum(u8) {
    up = 'A',
    down = 'B',
    right = 'C',
    left = 'D',
};

pub fn move(direction: Direction, spaces: usize) void {
    const stdout = std.io.getStdOut().writer();

    if (spaces == 0) return;

    if (spaces == 1) {
        stdout.print("\x1b[{c}", .{@intFromEnum(direction)}) catch {};
    } else {
        stdout.print("\x1b[{d}{c}", .{ spaces, @intFromEnum(direction) }) catch {};
    }
}

pub fn toLineStart() void {
    const stdout = std.io.getStdOut().writer();
    stdout.print("\r", .{}) catch {};
}

pub fn savePosition() void {
    const stdout = std.io.getStdOut().writer();
    stdout.print("\x1b[s", .{}) catch {};
}

pub fn restorePosition() void {
    const stdout = std.io.getStdOut().writer();
    stdout.print("\x1b[u", .{}) catch {};
}

pub fn toLineEnd() void {
    // TODO: Utilize explicit escape code if the terminal supports it
    move(.right, 999);
}

pub fn insert(text: []const u8) void {
    const stdout = std.io.getStdOut().writer();

    if (text.len == 0) return;

    if (text.len == 1) {
        stdout.print("\x1b[@{s}", .{text}) catch {};
    } else {
        stdout.print("\x1b[{d}@{s}", .{ text.len, text }) catch {};
    }
}

pub fn backspace() void {
    const stdout = std.io.getStdOut().writer();

    // `x08` shifts cursor left, `x1b[P` deletes the char
    // at the cursor's location, shifting all characters in front back
    //stdout.print("\x08\x1b[P", .{}) catch {};
    move(.left, 1);
    stdout.print("\x1b[P", .{}) catch {};
}

pub const ClearMode = enum(u8) {
    right = '0',
    left = '1',
    all = '2',
};

pub fn clearLine(mode: ClearMode) void {
    const stdout = std.io.getStdOut().writer();

    stdout.print("\x1b[{c}K", .{@intFromEnum(mode)}) catch {};
}

pub const TerminalMode = enum {
    normal,
    raw,
};

pub fn setTerminalMode(mode: TerminalMode) !void {
    var term_info = try std.posix.tcgetattr(
        std.posix.STDIN_FILENO,
    );

    switch (mode) {
        .normal => {
            term_info.lflag.ECHO = true;
            term_info.lflag.ICANON = true;
        },
        .raw => {
            term_info.lflag.ECHO = false;
            term_info.lflag.ICANON = false;
        },
    }

    try std.posix.tcsetattr(
        std.posix.STDIN_FILENO,
        .NOW,
        term_info,
    );
}

fn setTerminalToNormalMode() !void {
    var term_info = try std.posix.tcgetattr(
        std.posix.STDIN_FILENO,
    );

    term_info.lflag.ECHO = true;
    term_info.lflag.ICANON = true;

    try std.posix.tcsetattr(
        std.posix.STDIN_FILENO,
        .NOW,
        term_info,
    );
}

fn setTerminalToRawMode() !void {
    var term_info = try std.posix.tcgetattr(
        std.posix.STDIN_FILENO,
    );

    term_info.lflag.ECHO = false;
    term_info.lflag.ICANON = false;

    try std.posix.tcsetattr(
        std.posix.STDIN_FILENO,
        .NOW,
        term_info,
    );
}

pub const Size = struct {
    w: u16,
    h: u16,
};

pub fn terminalSize() Size {
    var ioctl: std.posix.system.winsize = undefined;
    _ = std.posix.system.ioctl(
        std.posix.STDOUT_FILENO,
        std.posix.T.IOCGWINSZ,
        @intFromPtr(&ioctl),
    );

    return .{
        .w = ioctl.ws_col,
        .h = ioctl.ws_row,
    };
}
