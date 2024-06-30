// Pipe an arbitrary amount of commands together in Zig
//
// Thanks to:
//   <https://people.cs.rutgers.edu/~pxk/416/notes/c-tutorials/pipe.html>
//   <https://gist.github.com/mplewis/5279108>

const std = @import("std");
const posix = std.posix;

const core = @import("../../main.zig");
const shell = @import("../shell.zig");
const Command = shell.Command;

const modules = shell.modules;

const IntErr = std.meta.Int(
    .unsigned,
    @bitSizeOf(anyerror),
);

pub const ChainRet = struct {
    //status: Status,
    ret: Return,

    // The index of the command that failed (if any)
    // This should only be read if `exit_code` > 0
    idx: usize,

    pub const Status = packed struct {
        signal: core.Signal = .none,
        _: u1 = undefined,
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
        status: Status,

        // Builtin module waa executed, returned something besides
        // `.success`
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
    const pipes = allocator.alloc(
        [2]posix.fd_t,
        commands.len - 1,
    ) catch unreachable;
    defer allocator.free(pipes);

    const error_pipes = allocator.alloc(
        [2]posix.fd_t,
        commands.len,
    ) catch unreachable;
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
                        .ret = .{
                            .module_exit_failure = exit_code,
                        },
                    };
                }
            }
        }

        const pid = posix.fork() catch unreachable;

        // Parent
        if (pid != 0) continue;

        // Child

        // Pipe stdin and stdout if needed
        if (commands.len > 1) {
            // > first command
            if (idx > 0) {
                posix.dup2(pipes[idx - 1][0], posix.STDIN_FILENO) catch unreachable;
            }

            // < last command
            if (idx < commands.len - 1) {
                posix.dup2(pipes[idx][1], posix.STDOUT_FILENO) catch unreachable;
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

            //const u8_err: [@sizeOf(anyerror)]u8 = @bitCast(@intFromError(err));

            _ = posix.write(
                error_pipes[idx][1],
                &.{@intFromEnum(errno)},
            ) catch unreachable;

            for (error_pipes) |pipe| {
                posix.close(pipe[0]);
                posix.close(pipe[1]);
            }

            //shell.child_error.* = @intFromError(err);
            // TODO: check error
            posix.exit(127);
            //};
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
    //var idx: usize = 0;
    for (commands, 0..) |_, idx| {
        //while (idx < commands.len) : (idx += 1) {
        const s: u16 = @truncate(posix.waitpid(-1, 0).status);
        const status: ChainRet.Status = @bitCast(s);

        if (s != 0 and ret.ret == .success) {
            ret.ret = if (@intFromEnum(status.signal) != 0) blk: {
                break :blk .{ .signal = status.signal };
            } else blk: {
                if (commands[idx] == .system) {
                    break :blk .{ .status = status };
                } else {
                    break :blk .{
                        .module_exit_failure = @enumFromInt(status.exit_code),
                    };
                }
            };

            ret.idx = idx;
        }
    }

    return ret;
}
