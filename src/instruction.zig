const Instruction = @This();

const std = @import("std");

const Cpu = @import("cpu.zig");

/// 4-bit elements of opcode, most significant first
nibbles: [4]u4,
/// high 4 bits, indicates class of opcode
high_4: u4,
/// first register specified
reg_X: u4,
/// second register specified
reg_Y: u4,
/// low 4 bits, used to disambiguate certain opcodes
low_4: u4,
/// low 8 bits
low_8: u8,
/// low 12 bits
low_12: u12,
/// the full 16-bit opcode
opcode: u16,

const test_seed: u64 = 0xDEADBEEFFEEBDAED;

pub fn decode(opcode: u16) Instruction {
    const nibbles = [4]u4{
        @as(u4, @truncate(opcode >> 12)),
        @as(u4, @truncate(opcode >> 8)),
        @as(u4, @truncate(opcode >> 4)),
        @as(u4, @truncate(opcode >> 0)),
    };

    return Instruction{
        .nibbles = nibbles,
        .high_4 = nibbles[0],
        .reg_X = nibbles[1],
        .reg_Y = nibbles[2],
        .low_4 = nibbles[3],
        .low_8 = @as(u8, @truncate(opcode)),
        .low_12 = @as(u12, @truncate(opcode)),
        .opcode = opcode,
    };
}

test "decode" {
    const inst = Instruction.decode(0xABCD);

    try std.testing.expectEqual([_]u4{ 0xA, 0xB, 0xC, 0xD }, inst.nibbles);
    try std.testing.expectEqual(0xA, inst.high_4);
    try std.testing.expectEqual(0xB, inst.reg_X);
    try std.testing.expectEqual(0xC, inst.reg_Y);
    try std.testing.expectEqual(0xD, inst.low_4);
    try std.testing.expectEqual(0xCD, inst.low_8);
    try std.testing.expectEqual(0xBCD, inst.low_12);
    try std.testing.expectEqual(0xABCD, inst.opcode);
}

pub fn exec(self: Instruction, cpu: *Cpu) !?u12 {
    return opcode_fn_table[self.high_4](self, cpu);
}

const InstructionError = error{
    BadReturn,
    IllegalOpcode,
    StackOverflow,
};

const OpcodeFn = *const fn (self: Instruction, cpu: *Cpu) InstructionError!?u12;

const opcode_fn_table: [16]OpcodeFn = .{
    op00EX, // 0
    op1NNN, // 1
    op2NNN, // 2
    op3XNN, // 3
    op4XNN, // 4
    op5XY0, // 5
    op6XNN, // 6
    op7XNN, // 7
    opLogical, // 8
    op9XY0, // 9
    opANNN, // A
    opBNNN, // B
    opCXNN, // C
    opDXYN, // D
    opInput, // E
    opMisc, // F
};

fn opNOOP(self: Instruction, cpu: *Cpu) !?u12 {
    _ = self;
    _ = cpu;
    return null;
}

/// 00E0: clear screen
/// 00EE: return from subroutine
fn op00EX(self: Instruction, cpu: *Cpu) !?u12 {
    switch (self.opcode) {
        0x00E0 => {
            @memset(&cpu.display, 0);
            cpu.display_dirty = true;
            return null;
        },
        0x00EE => {
            if (cpu.stack.popOrNull()) |return_address| {
                return return_address;
            } else {
                return error.BadReturn;
            }
        },
        else => return null,
    }
}

/// 1NNN: jump PC to address NNN
fn op1NNN(self: Instruction, cpu: *Cpu) !?u12 {
    _ = cpu;
    return self.low_12;
}

test "1NNN jump to address" {
    var cpu = try Cpu.init(&[_]u8{
        0x1A, 0xBC,
    }, test_seed);
    try cpu.cycle();
    try std.testing.expectEqual(0xABC, cpu.pc);
}

