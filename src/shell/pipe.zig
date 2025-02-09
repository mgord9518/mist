// Pipe an arbitrary amount of commands together in Zig
//
// Thanks to:
//   <https://people.cs.rutgers.edu/~pxk/416/notes/c-tutorials/pipe.html>
//   <https://gist.github.com/mplewis/5279108>

const std = @import("std");
const posix = std.posix;

const core = @import("../main.zig");
const shell = @import("../shell.zig");
const Command = shell.Command;

const modules = shell.modules;

pub const ChainRet = struct {
    ret: Return,

    // The index of the command that failed (if any)
    // This should only be read if `exit_code` > 0
    idx: usize = 0,

    pub const Status = packed struct(u16) {
        signal: core.Signal,
        _7: u1 = undefined,
        core_dump: bool = false,
        exit_code: u8,
    };

    pub const Return = union(enum) {
        // The command was successfully executed and exited with a status of 0
        success,

        // The command was terminated by a signal
        signal: core.Signal,

        // Command was successfully executed, if the command exited with a
        // non-zero status, this will be populated
        exit_code: u8,

        // Builtin module was executed, returned something besides `success`
        module_exit_failure: core.Error,

        // Command failed to execute, this most likely means the command
        // doesn't exist or isn't executable
        exec_failure: core.Error,
    };
};

