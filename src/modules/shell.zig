const std = @import("std");
const posix = std.posix;
const core = @import("../main.zig");

pub const modules = core.modules;
const pipe = @import("shell/pipe.zig");
const parser = @import("shell/parser.zig");
const cursor = @import("shell/curses.zig");
const History = @import("shell/History.zig");
const Int = std.math.big.int.Managed;
const fg = core.fg;

pub const exec_mode: core.ExecMode = .fork;

pub var logical_path: []const u8 = undefined;
pub var logical_path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;

// Shared memory so that a child thread can communicate errors
pub var child_error: *std.meta.Int(.unsigned, @bitSizeOf(anyerror)) = undefined;

pub const help = core.Help{
    .description = "minimal interactive shell. use `commands` for a list of built-in commands",
    //.usage = "",
    .usage = "{0s}",
    .options = &.{
        .{
            .flag = 'a',
            .description = "bruh",
        },
    },

    .exit_codes = &.{},
};

const Error = enum(u8) {
    success = 0,
    unknown_error = 1,
    usage_error = 2,
    not_found = 3,
};

// Simple wrapper around `StringHashMap` to automatically manage string memory
pub const VariableMap = struct {
    map: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) VariableMap {
        return .{ .map = std.StringHashMap([]const u8).init(allocator) };
    }

    pub fn deinit(self: *VariableMap) void {
        var it = self.map.keyIterator();

        while (it.next()) |key| {
            _ = self.remove(key.*);
        }

        self.map.deinit();
    }

    pub fn get(self: *VariableMap, name: []const u8) ?[]const u8 {
        return self.map.get(name);
    }

    pub fn put(self: *VariableMap, name: []const u8, value: []const u8) !void {
        const key = if (self.map.get(name)) |s| blk: {
            self.map.allocator.free(s);

            break :blk name;
        } else try self.map.allocator.dupe(u8, name);

        // TODO TYPE
        return try self.map.put(
            key,
            try self.map.allocator.dupe(u8, value),
        );
    }

    pub fn remove(self: *VariableMap, name: []const u8) bool {
        const key = self.map.getKey(name) orelse return false;
        const value = self.map.get(key) orelse unreachable;

        const ret = self.map.remove(key);
        self.map.allocator.free(key);
        self.map.allocator.free(value);

        return ret;
    }
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
            "mash::exit_code",
            std.fmt.bufPrint(
                &code_buf,
                "{d}",
                .{previous_status},
            ) catch unreachable,
        ) catch {};

        if (previous_status_name) |name| {
            variables.put("mash::exit_code_name", name) catch {};
        } else {
            _ = variables.remove("mash::exit_code_name");
        }

        var pipe_line = std.ArrayList(
            Command,
        ).init(allocator);
        defer pipe_line.deinit();

        var it = parser.SyntaxIterator.init(
            //allocator,
            arena_allocator,
            line,
        ) catch return 1;

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
            inline for (@typeInfo(modules).Struct.decls) |decl| {
                if (std.mem.eql(u8, decl.name, command.system.name)) {
                    // TODO free
                    var mod_args = std.ArrayList(core.Argument).init(allocator);

                    if (command.system.arguments != null) {
                        for (command.system.arguments.?) |arg_str| {
                            var mod_it = core.ArgumentParser.init(&.{arg_str});

                            while (mod_it.next()) |arg| {
                                try mod_args.append(arg);

                                if (arg == .option and arg.option.flag == 'h') {
                                    const mod = @field(modules, decl.name);

                                    print_help = mod.help;
                                    print_help_name = command.system.name;
                                }
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
            }

            if (added) continue;

            try pipe_line.append(command);
        }

        //std.debug.print("{}\n", .{pipe_line});

        if (pipe_line.items.len == 0) continue;

        const exit_status = pipe.chainCommands(
            allocator,
            pipe_line.items,
        );

        if (exit_status.status.exit_code != 0 or exit_status.status.signal != .none) {
            const command_name = if (pipe_line.items[exit_status.idx] == .module) blk: {
                break :blk pipe_line.items[exit_status.idx].module.name;
            } else blk: {
                break :blk pipe_line.items[exit_status.idx].system.name;
            };

            previous_status = exit_status.status.exit_code;
            previous_status_name = exitCodeName(
                command_name,
                pipe_line.items[exit_status.idx] == .module,
                exit_status.status,
            );
        }
        //std.debug.print("{}\n", .{exit_status});
    }
}

pub fn main(arguments: []const core.Argument) u8 {
    _ = arguments;

    const stdout_file = std.io.getStdOut();
    const stdout = stdout_file.writer();

    _ = stdout.write("\n Welcome to " ++
        comptime fg(.cyan) ++ "MIST" ++
        fg(.default) ++ "!\n\n" ++
        " This is a minimal shell inspired by UNIX, but it is not\n" ++
        " POSIX-compliant\n\n" ++
        " For a list of builtin modules, type: " ++
        fg(.cyan) ++ "commands" ++
        fg(.default) ++ "\n\n") catch unreachable;

    logical_path = std.posix.getcwd(
        &logical_path_buf,
    ) catch return 1;

    const shm = posix.mmap(
        null,
        @sizeOf(@TypeOf(child_error)),
        //posix.PROT.READ | posix.PROT.WRITE,
        posix.PROT.WRITE,
        .{
            .TYPE = .SHARED,
            .ANONYMOUS = true,
        },
        -1,
        0,
    ) catch unreachable;
    defer posix.munmap(shm);

    child_error = @ptrCast(shm.ptr);
    child_error.* = 0;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    variables = VariableMap.init(allocator);
    defer variables.deinit();

    variables.put("mash::exit_code", "0") catch {};
    // $tush::exit_code
    // $tush.exit_code
    // $env.

    //nonInteractiveLoop("bruh") catch unreachable;

    aliases = std.StringHashMap(Command).init(allocator);
    defer aliases.deinit();
    aliases.put(
        "bruh",
        .{ .system = .{ .name = "echo" } },
    ) catch {};

    //    core.disableSigint() catch unreachable;
    core.disableSig(.interrupt) catch unreachable;
    core.disableSig(.quit) catch unreachable;

    var print_prompt = true;

    // TODO: history limit
    //var history = std.ArrayList([]const u8).init(allocator);
    history = History.init(allocator);
    defer history.deinit();

    var previous_status: u8 = 0;
    var previous_status_name: ?[]const u8 = null;

    // Main loop
    while (true) {
        setTerminalToRawMode() catch return 1;

        if (child_error.* != 0) {
            std.debug.print("errsize {d} {!}\n", .{
                @sizeOf(?anyerror),
                @errorFromInt(child_error.*),
            });
        }

        var arena = std.heap.ArenaAllocator.init(allocator);
        const arena_allocator = arena.allocator();
        defer arena.deinit();

        var buf: [3]u8 = undefined;

        variables.put(
            "mash::exit_code",
            std.fmt.bufPrint(
                &buf,
                "{d}",
                .{previous_status},
            ) catch unreachable,
        ) catch {};

        if (previous_status_name) |name| {
            variables.put("mash::exit_code_name", name) catch {};
        } else {
            _ = variables.remove("mash::exit_code_name");
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
                stdout.print("\n", .{}) catch return 1;
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
                    history.allocator.dupe(u8, line.items) catch return 1,
                ) catch return 1;

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
                        line.appendSlice(history.list.items[history.list.items.len - history_cursor]) catch return 1;

                        cursor.move(.left, vcursor_pos);
                        stdout.print("\x1b[0K", .{}) catch return 1;

                        stdout.print("{s}", .{line.items}) catch return 1;

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
                            line.appendSlice(history.list.items[history.list.items.len - history_cursor]) catch return 1;
                        }

                        cursor.move(.left, cursor_pos);
                        //stdout.print("\x1b[0K", .{}) catch return 1;
                        cursor.clearLine(.right);

                        stdout.print("{s}", .{line.items}) catch return 1;
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
                            //stdout.print("\x1b[D", .{}) catch return 1;
                            cursor_pos -= 1;
                            vcursor_pos -= 1;
                        }

                        // Step back to start byte if needed
                        while (cursor_pos < line.items.len and line.items.len > 0 and line.items[cursor_pos] & 0b1100_0000 == 0b1000_0000) {
                            cursor_pos -= 1;
                        }

                        continue;
                    },
                    else => {
                        //                        stdout.print(
                        //                            "\x1b[{c}",
                        //                            .{char},
                        //                        ) catch return 1;
                    },
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
                    _ = line.insert(cursor_pos + idx, utf8_buf[idx]) catch return 1;
                }
                //_ = line_text.insert(cursor_pos, codepoint) catch return 1;
                cursor.savePosition();
                // Print updated line
                stdout.print("{s}", .{line.items[cursor_pos..]}) catch return 1;

                cursor_pos += continue_len + 1;
                vcursor_pos += 1;

                // Return to cursor position
                cursor.restorePosition();
                cursor.move(.right, 1);
                //cursor.move(.left, line.items[cursor_pos..].len);
            }
        }

        if (restart) continue;

        var it = parser.SyntaxIterator.init(
            //allocator,
            arena_allocator,
            line.items,
        ) catch return 1;
        //defer it.deinit();

        var print_help: ?core.Help = null;
        var print_help_name: []const u8 = &.{};

        // Parse the line text
        while (it.next() catch return 1) |entry| {
            if (entry != .command) continue;

            const command = aliases.get(
                entry.command.system.name,
            ) orelse entry.command;

            var added = false;
            // Convert to module command if it exists
            inline for (@typeInfo(modules).Struct.decls) |decl| {
                if (std.mem.eql(u8, decl.name, command.system.name)) {
                    // TODO free
                    var mod_args = std.ArrayList(core.Argument).init(allocator);

                    if (command.system.arguments != null) {
                        for (command.system.arguments.?) |arg_str| {
                            var mod_it = core.ArgumentParser.init(&.{arg_str});

                            while (mod_it.next()) |arg| {
                                mod_args.append(arg) catch return 1;

                                if (arg == .option and arg.option.flag == 'h') {
                                    const mod = @field(modules, decl.name);

                                    print_help = mod.help;
                                    print_help_name = command.system.name;
                                }
                            }
                        }
                    }

                    pipe_line.append(.{
                        .module = .{
                            .name = command.system.name,
                            .arguments = mod_args.items,
                        },
                    }) catch return 1;

                    added = true;
                }
            }

            if (added) continue;

            pipe_line.append(command) catch return 1;
        }

        if (print_help) |h| {
            core.printHelp(print_help_name, h) catch return 1;
            previous_status = 0;
            continue;
        }

        if (pipe_line.items.len == 0) continue;

        child_error.* = 0;

        setTerminalToNormalMode() catch return 1;

        const exit_status = pipe.chainCommands(
            allocator,
            pipe_line.items,
        );

        previous_status = 0;
        previous_status_name = null;

        if (exit_status.status.exit_code != 0 or exit_status.status.signal != .none) {
            const command_name = if (pipe_line.items[exit_status.idx] == .module) blk: {
                break :blk pipe_line.items[exit_status.idx].module.name;
            } else blk: {
                break :blk pipe_line.items[exit_status.idx].system.name;
            };

            previous_status = exit_status.status.exit_code;
            previous_status_name = exitCodeName(
                command_name,
                pipe_line.items[exit_status.idx] == .module,
                exit_status.status,
            );
        }
    }
}

fn exitCodeName(
    name: []const u8,
    is_module: bool,
    status: pipe.ChainRet.Status,
) ?[]const u8 {
    switch (status.signal) {
        .none => {},

        else => return @tagName(status.signal),
    }

    if (is_module) {
        if (std.enums.tagName(
            core.Error,
            @enumFromInt(status.exit_code),
        )) |tag| {
            return tag;
        }

        if (core.module_list.get(name)) |mod| {
            for (mod.help.exit_codes) |code| {
                if (code.code == status.exit_code) return code.name;
            }
        }
    }

    // Special case for not found and cannot execute
    // TODO: ensure these codes come from the shell
    if (child_error.* != 0) switch (status.exit_code) {
        126, 127 => |c| return @tagName(@as(core.Error, @enumFromInt(c))),

        else => {},
    };

    return null;
}

fn utf8ContinueLen(byte: u8) u2 {
    return switch (byte >> 4) {
        else => 0,
        0b1100 => 1,
        0b1110 => 2,
        0b1111 => 3,
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