/// 2NNN: call subroutine at address NNN
fn op2NNN(self: Instruction, cpu: *Cpu) !?u12 {
    // return to next instruction, not this one
    const return_address = cpu.pc + 2;
    cpu.stack.append(return_address) catch return error.StackOverflow;
    return self.low_12;
}

test "2NNN call subroutine" {
    // calls subroutine, then jumps back to the start (no return)
    var cpu = try Cpu.init(&[_]u8{
        0x22, 0x06, // 0x200: call 0x206
        0x00, 0x00,
        0x00, 0x00,
        0x12, 0x00, // 0x206: jump back to 0x200
    }, test_seed);

    // fill up the stack
    for (0..Cpu.stack_size) |i| {
        // execute call
        try cpu.cycle();
        try std.testing.expectEqual(i + 1, cpu.stack.len);
        try std.testing.expectEqual(0x202, cpu.stack.get(i));
        try std.testing.expectEqual(0x206, cpu.pc);
        // execute jump
        try cpu.cycle();
    }

    // this cycle should overflow the stack
    try std.testing.expectError(error.StackOverflow, cpu.cycle());
}

/// calculates the new PC based on whether to skip the next instruction or not
inline fn skipInstructionIf(cpu: *Cpu, should_skip: bool) u12 {
    return cpu.pc +% @as(u12, if (should_skip) 4 else 2);
}

/// 3XNN: skip instruction if register VX is equal to NN
fn op3XNN(self: Instruction, cpu: *Cpu) !?u12 {
    return skipInstructionIf(cpu, cpu.V[self.reg_X] == self.low_8);
}

test "3XNN skip equal immediate" {
    var cpu = try Cpu.init(&[_]u8{
        0x31, 0xAB,
        0x00, 0x00,
        0x31, 0xEE,
    }, test_seed);
    cpu.V[0x1] = 0xAB;
    // should skip to 0x204 (0xAB == 0xAB)
    try cpu.cycle();
    try std.testing.expectEqual(0x204, cpu.pc);
    // should step to 0x206 (0xAB != 0xEE)
    try cpu.cycle();
    try std.testing.expectEqual(0x206, cpu.pc);
}

/// 4XNN: skip instruction if register VX is not equal to NN
fn op4XNN(self: Instruction, cpu: *Cpu) !?u12 {
    return skipInstructionIf(cpu, cpu.V[self.reg_X] != self.low_8);
}

test "4XNN skip not equal immediate" {
    var cpu = try Cpu.init(&[_]u8{
        0x41, 0xDE,
        0x00, 0x00,
        0x41, 0xFF,
    }, test_seed);
    cpu.V[0x1] = 0xFF;
    // should skip to 0x204 (0xFF != 0xDE)
    try cpu.cycle();
    try std.testing.expectEqual(0x204, cpu.pc);
    // should step to 0x206 (0xFF == 0xFF)
    try cpu.cycle();
    try std.testing.expectEqual(0x206, cpu.pc);
}

/// 5XY0: skip instruction if register VX is equal to register VY
fn op5XY0(self: Instruction, cpu: *Cpu) !?u12 {
    return skipInstructionIf(cpu, cpu.V[self.reg_X] == cpu.V[self.reg_Y]);
}

test "5XY0 skip equal register" {
    var cpu = try Cpu.init(&[_]u8{
        0x51, 0x20,
        0x00, 0x00,
        0x51, 0x30,
    }, test_seed);
    cpu.V[0x1] = 0xAA;
    cpu.V[0x2] = 0xAA;
    cpu.V[0x3] = 0xFF;
    // should skip to 0x204 (0xAA == 0xAA)
    try cpu.cycle();
    try std.testing.expectEqual(0x204, cpu.pc);
    // should step to 0x206 (0xAA != 0xFF)
    try cpu.cycle();
    try std.testing.expectEqual(0x206, cpu.pc);
}

