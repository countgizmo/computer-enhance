const std = @import("std");
const fmt = std.fmt;
const Allocator = std.mem.Allocator;
const log = std.log;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const Register = @import("register_store.zig").Register;
const instruction = @import("instruction.zig");
const Instruction = instruction.Instruction;
const Opcode = instruction.Opcode;
const Operand = instruction.Operand;
const MemoryCalculation = instruction.MemoryCalculation;

fn explicitType(allocator: Allocator, inst: Instruction) ?[]u8 {
    if (inst.operand2) |operand2| {
        switch (operand2) {
            .immediate => |val| {
                if (val.size) |val_size| {
                    return fmt.allocPrint(allocator, "{s}", .{@tagName(val_size)}) catch null;
                }
            },
            else => {
                return null;
            }
        }
    }
    return null;
}

fn operandToStr(allocator: Allocator, operand: Operand) ![]u8 {
    var result: []u8 = switch (operand) {
        .register => |val| {
            return fmt.allocPrint(allocator, "{s}", .{@tagName(val)});
        },
        .immediate => |val| {
            return fmt.allocPrint(allocator, "{d}", .{val.value});
        },
        .mem_calc_no_disp => |val| {
            if (val.register2 != null) {
                return fmt.allocPrint(allocator,
                    "[{s} + {s}]", .{@tagName(val.register1), @tagName(val.register2.?)});
            }
            return fmt.allocPrint(allocator,
                "[{s}]", .{@tagName(val.register1)});
        },
        .mem_calc_with_disp => |val| {
            if (val.register2 != null) {
                switch (val.disp) {
                    .byte => |byte_disp| {
                        const sign: u8 = if (byte_disp >= 0) '+' else '-';
                        const display_value = if (byte_disp >= 0) byte_disp else byte_disp * -1;
                        return fmt.allocPrint(allocator,
                        "[{s} + {s} {c} {d}]", .{@tagName(val.register1), @tagName(val.register2.?), sign, display_value});
                    },
                    .word => |word_disp| {
                        const sign: u8 = if (word_disp >= 0) '+' else '-';
                        const display_value = if (word_disp >= 0) word_disp else word_disp * -1;
                        return fmt.allocPrint(allocator,
                        "[{s} + {s} {c} {d}]", .{@tagName(val.register1), @tagName(val.register2.?), sign, display_value});
                    },
                }
            }

            switch (val.disp) {
                .byte => |byte_disp| {
                    if (byte_disp != 0) {
                        const sign: u8 = if (byte_disp >= 0) '+' else '-';
                        const display_value = if (byte_disp >= 0) byte_disp else byte_disp * -1;
                        return fmt.allocPrint(allocator,
                        "[{s} {c} {d}]", .{@tagName(val.register1), sign, display_value});
                    }
                },
                .word => |word_disp| {
                    if (word_disp != 0) {
                        const sign: u8 = if (word_disp >= 0) '+' else '-';
                        const display_value = if (word_disp >= 0) word_disp else word_disp * -1;
                        return fmt.allocPrint(allocator,
                        "[{s} {c} {d}]", .{@tagName(val.register1), sign, display_value});
                    }
                }
            }

            return fmt.allocPrint(allocator,
                "[{s}]", .{@tagName(val.register1)});
        },
        .direct_address => |val| {
            return fmt.allocPrint(allocator, "[{d}]", .{val});
        },
        .signed_inc_to_ip => |val| {
            const sign: u8 = if (val >= 0) '+' else '-';
            const display_value = if (val >= 0) val else val * -1;
            return fmt.allocPrint(allocator, "{c}{d}", .{sign, display_value});
        }
    };

    return result;
}

fn bufPrintInstruction(allocator: Allocator, inst: Instruction) ![]u8 {
    const operand1 = try operandToStr(allocator, inst.operand1);
    defer allocator.free(operand1);


    if (inst.operand2) |op2| {
        const operand2 = try operandToStr(allocator, op2);
        defer allocator.free(operand2);
        const explicit_type = explicitType(allocator, inst);

        if (explicit_type) |et| {
            defer allocator.free(et);
            switch (inst.opcode) {
                .add, .sub, .cmp => {
                    return try fmt.allocPrint(allocator, "{s} {s} {s}, {s}", .{ @tagName(inst.opcode), et, operand1, operand2 });
                },
                else => {
                    return try fmt.allocPrint(allocator, "{s} {s}, {s} {s}", .{ @tagName(inst.opcode), operand1, et, operand2 });
                }
            }
        }

        return try fmt.allocPrint(allocator, "{s} {s}, {s}", .{ @tagName(inst.opcode), operand1, operand2 });
    } else {
        switch (inst.opcode) {
            .je, .jl, .jle, .jb, .jbe, .jp,
            .jo, .js, .jnz, .jnl, .jnle, .jnb,
            .jnbe, .jnp, .jno, .jns, .loop,
            .loopz, .loopnz, .jcxz => {
                return try fmt.allocPrint(allocator, "{s} $+2{s}", .{@tagName(inst.opcode), operand1});
            },
            else => {
                return try fmt.allocPrint(allocator, "{s} {s}", .{ @tagName(inst.opcode), operand1 });
            }
        }
    }

    return &.{};
}

