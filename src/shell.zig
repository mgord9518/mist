const std = @import("std");
const posix = std.posix;
const core = @import("main.zig");
const time = @import("time.zig");
const greeting = @embedFile("greeting");

pub const modules = core.modules;

const pipe = @import("shell/pipe.zig");
const parser = @import("shell/parser.zig");
const curses = @import("shell/curses.zig");
const History = @import("shell/History.zig");

pub const exec_mode: core.ExecMode = .fork;

pub var logical_path: []const u8 = undefined;
pub var logical_path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;

pub var debug_level: u2 = 3;

// 1st byte: identifier. `P` for procedure
// 2nd byte: u8, length of procedure name
// Next 2 bytes: LE u16, length of procedure
// Immediately followed by the procedure name, then the procedure contents
pub var shm: []align(std.mem.page_size) u8 = undefined;

pub const help = core.Help{
    .description = "minimal interactive shell. use `commands` for a list of built-in commands",
    .usage = "[SCRIPT]",
};

pub var variables: std.BufMap = undefined;
pub var procedures: std.BufMap = undefined;
pub var history: History = undefined;

pub const Command = struct {
    kind: enum {
        /// Module; source-only
        module,

        /// Plugin; loaded at runtime
        plugin,

        /// System command; anything that falls under `$PATH`
        system,
    },

    name: []const u8,
    arguments: []const []const u8 = &.{},
};

const Line = struct {
    pos: usize,
    contents: std.ArrayList(u8),

    fn stepForward(line: *Line) void {
        const remaining: u3 = utf8ContinueLen(line.contents.items[line.pos]);

        curses.move(.right, 1);
        line.pos += 1 + remaining;
    }

    fn stepBackward(line: *Line) void {
        if (line.pos > 0) {
            curses.move(.left, 1);
            line.pos -= 1;
        }

        while (line.pos < line.contents.items.len and line.contents.items.len > 0 and line.contents.items[line.*.pos] & 0b1100_0000 == 0b1000_0000) {
            line.pos -= 1;
        }
    }

    fn insert(line: *Line, string: []const u8) !void {
        for (string, 0..) |byte, idx| {
            _ = try line.contents.insert(
                line.pos + idx,
                byte,
            );
        }

        curses.insert(string);

        line.pos += string.len;
    }

    fn backspace(line: *Line) void {
        curses.backspace();
        line.pos -= 1;

        // Step back to start byte if needed
        while (line.contents.items[line.pos] & 0b1100_0000 == 0b1000_0000) {
            line.pos -= 1;
        }

        var remaining = utf8ContinueLen(line.contents.items[line.pos]);

        _ = line.contents.orderedRemove(line.pos);

        while (remaining > 0) : (remaining -= 1) {
            _ = line.contents.orderedRemove(line.pos);
        }
    }

    fn replaceWith(line: *Line, new_contents: []const u8) !void {
        line.contents.shrinkAndFree(0);
        try line.contents.appendSlice(new_contents);

        curses.restorePosition();
        curses.clearLine(.right);

        std.debug.print("{s}", .{line.contents.items});

        line.pos = line.contents.items.len;
    }

    // Tab-finish, auto-fills the "word" that contians the cursor if a matching
    // filename is found
    fn autoFinishWord(
        line: *Line,
        allocator: std.mem.Allocator,
    ) !void {
        var it = try parser.SyntaxIterator.init(
            allocator,
            line.contents.items,
        );
        defer it.deinit();

        var token_start: usize = 0;
        var word: []const u8 = "";

        while (try it.nextToken()) |token| {
            if (token != .string) {
                token_start = it.pos;
                continue;
            }

            if (line.pos < token_start or line.pos > it.pos) {
                allocator.free(token.string);
                continue;
            }

            token_start = it.pos;
            word = token.string;
        }

        const cwd = std.fs.cwd();
        var dir = cwd.openDir(
            parentPath(word),
            .{ .iterate = true },
        ) catch return;

        var basename = std.fs.path.basename(word);
        if (word.len > 0 and word[word.len - 1] == '/') basename = "";

        var dir_it = dir.iterate();
        while (try dir_it.next()) |entry| {
            if (entry.name.len < basename.len) continue;

            const start = entry.name[0..basename.len];

            if (!std.mem.eql(u8, start, basename)) continue;

            // TODO: Proper cursor placement when in middle of word
            try line.insert(entry.name[basename.len..]);

            if (entry.kind == .directory and line.contents.items[line.contents.items.len - 1] != '/') {
                try line.insert("/");
            }

            // TODO: allow selecting between all available
            break;
        }
    }
};

