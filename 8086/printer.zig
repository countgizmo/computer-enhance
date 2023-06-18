const std = @import("std");
const fmt = std.fmt;
const ArrayList = std.ArrayList;
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

pub const mem_calc_human_readable = [_][]const u8{
    "[bx + si]",
    "[bx + di]",
    "[bp + si]",
    "[bp + di]",};

fn operandToStr(allocator: Allocator, operand: Operand) ![]u8 {
    var result: []u8 = switch (operand) {
        .register => |val| {
            return fmt.allocPrint(allocator, "{s}", .{@tagName(val)});
        },
        .immediate => |val| {
            return fmt.allocPrint(allocator, "{d}", .{val});
        },
        .memory_calculation => |val| {
            const hr = mem_calc_human_readable[@enumToInt(val)];
            return fmt.allocPrint(allocator, "{s}", .{hr});
        },
    };

    return result;
}

fn bufPrintInstruction(allocator: Allocator, inst: Instruction) ![]u8 {
    const operand1 = try operandToStr(allocator, inst.operand1);
    defer allocator.free(operand1);

    if (inst.operand2) |op2| {
        const operand2 = try operandToStr(allocator, op2);
        defer allocator.free(operand2);
        return try fmt.allocPrint(allocator, "{s} {s} {s}", .{ @tagName(inst.opcode), operand1, operand2 });
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
    try stdout.print("; bits 16\n\n", .{});
}

test "print mov" {
    const inst: Instruction = .{
        .opcode = Opcode.mov,
        .operand1 = .{
            .register = Register.al,
        },
        .operand2 = .{
            .immediate = 3456,
        },
    };
    var buf: [256]u8 = undefined;
    const expected = "mov al 3456";
    const actual = try bufPrintInstruction(&buf, inst);
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
            .memory_calculation = MemoryCalculation.bx_si,
        },
    };
    const expected = "mov al [bx + si]";
    const actual = try bufPrintInstruction(allocator, inst);
    defer allocator.free(actual);
    try std.testing.expectEqualSlices(u8, expected, actual);
}
