const std = @import("std");
const log = std.log;
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const utils = @import("utils.zig");
const register_store = @import("register_store.zig");
const memory = @import("memory.zig");
const printer = @import("printer.zig");
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

fn cmp(a: u16, b: u16) void {
    const result = sub(a, b);
    flagsCheck(result);
}

fn sub(a: u16, b: u16) u16 {
    const result: i16 = @as(i16, @bitCast(a)) - @as(i16, @bitCast(b));
    return @as(u16, @bitCast(result));
}

fn add(a: u16, b: u16) u16 {
    const result: i16 = @as(i16, @bitCast(a)) + @as(i16, @bitCast(b));
    return @as(u16, @bitCast(result));
}

fn readWordFromMemory(address: u16) u16 {
    const lo = memory.load(address);
    const hi = memory.load(address+1);
    return utils.combineU8(lo, hi);
}

fn writeFromAddressToRegister(destination: Register, address: u16) void {
    const lo = memory.load(address);
    const hi = memory.load(address+1);
    const val = utils.combineU8(lo, hi);
    register_store.write(destination, val);
}

fn movToRegister(destination: Register, source: Operand) void {
    switch (source) {
        .immediate => |immediate| {
            register_store.write(destination, immediate.value);
        },
        .register => |reg| {
            register_store.writeFromRegister(destination, reg);
        },
        .direct_address => |address| {
            writeFromAddressToRegister(destination, address);
        },
        .mem_calc_no_disp => |calc_no_disp| {
            const address = calculateAddress(calc_no_disp.register1, calc_no_disp.register2); 
            writeFromAddressToRegister(destination, address);
        },
        else => {
            return;
        }
    }
}

fn movToDirectAddress(address: u16, source: Operand) void {
    switch (source) {
        .immediate => |immediate| {
            if (immediate.size) |size| {
                switch (size) {
                    .byte => {
                        const val = utils.u16ToU8(immediate.value);
                        memory.store(address, val);
                    },
                    .word => {
                        const val = utils.splitU16(immediate.value);
                        memory.store(address, val[0]);
                        memory.store(address+1, val[1]);
                    }
                }
            }
        },
        .register => |reg| {
            const val = utils.splitU16(register_store.read(reg));
            memory.store(address, val[0]);
            memory.store(address+1, val[1]);
        },
        else => {
            return;
        }
    }
}

fn calculateAddress(register1: Register, register2: ?Register) u16 {
    var address = register_store.read(register1);

    if (register2) |reg2| {
        address += register_store.read(reg2);
    }

    return address;
}

fn calculateAddressWithDisp(calc: instruction.MemCalcWithDisp) u16 {
    var address = calculateAddress(calc.register1, calc.register2);

    switch (calc.disp) {
        .byte => |byte_disp| {
            const result = @as(i16, @bitCast(address)) + @as(i8, @bitCast(byte_disp));
            address = @as(u16, @bitCast(result));
        },
        .word => |word_disp| {
            const result = @as(i16, @bitCast(address)) + @as(i16, @bitCast(word_disp));
            address = @as(u16, @bitCast(result));
        }
    }

    return address;
}

fn movToAddressWithDisplacement(calc: instruction.MemCalcWithDisp, source: Operand) void {
    const address = calculateAddressWithDisp(calc); 
    return movToDirectAddress(address, source);
}

fn movToAddressNoDisplacement(calc: instruction.MemCalcNoDisp, source: Operand) void {
    const address = calculateAddress(calc.register1, calc.register2); 
    return movToDirectAddress(address, source);
}