// Re-allocs a command
pub fn dupeCommand(allocator: std.mem.Allocator, command: Command) !Command {
    var kind = command.kind;
    if (core.module_list.get(command.name)) |_| {
        kind = .module;
    }

    if (core.plugin_list.get(command.name)) |_| {
        kind = .plugin;
    }

    var mod_args = std.ArrayList([]const u8).init(allocator);

    for (command.arguments) |arg| {
        try mod_args.append(arg);
    }

    return .{
        .kind = kind,
        .name = command.name,
        .arguments = mod_args.items,
    };
}

pub fn runLine(
    allocator: std.mem.Allocator,
    reader: anytype,
    line: []const u8,
    interactive: bool,
) !pipe.ChainRet {
    var arena = std.heap.ArenaAllocator.init(allocator);
    const arena_allocator = arena.allocator();
    defer arena.deinit();

    var pipe_line = std.ArrayList(
        Command,
    ).init(arena_allocator);
    defer pipe_line.deinit();

    var it = try parser.SyntaxIterator.init(
        arena_allocator,
        line,
    );
    defer it.deinit();

    // Parse the line text
    // Memory is freed between `next` calls, so commands must be copied
    // before being piped together
    while (try it.next()) |entry| {
        if (entry != .command) continue;

        const command = try dupeCommand(
            arena_allocator,
            entry.command,
        );

        try pipe_line.append(command);
    }

    const exit_status = try pipe.chainCommands(
        arena_allocator,
        reader,
        pipe_line.items,
    );

    if (interactive and exit_status.ret == .module_exit_failure) {
        const mod_name = pipe_line.items[exit_status.idx].name;

        if (exit_status.ret.module_exit_failure == .usage_error) {
            const mod = core.module_list.get(mod_name) orelse unreachable;
            core.printHelp(mod_name, mod.help) catch {};
        }
    }

    // Procedure set, lets read it
    if (shm[0] == 'P') {
        const name_len = shm[1];
        const name = shm[4..][0..name_len];
        const procedure_len_u8 = shm[2..4];
        const procedure_len: u16 = @bitCast(procedure_len_u8.*);
        const procedure = shm[4..][name_len..][0..procedure_len];

        procedures.put(
            name,
            procedure,
        ) catch unreachable;

        shm[0] = '\x00';
    }

    return exit_status;
}

pub fn nonInteractiveLoop(script_path: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const cwd = std.fs.cwd();
    var file = try cwd.openFile(script_path, .{});
    defer file.close();

    var buf: [4096]u8 = undefined;

    var previous_status: u8 = 0;
    var previous_status_name: ?[]const u8 = null;

    var line_num: usize = 1;

    var reader = file.reader();
    while (try reader.readUntilDelimiterOrEof(&buf, '\n')) |line| : (line_num += 1) {
        var code_buf: [3]u8 = undefined;

        variables.put(
            "mist.exit_code",
            std.fmt.bufPrint(
                &code_buf,
                "{d}",
                .{previous_status},
            ) catch unreachable,
        ) catch {};

        if (previous_status_name) |name| {
            variables.put("mist.status.name", name) catch {};
        } else {
            _ = variables.remove("mist.status.name");
        }

        const exit_status = runLine(
            allocator,
            reader,
            line,
            false,
        ) catch unreachable;

        previous_status_name = statusName(exit_status.ret);
        previous_status = statusCode(exit_status.ret);

        const command_name = "FIXME";

        if (previous_status_name) |err_name| {
            printError(
                "{s} {s}\n",
                line_num,
                exit_status.idx,
                .{ command_name, err_name },
            );
        } else if (previous_status != 0) {
            printError(
                "{s} exit code: {d}\n",
                line_num,
                exit_status.idx,
                .{ command_name, previous_status },
            );
        }
    }
}

pub fn interactiveLoop() !void {
    try curses.setTerminalMode(.raw);
}

pub fn printError(
    comptime fmt: []const u8,
    line_num: usize,
    sep_idx: usize,
    args: anytype,
) void {
    std.debug.print(
        "{}{d:>3} | {d} :: {}",
        .{ core.ColorName.red, line_num, sep_idx, core.ColorName.default },
    );

    std.debug.print(
        fmt,
        args,
    );
}

