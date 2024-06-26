const std = @import("std");
const builtin = std.builtin;
const zware = @import("zware");
const Store = zware.Store;
const Module = zware.Module;
const Instance = zware.Instance;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
const core = @import("../main.zig");

pub const exec_mode: core.ExecMode = .fork;

pub const help = core.Help{
    .description = "run WASM executables",
    .usage = "{0s}",
    .options = &.{
        //.{ .flag = 'm', .description = "max memory" },
    },
    .exit_codes = &.{
        //.{ .flag = 'm', .description = "max memory" },
    },
};

pub fn initHostFunctions(store: *zware.Store) !void {
    //    try store.exposeHostFunction(
    //        "wasi_snapshot_preview1",
    //        "proc_exit",
    //        zware.wasi.proc_exit,
    //        &[_]zware.ValType{.I32},
    //        &[_]zware.ValType{},
    //    );
    //var p = Expose(proc_exit).params();
    //var p: [@typeInfo(@TypeOf(proc_exit)).Fn.params.len]zware.ValType = undefined;

    // TODO: some weird lifetime issue when trying to use `Expose` directly
    // declaring the variables as globals also fixes it, but this is easier
    // for now
    //    const p = try std.heap.page_allocator.alloc(
    //        zware.ValType,
    //        @typeInfo(@TypeOf(proc_exit)).Fn.params.len,
    //    );
    //
    //    @memcpy(p, &Expose(proc_exit).params());

    //    for (Expose(proc_exit).params(), 0..) |param, idx| {
    //        p[idx] = param;
    //        std.debug.print("mv {} {}\n", .{ @intFromEnum(p[idx]), @intFromEnum(param) });
    //    }

    try expose(store, "wasi_snapshot_preview1", "proc_exit", proc_exit);

    try store.exposeHostFunction(
        "wasi_snapshot_preview1",
        "fd_write",
        zware.wasi.fd_write,
        &[_]zware.ValType{.I32} ** 4,
        &.{.I32},
    );
    try store.exposeHostFunction(
        "wasi_snapshot_preview1",
        "args_get",
        zware.wasi.args_get,
        &[_]zware.ValType{ .I32, .I32 },
        &[_]zware.ValType{.I32},
    );
    try store.exposeHostFunction(
        "wasi_snapshot_preview1",
        "args_sizes_get",
        zware.wasi.args_sizes_get,
        &[_]zware.ValType{ .I32, .I32 },
        &[_]zware.ValType{.I32},
    );
    if (true) {
        try store.exposeHostFunction("wasi_snapshot_preview1", "fd_close", zware.wasi.fd_close, &[_]zware.ValType{.I32}, &[_]zware.ValType{.I32});
        try store.exposeHostFunction("wasi_snapshot_preview1", "fd_fdstat_get", zware.wasi.fd_fdstat_get, &[_]zware.ValType{ .I32, .I32 }, &[_]zware.ValType{.I32});
        try store.exposeHostFunction("wasi_snapshot_preview1", "fd_fdstat_set_flags", zware.wasi.fd_fdstat_set_flags, &[_]zware.ValType{ .I32, .I32 }, &[_]zware.ValType{.I32});
        try store.exposeHostFunction("wasi_snapshot_preview1", "fd_filestat_get", zware.wasi.fd_filestat_get, &[_]zware.ValType{ .I32, .I32 }, &[_]zware.ValType{.I32});
        try store.exposeHostFunction("wasi_snapshot_preview1", "fd_prestat_get", zware.wasi.fd_prestat_get, &[_]zware.ValType{ .I32, .I32 }, &[_]zware.ValType{.I32});
        try store.exposeHostFunction("wasi_snapshot_preview1", "fd_prestat_dir_name", zware.wasi.fd_prestat_dir_name, &[_]zware.ValType{ .I32, .I32, .I32 }, &[_]zware.ValType{.I32});
        try store.exposeHostFunction("wasi_snapshot_preview1", "fd_read", zware.wasi.fd_read, &[_]zware.ValType{ .I32, .I32, .I32, .I32 }, &[_]zware.ValType{.I32});
        try store.exposeHostFunction("wasi_snapshot_preview1", "fd_seek", zware.wasi.fd_seek, &[_]zware.ValType{ .I32, .I64, .I32, .I32 }, &[_]zware.ValType{.I32});
        try store.exposeHostFunction("wasi_snapshot_preview1", "fd_write", zware.wasi.fd_write, &[_]zware.ValType{ .I32, .I32, .I32, .I32 }, &[_]zware.ValType{.I32});
        try store.exposeHostFunction("wasi_snapshot_preview1", "path_create_directory", zware.wasi.path_create_directory, &[_]zware.ValType{ .I32, .I32, .I32 }, &[_]zware.ValType{.I32});
        try store.exposeHostFunction("wasi_snapshot_preview1", "path_filestat_get", zware.wasi.path_filestat_get, &[_]zware.ValType{ .I32, .I32, .I32, .I32, .I32 }, &[_]zware.ValType{.I32});
        try store.exposeHostFunction("wasi_snapshot_preview1", "path_open", zware.wasi.path_open, &[_]zware.ValType{ .I32, .I32, .I32, .I32, .I32, .I64, .I64, .I32, .I32 }, &[_]zware.ValType{.I32});
    }
}

