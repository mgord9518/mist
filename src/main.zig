const std = @import("std");
const posix = std.posix;
const SIG = posix.SIG;
pub const modules = @import("modules.zig");

/// How a module should be executed when called inside the shell
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

/// As these will be used in the future for plugins, the numeric values
/// should really try not to change unless there is a good reason. If the
/// values do change, MIST should keep a revision history so that old
/// plugins can still have their errors shown correctly
pub const Error = enum(u7) {
    success = 0,
    unknown_error = 1,
    usage_error = 2,

    // Filesystem
    file_not_found = 16,
    access_denied = 17,
    cwd_not_found = 18,
    name_too_long = 19,
    not_dir = 20,
    not_file = 21,
    sym_link_loop = 22,

    // IO
    read_failure = 32,
    write_failure = 33,
    input_output = 34,
    broken_pipe = 35,

    // Variables
    invalid_variable = 48,
    invalid_env_variable = 49,

    // System
    out_of_memory = 64,
    no_space_left = 65,
    not_equal = 66,
    system_resources = 67,

    // Encoding/ compression
    corrupt_input = 80,

    // Misc
    false = 96,
    invalid_argument = 97,

    // Exec
    command_cannot_execute = 126,
    command_not_found = 127,

    _,
};

pub fn genericMain(
    comptime mainFn: fn ([]const []const u8) anyerror!void,
) fn ([]const []const u8) Error {
    return struct {
        pub fn mainImpl(arguments: []const []const u8) Error {
            mainFn(arguments) catch |err| {
                return switch (err) {
                    error.NoSpaceLeft => .no_space_left,
                    error.UsageError => .usage_error,
                    error.InputOutput => .input_output,
                    error.OutOfMemory => .out_of_memory,

                    error.FileTooBig,
                    error.DiskQuota,
                    error.ProcessFdQuotaExceeded,
                    error.SystemFdQuotaExceeded,
                    error.DeviceBusy,
                    error.SystemResources,
                    error.NotOpenForWriting,
                    => .system_resources,

                    error.NotDir => .not_dir,
                    error.SymLinkLoop => .sym_link_loop,
                    error.InvalidArgument => .invalid_argument,
                    error.AccessDenied => .access_denied,
                    error.BrokenPipe => .broken_pipe,
                    error.FileNotFound => .file_not_found,

                    error.NotEqual => .not_equal,

                    else => .unknown_error,
                };
            };

            return .success;
        }
    }.mainImpl;
}

pub const Module = struct {
    help: ?Help,
    main: *const fn ([]const []const u8) Error,
    exec_mode: ExecMode,
    no_display: bool,
};

pub const PluginMain = *const fn (
    argc: usize,
    argv: [*]?[*]const u8,
    argvc: [*]usize,
) callconv(.C) u8;
//pub const PluginMain = *const fn () callconv(.C) usize;

pub const module_list = blk: {
    const mod_decls = @typeInfo(modules).Struct.decls;

    const T = std.meta.Tuple(&.{ []const u8, Module });
    var list: [mod_decls.len]T = undefined;

    for (mod_decls, 0..) |decl, idx| {
        const mod = @field(modules, decl.name);

        list[idx] = .{
            decl.name,
            .{
                .help = if (@hasDecl(mod, "help")) mod.help else null,
                .main = &mod.main,
                .exec_mode = mod.exec_mode,
                .no_display = @hasDecl(mod, "no_display") and mod.no_display,
            },
        };
    }

    break :blk std.StaticStringMap(Module).initComptime(list);
};

pub var plugin_list: std.StringHashMap(PluginMain) = undefined;

pub const Help = struct {
    description: []const u8,
    usage: []const u8,
    options: ?[]const Option = null,

    // These are simply for printing the help menu
    // all options must be parsed by the module itself
    pub const Option = struct {
        flag: u8,
        description: []const u8,
    };
};

const PluginHelp = extern struct {
    description: String,
    usage: String,
    options: Options,

    const Options = extern struct {
        len: u32,
        ptr: [*]const Option,
    };

    const Option = struct {
        flag: u8,
        description: String,
    };

    const String = extern struct {
        len: u32,
        ptr: [*]const u8,
    };
};

pub const Argument = union(enum) {
    positional: []const u8,

    option: u8,
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    try init(allocator);

    const argv = std.os.argv;
    const argv0 = std.mem.sliceTo(argv[0], 0);

    var args = std.ArrayList([]const u8).init(allocator);
    for (argv) |arg| {
        try args.append(std.mem.sliceTo(arg, 0));
    }

    const print_help = false;

    const basename = std.fs.path.basename(argv0);

    if (module_list.get(basename)) |mod| {
        if (print_help) {
            try printHelp(basename, mod.help);
            return;
        }

        _ = mod.main(args.items[1..]);
    } else {
        @panic("Module not found!");
    }
}

fn init(allocator: std.mem.Allocator) !void {
    plugin_list = std.StringHashMap(PluginMain).init(allocator);
}