pub fn debug(level: u2, str: []const u8) void {
    if (level > debug_level) return;

    switch (debug_level) {
        0 => {},
        3 => {
            std.debug.print("{}::{} {s}{}\n", .{ core.ColorName.cyan, core.ColorName.default, str, core.ColorName.default });
        },
        2 => {
            std.debug.print("{}::{} {s}{}\n", .{ core.ColorName.yellow, core.ColorName.default, str, core.ColorName.default });
        },
        1 => {
            std.debug.print("{}::{} {s}{}\n", .{ core.ColorName.red, core.ColorName.default, str, core.ColorName.default });
        },
    }
}

fn handleInput(
    allocator: std.mem.Allocator,
    print_prompt: *bool,
    current_line: *Line,
    restart: *bool,
    history_cursor: *usize,
    print_handled: *bool,
) !bool {
    const stdout_file = std.io.getStdOut();
    const stdout = stdout_file.writer();

    var char = readCodepoint() catch unreachable;

    switch (char) {
        '\n' => {
            try stdout.print("\n", .{});
            print_prompt.* = true;
            current_line.*.pos = 0;

            if (current_line.*.contents.items.len == 0) return false;
            if (std.mem.eql(
                u8,
                current_line.*.contents.items,
                history.last() orelse "",
            )) return false;

            try history.append(
                try history.allocator.dupe(u8, current_line.*.contents.items),
            );

            return false;
        },
        // Ctrl+l
        '\x0c' => {
            _ = modules.clear.main(&.{});
            print_prompt.* = true;
            restart.* = true;
            return false;
        },
        // Backspace
        '\x7f' => {
            print_handled.* = true;
            if (current_line.*.pos > 0) {
                current_line.*.backspace();
            }
        },
        '\t' => {
            print_handled.* = true;
            try current_line.*.autoFinishWord(
                allocator,
            );
        },
        else => {},
    }

    print_prompt.* = false;

    // ANSI control
    if (char == '\x1b') {
        print_handled.* = true;

        _ = getChar();

        char = readCodepoint() catch unreachable;
        switch (char) {
            // Up arrow
            'A' => {
                if (history_cursor.* >= history.list.items.len) return true;
                history_cursor.* += 1;

                try current_line.*.replaceWith(history.list.items[history.list.items.len - history_cursor.*]);

                return true;
            },
            // Down arrow
            'B' => {
                if (history_cursor.* > 0) history_cursor.* -= 1;

                current_line.*.contents.shrinkAndFree(0);

                if (history_cursor.* > 0) {
                    try current_line.*.contents.appendSlice(history.list.items[history.list.items.len - history_cursor.*]);
                    //try current_line.*.insert(history.list.items[history.list.items.len - history_cursor.*]);
                }

                curses.restorePosition();
                curses.clearLine(.right);

                try stdout.print("{s}", .{current_line.*.contents.items});
                current_line.*.pos = current_line.*.contents.items.len;
                return true;
            },
            'C' => {
                if (current_line.*.pos < current_line.*.contents.items.len) {
                    current_line.*.stepForward();
                }

                return true;
            },
            'D' => {
                current_line.stepBackward();

                return true;
            },
            else => {},
        }
    }

    // Insert a single UTF-8 codepoint
    if (!print_handled.*) {
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(char, &buf) catch unreachable;

        const size = curses.terminalSize();
        _ = size;

        try current_line.*.insert(buf[0..len]);
    }

    return true;
}

fn init(_: std.mem.Allocator) !void {
    const stdout_file = std.io.getStdOut();
    const stdout = stdout_file.writer();

    const cwd = std.fs.cwd();

    shm = std.posix.mmap(
        null,
        4096,
        std.posix.PROT.READ | std.posix.PROT.WRITE,
        .{ .TYPE = .SHARED, .ANONYMOUS = true },
        -1,
        0,
    ) catch unreachable;

    // TODO: support multiple plugins paths
    if (std.posix.getenv("MIST_PLUGIN_PATH")) |plugin_path| {
        var plugin_dir = try cwd.openDir(plugin_path, .{ .iterate = true });

        var it = plugin_dir.iterate();
        while (try it.next()) |entry| {
            std.debug.print("ent: {s}\n", .{entry.name});
        }
    } else {
        debug(2, "environment variable `MIST_PLUGIN_PATH` not set, no plugins will be automatically loaded");
    }

    core.usagePrint(stdout, greeting) catch unreachable;
}

fn deinit(_: std.mem.Allocator) void {
    std.posix.munmap(shm);
}