/// Pipes together multiple system commands
pub fn chainCommands(
    a: std.mem.Allocator,
    reader: anytype,
    c: []const Command,
) !ChainRet {
    var arena = std.heap.ArenaAllocator.init(a);
    const allocator = arena.allocator();
    defer arena.deinit();

    if (c.len == 0) {
        return .{
            .idx = 0,
            .ret = .success,
        };
    }

    const heredoc_pipe = try posix.pipe();
    var commands = c;

    // TODO: don't hardcode this
    var heredoc = false;
    var heredoc_string: []const u8 = "END";
    if (c[0] == .system) {
        if (std.mem.eql(u8, c[0].system.name, "<<")) {
            heredoc = true;
            commands = c[1..];

            if (c[0].system.arguments.len == 1) {
                heredoc_string = c[0].system.arguments[0];
            }
        }
    }

    const pipes = try allocator.alloc(
        [2]posix.fd_t,
        commands.len - 1,
    );
    defer allocator.free(pipes);

    // For system commands, these are only used to detect an execve failure
    // but for modules, they are used to set shell variables via fileno `4`
    const error_pipes = try allocator.alloc(
        [2]posix.fd_t,
        commands.len,
    );
    defer allocator.free(error_pipes);

    // Open all pipes
    for (pipes, 0..) |_, idx| {
        pipes[idx] = posix.pipe() catch unreachable;
    }

    for (error_pipes, 0..) |_, idx| {
        error_pipes[idx] = posix.pipe2(.{
            .CLOEXEC = true,
        }) catch unreachable;
    }

    var pid_map = std.AutoHashMap(
        posix.pid_t,
        usize,
    ).init(allocator);
    defer pid_map.deinit();

    for (commands, 0..) |command, idx| {
        if (command != .system) {
            if (core.module_list.get(command.module.name)) |mod| {
                if (mod.exec_mode == .function) {
                    // TODO: fix with piping
                    const exit_code = mod.main(command.module.arguments);

                    return .{
                        .idx = 0,
                        .ret = if (exit_code == .success) blk: {
                            break :blk .success;
                        } else .{
                            .module_exit_failure = exit_code,
                        },
                    };
                }
            }
        }

        const pid = posix.fork() catch unreachable;
        try pid_map.put(pid, idx);

        // Parent
        if (pid != 0) continue;

        // Child
        if (heredoc and idx == 0) {
            try posix.dup2(heredoc_pipe[0], posix.STDIN_FILENO);
        }

        // Pipe stdin and stdout if needed
        if (commands.len > 1) {

            // > first command
            if (idx > 0) {
                try posix.dup2(pipes[idx - 1][0], posix.STDIN_FILENO);
            }

            // < last command
            if (idx < commands.len - 1) {
                try posix.dup2(pipes[idx][1], posix.STDOUT_FILENO);
            }
        }

        // Close pipes
        posix.close(heredoc_pipe[1]);
        for (pipes) |pipe| {
            posix.close(pipe[0]);
            posix.close(pipe[1]);
        }

        // Re-enable signal handlers
        try core.enableSig(.interrupt);
        try core.enableSig(.quit);

        var exit_code: u8 = 0;
        var err_pipe_contents: []const u8 = "\x00";

        // Execute command
        switch (command) {
            .module => {
                try posix.dup2(error_pipes[idx][1], 4);

                // TODO: error
                const mod = core.module_list.get(
                    command.module.name,
                ) orelse unreachable;

                exit_code = @intFromEnum(
                    mod.main(command.module.arguments),
                );
            },
            .system => {
                var argv = std.ArrayList([]const u8).init(a);

                try argv.append(command.system.name);
                try argv.appendSlice(command.system.arguments);

                const err = std.process.execv(
                    a,
                    argv.items,
                );

                _ = posix.write(
                    error_pipes[idx][1],
                    "E",
                ) catch unreachable;

                const errno: core.Error = switch (err) {
                    error.FileNotFound => .command_not_found,
                    error.AccessDenied => .access_denied,
                    error.NameTooLong => .name_too_long,
                    error.SystemResources => .system_resources,
                    else => {
                        std.debug.print("FIXME {s} {!}\n", .{ @src().file, err });
                        unreachable;
                    },
                };

                err_pipe_contents = &.{@intFromEnum(errno)};

                exit_code = @intFromEnum(errno);
            },
        }

        _ = posix.write(
            error_pipes[idx][1],
            err_pipe_contents,
        ) catch unreachable;

        for (error_pipes) |pipe| {
            posix.close(pipe[0]);
            posix.close(pipe[1]);
        }

        posix.exit(exit_code);
    }

    // Close pipes in parent
    posix.close(heredoc_pipe[0]);
    for (pipes) |pipe| {
        posix.close(pipe[0]);
        posix.close(pipe[1]);
    }

    var buf: [4]u8 = undefined;
    buf[0] = 0;

    var ret = ChainRet{
        .ret = .success,
        .idx = 0,
    };

    var heredoc_file = std.fs.File{
        .handle = heredoc_pipe[1],
    };

    if (heredoc) {
        var list = std.ArrayList(u8).init(a);
        defer list.deinit();

        while (true) {
            reader.streamUntilDelimiter(
                list.writer(),
                '\n',
                null,
            ) catch |err| {
                switch (err) {
                    error.EndOfStream => break,
                    else => return err,
                }
            };

            if (std.mem.eql(u8, heredoc_string, list.items)) {
                break;
            }

            heredoc_file.writer().print("{s}\n", .{list.items}) catch break;
            list.shrinkAndFree(0);
        }

        posix.close(heredoc_pipe[1]);
    }

    // Wait for all commands to exit
    for (commands) |_| {
        const wait_res = posix.waitpid(-1, 0);

        const s: u16 = @truncate(wait_res.status);
        const status: ChainRet.Status = @bitCast(s);
        const idx = pid_map.get(wait_res.pid).?;

        if (s == 0 or ret.ret != .success) continue;

        ret.idx = idx;

        ret.ret = if (@intFromEnum(status.signal) != 0) blk: {
            break :blk .{ .signal = status.signal };
        } else blk: {
            if (commands[idx] == .system) {
                break :blk .{ .exit_code = status.exit_code };
            } else {
                if (status.exit_code == 0) {
                    break :blk .success;
                }

                break :blk .{
                    .module_exit_failure = @enumFromInt(status.exit_code),
                };
            }
        };
    }

    for (error_pipes, 0..) |pipe, pipe_idx| {
        posix.close(pipe[1]);

        var variable_buf = std.ArrayList(u8).init(allocator);
        defer variable_buf.deinit();

        while (true) {
            // If we can't read from the error pipe, it should be safe to
            // assume it's been closed due to a successful command exec
            const read_amount = posix.read(
                pipe[0],
                &buf,
            ) catch 0;

            if (read_amount > 0) {
                try variable_buf.appendSlice(
                    buf[0..read_amount],
                );
            } else {
                break;
            }
        }

        if (variable_buf.items.len < 2) continue;

        const id = variable_buf.items[0];

        switch (id) {
            'V' => {
                const name_len = variable_buf.items[1];

                shell.variables.put(
                    variable_buf.items[2..][0..name_len],
                    variable_buf.items[2..][name_len .. variable_buf.items.len - 3],
                ) catch unreachable;
            },
            'E' => {
                const code = variable_buf.items[1];

                ret.ret = .{
                    .exec_failure = @enumFromInt(code),
                };
                ret.idx = pipe_idx;
            },
            else => |new_id| {
                std.debug.print("id {c} {x}\n", .{ new_id, new_id });
            },
        }

        posix.close(pipe[0]);
    }

    // TODO: read this properly
    const name_len: u8 = shell.shm[1];
    const plen: u16 = 8;
    const proc_len: *const u16 = &plen;

    shell.procedures.put(
        "T",
        shell.shm[4 + name_len ..][0..proc_len.*],
    ) catch unreachable;

    return ret;
}