pub fn main(arguments: []const core.Argument) u8 {
    if (arguments.len < 1) return 2;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const cwd = std.fs.cwd();
    const file = cwd.openFile(arguments[0].positional, .{}) catch return 1;

    const bytes = file.readToEndAlloc(allocator, 16 * 1024 * 1024) catch return 1;
    defer allocator.free(bytes);

    var store = Store.init(allocator);
    defer store.deinit();

    initHostFunctions(&store) catch return 1;

    var module = Module.init(allocator, bytes);
    defer module.deinit();
    module.decode() catch return 1;

    var instance = Instance.init(allocator, &store, module);
    instance.instantiate() catch unreachable;
    defer instance.deinit();

    //_ = std.mem.eql(zware.ValType, &Expose(proc_exit).params(), &[_]zware.ValType{.I32});

    //    std.debug.print("PARAMS {any} {any}\n", .{
    //        std.mem.eql(
    //            zware.ValType,
    //            &Expose(proc_exit).params(),
    //            &[_]zware.ValType{.I32},
    //        ),
    //        &Expose(proc_exit).params(),
    //    });

    //    Expose(inc).run() catch |err| {
    //        std.debug.print("expose {!}\n", .{err});
    //    };

    //    inline for (Expose(proc_exit).params()) |param| {
    //        std.debug.print("PARAM: {}\n", .{param});
    //    }

    //instance.wasi_args.append(@constCast("TEST")) catch return 69;

    //const args = instance.forwardArgs(allocator) catch return 1;
    //defer std.process.argsFree(allocator, args);

    //var out = [1]u64{0};

    instance.addWasiPreopen(0, "stdin", std.posix.STDIN_FILENO) catch {};
    instance.addWasiPreopen(1, "stdout", std.posix.STDOUT_FILENO) catch {};
    instance.addWasiPreopen(2, "stderr", std.posix.STDERR_FILENO) catch {};
    //   instance.addWasiPreopen(3, "./", std.fs.cwd().fd) catch {};

    const stack = 2048;

    // Startpoint
    // instance.invoke("_shell_module_main", &.{}, &out, .{
    instance.invoke("_start", &.{}, &.{}, .{
        .operand_stack_size = stack,
        .label_stack_size = stack,
        .frame_stack_size = stack,
    }) catch unreachable;

    //const result: u8 = @truncate(out[0]);
    //std.debug.print("result = {d}\n", .{result});

    //return result;
    return 0;
}

pub fn inc(i: u32, _: u16) u32 {
    return i + 1;
}

//pub fn wrap(vm: *zware.VirtualMachine) zware.WasmError!void {
//
//}

pub fn proc_exit(exit_code: u8) void {
    std.posix.exit(exit_code);
}

// TODO: remove need for allocation
pub fn expose(store: *zware.Store, module: []const u8, func_name: []const u8, func: anytype) !void {
    const T = @TypeOf(func);
    const type_info = @typeInfo(T);

    const p = try std.heap.page_allocator.alloc(
        zware.ValType,
        type_info.Fn.params.len,
    );

    const v_p = comptime blk: {
        var vp: [type_info.Fn.params.len]zware.ValType = undefined;

        for (type_info.Fn.params, 0..) |param, idx| {
            // TODO: floats
            if (@bitSizeOf(param.type.?) <= 32) {
                vp[idx] = .I32;
            } else if (@bitSizeOf(param.type.?) <= 64) {
                vp[idx] = .I64;
            } else unreachable;
        }

        break :blk vp;
    };

    @memcpy(p, &v_p);

    try store.exposeHostFunction(
        module,
        func_name,
        getExposeFn(proc_exit),
        p,
        &[_]zware.ValType{},
    );
}

/// Generate a function that automatically pops params off the VM stack and
/// Pushes the return value
/// `func` must only contain params that are < 64 bits in size individually
fn getExposeFn(func: anytype) fn (*zware.VirtualMachine) zware.WasmError!void {
    return struct {
        const Self = @This();

        pub fn run(vm: *zware.VirtualMachine) zware.WasmError!void {
            const T = @TypeOf(func);
            const type_info = @typeInfo(T);

            comptime var fields: [type_info.Fn.params.len]builtin.Type.StructField = undefined;
            comptime var idx = 0;

            inline for (type_info.Fn.params) |param| {
                fields[idx] = .{
                    .name = std.fmt.comptimePrint("{d}", .{idx}),
                    .type = param.type.?,
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = @alignOf(param.type.?),
                };

                idx += 1;
            }

            const S = @Type(.{
                .Struct = .{
                    .layout = .auto,
                    .fields = &fields,
                    .decls = &.{},
                    .is_tuple = true,
                },
            });

            var p: S = undefined;
            inline for (@typeInfo(S).Struct.fields, 0..) |field, i| {
                if (@bitSizeOf(field.type) > 64) {
                    return error.OperandSizeTooLarge;
                }

                p[i] = @truncate(vm.popAnyOperand());
            }

            @call(.auto, func, p);
        }
    }.run;
}

pub fn buildFn(func: anytype) void {
    const T = @TypeOf(func);
    const type_info = @typeInfo(T);

    if (type_info != .Fn) unreachable;

    inline for (type_info.Fn.params) |param| {
        std.debug.print("{}\n", .{param});
    }
}