/// 6XNN: set register VX to NN
fn op6XNN(self: Instruction, cpu: *Cpu) !?u12 {
    cpu.V[self.reg_X] = self.low_8;
    return null;
}

test "6XNN set register" {
    var cpu = try Cpu.init(&[_]u8{
        0x6A, 0xCD,
    }, test_seed);
    try cpu.cycle();
    try std.testing.expectEqual(0xCD, cpu.V[0xA]);
}

/// 7XNN: add value NN to register VX;
/// VF is unaffected by overflow
fn op7XNN(self: Instruction, cpu: *Cpu) !?u12 {
    cpu.V[self.reg_X] +%= self.low_8;
    return null;
}

test "7XNN add value to register" {
    var cpu = try Cpu.init(&[_]u8{
        0x7A, 0x37,
        0x7A, 0xFF,
        0x7A, 0xCB,
    }, test_seed);
    // VA = 0x37
    try cpu.cycle();
    try std.testing.expectEqual(0x37, cpu.V[0xA]);
    // always ensure carry flag was not set
    try std.testing.expectEqual(0x0, cpu.V[0xF]);
    // VA = 0x36 (0xFF = subtract 1)
    try cpu.cycle();
    try std.testing.expectEqual(0x36, cpu.V[0xA]);
    try std.testing.expectEqual(0x0, cpu.V[0xF]);
    // VA = 0x1
    try cpu.cycle();
    try std.testing.expectEqual(0x1, cpu.V[0xA]);
    try std.testing.expectEqual(0x0, cpu.V[0xF]);
}

const LogicalOpcodeResult = struct {
    u8, // new VX value
    ?u8, // new VF value, or null if unchanged
};

const LogicalOpcodeFn = *const fn (vx: u8, vy: u8) InstructionError!LogicalOpcodeResult;

fn opLogical(self: Instruction, cpu: *Cpu) !?u12 {
    const logical_opcode_fn_table: [15]LogicalOpcodeFn = .{
        op8XY0,
        op8XY1,
        op8XY2,
        op8XY3,
        op8XY4,
        op8XY5,
        op8XY6,
        op8XY7,
        opLogicalNOOP,
        opLogicalNOOP,
        opLogicalNOOP,
        opLogicalNOOP,
        opLogicalNOOP,
        opLogicalNOOP,
        op8XYE,
    };

    const which_logical_fn = logical_opcode_fn_table[self.low_4];
    const result = try which_logical_fn(cpu.V[self.reg_X], cpu.V[self.reg_Y]);
    cpu.V[self.reg_X] = result[0];
    if (result[1]) |new_vf| {
        cpu.V[0xF] = new_vf;
    }
    return null;
}

fn opLogicalNOOP(vx: u8, vy: u8) !LogicalOpcodeResult {
    _ = vx;
    _ = vy;
    return .{ 0, 0 };
}

/// 8XY0: set register VX to value of register VY
fn op8XY0(vx: u8, vy: u8) !LogicalOpcodeResult {
    _ = vx;
    return .{ vy, null };
}

test "8XY0 set VX to VY" {
    var cpu = try Cpu.init(&[_]u8{
        0x8A, 0xB0,
    }, test_seed);
    cpu.V[0xA] = 5;
    cpu.V[0xB] = 10;
    try cpu.cycle();
    try std.testing.expectEqual(10, cpu.V[0xA]);
    try std.testing.expectEqual(10, cpu.V[0xB]);
}

/// 8XY1: set register VX to bitwise OR of VX and VY
fn op8XY1(vx: u8, vy: u8) !LogicalOpcodeResult {
    return .{ vx | vy, null };
}

test "8XY1 set VX to VX | VY" {
    var cpu = try Cpu.init(&[_]u8{
        0x8C, 0xD1,
    }, test_seed);
    cpu.V[0xC] = 0b01010101;
    cpu.V[0xD] = 0b10101010;
    try cpu.cycle();
    try std.testing.expectEqual(0b11111111, cpu.V[0xC]);
    try std.testing.expectEqual(0b10101010, cpu.V[0xD]);
}

