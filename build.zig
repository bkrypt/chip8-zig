const std = @import("std");
const zsdl = @import("zsdl");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zig-emu-chip8",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const zsdl_pkg = b.dependency("zsdl", .{});
    exe.root_module.addImport("zsdl2", zsdl_pkg.module("zsdl2"));

    zsdl.addLibraryPathsTo(exe);
    zsdl.addRPathsTo(exe);
    zsdl.link_SDL2(exe);
    zsdl.install_sdl2(&exe.step, target.result, .bin);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
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

    exe_unit_tests.root_module.addImport("zsdl2", zsdl_pkg.module("zsdl2"));

    zsdl.addLibraryPathsTo(exe_unit_tests);
    zsdl.link_SDL2(exe_unit_tests);

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    if (target.result.os.tag == .windows) {
        run_exe_unit_tests.setCwd(.{
            .cwd_relative = b.getInstallPath(.bin, ""),
        });
    }

    zsdl.install_sdl2(&exe_unit_tests.step, target.result, .lib);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
