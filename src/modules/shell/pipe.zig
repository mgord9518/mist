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

pub const ChainRet = struct {
    //exit_code: u8,
    status: Status,

    // The index of the command that failed (if any)
    // This should only be read if `exit_code` > 0
    idx: usize,

    pub const Status = packed struct {
        signal: core.Signal = .none,
        _: u1 = undefined,
        core_dump: bool = false,
        exit_code: u8,
    };
};

/// Pipes together multiple system commands
pub fn chainCommands(
    a: std.mem.Allocator,
    commands: []const Command,
) ChainRet {
    var arena = std.heap.ArenaAllocator.init(a);
    const allocator = arena.allocator();
    defer arena.deinit();

    // TODO: proper error handling
    const pipes = allocator.alloc(
        [2]posix.fd_t,
        commands.len - 1,
    ) catch unreachable;
    defer allocator.free(pipes);

    // Open all pipes
    for (pipes, 0..) |_, idx| {
        pipes[idx] = posix.pipe() catch unreachable;
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
                        //.exit_code = exit_code,
                        .status = .{
                            .exit_code = @intFromEnum(exit_code),
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
                posix.dup2(pipes[idx - 1][0], 0) catch unreachable;
            }

            // < last command
            if (idx < commands.len - 1) {
                posix.dup2(pipes[idx][1], 1) catch unreachable;
            }
        }

        // Close pipes
        for (pipes, 0..) |_, j| {
            posix.close(pipes[j][0]);
            posix.close(pipes[j][1]);
        }

        // Re-enable signal handlers
        core.enableSig(.interrupt) catch unreachable;
        core.enableSig(.quit) catch unreachable;

        // Execute command
        if (command != .system) {

            // TODO: error
            const mod = core.module_list.get(command.module.name) orelse posix.exit(127);

            posix.exit(@intFromEnum(mod.main(command.module.arguments)));
        } else {
            const err = posix.execvpeZ(
                command_string.?[0].?,
                command_string.?,
                @ptrCast(environ.ptr),
            ); //catch {

            shell.child_error.* = @intFromError(err);
            // TODO: check error
            posix.exit(127);
            //};
        }
    }

    // Close pipes in parent
    for (pipes, 0..) |_, idx| {
        posix.close(pipes[idx][0]);
        posix.close(pipes[idx][1]);
    }

    var ret = ChainRet{
        .status = .{
            .exit_code = 0,
        },
        .idx = 0,
    };

    // Wait for all commands to exit
    var idx: usize = 0;
    while (idx < commands.len) : (idx += 1) {
        const status: u16 = @truncate(posix.waitpid(-1, 0).status);

        if (status != 0 and ret.status.exit_code == 0) {
            ret.status = @bitCast(status);

            ret.idx = idx;
        }
    }

    return ret;
}