/// 8XY2: set register VX to bitwise AND of VX and VY
fn op8XY2(vx: u8, vy: u8) !LogicalOpcodeResult {
    return .{ vx & vy, null };
}

test "8XY2 set VX to VX & VY" {
    var cpu = try Cpu.init(&[_]u8{
        0x8B, 0xC2,
    }, test_seed);
    cpu.V[0xB] = 0b11110000;
    cpu.V[0xC] = 0b00001111;
    try cpu.cycle();
    try std.testing.expectEqual(0b00000000, cpu.V[0xB]);
    try std.testing.expectEqual(0b00001111, cpu.V[0xC]);
}

/// 8XY3: set register VX to bitwise XOR of VX and VY
fn op8XY3(vx: u8, vy: u8) !LogicalOpcodeResult {
    return .{ vx ^ vy, null };
}

test "8XY3 set VX to VX ^ VY" {
    var cpu = try Cpu.init(&[_]u8{
        0x81, 0x53,
    }, test_seed);
    cpu.V[0x1] = 0b10101010;
    cpu.V[0x5] = 0b01010101;
    try cpu.cycle();
    try std.testing.expectEqual(0b11111111, cpu.V[0x1]);
    try std.testing.expectEqual(0b01010101, cpu.V[0x5]);
}

/// 8XY4: set register VX to VX + VY; set VF to 1 if overflow occurred, 0 otherwise
fn op8XY4(vx: u8, vy: u8) !LogicalOpcodeResult {
    const result = @addWithOverflow(vx, vy);
    return .{ result[0], result[1] };
}

test "8XY4 set VX to VX + VY" {
    var cpu = try Cpu.init(&[_]u8{
        0x8A, 0xB4,
        0x8D, 0xE4,
    }, test_seed);
    cpu.V[0xA] = 64;
    cpu.V[0xB] = 64;
    cpu.V[0xD] = 155;
    cpu.V[0xE] = 102;
    // no overflow this cycle
    try cpu.cycle();
    try std.testing.expectEqual(128, cpu.V[0xA]);
    try std.testing.expectEqual(64, cpu.V[0xB]);
    try std.testing.expectEqual(0, cpu.V[0xF]);
    // this cycle should set carry flag
    try cpu.cycle();
    try std.testing.expectEqual(1, cpu.V[0xD]);
    try std.testing.expectEqual(102, cpu.V[0xE]);
    try std.testing.expectEqual(1, cpu.V[0xF]);
}

/// 8XY5: set register VX to VX - VY; set VF to 0 if underflow occurred, 1 otherwise
fn op8XY5(vx: u8, vy: u8) !LogicalOpcodeResult {
    const result = @subWithOverflow(vx, vy);
    return .{ result[0], 1 - result[1] };
}

test "8XY5 set VX to VX - VY" {
    var cpu = try Cpu.init(&[_]u8{
        0x83, 0x45,
        0x8A, 0xB5,
    }, test_seed);
    cpu.V[0x3] = 50;
    cpu.V[0x4] = 26;
    cpu.V[0xA] = 128;
    cpu.V[0xB] = 129;
    // no underflow this cycle
    try cpu.cycle();
    try std.testing.expectEqual(24, cpu.V[0x3]);
    try std.testing.expectEqual(26, cpu.V[0x4]);
    try std.testing.expectEqual(1, cpu.V[0xF]);
    // underflow this cycle
    try cpu.cycle();
    try std.testing.expectEqual(255, cpu.V[0xA]);
    try std.testing.expectEqual(129, cpu.V[0xB]);
    try std.testing.expectEqual(0, cpu.V[0xF]);
}

