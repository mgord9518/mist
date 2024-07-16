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
    idx: usize,

    pub const Status = packed struct {
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
    commands: []const Command,
) !ChainRet {
    var arena = std.heap.ArenaAllocator.init(a);
    const allocator = arena.allocator();
    defer arena.deinit();

    // TODO: proper error handling
    const pipes = try allocator.alloc(
        [2]posix.fd_t,
        commands.len - 1,
    );
    defer allocator.free(pipes);

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

    const environ_len = std.os.environ.len + 1;

    const t: []?[*:0]const u8 = allocator.alloc(
        ?[*:0]const u8,
        environ_len + 1,
    ) catch unreachable;
    t[environ_len] = null;
    for (std.os.environ, 0..) |env, idx| {
        t[idx] = env;
    }

    var pid_map = std.AutoHashMap(
        posix.pid_t,
        usize,
    ).init(allocator);
    defer pid_map.deinit();

    t[environ_len - 1] = "bruh:u32=\x45\x00\x00\x00";

    const environ: [][*:0]const u8 = @ptrCast(t[0..environ_len :null]);

    for (commands, 0..) |command, idx| {
        var command_string: ?[*:null]?[*:0]const u8 = null;

        // Need to do allocations before forking because
        // calling malloc (which could possibly be the allocator given) in a
        // fork child is illegal under POSIX
        if (command == .system) {
            const args = command.system.arguments orelse &.{};

            const temp = allocator.alloc(
                ?[*:0]const u8,
                args.len + 2,
            ) catch unreachable;

            temp[args.len + 1] = null;
            command_string = temp[0 .. args.len + 1 :null];

            command_string.?[0] = (allocator.dupeZ(
                u8,
                command.system.name,
            ) catch unreachable).ptr;

            for (args, 1..) |arg, idx2| {
                command_string.?[idx2] = (allocator.dupeZ(
                    u8,
                    arg,
                ) catch unreachable).ptr;
            }
        }

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
        for (pipes) |pipe| {
            posix.close(pipe[0]);
            posix.close(pipe[1]);
        }

        // Re-enable signal handlers
        try core.enableSig(.interrupt);
        try core.enableSig(.quit);

        // Execute command
        if (command != .system) {
            // TODO: error
            const mod = core.module_list.get(
                command.module.name,
            ) orelse unreachable;

            posix.exit(@intFromEnum(mod.main(command.module.arguments)));
        } else {
            const err = posix.execvpeZ(
                command_string.?[0].?,
                command_string.?,
                @ptrCast(environ.ptr),
            );

            const errno: core.Error = switch (err) {
                error.FileNotFound => .command_not_found,
                else => unreachable,
            };

            _ = posix.write(
                error_pipes[idx][1],
                &.{@intFromEnum(errno)},
            ) catch unreachable;

            for (error_pipes) |pipe| {
                posix.close(pipe[0]);
                posix.close(pipe[1]);
            }

            posix.exit(127);
        }
    }

    // Close pipes in parent
    for (pipes) |pipe| {
        posix.close(pipe[0]);
        posix.close(pipe[1]);
    }

    var buf: [1]u8 = .{0};
    for (error_pipes) |pipe| {
        posix.close(pipe[1]);

        // If we can't read from the error pipe, it should be safe to
        // assume it's been closed due to a successful command exec
        _ = posix.read(pipe[0], &buf) catch {};
        posix.close(pipe[0]);
    }

    const err: core.Error = @enumFromInt(buf[0]);

    var ret = ChainRet{
        .ret = if (err == .success) blk: {
            break :blk .success;
        } else blk: {
            break :blk .{
                .exec_failure = err,
            };
        },
        .idx = 0,
    };

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

    return ret;
}
