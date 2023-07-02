const std = @import("std");
const expect = std.testing.expect;
const register_store = @import("register_store.zig");
const Register = register_store.Register;
const instruction = @import("instruction.zig");
const Instruction = instruction.Instruction;
const Operand = instruction.Operand;
const Opcode = instruction.Opcode;

const CpuError = error {
    MovSourceNotFound,
};

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
                return error.MovSourceNotFound;
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