/// 8XY6: set VX to VY >> 1; set VF to the value of shifted out bit
fn op8XY6(vx: u8, vy: u8) !LogicalOpcodeResult {
    _ = vy;
    return .{ vx >> 1, vx & 0x01 };
}

test "8XY6 set VX to VX >> 1" {
    var cpu = try Cpu.init(&[_]u8{
        0x8A, 0xB6,
    }, test_seed);
    cpu.V[0xA] = 255;
    cpu.V[0xB] = 7;
    try cpu.cycle();
    try std.testing.expectEqual(255 >> 1, cpu.V[0xA]);
    try std.testing.expectEqual(7, cpu.V[0xB]);
    try std.testing.expectEqual(1, cpu.V[0xF]);
}

/// 8XY7: set register VX to VY - VX; set VF to 0 if underflow occurred, 0 otherwise
fn op8XY7(vx: u8, vy: u8) !LogicalOpcodeResult {
    const result = @subWithOverflow(vy, vx);
    return .{ result[0], 1 - result[1] };
}

test "8XY7 set VX to VY - VX" {
    var cpu = try Cpu.init(&[_]u8{
        0x82, 0x37,
        0x8D, 0xE7,
    }, test_seed);
    cpu.V[0x2] = 12;
    cpu.V[0x3] = 21;
    cpu.V[0xD] = 129;
    cpu.V[0xE] = 0;
    // no underflow this cycle
    try cpu.cycle();
    try std.testing.expectEqual(9, cpu.V[0x2]);
    try std.testing.expectEqual(21, cpu.V[0x3]);
    try std.testing.expectEqual(1, cpu.V[0xF]);
    // underflow this cycle
    try cpu.cycle();
    try std.testing.expectEqual(127, cpu.V[0xD]);
    try std.testing.expectEqual(0, cpu.V[0xE]);
    try std.testing.expectEqual(0, cpu.V[0xF]);
}

/// 8XYE: set register VX to VY << 1; set VF to the value of shifted out bit
fn op8XYE(vx: u8, vy: u8) !LogicalOpcodeResult {
    _ = vy;
    return .{ vx << 1, vx >> 7 };
}

test "8XYE set VX to VX << 1" {
    var cpu = try Cpu.init(&[_]u8{
        0x8B, 0xCE,
    }, test_seed);
    cpu.V[0xB] = 32;
    cpu.V[0xC] = 128;
    try cpu.cycle();
    try std.testing.expectEqual(32 << 1, cpu.V[0xB]);
    try std.testing.expectEqual(128, cpu.V[0xC]);
    try std.testing.expectEqual(0, cpu.V[0xF]);
}

/// 9XY0: skip instruction if register VX is not equal register VY
fn op9XY0(self: Instruction, cpu: *Cpu) !?u12 {
    return skipInstructionIf(cpu, cpu.V[self.reg_X] != cpu.V[self.reg_Y]);
}

test "9XY0 skip not equal register" {
    var cpu = try Cpu.init(&[_]u8{
        0x9A, 0xE0,
        0x00, 0x00,
        0x9A, 0xB0,
    }, test_seed);
    cpu.V[0xA] = 0x22;
    cpu.V[0xE] = 0x88;
    cpu.V[0xB] = 0x22;
    // should skip to 0x204 (0x22 != 0x88)
    try cpu.cycle();
    try std.testing.expectEqual(0x204, cpu.pc);
    // should step to 0x206 (0x22 == 0x22)
    try cpu.cycle();
    try std.testing.expectEqual(0x206, cpu.pc);
}

/// ANNN: set address register I to NNN
fn opANNN(self: Instruction, cpu: *Cpu) !?u12 {
    cpu.I = self.low_12;
    return null;
}

test "ANNN set address register I" {
    var cpu = try Cpu.init(&[_]u8{
        0xA2, 0x48,
    }, test_seed);
    try cpu.cycle();
    try std.testing.expectEqual(0x248, cpu.I);
}

