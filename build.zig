const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "mist",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Currently needed to load plugins until
    // <https://github.com/ziglang/zig/issues/21196> is resolved
    //
    // Well, it does partially work without libc, it just only seems to load
    // libraries built with Zig which are compiled with a release mode?
    // Debug builds crash... let's wait until DynLib becomes more stable and
    // plugins should be able to be written in anything supporting C ABI
    exe.linkLibC();

    if (false) {
        const zware_dep = b.dependency("zware", .{
            .target = target,
            .optimize = optimize,
        });

        const zware_module = zware_dep.module("zware");
        exe.root_module.addImport("zware", zware_module);
    }

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
