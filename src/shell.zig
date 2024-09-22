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
const fg = core.fg;

pub const exec_mode: core.ExecMode = .fork;

pub var logical_path: []const u8 = undefined;
pub var logical_path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;

// 1st byte: identifier. `P` for procedure
// 2nd byte: u8, length of procedure name
// Next 2 bytes: LE u16, length of procedure
pub var shm: []align(std.mem.page_size) u8 = undefined;

pub const help = core.Help{
    .description = "minimal interactive shell. use `commands` for a list of built-in commands",
    .usage = "[SCRIPT]",
};

pub var variables: std.BufMap = undefined;
pub var procedures: std.BufMap = undefined;
pub var history: History = undefined;

pub const Command = union(enum) {
    /// Module; may be a shell builtin or any other command implemented in the
    /// `src/modules` directory
    module: struct {
        name: []const u8,
        arguments: []const core.Argument = &.{},
    },

    /// System command; anything that falls under `$PATH`
    system: struct {
        name: []const u8,
        arguments: []const []const u8 = &.{},
    },
};

// Re-allocs a command and converts it to a module if needed
pub fn processCommand(allocator: std.mem.Allocator, command: Command) !Command {
    // Convert to module command if it exists
    if (core.module_list.get(command.system.name)) |_| {
        // TODO free
        var mod_args = std.ArrayList(core.Argument).init(allocator);

        var mod_it = core.ArgumentParser.init(command.system.arguments);

        while (mod_it.next()) |arg| {
            try mod_args.append(arg);
        }

        return .{
            .module = .{
                .name = command.system.name,
                .arguments = mod_args.items,
            },
        };
    }

    if (command == .system) {
        var mod_args = std.ArrayList([]const u8).init(allocator);

        for (command.system.arguments) |arg| {
            try mod_args.append(arg);
        }

        return Command{
            .system = .{
                .name = command.system.name,
                .arguments = mod_args.items,
            },
        };
    }

    unreachable;
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

        const command = try processCommand(
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
        const mod_name = pipe_line.items[exit_status.idx].module.name;

        if (exit_status.ret.module_exit_failure == .usage_error) {
            const mod = core.module_list.get(mod_name) orelse unreachable;
            core.printHelp(mod_name, mod.help) catch {};
        }
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
            //file.reader(),
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

pub fn printError(
    comptime fmt: []const u8,
    line_num: usize,
    sep_idx: usize,
    args: anytype,
) void {
    std.debug.print(
        fg(.red) ++ "{d:>3} | {d} :: " ++ fg(.default),
        .{ line_num, sep_idx },
    );

    std.debug.print(
        fmt,
        args,
    );
}

pub fn main(arguments: []const core.Argument) core.Error {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const stdout_file = std.io.getStdOut();
    const stdout = stdout_file.writer();

    var stdin_file = std.io.getStdIn();

    var target: ?[]const u8 = null;
    for (arguments) |arg| {
        if (arg == .option) return .usage_error;

        if (arg == .positional) {
            target = arg.positional;
        }
    }

    logical_path = std.posix.getcwd(
        &logical_path_buf,
    ) catch return .cwd_not_found;

    variables = std.BufMap.init(allocator);
    defer variables.deinit();

    variables.put("mist.exit_code", "0") catch {};

    procedures = std.BufMap.init(allocator);
    defer procedures.deinit();

    procedures.put(
        "TEST",
        "print hi",
    ) catch unreachable;

    if (target) |script_path| {
        variables.put(
            "0",
            script_path,
        ) catch {};

        nonInteractiveLoop(script_path) catch unreachable;
        return .success;
    }

    core.usagePrint(stdout, greeting) catch unreachable;

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
        curses.setTerminalMode(.raw) catch return .unknown_error;

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

        var cursor_pos: usize = 0;
        var vcursor_pos: usize = 0;

        var restart = false;

        while (true) {
            var print_handled = false;

            var char = getChar();

            if (char == '\n') {
                stdout.print("\n", .{}) catch return .unknown_error;
                print_prompt = true;
                cursor_pos = 0;
                vcursor_pos = 0;

                if (line.items.len == 0) break;
                if (std.mem.eql(
                    u8,
                    line.items,
                    history.last() orelse "",
                )) break;

                history.append(
                    history.allocator.dupe(u8, line.items) catch return .unknown_error,
                ) catch return .unknown_error;

                break;
            }

            // Ctrl+l
            if (char == '\x0c') {
                _ = modules.clear.main(&.{});
                print_prompt = true;
                restart = true;
                break;
            }

            print_prompt = false;

            // Backspace
            if (char == '\x7f') {
                print_handled = true;
                if (cursor_pos > 0) {
                    curses.backspace();
                    cursor_pos -= 1;
                    vcursor_pos -= 1;

                    // Step back to start byte if needed
                    while (line.items[cursor_pos] & 0b1100_0000 == 0b1000_0000) {
                        cursor_pos -= 1;
                    }

                    var remaining = utf8ContinueLen(line.items[cursor_pos]);

                    _ = line.orderedRemove(cursor_pos);

                    while (remaining > 0) : (remaining -= 1) {
                        _ = line.orderedRemove(cursor_pos);
                    }
                }
            }

            if (char == '\t') {
                print_handled = true;
                autoFinishLine(
                    allocator,
                    line.items,
                    cursor_pos,
                ) catch unreachable;
            }

            // ANSI control
            if (char == '\x1b') {
                print_handled = true;

                _ = getChar();

                char = getChar();
                switch (char) {
                    // Up arrow
                    'A' => {
                        if (history_cursor >= history.list.items.len) continue;
                        history_cursor += 1;

                        line.shrinkAndFree(0);
                        line.appendSlice(history.list.items[history.list.items.len - history_cursor]) catch return .unknown_error;

                        curses.restorePosition();
                        curses.clearLine(.right);

                        stdout.print("{s}", .{line.items}) catch return .unknown_error;

                        cursor_pos = line.items.len;
                        vcursor_pos = line.items.len;
                        continue;
                    },
                    // Down arrow
                    'B' => {
                        //if (history_cursor <= 1) continue;
                        if (history_cursor > 0) history_cursor -= 1;

                        line.shrinkAndFree(0);

                        if (history_cursor > 0) {
                            line.appendSlice(history.list.items[history.list.items.len - history_cursor]) catch return .unknown_error;
                        }

                        curses.restorePosition();
                        curses.clearLine(.right);

                        stdout.print("{s}", .{line.items}) catch return .unknown_error;
                        cursor_pos = line.items.len;
                        vcursor_pos = line.items.len;
                        continue;
                    },
                    'C' => {
                        if (cursor_pos < line.items.len) {
                            const remaining: u3 = utf8ContinueLen(line.items[cursor_pos]);

                            curses.move(.right, 1);
                            cursor_pos += 1 + remaining;
                            vcursor_pos += 1 + remaining;
                        }

                        continue;
                    },
                    'D' => {
                        if (cursor_pos > 0) {
                            curses.move(.left, 1);
                            cursor_pos -= 1;
                            vcursor_pos -= 1;
                        }

                        // Step back to start byte if needed
                        while (cursor_pos < line.items.len and line.items.len > 0 and line.items[cursor_pos] & 0b1100_0000 == 0b1000_0000) {
                            cursor_pos -= 1;
                        }

                        continue;
                    },
                    else => {},
                }
            }

            // Insert a single codepoint
            if (!print_handled) {
                var utf8_buf: [4]u8 = undefined;
                utf8_buf[0] = char;

                const continue_len: u3 = utf8ContinueLen(char);
                for (utf8_buf[1..][0..continue_len], 1..) |_, idx| {
                    utf8_buf[idx] = getChar();
                }

                const codepoint = utf8_buf[0 .. continue_len + 1];

                for (codepoint, 0..) |byte, idx| {
                    _ = line.insert(
                        cursor_pos + idx,
                        byte,
                    ) catch return .unknown_error;
                }

                curses.insert(codepoint);

                cursor_pos += continue_len + 1;
                vcursor_pos += 1;
            }
        }

        if (restart) continue;

        curses.setTerminalMode(.normal) catch return .unknown_error;

        const exit_status = runLine(
            allocator,
            stdin_file.reader(),
            line.items,
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

fn autoFinishLine(
    allocator: std.mem.Allocator,
    line: []const u8,
    cursor_pos: usize,
) !void {
    const cwd = std.fs.cwd();
    var dir = try cwd.openDir(".", .{ .iterate = true });

    var it = try parser.SyntaxIterator.init(
        allocator,
        line,
    );
    defer it.deinit();

    var token_start: usize = 0;
    while (try it.nextToken()) |token| {
        if (token != .string) {
            token_start = it.pos;
            continue;
        }

        if (cursor_pos < token_start) continue;
        if (cursor_pos > it.pos) continue;

        const word = token.string;

        var dir_it = dir.iterate();
        while (try dir_it.next()) |entry| {
            if (entry.name.len < word.len) continue;

            if (std.mem.eql(u8, entry.name[0..word.len], word)) {
                std.debug.print("\nls {s}", .{
                    entry.name,
                });
            }
        }

        allocator.free(word);

        token_start = it.pos;
    }
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
        .exec_failure => "command_not_found",
        .module_exit_failure => |err| {
            if (err == .success) return null;

            return @tagName(err);
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