fn getEAClocks(operand: Operand) usize {
    switch (operand) {
        .direct_address => {
            return 6;
        },
        else => {}
    }

    return 0;
}

fn getMovClocks(inst: Instruction) usize {
    switch(inst.operand1) {
        .register => {
            switch(inst.operand2.?) {
                .register => {
                    return 2;
                },
                .immediate => {
                    return 4;
                },
                .mem_calc_no_disp => {
                    return 8 + getEAClocks(inst.operand2.?);
                },
                .mem_calc_with_disp => {
                    return 69;
                },
                .direct_address => {
                    return 8 + getEAClocks(inst.operand2.?);
                },
                else => {
                    return 0;
                }
            }
        },
        else => {
        }
    }
    return 0;
}

fn getClocks(inst: Instruction) usize {
    var result: usize = 0;

    switch (inst.opcode) {
        .mov => {
            result = getMovClocks(inst);
        },
        else => {}
    }

    return result;
}

pub fn printInstruction(allocator: Allocator, inst: Instruction, show_clocks: bool) !void {
    const stdout = std.io.getStdOut().writer();
    const inst_str = try bufPrintInstruction(allocator, inst);

    if (show_clocks) {
        const clocks = getClocks(inst);
        try stdout.print("{s} ; Clocks = {d}", .{inst_str, clocks});
    } else {
        try stdout.print("{s}", .{inst_str});
    }
}

pub fn printHeader(file_name: []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("; FILE: {s}\n", .{file_name});
    try stdout.print("bits 16\n\n", .{});
}

pub fn printListing(allocator: Allocator, file_name: []const u8, insts: []Instruction, show_clocks: bool) !void {
    const stdout = std.io.getStdOut().writer();
    try printHeader(file_name);
    for (insts) |inst| {
        try printInstruction(allocator, inst, show_clocks);
        try stdout.print("\n", .{});
    }
}

test "print mov" {
    var allocator = std.testing.allocator;
    const inst: Instruction = .{
        .opcode = Opcode.mov,
        .operand1 = .{
            .register = Register.al,
        },
        .operand2 = .{
            .immediate = .{ .value = 3456 },
        },
    };
    const expected = "mov al, 3456";
    const actual = try bufPrintInstruction(allocator, inst);
    defer allocator.free(actual);
    try std.testing.expectEqualSlices(u8, expected, actual);
}

test "print memory calculation" {
    var allocator = std.testing.allocator;
    const inst: Instruction = .{
        .opcode = Opcode.mov,
        .operand1 = .{
            .register = Register.al,
        },
        .operand2 = .{
            .mem_calc_no_disp = .{
                .register1 = Register.bx,
                .register2 = Register.si,
            },
        },
    };
    const expected = "mov al, [bx + si]";
    const actual = try bufPrintInstruction(allocator, inst);
    defer allocator.free(actual);
    try std.testing.expectEqualSlices(u8, expected, actual);
}

test "print memory calculation with 8-bit displacemenet" {
    var allocator = std.testing.allocator;
    const inst: Instruction = .{
        .opcode = Opcode.mov,
        .operand1 = .{
            .register = Register.al,
        },
        .operand2 = .{
            .mem_calc_with_disp = .{
                .register1 = Register.bx,
                .register2 = Register.si,
                .disp = .{ .byte = 4, },
            },
        },
    };
    const expected = "mov al, [bx + si + 4]";
    const actual = try bufPrintInstruction(allocator, inst);
    defer allocator.free(actual);
    try std.testing.expectEqualSlices(u8, expected, actual);
}

test "print memory calculation with displacemenet in destination" {
    var allocator = std.testing.allocator;
    const inst: Instruction = .{
        .opcode = Opcode.mov,
        .operand1 = .{
            .mem_calc_with_disp = .{
                .register1 = Register.si,
                .disp = .{ .word = -300, },
            },
        },
        .operand2 = .{
            .register = Register.cx,
        },
    };
    const expected = "mov [si - 300], cx";
    const actual = try bufPrintInstruction(allocator, inst);
    defer allocator.free(actual);
    try std.testing.expectEqualSlices(u8, expected, actual);
}


