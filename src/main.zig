const std = @import("std");
const posix = std.posix;
const SIG = posix.SIG;
pub const modules = @import("modules.zig");
//pub const usage_print = @import("usage_print.zig").usage_print;

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

/// Shared exit codes
/// Any error that can reasonably be assumed to be generic should be here
pub const Error = enum(u7) {
    success = 0,
    unknown_error = 1,
    usage_error = 2,

    // Filesystem
    file_not_found,
    access_denied,
    cwd_not_found,
    name_too_long,

    // IO
    read_failure,
    write_failure,

    // Variables
    invalid_variable,
    invalid_env_variable,

    // System
    out_of_memory,
    no_space_left,
    not_equal,
    system_resources,

    // Encoding/ compression
    corrupt_input,

    // Misc
    false,

    // Exec
    command_cannot_execute = 126,
    command_not_found = 127,
};

pub const Module = struct {
    help: ?Help,
    main: *const fn ([]const Argument) Error,
    exec_mode: ExecMode,
    no_display: bool,
};

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

pub const Help = struct {
    description: []const u8,
    usage: []const u8,
    options: ?[]const Help.Option = null,

    // These are simply for printing the help menu
    // all options must be parsed by the module itself
    pub const Option = struct {
        flag: u8,
        description: []const u8,
    };
};

pub const Argument = union(enum) {
    positional: []const u8,

    // Done this way to make converting between []Argument and [][]u8 cheap
    option: *const [2]u8,
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

    var arguments = std.ArrayList(Argument).init(allocator);

    var it = ArgumentParser.init(args.items);
    while (it.next()) |entry| {
        if (entry == .option and entry.option[1] == 'h') {
            print_help = true;
        }

        try arguments.append(entry);
    }

    const basename = std.fs.path.basename(argv0);

    if (module_list.get(basename)) |mod| {
        if (print_help) {
            try printHelp(basename, mod.help);
            //return;
            unreachable;
        }

        _ = mod.main(arguments.items[1..]);
    } else {
        @panic("Module not found!");
    }
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
                    .option = it.arguments[it.current_arg][it.idx..][0..2],
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
        \\{2s}usage{1s}: {0s} 
    , .{
        name,
        fg(.default),
        fg(.yellow),
    });

    try usagePrint(stdout, help.usage);

    try stdout.print("\n\n", .{});

    if (help.options) |options| {
        try stdout.print(
            \\{1s}options{0s}:
            \\
        , .{
            fg(.default),
            fg(.yellow),
        });

        for (options) |option| {
            try stdout.print("{0s}  {1s}-{2c}{0s}: {3s}\n", .{
                fg(.default),
                fg(.cyan),
                option.flag,
                option.description,
            });
        }

        _ = try stdout.write("\n");
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
    pub const required = fg(.yellow);
    pub const optional = fg(.cyan);
    pub const module = fg(.green);

    pub const fs = struct {
        pub const file = fg(.default);
        pub const directory = fg(.bright_blue);
        pub const sym_link = fg(.cyan);
        pub const device = fg(.yellow);
        pub const executable = fg(.bright_green);
    };
};

pub fn usagePrint(writer: anytype, in: []const u8) !void {
    var in_grave = false;

    for (in) |byte| {
        _ = try writer.write(switch (byte) {
            '<' => "<" ++ colors.required,
            '>' => comptime fg(.default) ++ ">",
            '[' => "[" ++ colors.optional,
            ']' => comptime fg(.default) ++ "]",
            '`' => blk: {
                in_grave = !in_grave;

                if (in_grave) {
                    break :blk "`" ++ colors.module;
                } else {
                    break :blk comptime fg(.default) ++ "`";
                }
            },

            else => &[_]u8{byte},
        });
    }
}
