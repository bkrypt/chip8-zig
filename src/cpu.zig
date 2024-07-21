const Cpu = @This();

const std = @import("std");

const Instruction = @import("instruction.zig");
const font_data = @import("font.zig").font_data;

pub const memory_size = 4096;
pub const display_width = 64;
pub const display_height = 32;
pub const initial_pc = 0x200;
pub const stack_size = 16;
pub const font_base_address = 0x050;
pub const font_glyph_stride = 5;

/// general 8-bit registers V0-VF
V: [16]u8 = .{0} ** 16,
/// 12-bit memory index register
I: u12 = 0,
/// program counter
pc: u12 = initial_pc,
/// call stack
stack: std.BoundedArray(u12, stack_size),
/// random number generator
rand: std.Random.DefaultPrng,

/// 4KiB system memory
mem: [memory_size]u8,

/// display 64x32 pixels in row-major order
display: [display_width * display_height / 8]u8 = .{0} ** (display_width * display_height / 8),
/// whether the contents of `display` have been modified since the last time this flag was set
display_dirty: bool = false,

/// delay timer
dt: u8 = 0,
/// sound timer
st: u8 = 0,

/// pressed state of each key 0-F
keys: [16]bool = .{false} ** 16,
/// which register should receive the next key press; not null when FX0A instruction is active
next_key_register: ?u4 = null,

pub fn initInPlace(cpu: *Cpu, program: []const u8, seed: u64) !void {
    cpu.* = Cpu{
        .stack = std.BoundedArray(u12, stack_size){},
        .rand = std.Random.DefaultPrng.init(seed),
        .mem = undefined,
    };
    @memset(&cpu.mem, 0);
    @memcpy(cpu.mem[font_base_address..].ptr, font_data);
    @memcpy(cpu.mem[initial_pc..].ptr, program);
}

pub fn init(program: []const u8, seed: u64) !Cpu {
    var cpu: Cpu = undefined;
    try initInPlace(&cpu, program, seed);
    return cpu;
}

pub fn cycle(self: *Cpu) !void {
    const opcode = std.mem.readInt(u16, self.mem[self.pc..][0..2], .big);
    const inst = Instruction.decode(opcode);

    if (try inst.exec(self)) |new_pc| {
        self.pc = new_pc;
    } else {
        self.pc +%= 2;
    }
}

pub fn timerTick(self: *Cpu) void {
    if (self.dt > 0) self.dt -= 1;
    if (self.st > 0) self.st -= 1;
}

pub fn getPixel(self: Cpu, x: u8, y: u8) u1 {
    const pixel_index: u16 = display_width * @as(u16, y) + @as(u16, x);

    const byte_index: u16 = pixel_index / 8;
    const bit_index: u3 = @truncate(pixel_index);

    return @truncate(self.display[byte_index] >> bit_index);
}

test "getPixel" {
    var cpu = try Cpu.init(&.{}, 0);
    cpu.display[0] = 0b10000100;

    const pixel = cpu.getPixel(2, 0);

    try std.testing.expectEqual(1, pixel);
}

pub fn invertPixel(self: *Cpu, x: u8, y: u8) void {
    const pixel_index: u16 = display_width * @as(u16, y) + @as(u16, x);

    const byte_index: u16 = pixel_index / 8;
    const bit_index: u3 = @truncate(pixel_index);

    self.display[byte_index] ^= (@as(u8, 1) << bit_index);
}

test "invertPixel" {
    var cpu = try Cpu.init(&.{}, 0);
    cpu.display[0] = 0b10000000;

    cpu.invertPixel(7, 0);

    try std.testing.expectEqual(0, cpu.display[0]);
}

pub fn setKeys(self: *Cpu, new_keys: *const [16]bool) void {
    if (self.next_key_register) |register| new_key_block: {
        for (new_keys, self.keys, 0..) |is_pressed, was_pressed, key| {
            if (is_pressed and !was_pressed) {
                // store key in target register
                self.V[register] = @intCast(key);
                // advance pc to next instruction
                self.pc +%= 2;
                // indicate we are no longer waiting for a key press
                self.next_key_register = null;
                // break out of the loop in case multiple keys were pressed at once
                break :new_key_block;
            }
        }
    }

    @memcpy(&self.keys, new_keys);
}

test "setKeys" {
    var cpu = try Cpu.init(&.{}, 0);
    // assert initial all false state of cpu.keys
    try std.testing.expectEqualSlices(bool, &[_]bool{false} ** 16, &cpu.keys);

    cpu.setKeys(&[_]bool{true} ** 16);
    try std.testing.expectEqualSlices(bool, &[_]bool{true} ** 16, &cpu.keys);
}