/// BNNN: jump to NNN + V0
fn opBNNN(self: Instruction, cpu: *Cpu) !?u12 {
    return self.low_12 + cpu.V[0x0];
}

test "BNNN jump to NNN + V0" {
    var cpu = try Cpu.init(&[_]u8{
        0xB1, 0x23,
    }, test_seed);
    cpu.V[0x0] = 0x32;
    try cpu.cycle();
    try std.testing.expectEqual(0x155, cpu.pc);
}

/// CXNN: set register VX to NN & rand()
fn opCXNN(self: Instruction, cpu: *Cpu) !?u12 {
    cpu.V[self.reg_X] = self.low_8 & cpu.rand.random().int(u8);
    return null;
}

test "CXNN set register VX to NN & rand()" {
    var cpu = try Cpu.init(&[_]u8{
        0xCA, 0xE0, // will be AND'd with rand(0xB6)
    }, test_seed);
    cpu.V[0xA] = 0xFF;
    try cpu.cycle();
    try std.testing.expectEqual(0xA0, cpu.V[0xA]); // 0xE0 & 0xB6 = 0xA0
}

/// DXYN: draw 8xN sprite at address I in memory at (X, Y) on screen;
/// set VF to 1 if any pixel was turned off, 0 otherwise
fn opDXYN(self: Instruction, cpu: *Cpu) !?u12 {
    cpu.V[0xF] = 0;

    const sprite = cpu.mem[cpu.I..][0..self.low_4];

    const x_start = cpu.V[self.reg_X] % Cpu.display_width;
    const y_start = cpu.V[self.reg_Y] % Cpu.display_height;

    for (sprite, 0..) |row, y_sprite| {
        for (0..8) |x_sprite| {
            const pixel: u1 = @truncate(row >> @intCast(7 - x_sprite));

            const x: u8 = @intCast(x_start + x_sprite);
            const y: u8 = @intCast(y_start + y_sprite);

            if (x >= Cpu.display_width or y >= Cpu.display_height) {
                continue;
            }

            if (pixel == 1) {
                if (cpu.getPixel(x, y) == 1) {
                    cpu.V[0xF] = 1;
                }
                cpu.invertPixel(x, y);
                cpu.display_dirty = true;
            }
        }
    }

    return null;
}

test "DXYN draw sprite" {
    var cpu = try Cpu.init(&[_]u8{
        0xD1, 0x24,
    }, test_seed);
    try cpu.cycle();
}

/// EX9E: skip next instruction if key in register VX is pressed
/// EXA1: skip next instruction if key in reigster VX is not pressed
fn opInput(self: Instruction, cpu: *Cpu) !?u12 {
    return switch (self.low_8) {
        0x9E => skipInstructionIf(cpu, cpu.keys[cpu.V[self.reg_X]]),
        0xA1 => skipInstructionIf(cpu, !cpu.keys[cpu.V[self.reg_X]]),
        else => error.IllegalOpcode,
    };
}

test "EX## illegal opcode" {
    var cpu = try Cpu.init(&[_]u8{
        0xEA, 0x1F,
    }, test_seed);

    try std.testing.expectError(error.IllegalOpcode, cpu.cycle());
}

test "EX9E skip if pressed" {
    var cpu = try Cpu.init(&[_]u8{
        0xEA, 0x9E,
        0x00, 0x00,
        0xE0, 0x9E,
    }, test_seed);
    cpu.V[0xA] = 0xF;
    cpu.keys[0xF] = true;
    // should skip
    try cpu.cycle();
    try std.testing.expectEqual(0x204, cpu.pc);
    // should not skip
    try cpu.cycle();
    try std.testing.expectEqual(0x206, cpu.pc);
}