pub fn main(arguments: []const []const u8) core.Error {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    init(allocator) catch unreachable;
    defer deinit(allocator);

    var stdin_file = std.io.getStdIn();

    var target: ?[]const u8 = null;
    for (arguments) |arg| {
        target = arg;
    }

    logical_path = std.posix.getcwd(
        &logical_path_buf,
    ) catch return .cwd_not_found;

    variables = std.BufMap.init(allocator);
    defer variables.deinit();

    variables.put("mist.exit_code", "0") catch {};

    procedures = std.BufMap.init(allocator);
    defer procedures.deinit();

    if (target) |script_path| {
        variables.put(
            "0",
            script_path,
        ) catch {};

        nonInteractiveLoop(script_path) catch unreachable;
        return .success;
    }

    core.disableSig(.interrupt) catch unreachable;
    core.disableSig(.quit) catch unreachable;

    var print_prompt = true;

    // TODO: history limit
    history = History.init(allocator);
    defer history.deinit();

    var previous_status: u8 = 0;
    var previous_status_name: ?[]const u8 = null;

    // Main loop
    while (true) {
        interactiveLoop() catch return .unknown_error;

        var buf: [3]u8 = undefined;

        variables.put(
            "mist.status",
            std.fmt.bufPrint(
                &buf,
                "{d}",
                .{previous_status},
            ) catch unreachable,
        ) catch {};

        if (previous_status_name) |name| {
            variables.put("mist.status.name", name) catch {};
        } else {
            _ = variables.remove("mist.status.name");
        }

        // How many entries to travel up the history
        var history_cursor: usize = 0;

        if (print_prompt) {
            _ = modules.prompt.main(&.{});
            curses.savePosition();
        }

        var line = std.ArrayList(u8).init(allocator);
        defer line.deinit();

        var current_line = Line{
            .contents = line,
            .pos = 0,
        };

        var restart = false;
        var should_continue = true;

        while (should_continue) {
            var print_handled = false;

            should_continue = handleInput(
                allocator,
                &print_prompt,
                &current_line,
                &restart,
                &history_cursor,
                &print_handled,
            ) catch unreachable;
        }

        if (restart) continue;

        curses.setTerminalMode(.normal) catch return .unknown_error;

        const exit_status = runLine(
            allocator,
            stdin_file.reader(),
            current_line.contents.items,
            true,
        ) catch unreachable;

        variables.put(
            "mist.status.index",
            std.fmt.bufPrint(
                &buf,
                "{d}",
                .{exit_status.idx},
            ) catch unreachable,
        ) catch {};

        previous_status_name = statusName(exit_status.ret);
        previous_status = statusCode(exit_status.ret);
    }
}

fn parentPath(path: []const u8) []const u8 {
    if (path.len == 0) return ".";

    if (path[path.len - 1] == '/') return path;

    if (std.fs.path.dirname(path) == null) {
        if (path[path.len - 1] == '/') return path;

        return ".";
    }

    return std.fs.path.dirname(path).?;
}

pub fn statusCode(
    exec_status: pipe.ChainRet.Return,
) u8 {
    return switch (exec_status) {
        .success => 0,
        .signal => |signal| @as(u8, @intFromEnum(signal)) + 127,
        .exec_failure => 127,
        .exit_code => |exit_code| exit_code,
        .module_exit_failure => |err| @intFromEnum(err),
    };
}

pub fn statusName(
    exec_status: pipe.ChainRet.Return,
) ?[]const u8 {
    return switch (exec_status) {
        .success => null,
        .signal => |signal| @tagName(signal),
        .exec_failure => |code| @tagName(code),
        .module_exit_failure => |err| {
            if (err == .success) return null;

            return std.enums.tagName(@TypeOf(err), err) orelse "unknown_error";
        },
        .exit_code => null,
    };
}

fn utf8ContinueLen(byte: u8) u2 {
    return switch (byte >> 4) {
        0b1100 => 1,
        0b1110 => 2,
        0b1111 => 3,

        else => 0,
    };
}

fn getChar() u8 {
    const stdin = std.io.getStdIn().reader();

    var buf: [1]u8 = undefined;
    _ = stdin.read(&buf) catch {
        std.debug.print("getChar FAIL {d} `{c}`\n", .{ buf[0], buf[0] });
        unreachable;
    };

    return buf[0];
}

fn readCodepoint() !u21 {
    const char = getChar();

    var utf8_buf: [4]u8 = undefined;
    utf8_buf[0] = char;

    const continue_len: u3 = utf8ContinueLen(char);

    for (utf8_buf[1..][0..continue_len], 1..) |_, idx| {
        utf8_buf[idx] = getChar();
    }

    return std.unicode.utf8Decode(utf8_buf[0 .. continue_len + 1]);
}