test "print memory calculation with zero 8-bit displacemenet" {
    var allocator = std.testing.allocator;
    const inst: Instruction = .{
        .opcode = Opcode.mov,
        .operand1 = .{
            .register = Register.al,
        },
        .operand2 = .{
            .mem_calc_with_disp = .{
                .register1 = Register.bx,
                .disp = .{ .byte = 0, },
            },
        },
    };
    const expected = "mov al, [bx]";
    const actual = try bufPrintInstruction(allocator, inst);
    defer allocator.free(actual);
    try std.testing.expectEqualSlices(u8, expected, actual);
}


test "print memory calculation with 16-bit displacemenet" {
    var allocator = std.testing.allocator;
    const inst: Instruction = .{
        .opcode = Opcode.mov,
        .operand1 = .{
            .register = Register.al,
        },
        .operand2 = .{
            .mem_calc_with_disp = .{
                .register1 = Register.bx,
                .register2 = Register.si,
                .disp = .{ .word = 4999, },
            },
        },
    };
    const expected = "mov al, [bx + si + 4999]";
    const actual = try bufPrintInstruction(allocator, inst);
    defer allocator.free(actual);
    try std.testing.expectEqualSlices(u8, expected, actual);
}

test "print destination mem calc with explicit byte size in source" {
    var allocator = std.testing.allocator;
    const inst: Instruction = .{
        .opcode = Opcode.mov,
        .operand1 = .{
            .mem_calc_no_disp = .{
                .register1 = Register.bp,
                .register2 = Register.di,
            },
        },
        .operand2 = .{
            .immediate = .{
                .value = 7,
                .size = .byte,
            },
        },
    };
    const expected = "mov [bp + di], byte 7";

    const actual = try bufPrintInstruction(allocator, inst);
    defer allocator.free(actual);
    try std.testing.expectEqualSlices(u8, expected, actual);
}

test "print destination mem calc with explicit word size in source" {
    var allocator = std.testing.allocator;
    const inst: Instruction = .{
        .opcode = Opcode.mov,
        .operand1 = .{
            .mem_calc_with_disp = .{
                    .register1 = Register.di,
                    .disp = .{ .word = 901 },
            },
        },
        .operand2 = .{
            .immediate = .{
                .value = 347,
                .size = .word,
            },
        },
    };

    const expected = "mov [di + 901], word 347";
    const actual = try bufPrintInstruction(allocator, inst);
    defer allocator.free(actual);
    try std.testing.expectEqualSlices(u8, expected, actual);
}

test "print direct address in source" {
    var allocator = std.testing.allocator;
    const inst: Instruction = .{
        .opcode = Opcode.mov,
        .operand1 = .{
            .register = Register.bp,
        },
        .operand2 = .{
            .direct_address = 5,
        },
    };

    const expected = "mov bp, [5]";
    const actual = try bufPrintInstruction(allocator, inst);
    defer allocator.free(actual);
    try std.testing.expectEqualSlices(u8, expected, actual);
}

test "print accumulator to memory" {
    var allocator = std.testing.allocator;
    const inst: Instruction = .{
        .opcode = Opcode.mov,
        .operand1 = .{
            .direct_address = 2554,
        },
        .operand2 = .{
            .register = Register.ax,
        },
    };

    const expected = "mov [2554], ax";
    const actual = try bufPrintInstruction(allocator, inst);
    defer allocator.free(actual);
    try std.testing.expectEqualSlices(u8, expected, actual);
}

test "print add immediate" {
    var allocator = std.testing.allocator;
    const inst: Instruction = .{
        .opcode = Opcode.add,
        .operand1 = .{
            .register = Register.si,
        },
        .operand2 = .{
            .immediate = .{
                .value = 2,
            },
        },
    };

    const expected = "add si, 2";
    const actual = try bufPrintInstruction(allocator, inst);
    defer allocator.free(actual);
    try std.testing.expectEqualSlices(u8, expected, actual);
}

test "print add explicit type" {
    var allocator = std.testing.allocator;
    const inst: Instruction = .{
        .opcode = Opcode.add,
        .operand1 = .{
            .mem_calc_with_disp = .{
                .register1 = Register.bp,
                .register2 = Register.si,
                .disp = .{ .word = 1000, },
            },
        },
        .operand2 = .{
            .immediate = .{
                .value = 29,
                .size = .word,
            },
        },
    };

    const expected = "add word [bp + si + 1000], 29";
    const actual = try bufPrintInstruction(allocator, inst);
    defer allocator.free(actual);
    try std.testing.expectEqualSlices(u8, expected, actual);
}

test "print jump" {
    var allocator = std.testing.allocator;
    const inst: Instruction = .{
        .opcode = Opcode.je,
        .operand1 = .{
            .signed_inc_to_ip = -2
        },
    };

    // Using $+2 for NASM: $+2 followed by the actuall offset.
    const expected = "je $+2-2";
    const actual = try bufPrintInstruction(allocator, inst);
    defer allocator.free(actual);
    try std.testing.expectEqualSlices(u8, expected, actual);
}