test "EXA1 skip if not pressed" {
    var cpu = try Cpu.init(&[_]u8{
        0xE0, 0xA1,
        0x00, 0x00,
        0xEA, 0xA1,
    }, test_seed);
    cpu.V[0xA] = 0xF;
    cpu.keys[0xF] = true;
    // should skip
    try cpu.cycle();
    try std.testing.expectEqual(0x204, cpu.pc);
    // should not skip
    try cpu.cycle();
    try std.testing.expectEqual(0x206, cpu.pc);
}

fn opMisc(self: Instruction, cpu: *Cpu) !?u12 {
    const misc_fn_table = comptime blk: {
        var fns: [256]OpcodeFn = .{opNOOP} ** 256;
        fns[0x07] = opFX07;
        fns[0x15] = opFX15;
        fns[0x18] = opFX18;
        fns[0x0A] = opFX0A;
        fns[0x1E] = opFX1E;
        fns[0x29] = opFX29;
        fns[0x33] = opFX33;
        fns[0x55] = opFX55;
        fns[0x65] = opFX65;
        break :blk fns;
    };

    return misc_fn_table[self.low_8](self, cpu);
}

/// FX07: set register VX to value of delay timer
fn opFX07(self: Instruction, cpu: *Cpu) !?u12 {
    cpu.V[self.reg_X] = cpu.dt;
    return null;
}

test "FX07 set VX to value of dt" {
    var cpu = try Cpu.init(&[_]u8{
        0xFA, 0x07,
    }, test_seed);
    cpu.dt = 0xAB;
    try cpu.cycle();
    try std.testing.expectEqual(0xAB, cpu.V[0xA]);
}

/// FX0A: wait for next key press; store key value in VX
fn opFX0A(self: Instruction, cpu: *Cpu) !?u12 {
    cpu.next_key_register = self.reg_X;
    return cpu.pc;
}

test "FX0A wait for key press" {
    var cpu = try Cpu.init(&[_]u8{
        0xF2, 0x0A,
    }, test_seed);
    // should remain on key press instruction
    try cpu.cycle();
    var new_keys: [16]bool = .{false} ** 16;
    cpu.setKeys(&new_keys);
    try std.testing.expectEqual(0x2, cpu.next_key_register);
    try std.testing.expectEqual(0x200, cpu.pc);
    // should store key (0xF) in VX and advance pc
    try cpu.cycle();
    new_keys[0xF] = true; // set F key as pressed
    cpu.setKeys(&new_keys);
    try std.testing.expectEqual(null, cpu.next_key_register);
    try std.testing.expectEqual(0xF, cpu.V[0x2]);
    try std.testing.expectEqual(0x202, cpu.pc);
}

/// FX15: set delay timer to register VX
fn opFX15(self: Instruction, cpu: *Cpu) !?u12 {
    cpu.dt = cpu.V[self.reg_X];
    return null;
}

test "FX15 set dt to VX" {
    var cpu = try Cpu.init(&[_]u8{
        0xFC, 0x15,
    }, test_seed);
    cpu.V[0xC] = 0xAA;
    try cpu.cycle();
    try std.testing.expectEqual(0xAA, cpu.dt);
}

/// FX18: set sound timer to register VX
fn opFX18(self: Instruction, cpu: *Cpu) !?u12 {
    cpu.st = cpu.V[self.reg_X];
    return null;
}

test "FX18 set st to VX" {
    var cpu = try Cpu.init(&[_]u8{
        0xFE, 0x18,
    }, test_seed);
    cpu.V[0xE] = 0xF1;
    try cpu.cycle();
    try std.testing.expectEqual(0xF1, cpu.st);
}

/// FX1E: set memory index register I to I + VX; set VF to 1 of overflow occurrs, 0 otherwise
fn opFX1E(self: Instruction, cpu: *Cpu) !?u12 {
    const result = @addWithOverflow(cpu.I, cpu.V[self.reg_X]);
    cpu.I = result[0];
    cpu.V[0xF] = result[1];
    return null;
}

