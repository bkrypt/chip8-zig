const std = @import("std");
const sdl = @import("zsdl2");

const Cpu = @import("cpu.zig");
const Keyboard = @import("keyboard.zig");

fn hz(f: usize) f64 {
    return 1.0 / @as(f64, @floatFromInt(f));
}

fn sToNs(s: f64) u64 {
    return @as(u64, @intFromFloat(s * 1_000_000_000.0));
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try sdl.init(.{ .video = true });
    defer sdl.quit();

    const rom = try std.fs.cwd().readFileAlloc(allocator, "roms/test-opcode.ch8", 4096 - 512);
    defer allocator.free(rom);

    var cpu = try Cpu.init(rom, @intCast(std.time.milliTimestamp()));
    var keyboard = try Keyboard.init(allocator);
    defer keyboard.deinit();

    const window = try sdl.Window.create(
        "zig-emu-chip8",
        sdl.Window.pos_undefined,
        sdl.Window.pos_undefined,
        1280,
        640,
        .{},
    );
    defer window.destroy();

    const renderer = try sdl.Renderer.create(window, -1, .{ .accelerated = true });
    defer renderer.destroy();

    const target = try sdl.Renderer.createTexture(renderer, .rgb24, .target, 64, 32);
    defer target.destroy();

    var frame_timer = try std.time.Timer.start();
    var timer_timer = try std.time.Timer.start();

    const frame_ns = sToNs(hz(900));
    const timer_ns = sToNs(hz(60));

    main_loop: while (true) {
        frame_timer.reset();

        var event: sdl.Event = undefined;
        while (sdl.pollEvent(&event)) {
            switch (event.type) {
                .quit => break :main_loop,
                .keydown => {
                    if (event.key.keysym.scancode == .escape) {
                        break :main_loop;
                    }
                },
                else => continue,
            }
        }

        keyboard.updateState();
        cpu.setKeys(&keyboard.keys);

        if (timer_timer.read() >= timer_ns) {
            cpu.timerTick();
            timer_timer.reset();
        }

        try cpu.cycle();

        if (cpu.display_dirty) {
            try renderer.setTarget(target);
            try renderer.setDrawColorRGB(0, 0, 0);
            try renderer.clear();
            try renderer.setDrawColorRGB(255, 255, 255);
            for (0..Cpu.display_height) |y_pixel| {
                for (0..Cpu.display_width) |x_pixel| {
                    const x: u8 = @intCast(x_pixel);
                    const y: u8 = @intCast(y_pixel);
                    if (cpu.getPixel(x, y) == 1) {
                        try renderer.drawPoint(x, y);
                    }
                }
            }

            try renderer.setTarget(null);
            try renderer.setDrawColorRGB(0, 0, 0);
            try renderer.clear();
            try renderer.copy(target, null, null);

            renderer.present();
            cpu.display_dirty = false;
        }

        const sleep_time = @subWithOverflow(frame_ns, frame_timer.read());
        if (sleep_time[1] == 0) {
            std.time.sleep(sleep_time[0]);
        }
    }
}

comptime {
    std.testing.refAllDecls(@import("instruction.zig"));
    std.testing.refAllDecls(@import("font.zig"));
}
