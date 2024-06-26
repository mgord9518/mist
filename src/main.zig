const std = @import("std");
const posix = std.posix;
const SIG = posix.SIG;
pub const modules = @import("modules.zig");

// How a module should be executed when called inside the shell
pub const ExecMode = enum {
    // Fork the process, then call the main function
    // This must be used for any modules that may hang or exit
    fork,

    // Directly call the main function, this is faster but may only be used
    // in certain situations, such as:
    //  * non-blocking commands that perform a simple function
    //  * do not exit unless the intended functionality is to also exit the
    //    shell (such as the exit builtin)
    function,
};

/// Shared exit codes
/// Any error that can reasonably be assumed to be generic should be here
pub const Error = enum(u8) {
    success = 0,
    unknown_error = 1,
    usage_error = 2,

    // Filesystem
    file_not_found = 16,
    access_denied = 17,

    // Variables
    invalid_variable = 64,
    invalid_env_variable = 65,

    // Memory
    out_of_memory = 80,

    // Exec
    command_cannot_execute = 126,
    command_not_found = 127,
    _,
};

pub const Module = struct {
    help: Help,
    main: *const fn ([]const Argument) Error,
    exec_mode: ExecMode,
};

pub const module_list = blk: {
    const mod_decls = @typeInfo(modules).Struct.decls;

    const T = std.meta.Tuple(&.{ []const u8, Module });
    var list: [mod_decls.len]T = undefined;

    for (mod_decls, 0..) |decl, idx| {
        const mod = @field(modules, decl.name);
        const type_info = @typeInfo(@TypeOf(mod.main));
        if (type_info != .Fn) {
            @compileError("Return type of `main` must be `fn ([]const core.Argument) u8`");
        }

        if (@bitSizeOf(type_info.Fn.return_type.?) != 8) {
            @compileError("Return type of `main` must be `fn ([]const core.Argument) u8`");
        }

        list[idx] = .{
            decl.name,
            .{
                .help = mod.help,
                .main = @ptrCast(&mod.main),
                .exec_mode = mod.exec_mode,
            },
        };
    }

    //break :blk list;
    break :blk std.StaticStringMap(Module).initComptime(list);
};

pub const Help = struct {
    description: []const u8,
    usage: []const u8,
    options: []const Help.Option,

    /// Custom:q
    exit_codes: []const Help.ExitCode,

    // These are simply for printing the help menu
    // all options must be parsed by the module itself
    pub const Option = struct {
        flag: u8,
        description: []const u8,
    };

    pub const ExitCode = struct {
        code: u8,
        name: []const u8,
    };
};

pub const Option = struct {
    flag: u8,
    arg: ?[]const u8 = null,
    payload: ?union(enum) {
        positional: []const u8,
        many_positionals: [][]const u8,
    } = null,
};

pub const Argument = union(enum) {
    positional: []const u8,
    option: Option,
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const argv = std.os.argv;
    const argv0 = std.mem.sliceTo(argv[0], 0);

    var args = std.ArrayList([]const u8).init(allocator);
    for (argv) |arg| {
        try args.append(std.mem.sliceTo(arg, 0));
    }

    var print_help = false;

    var it = ArgumentParser.init(args.items);
    while (it.next()) |entry| {
        if (entry == .option and entry.option.flag == 'h') {
            print_help = true;
        }

        //        switch (entry) {
        //            .positional => |string| std.debug.print(fg(.default) ++ "pos: {s}\n", .{string}),
        //            .option => |arg| std.debug.print(fg(.cyan) ++ "opt: {c}\n", .{arg.flag}),
        //        }
    }

    const arguments = std.ArrayList(Argument).init(allocator);

    const basename = std.fs.path.basename(argv0);
    inline for (@typeInfo(modules).Struct.decls) |decl| {
        if (std.mem.eql(u8, decl.name, basename)) {
            const mod = @field(modules, decl.name);

            if (print_help) {
                try printHelp(basename, mod.help);
                //return;
                unreachable;
            }

            _ = mod.main(arguments.items);
        }
    }
}