fn execMov(inst: Instruction) !void {
    if (inst.operand2 == null) {
        return error.SourceNotFound;
    }

    switch (inst.operand1) {
        .register => |reg| {
            return movToRegister(reg, inst.operand2.?);
        },
        .direct_address => |address| {
            return movToDirectAddress(address, inst.operand2.?);
        },
        .mem_calc_no_disp => |calc_no_disp| {
            return movToAddressNoDisplacement(calc_no_disp, inst.operand2.?);
        },
        .mem_calc_with_disp => |calc| {
            return movToAddressWithDisplacement(calc, inst.operand2.?);
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
    const dst = register_store.read(destination);
    switch (source) {
        .register => |reg| {
            const src = register_store.read(reg);
            cmp(dst, src);
        },
        .immediate => |immediate| {
            cmp(dst, immediate.value);
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
    var result: u16 = undefined;
    const dst = register_store.read(destination);
    var src: u16 = undefined;

    switch (source) {
        .immediate => |immediate| {
            src = immediate.value;
        },
        .mem_calc_no_disp => |calc_no_disp| {
            const address = calculateAddress(calc_no_disp.register1, calc_no_disp.register2); 
            src = readWordFromMemory(address);
        },
        else => {
            return;
        }
    }

    result = add(dst, src);
    register_store.write(destination, result);
    flagsCheck(result);
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

fn execJneJnz(inst: Instruction) !void {
    const zf = flags.getFlag(.zf);
    const ip = register_store.readIP();
    if (zf != 1) {
        const new_ip = @as(i16, @bitCast(ip)) + @as(i16, @intCast(inst.operand1.signed_inc_to_ip));
        register_store.writeIP(@as(u16, @bitCast(new_ip)));
    }
}

fn execLoop(inst: Instruction) !void {
    const source = .{
        .immediate = .{ .value = 1},
    };
    subFromRegister(.cx, source);
    try execJneJnz(inst);
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
        .jnz => {
            try execJneJnz(inst);
        },
        .loop => {
            try execLoop(inst);
        },
        else => {
            return;
        }
    }
}

fn getInstruction(insts: []Instruction, ip: u16) ?Instruction {
    var offset: usize = 0;
    var idx: usize = 0;
    while (idx < insts.len) : (idx += 1) {
        if (offset == ip) {
            return insts[idx];
        }
        offset += insts[idx].size;
    }

    return null;
}

pub fn execInstrucitons(insts: []Instruction) !void {
    var current_ip = register_store.readIP();
    while (getInstruction(insts, current_ip)) |inst| {
        const new_ip = current_ip + inst.size;
        register_store.writeIP(new_ip);
        try execInstruction(inst);
        current_ip = register_store.readIP();
    }
}

test "moving immediate to memory" {
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
}

test "moving byte immediate to memory" {
    const inst: Instruction = .{
        .opcode = .mov,
        .operand1 = .{
            .direct_address = 1000
        },
        .operand2 = .{
            .immediate = .{ .value = 250, .size = .byte },
        },
    };

    try execInstruction(inst);
    try expect(memory.load(1000) == 250);
    try expect(memory.load(1001) == 0);
}

test "moving word immediate to memory" {
    const inst: Instruction = .{
        .opcode = .mov,
        .operand1 = .{
            .direct_address = 2000
        },
        .operand2 = .{
            .immediate = .{ .value = 0b0000010011100010, .size = .word },
        },
    };

    try execInstruction(inst);
    try expect(memory.load(2000) == 0b11100010);
    try expect(memory.load(2001) == 0b00000100);
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
            .immediate = .{ .value = @as(u16, @bitCast(immediate1)) },
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

    try expect(@as(i16, @bitCast(result)) == -7934);
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

    try expect(@as(i16, @bitCast(result)) == 0);
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
            .immediate = .{ .value = @as(u16, @bitCast(immediate1)) },
        },
        .size = 2,
    };

    const inst2: Instruction = .{
        .opcode = Opcode.mov,
        .operand1 = .{
            .register = .cx,
        },
        .operand2 = .{
            .immediate = .{ .value = 3841 },
        },
        .size = 2,
    };

    const inst3: Instruction = .{
        .opcode = Opcode.sub,
        .operand1 = .{
            .register = .bx,
        },
        .operand2 = .{
            .register = .cx,
        },
        .size = 3,
    };

    const inst4: Instruction = .{
        .opcode = Opcode.mov,
        .operand1 = .{
            .register = .sp,
        },
        .operand2 = .{
            .immediate = .{ .value = 998 },
        },
        .size = 2,
    };

    const inst5: Instruction = .{
        .opcode = Opcode.mov,
        .operand1 = .{
            .register = .bp,
        },
        .operand2 = .{
            .immediate = .{ .value = 999 },
        },
        .size = 2,
    };

    const inst6: Instruction = .{
        .opcode = Opcode.cmp,
        .operand1 = .{
            .register = .bp,
        },
        .operand2 = .{
            .register = .sp,
        },
        .size = 3,
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

    try expect(@as(i16, @bitCast(result)) == 999);
    try expect(flags.getFlag(.sf) == 0);
    try expect(flags.getFlag(.zf) == 0);
}

test "get instruction by IP" {
    const immediate1: i16 = -4093;
    const inst1: Instruction = .{
        .opcode = Opcode.mov,
        .operand1 = .{
            .register = .bx,
        },
        .operand2 = .{
            .immediate = .{ .value = @as(u16, @bitCast(immediate1)) },
        },
        .size = 2,
    };

    const inst2: Instruction = .{
        .opcode = Opcode.mov,
        .operand1 = .{
            .register = .cx,
        },
        .operand2 = .{
            .immediate = .{ .value = 3841 },
        },
        .size = 2,
    };

    const inst3: Instruction = .{
        .opcode = Opcode.sub,
        .operand1 = .{
            .register = .bx,
        },
        .operand2 = .{
            .register = .cx,
        },
        .size = 3,
    };

    var allocator = std.testing.allocator;
    var instructions = ArrayList(Instruction).init(allocator);
    defer instructions.deinit();
    try instructions.append(inst1);
    try instructions.append(inst2);
    try instructions.append(inst3);

    if (getInstruction(instructions.items, 2)) |target_inst| {
        try expect(target_inst.opcode == inst2.opcode);
        try expect(target_inst.operand1.register == inst2.operand1.register);
        try expect(target_inst.operand2.?.immediate.value == inst2.operand2.?.immediate.value);
    }

    if (getInstruction(instructions.items, 4)) |target_inst| {
        try expect(target_inst.opcode == inst3.opcode);
        try expect(target_inst.operand1.register == inst3.operand1.register);
        try expect(target_inst.operand2.?.register == inst3.operand2.?.register);
    }

    const no_inst = getInstruction(instructions.items, 5);
    try expect(no_inst == null);
}