test "FX1E set I to I + VX" {
    var cpu = try Cpu.init(&[_]u8{
        0xFA, 0x1E,
        0xFB, 0x1E,
    }, test_seed);
    cpu.I = 0xF00;
    cpu.V[0xA] = 0xFF;
    cpu.V[0xB] = 0x01;
    // no overflow this cycle
    try cpu.cycle();
    try std.testing.expectEqual(0xFFF, cpu.I);
    try std.testing.expectEqual(0, cpu.V[0xF]);
    // carry flag should be set this cycle
    try cpu.cycle();
    try std.testing.expectEqual(0x00, cpu.I);
    try std.testing.expectEqual(1, cpu.V[0xF]);
}

/// FX29: set I to the address of the sprite for the glyph in VX
fn opFX29(self: Instruction, cpu: *Cpu) !?u12 {
    cpu.I = Cpu.font_base_address + (Cpu.font_glyph_stride * cpu.V[self.reg_X]);
    return null;
}

test "FX29 set I to address of font glyph" {
    var cpu = try Cpu.init(&[_]u8{
        0xFE, 0x29,
    }, test_seed);
    cpu.V[0xE] = 0x1;
    try cpu.cycle();
    try std.testing.expectEqual(Cpu.font_base_address + Cpu.font_glyph_stride * 0x1, cpu.I);
}

/// FX33: split value in register VX into 3 digits, stored sequentially starting at address I
fn opFX33(self: Instruction, cpu: *Cpu) !?u12 {
    var value = cpu.V[self.reg_X];
    for (0..3) |i| {
        cpu.mem[(cpu.I + 2) - i] = value % 10;
        value /= 10;
    }
    return null;
}

test "FX33 binary-coded decimal conversion" {
    var cpu = try Cpu.init(&[_]u8{
        0xFA, 0x33,
    }, test_seed);
    cpu.V[0xA] = 123;
    cpu.I = 0x300;
    try cpu.cycle();
    try std.testing.expectEqual(0x300, cpu.I);
    try std.testing.expectEqual(123, cpu.V[0xA]);
    try std.testing.expectEqual(1, cpu.mem[cpu.I + 0]);
    try std.testing.expectEqual(2, cpu.mem[cpu.I + 1]);
    try std.testing.expectEqual(3, cpu.mem[cpu.I + 2]);
}

/// FX55: load registers V0 - VX into memory starting at address I
fn opFX55(self: Instruction, cpu: *Cpu) !?u12 {
    for (0..self.reg_X + 1) |index| {
        cpu.mem[cpu.I + index] = cpu.V[index];
    }
    return null;
}

test "FX55 store registers" {
    var cpu = try Cpu.init(&[_]u8{
        0xF5, 0x55,
    }, test_seed);
    cpu.I = 0x300;
    @memcpy(cpu.V[0..5], &[_]u8{ 1, 2, 3, 4, 5 });
    try cpu.cycle();
    try std.testing.expectEqual(0x300, cpu.I);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 1, 2, 3, 4, 5 }, cpu.mem[cpu.I .. cpu.I + 5]);
}

/// FX65: store memory starting at address I into registers V0 - VX
fn opFX65(self: Instruction, cpu: *Cpu) !?u12 {
    for (0..self.reg_X + 1) |index| {
        cpu.V[index] = cpu.mem[cpu.I + index];
    }
    return null;
}

test "FX65 load registers" {
    var cpu = try Cpu.init(&[_]u8{
        0xF5, 0x65,
    }, test_seed);
    cpu.I = 0x400;
    @memcpy(cpu.mem[cpu.I..][0..5], &[_]u8{ 5, 4, 3, 2, 1 });
    try cpu.cycle();
    try std.testing.expectEqual(0x400, cpu.I);
    try std.testing.expectEqualSlices(u8, &[_]u8{0} ** 11, cpu.V[5..]);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 5, 4, 3, 2, 1 }, cpu.V[0..5]);
}
