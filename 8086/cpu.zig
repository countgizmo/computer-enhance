const std = @import("std");
const log = std.log;
const expect = std.testing.expect;
const register_store = @import("register_store.zig");
const Register = register_store.Register;
const instruction = @import("instruction.zig");
const Instruction = instruction.Instruction;
const Operand = instruction.Operand;
const Opcode = instruction.Opcode;
const flags = @import("flags.zig");

const CpuError = error {
    SourceNotFound,
};

fn flagsCheck(value: u16) void {
    if (value == 0) {
        flags.setFlag(.zf, 1);
    } else {
        flags.setFlag(.zf, 0);
    }

    if (value != 0) {
        if (value & (1 << 15) != 0) {
            flags.setFlag(.sf, 1);
        } else {
            flags.setFlag(.sf, 0);
        }
    }
}

fn sub(a: u16, b: u16) u16 {
    const result: i16 = @bitCast(i16, a) - @bitCast(i16, b);
    return @bitCast(u16, result);
}

fn add(a: u16, b: u16) u16 {
    const result: i16 = @bitCast(i16, a) + @bitCast(i16, b);
    return @bitCast(u16, result);
}

fn movToRegister(destination: Register, source: Operand) void {
    switch (source) {
        .immediate => |immediate| {
            register_store.write(destination, immediate.value);
        },
        .register => |reg| {
            register_store.writeFromRegister(destination, reg);
        },
        else => {
            return;
        }
    }
}

fn execMov(inst: Instruction) !void {
    switch (inst.operand1) {
        .register => |reg| {
            if (inst.operand2) |operand2| {
                return movToRegister(reg, operand2);
            } else {
                return error.SourceNotFound;
            }
        },
        else => {
            return;
        }
    }
}

fn subFromRegister(destination: Register, source: Operand) void {
    switch (source) {
        .register => |reg| {
            const src = register_store.read(reg);
            const dst = register_store.read(destination);
            const result = sub(dst, src);
            flagsCheck(result);
            register_store.write(destination, result);
        },
        .immediate => |immediate| {
            const src = immediate.value;
            const dst = register_store.read(destination);
            const result = sub(dst, src);
            flagsCheck(result);
            register_store.write(destination, result);
        },
        else => {
            return;
        }
    }
}

fn execSub(inst: Instruction) !void {
    switch (inst.operand1) {
        .register => |reg| {
            if (inst.operand2) |operand2| {
                return subFromRegister(reg, operand2);
            } else {
                return error.SourceNotFound;
            }
        },
        else => {
            return;
        }
    }
}

fn cmpWithRegister(destination: Register, source: Operand) void {
    switch (source) {
        .register => |reg| {
            const src = register_store.read(reg);
            const dst = register_store.read(destination);
            const result = sub(dst, src);
            flagsCheck(result);
        },
        else => {
            return;
        }
    }
}

fn execCmp(inst: Instruction) !void {
    switch (inst.operand1) {
        .register => |reg| {
            if (inst.operand2) |operand2| {
                return cmpWithRegister(reg, operand2);
            } else {
                return error.SourceNotFound;
            }
        },
        else => {
            return;
        }
    }
}

fn addToRegister(destination: Register, source: Operand) void {
    switch (source) {
        .immediate => |immediate| {
            const src = immediate.value;
            const dst = register_store.read(destination);
            const result = add(dst, src);
            flagsCheck(result);
            register_store.write(destination, result);
        },
        else => {
            return;
        }
    }
}

fn execAdd(inst: Instruction) !void {
    switch (inst.operand1) {
        .register => |reg| {
            if (inst.operand2) |operand2| {
                return addToRegister(reg, operand2);
            } else {
                return error.SourceNotFound;
            }
        },
        else => {
            return;
        }
    }
}

pub fn execInstruction(inst: Instruction) !void {
    switch (inst.opcode) {
        .mov => {
            try execMov(inst);
        },
        .sub => {
            try execSub(inst);
        },
        .cmp => {
            try execCmp(inst);
        },
        .add => {
            try execAdd(inst);
        },
        else => {
            return;
        }
    }
}

pub fn execInstrucitons(insts: []Instruction) !void {
    for (insts) |inst| {
        try execInstruction(inst);
    }
}

test "moving mmediate to memory" {
    const inst: Instruction = .{
        .opcode = Opcode.mov,
        .operand1 = .{
            .register = .ax,
        },
        .operand2 = .{
            .immediate = .{ .value = 1},
        },
    };

    try execInstruction(inst);
    try expect(register_store.read(.ax) == 1);
}

test "moving to low register" {
    const inst1: Instruction = .{
        .opcode = Opcode.mov,
        .operand1 = .{
            .register = .bx,
        },
        .operand2 = .{
            .immediate = .{ .value = 0x4444},
        },
    };

    const inst2: Instruction = .{
        .opcode = Opcode.mov,
        .operand1 = .{
            .register = .bl,
        },
        .operand2 = .{
            .immediate = .{ .value = 0x33},
        },
    };

    try execInstruction(inst1);
    try execInstruction(inst2);
    try expect(register_store.read(.bl) == 0x33);
    try register_store.printStatus();
}