fn deinit() !void {
    plugin_list.deinit();
}

pub const ArgumentParser = struct {
    state: State = .none,

    arguments: []const []const u8,

    current_arg: usize = 0,
    idx: usize = 0,

    const State = enum {
        flags_ended,
        none,
    };

    pub fn init(arguments: []const []const u8) ArgumentParser {
        return .{
            .arguments = arguments,
            .current_arg = 0,
        };
    }

    pub fn next(it: *ArgumentParser) ?Argument {
        if (it.current_arg == it.arguments.len) return null;

        const arg = it.arguments[it.current_arg];

        if (arg.len == 0) {
            it.current_arg += 1;
            return .{
                .positional = "",
            };
        }

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

                it.idx += 1;
                return .{
                    .option = it.arguments[it.current_arg][it.idx],
                };
            },
        }

        it.current_arg += 1;
        it.idx = 0;

        return it.next();
    }
};

pub fn printHelp(name: []const u8, h: ?Help) !void {
    const help = h orelse return;

    const stdout_file = std.io.getStdOut();
    const stdout = stdout_file.writer();

    try stdout.print(
        \\{2}usage{1}: {0s} 
    , .{
        name,
        ColorName.default,
        ColorName.yellow,
    });

    try usagePrint(stdout, help.usage);

    try stdout.print("\n\n", .{});

    if (help.options) |options| {
        try stdout.print(
            \\{1s}options{0s}:
            \\
        , .{
            ColorName.default,
            ColorName.yellow,
        });

        for (options) |option| {
            try stdout.print("{0s}  {1s}-{2c}{0s}: {3s}\n", .{
                ColorName.default,
                ColorName.cyan,
                option.flag,
                option.description,
            });
        }

        _ = try stdout.write("\n");
    }
}

pub const ColorName = enum(u8) {
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

    pub fn format(
        self: ColorName,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        out_stream: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        return out_stream.print(
            "\x1b[;{d}m",
            .{@intFromEnum(self)},
        );
    }
};

pub fn fg(comptime color: ColorName) [:0]const u8 {
    return std.fmt.comptimePrint(
        "\x1b[;{d}m",
        .{@intFromEnum(color)},
    );
}

pub const Signal = enum(u6) {
    hang_up = SIG.HUP,
    interrupt = SIG.INT,
    quit = SIG.QUIT,
    illegal_instruction = SIG.ILL,
    trap = SIG.TRAP,
    abnormal_return = SIG.ABRT,
    bus = SIG.BUS,
    floating_point_exception = SIG.FPE,
    kill = SIG.KILL,
    usr_1 = SIG.USR1,
    segmentation_fault = SIG.SEGV,
    usr_2 = SIG.USR2,
    pipe = SIG.PIPE,
    alarm = SIG.ALRM,
    terminate = SIG.TERM,
    child = SIG.CHLD,
    @"continue" = SIG.CONT,
    stop = SIG.STOP,
    terminal_stop = SIG.TSTP,
    // TODO SIGTTIN, SIGTTOU
    urgent = SIG.URG,
    exceeded_cpu_limit = SIG.XCPU,
    //exceeded_file_size_limit = SIG.FSZ,
    virtual_alarm = SIG.VTALRM,
};

fn sigImpl(signal: Signal, enable: bool) !void {
    const handler = if (enable) SIG.DFL else SIG.IGN;

    var action = posix.Sigaction{
        .handler = .{
            .handler = handler,
        },
        .mask = posix.empty_sigset,
        .flags = 0,
    };

    try posix.sigaction(
        @intFromEnum(signal),
        &action,
        null,
    );
}

pub fn disableSig(signal: Signal) !void {
    try sigImpl(signal, false);
}

pub fn enableSig(signal: Signal) !void {
    try sigImpl(signal, true);
}

pub const colors = struct {
    pub const required = ColorName.yellow;
    pub const optional = ColorName.cyan;
    pub const module = ColorName.green;

    pub const fs = struct {
        pub const file = ColorName.default;
        pub const directory = ColorName.bright_blue;
        pub const broken_sym_link = ColorName.bright_red;
        pub const sym_link = ColorName.cyan;
        pub const device = ColorName.yellow;
        pub const executable = ColorName.bright_green;
    };
};

pub fn usagePrint(writer: anytype, in: []const u8) !void {
    var in_grave = false;

    for (in) |byte| {
        switch (byte) {
            '<' => try writer.print("<{}", .{colors.required}),
            '>', ']' => try writer.print("{}{c}", .{ ColorName.default, byte }),
            '[' => try writer.print("[{}", .{colors.optional}),
            '`' => {
                in_grave = !in_grave;

                if (in_grave) {
                    try writer.print("`{}", .{colors.module});
                } else {
                    try writer.print("{}`", .{ColorName.default});
                }
            },

            else => {
                _ = try writer.write(&.{byte});
            },
        }
    }
}