pub const ArgumentParser = struct {
    state: enum {
        none,
        flags_ended,
    } = .none,
    arguments: []const []const u8,

    current_arg: usize = 0,
    idx: usize = 0,

    pub fn init(arguments: []const []const u8) ArgumentParser {
        return .{
            .arguments = arguments,
            .current_arg = 0,
        };
    }

    pub fn next(it: *ArgumentParser) ?Argument {
        if (it.current_arg == it.arguments.len) return null;

        const arg = it.arguments[it.current_arg];
        // Send as positional arg
        if (arg[0] != '-' or it.state == .flags_ended) {
            it.current_arg += 1;
            return .{
                .positional = arg,
            };
        }

        if (arg.len == 1) {
            it.current_arg += 1;
            return .{
                .positional = arg,
            };
        }

        //switch (arg[it.idx]) {
        switch (arg[1]) {
            '-' => {
                it.state = .flags_ended;
            },
            else => {
                if (arg.len == it.idx + 1) {
                    it.current_arg += 1;
                    it.idx = 0;

                    return it.next();
                }

                defer it.idx += 1;
                return .{
                    .option = .{
                        .flag = it.arguments[it.current_arg][it.idx + 1],
                    },
                };
            },
        }

        it.current_arg += 1;
        it.idx = 0;

        return it.next();
    }
};

pub fn printHelp(name: []const u8, help: Help) !void {
    //const argv = std.os.argv;
    //const argv0 = std.mem.sliceTo(argv[0], 0);

    std.debug.print(
        \\{3s}usage{2s}: {4s} {0s}
        \\
        \\{1s}
        \\
        \\
    , .{
        //argv0,
        help.usage,
        help.description,
        fg(.default),
        fg(.yellow),
        name,
    });

    if (help.options.len > 0) {
        std.debug.print(
            \\{1s}options{0s}:
            \\
        , .{
            fg(.default),
            fg(.yellow),
        });
    }

    for (help.options) |option| {
        std.debug.print("{0s}  {1s}-{2c}{0s}: {3s}\n", .{
            fg(.default),
            fg(.cyan),
            option.flag,
            option.description,
        });
    }

    if (help.options.len > 0) {
        std.debug.print("\n", .{});
    }

    if (help.exit_codes.len > 0) {
        std.debug.print(
            \\{1s}exit codes{0s}:
            \\
        , .{
            fg(.default),
            fg(.yellow),
        });
    }

    for (help.exit_codes) |code| {
        std.debug.print("{0s}  {1s}{2d}{0s}: {3s}\n", .{
            fg(.default),
            fg(.cyan),
            code.code,
            code.name,
        });
    }

    if (help.exit_codes.len > 0) {
        std.debug.print("\n", .{});
    }
}

const ColorName = enum(comptime_int) {
    reset = 0,
    default = 39,

    black = 30,
    red = 31,
    green = 32,
    yellow = 33,
    blue = 34,
    magenta = 35,
    cyan = 36,
    white = 37,

    bright_black = 90,
    bright_red = 91,
    bright_green = 92,
    bright_yellow = 93,
    bright_blue = 94,
    bright_magenta = 95,
    bright_cyan = 96,
    bright_white = 97,
};

// TODO: make this less jank
pub fn fg(comptime color: ColorName) [:0]const u8 {
    //pub fn fg(comptime color: ColorName) *const [std.fmt.comptimePrint("\x1b[;{d}m", .{@intFromEnum(color)}).len:0]u8 {
    return std.fmt.comptimePrint(
        "\x1b[;{d}m",
        .{@intFromEnum(color)},
    );
}

pub fn printError(comptime fmt: []const u8, args: anytype) void {
    //std.debug.print(fg(.red) ++ "shell:ls " ++ fg(.default) ++ fmt, args);
    //std.debug.print("shell " ++ fg(.red) ++ ":: " ++ fg(.default) ++ fmt, args);
    std.debug.print(fg(.red) ++ ":: " ++ fg(.default) ++ fmt, args);
}

pub const Signal = enum(u6) {
    none = 0,
    hang_up = SIG.HUP,
    interrupt = SIG.INT,
    quit = SIG.QUIT,
    illegal_instruction = SIG.ILL,
    trap = SIG.TRAP,
    abnormal = SIG.ABRT,
    bus = SIG.BUS,
    floating_point_exception = SIG.FPE,
    kill = SIG.KILL,
    segmentation_fault = SIG.SEGV,
};

pub fn disableSig(signal: Signal) !void {
    var action = std.posix.Sigaction{
        .handler = .{ .handler = SIG.IGN },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };

    try std.posix.sigaction(
        @intFromEnum(signal),
        &action,
        null,
    );
}

pub fn enableSig(signal: Signal) !void {
    var action = std.posix.Sigaction{
        .handler = .{ .handler = SIG.DFL },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };

    try std.posix.sigaction(
        @intFromEnum(signal),
        &action,
        null,
    );
}

pub fn runModule(name: []const u8, arguments: ?[]const Argument) !u8 {
    // Run module if it exists
    inline for (@typeInfo(modules).Struct.decls) |decl| {
        if (std.mem.eql(u8, decl.name, name)) {
            const mod = @field(modules, decl.name);

            return mod.main(arguments orelse &.{});
        }
    }

    // Module not found
    return error.ModuleNotFound;
}
