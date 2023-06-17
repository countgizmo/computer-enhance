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

fn operandToStr(operand: Operand) []const u8 {
    var buf: [16]u8 = undefined;
    const result: []const u8 = switch (operand) {
        .register => |val| @tagName(val),
        .immediate => |val| {
            var foo: []u8 = &.{};
            return fmt.bufPrint(&buf, "{d}", .{val}) catch foo;
        },
    };

    return result;
}

fn bufPrintInstruction(buf: []u8, inst: Instruction) ![]u8 {
    var result: []u8 = undefined;
    const operand1 = operandToStr(inst.operand1);

    if (inst.operand2) |op2| {
        const operand2 = operandToStr(op2);
        result = try fmt.bufPrint(buf, "{s} {s} {s}", .{ @tagName(inst.opcode), operand1, operand2 });
    } else {
        result = try fmt.bufPrint(buf, "{s} {s}", .{ @tagName(inst.opcode), operand1 });
    }

    return result;
}

pub fn printInstruction(inst: Instruction) !void {
    var buf: [256]u8 = undefined;
    const stdout = std.io.getStdOut().writer();
    const inst_str = try bufPrintInstruction(&buf, inst);
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
