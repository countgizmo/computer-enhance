const std = @import("std");
const fmt = std.fmt;
const Allocator = std.mem.Allocator;
const log = std.log;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const instruction = @import("instruction.zig");
const Instruction = instruction.Instruction;
const Opcode = instruction.Opcode;
const Register = instruction.Register;
const Operand = instruction.Operand;
const MemoryCalculation = instruction.MemoryCalculation;

fn operandToStr(allocator: Allocator, operand: Operand) ![]u8 {
    var result: []u8 = switch (operand) {
        .register => |val| {
            return fmt.allocPrint(allocator, "{s}", .{@tagName(val)});
        },
        .immediate => |val| {
            if (val.size) |data_size| {
                return fmt.allocPrint(allocator, "{s} {d}", .{@tagName(data_size), val.value});
            }
            return fmt.allocPrint(allocator, "{d}", .{val.value});
        },
        .mem_calc_no_disp => |val| {
            if (val.mem_calc.register2 != null) {
                return fmt.allocPrint(allocator,
                    "[{s} + {s}]", .{@tagName(val.mem_calc.register1), @tagName(val.mem_calc.register2.?)});
            }
            return fmt.allocPrint(allocator,
                "[{s}]", .{@tagName(val.mem_calc.register1)});
        },
        .mem_calc_with_disp => |val| {
            if (val.register2 != null) {
                if (val.disp) |disp| {
                    switch (disp) {
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
                } else {
                    return fmt.allocPrint(allocator,
                        "[{s} + {s}]", .{@tagName(val.register1), @tagName(val.register2.?)});
                }
            }

            if (val.disp) |disp| {
                switch (disp) {
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
            }

            return fmt.allocPrint(allocator,
                "[{s}]", .{@tagName(val.register1)});
        },
        .direct_address => |val| {
            return fmt.allocPrint( allocator, "[{d}]", .{val});
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
        return try fmt.allocPrint(allocator, "{s} {s}, {s}", .{ @tagName(inst.opcode), operand1, operand2 });
    } else {
        return try fmt.allocPrint(allocator, "{s} {s}", .{ @tagName(inst.opcode), operand1 });
    }

    return &.{};
}

pub fn printInstruction(allocator: Allocator, inst: Instruction) !void {
    const stdout = std.io.getStdOut().writer();
    const inst_str = try bufPrintInstruction(allocator, inst);
    try stdout.print("{s}\n", .{inst_str});
}

pub fn printHeader(file_name: []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("; FILE: {s}\n", .{file_name});
    try stdout.print("bits 16\n\n", .{});
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
                .mem_calc = .{
                    .register1 = Register.bx,
                    .register2 = Register.si,
                },
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
                .mem_calc = .{
                    .register1 = Register.bp,
                    .register2 = Register.di,
                },
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
