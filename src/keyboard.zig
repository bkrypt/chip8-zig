const Keyboard = @This();

const std = @import("std");
const sdl = @import("zsdl2");

pub const num_keys = 16;

/// chip8 key to mapped SDL scan code
const key_bindings = [_]struct { u4, u32 }{
    .{ 0x0, @intFromEnum(sdl.Scancode.x) },
    .{ 0x1, @intFromEnum(sdl.Scancode.@"1") },
    .{ 0x2, @intFromEnum(sdl.Scancode.@"2") },
    .{ 0x3, @intFromEnum(sdl.Scancode.@"3") },
    .{ 0x4, @intFromEnum(sdl.Scancode.q) },
    .{ 0x5, @intFromEnum(sdl.Scancode.w) },
    .{ 0x6, @intFromEnum(sdl.Scancode.e) },
    .{ 0x7, @intFromEnum(sdl.Scancode.a) },
    .{ 0x8, @intFromEnum(sdl.Scancode.s) },
    .{ 0x9, @intFromEnum(sdl.Scancode.d) },
    .{ 0xA, @intFromEnum(sdl.Scancode.z) },
    .{ 0xB, @intFromEnum(sdl.Scancode.c) },
    .{ 0xC, @intFromEnum(sdl.Scancode.@"4") },
    .{ 0xD, @intFromEnum(sdl.Scancode.r) },
    .{ 0xE, @intFromEnum(sdl.Scancode.f) },
    .{ 0xF, @intFromEnum(sdl.Scancode.v) },
};

/// maps SDL scan codes to chip8 keypad keys
key_map: std.AutoHashMap(u32, u4),

/// pressed state of each chip8 key 0-F
keys: [16]bool = .{false} ** 16,

pub fn initInPlace(keyboard: *Keyboard, allocator: std.mem.Allocator) !void {
    keyboard.* = Keyboard{
        .key_map = std.AutoHashMap(u32, u4).init(allocator),
    };
    try keyboard.key_map.ensureTotalCapacity(num_keys);
    for (key_bindings) |binding| {
        keyboard.key_map.putAssumeCapacity(binding[1], binding[0]);
    }
}

pub fn init(allocator: std.mem.Allocator) !Keyboard {
    var keyboard: Keyboard = undefined;
    try initInPlace(&keyboard, allocator);
    return keyboard;
}

pub fn deinit(self: *Keyboard) void {
    self.key_map.deinit();
}

pub fn updateState(self: *Keyboard) void {
    const keyboard_state = sdl.getKeyboardState();
    var iterator = self.key_map.iterator();
    while (iterator.next()) |entry| {
        if (keyboard_state[entry.key_ptr.*] == 0) {
            self.keys[entry.value_ptr.*] = false;
        } else {
            self.keys[entry.value_ptr.*] = true;
        }
    }
}