test "moving to high register" {
    const inst1: Instruction = .{
        .opcode = Opcode.mov,
        .operand1 = .{
            .register = .dx,
        },
        .operand2 = .{
            .immediate = .{ .value = 0x8888},
        },
    };

    const inst2: Instruction = .{
        .opcode = Opcode.mov,
        .operand1 = .{
            .register = .dh,
        },
        .operand2 = .{
            .immediate = .{ .value = 0x77},
        },
    };

    try execInstruction(inst1);
    try execInstruction(inst2);
    try expect(register_store.read(.dh) == 0x77);
    try expect(register_store.read(.dl) == 0x88);
}

test "subtracting two registers with negative result" {
    const immediate1: i16 = -4093;
    const inst1: Instruction = .{
        .opcode = Opcode.mov,
        .operand1 = .{
            .register = .bx,
        },
        .operand2 = .{
            .immediate = .{ .value = @bitCast(u16, immediate1) },
        },
    };

    const inst2: Instruction = .{
        .opcode = Opcode.mov,
        .operand1 = .{
            .register = .cx,
        },
        .operand2 = .{
            .immediate = .{ .value = 3841 },
        },
    };

    const inst3: Instruction = .{
        .opcode = Opcode.sub,
        .operand1 = .{
            .register = .bx,
        },
        .operand2 = .{
            .register = .cx,
        },
    };


    register_store.resetRegisters();
    flags.resetFlags();
    try execInstruction(inst1);
    try execInstruction(inst2);
    try execInstruction(inst3);

    const result = register_store.read(.bx);

    try register_store.printStatus();
    try flags.printStatus();
    try expect(@bitCast(i16, result) == -7934);
    try expect(flags.getFlag(.sf) == 1);
    try expect(flags.getFlag(.zf) == 0);
}

test "subtracting two registers with zero result" {
    const inst1: Instruction = .{
        .opcode = Opcode.mov,
        .operand1 = .{
            .register = .bx,
        },
        .operand2 = .{
            .immediate = .{ .value = 3841 },
        },
    };

    const inst2: Instruction = .{
        .opcode = Opcode.mov,
        .operand1 = .{
            .register = .cx,
        },
        .operand2 = .{
            .immediate = .{ .value = 3841 },
        },
    };

    const inst3: Instruction = .{
        .opcode = Opcode.sub,
        .operand1 = .{
            .register = .bx,
        },
        .operand2 = .{
            .register = .cx,
        },
    };


    register_store.resetRegisters();
    flags.resetFlags();
    try execInstruction(inst1);
    try execInstruction(inst2);
    try execInstruction(inst3);

    const result = register_store.read(.bx);

    try register_store.printStatus();
    try flags.printStatus();
    try expect(@bitCast(i16, result) == 0);
    try expect(flags.getFlag(.sf) == 0);
    try expect(flags.getFlag(.zf) == 1);
}

test "comparing flow" {
    const immediate1: i16 = -4093;
    const inst1: Instruction = .{
        .opcode = Opcode.mov,
        .operand1 = .{
            .register = .bx,
        },
        .operand2 = .{
            .immediate = .{ .value = @bitCast(u16, immediate1) },
        },
    };

    const inst2: Instruction = .{
        .opcode = Opcode.mov,
        .operand1 = .{
            .register = .cx,
        },
        .operand2 = .{
            .immediate = .{ .value = 3841 },
        },
    };

    const inst3: Instruction = .{
        .opcode = Opcode.sub,
        .operand1 = .{
            .register = .bx,
        },
        .operand2 = .{
            .register = .cx,
        },
    };

    const inst4: Instruction = .{
        .opcode = Opcode.mov,
        .operand1 = .{
            .register = .sp,
        },
        .operand2 = .{
            .immediate = .{ .value = 998 },
        },
    };

    const inst5: Instruction = .{
        .opcode = Opcode.mov,
        .operand1 = .{
            .register = .bp,
        },
        .operand2 = .{
            .immediate = .{ .value = 999 },
        },
    };

    const inst6: Instruction = .{
        .opcode = Opcode.cmp,
        .operand1 = .{
            .register = .bp,
        },
        .operand2 = .{
            .register = .sp,
        },
    };


    register_store.resetRegisters();
    flags.resetFlags();
    try execInstruction(inst1);
    try execInstruction(inst2);
    try execInstruction(inst3);

    try expect(flags.getFlag(.sf) == 1);
    try expect(flags.getFlag(.zf) == 0);

    try execInstruction(inst4);
    try execInstruction(inst5);
    try execInstruction(inst6);

    const result = register_store.read(.bp);

    try register_store.printStatus();
    try flags.printStatus();

    try expect(@bitCast(i16, result) == 999);
    try expect(flags.getFlag(.sf) == 0);
    try expect(flags.getFlag(.zf) == 0);
}
