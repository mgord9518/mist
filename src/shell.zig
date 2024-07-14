const std = @import("std");
const posix = std.posix;
const core = @import("main.zig");
const usage_print = core.usage_print;
const time = @import("time.zig");
const greeting = @embedFile("greeting");

pub const modules = core.modules;
pub const VariableMap = @import("shell/VariableMap.zig");

const pipe = @import("shell/pipe.zig");
const parser = @import("shell/parser.zig");
const cursor = @import("shell/curses.zig");
const History = @import("shell/History.zig");
const fg = core.fg;

pub const exec_mode: core.ExecMode = .fork;

pub var logical_path: []const u8 = undefined;
pub var logical_path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;

pub const help = core.Help{
    .description = "minimal interactive shell. use `commands` for a list of built-in commands",
    .usage = core.usage_print("[SCRIPT]"),
};

pub var variables: VariableMap = undefined;
pub var aliases: std.StringHashMap(Command) = undefined;
pub var history: History = undefined;

pub const Command = union(enum) {
    /// Module; may be a shell builtin or any other command implemented in the
    /// `src/modules` directory
    module: struct {
        name: []const u8,
        arguments: []const core.Argument,
    },

    /// System command; anything that falls under `$PATH`
    system: struct {
        name: []const u8,
        arguments: ?[]const []const u8 = null,
    },
};

pub fn nonInteractiveLoop(script_path: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const cwd = std.fs.cwd();
    var file = try cwd.openFile(script_path, .{});
    defer file.close();

    var buf: [4096]u8 = undefined;

    var previous_status: u8 = 0;
    var previous_status_name: ?[]const u8 = null;

    var reader = file.reader();
    while (try reader.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        var arena = std.heap.ArenaAllocator.init(allocator);
        const arena_allocator = arena.allocator();
        defer arena.deinit();

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
            variables.put("mist.exit_code_name", name) catch {};
        } else {
            _ = variables.remove("mist.exit_code_name");
        }

        var pipe_line = std.ArrayList(
            Command,
        ).init(allocator);
        defer pipe_line.deinit();

        var it = try parser.SyntaxIterator.init(
            //allocator,
            arena_allocator,
            line,
        );

        var print_help: ?core.Help = null;
        var print_help_name: []const u8 = &.{};

        // Parse the line text
        while (try it.next()) |entry| {
            if (entry != .command) continue;

            const command = aliases.get(
                entry.command.system.name,
            ) orelse entry.command;

            var added = false;

            // Convert to module command if it exists
            if (core.module_list.get(command.system.name)) |mod| {
                // TODO free
                var mod_args = std.ArrayList(core.Argument).init(allocator);

                if (command.system.arguments != null) {
                    var mod_it = core.ArgumentParser.init(command.system.arguments.?);

                    while (mod_it.next()) |arg| {
                        try mod_args.append(arg);

                        if (arg == .option and arg.option.flag == 'h') {
                            print_help = mod.help;
                            print_help_name = command.system.name;
                        }
                    }
                }

                try pipe_line.append(.{
                    .module = .{
                        .name = command.system.name,
                        .arguments = mod_args.items,
                    },
                });

                added = true;
            }

            if (added) continue;
            try pipe_line.append(command);
        }

        if (pipe_line.items.len == 0) continue;

        const exit_status = pipe.chainCommands(
            allocator,
            pipe_line.items,
        ) catch unreachable;

        previous_status_name = statusName(
            exit_status.ret,
        );

        previous_status = statusCode(
            exit_status.ret,
        );

        if (previous_status_name) |err_name| {
            core.printError("{s}\n", .{err_name});
        }
    }
}

pub fn main(arguments: []const core.Argument) core.Error {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const stdout_file = std.io.getStdOut();
    const stdout = stdout_file.writer();

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

    variables = VariableMap.init(allocator);
    defer variables.deinit();

    variables.put("mist.exit_code", "0") catch {};

    if (target) |script_path| {
        nonInteractiveLoop(script_path) catch unreachable;
        return .success;
    }

    _ = stdout.write(comptime usage_print(greeting)) catch unreachable;

    aliases = std.StringHashMap(Command).init(allocator);
    defer aliases.deinit();
    aliases.put(
        "bruh",
        .{ .system = .{ .name = "echo" } },
    ) catch {};

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
        setTerminalToRawMode() catch return .unknown_error;

        var arena = std.heap.ArenaAllocator.init(allocator);
        const arena_allocator = arena.allocator();
        defer arena.deinit();

        var buf: [3]u8 = undefined;

        variables.put(
            "mist.exit_code",
            std.fmt.bufPrint(
                &buf,
                "{d}",
                .{previous_status},
            ) catch unreachable,
        ) catch {};

        if (previous_status_name) |name| {
            variables.put("mist.exit_code_name", name) catch {};
        } else {
            _ = variables.remove("mist.exit_code_name");
        }

        // How many entries to travel up the history
        var history_cursor: usize = 0;

        var pipe_line = std.ArrayList(
            Command,
        ).init(allocator);
        defer pipe_line.deinit();

        if (print_prompt) {
            _ = modules.prompt.main(&.{});
        }

        var line = std.ArrayList(u8).init(allocator);
        defer line.deinit();

        // Use Unicode codepoints instead of UTF-8 due to easier indexing
        var line_text = std.ArrayList(u21).init(allocator);
        defer line_text.deinit();

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
                    cursor.backspace();
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

            if (char == '\t') print_handled = true;

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

                        cursor.move(.left, vcursor_pos);
                        stdout.print("\x1b[0K", .{}) catch return .unknown_error;

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

                        cursor.move(.left, cursor_pos);
                        cursor.clearLine(.right);

                        stdout.print("{s}", .{line.items}) catch return .unknown_error;
                        cursor_pos = line.items.len;
                        vcursor_pos = line.items.len;
                        continue;
                    },
                    'C' => {
                        if (cursor_pos < line.items.len) {
                            const remaining = utf8ContinueLen(line.items[cursor_pos]);

                            cursor.move(.right, 1);
                            cursor_pos += 1 + remaining;
                            vcursor_pos += 1 + remaining;
                        }

                        continue;
                    },
                    'D' => {
                        if (cursor_pos > 0) {
                            cursor.move(.left, 1);
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

                var idx: usize = 0;

                while (idx <= continue_len) : (idx += 1) {
                    _ = line.insert(cursor_pos + idx, utf8_buf[idx]) catch return .unknown_error;
                }

                cursor.savePosition();
                // Print updated line
                stdout.print("{s}", .{line.items[cursor_pos..]}) catch return .unknown_error;

                cursor_pos += continue_len + 1;
                vcursor_pos += 1;

                // Return to cursor position
                cursor.restorePosition();
                cursor.move(.right, 1);
            }
        }

        if (restart) continue;

        var it = parser.SyntaxIterator.init(
            arena_allocator,
            line.items,
        ) catch return .unknown_error;
        defer it.deinit();

        var print_help: ?core.Help = null;
        var print_help_name: []const u8 = &.{};

        // Parse the line text
        while (it.next() catch return .unknown_error) |entry| {
            if (entry != .command) continue;

            const command = aliases.get(
                entry.command.system.name,
            ) orelse entry.command;

            var added = false;
            // Convert to module command if it exists
            if (core.module_list.get(command.system.name)) |mod| {
                // TODO free
                var mod_args = std.ArrayList(core.Argument).init(allocator);

                if (command.system.arguments != null) {
                    var mod_it = core.ArgumentParser.init(command.system.arguments.?);

                    while (mod_it.next()) |arg| {
                        mod_args.append(arg) catch unreachable;

                        if (arg == .option and arg.option.flag == 'h') {
                            print_help = mod.help;
                            print_help_name = command.system.name;
                        }
                    }
                }

                pipe_line.append(.{
                    .module = .{
                        .name = command.system.name,
                        .arguments = mod_args.items,
                    },
                }) catch unreachable;

                added = true;
            }

            if (added) continue;

            pipe_line.append(command) catch return .unknown_error;
        }

        if (print_help) |h| {
            core.printHelp(print_help_name, h) catch return .unknown_error;
            previous_status = 0;
            continue;
        }

        if (pipe_line.items.len == 0) continue;

        setTerminalToNormalMode() catch return .unknown_error;

        previous_status = 0;
        previous_status_name = null;

        const exit_status = pipe.chainCommands(
            allocator,
            pipe_line.items,
        ) catch unreachable;

        previous_status_name = statusName(
            exit_status.ret,
        );

        previous_status = statusCode(
            exit_status.ret,
        );

        if (exit_status.ret == .module_exit_failure) {
            const mod_name = pipe_line.items[exit_status.idx].module.name;

            if (exit_status.ret.module_exit_failure == .usage_error) {
                const mod = core.module_list.get(mod_name) orelse unreachable;
                core.printHelp(mod_name, mod.help) catch {};
            }
        }

        //if (exit_status.ret == .status and pipe_line.items[exit_status.idx] == .module) {

        //}
    }
}

fn statusCode(
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

fn statusName(
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
