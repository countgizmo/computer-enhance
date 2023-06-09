const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const instruction = @import("instruction.zig");

const example = instruction.Instruction{
    .opcode = instruction.Opcode.Mov,
    .operand1 = .{
        .location = instruction.OperandType.Register,
        .register = instruction.Register.CX,
    },
    .operand2 = .{
        .location = instruction.OperandType.Register,
        .register = instruction.Register.BX,
    },
};

const encoding = struct {
    mnemonic: []const u8,
    bits_enc: []const u8,
};

const DecodedSizes = struct {
    opcode: u8 = 0,
    d_bit: u8 = 0,
    w_bit: u8 = 0,
    mod: u8 = 0,
    reg: u8 = 0,
    rm: u8 = 0,
    disp_lo: u8 = 0,
    disp_hi: u8 = 0,
};

fn isNumber(ch: u8) bool {
    return (ch >= '0' and ch <= '9');
}

fn charToDigit(ch: u8) u8 {
    return std.fmt.charToDigit(ch, 10) catch 0;
}

fn populateSize(sizes: *DecodedSizes, key_buffer: []u8, value_buffer: u8) void {
    if (std.mem.startsWith(u8, key_buffer, "opcode")) {
        sizes.opcode = charToDigit(value_buffer);
    } else if (std.mem.startsWith(u8, key_buffer, "disp-lo")) {
        sizes.disp_lo = charToDigit(value_buffer);
    } else if (std.mem.startsWith(u8, key_buffer, "disp-hi")) {
        sizes.disp_hi = charToDigit(value_buffer);
    } else if (std.mem.startsWith(u8, key_buffer, "mod")) {
        sizes.mod = charToDigit(value_buffer);
    } else if (std.mem.startsWith(u8, key_buffer, "reg")) {
        sizes.reg = charToDigit(value_buffer);
    } else if (std.mem.startsWith(u8, key_buffer, "rm")) {
        sizes.rm = charToDigit(value_buffer);
    } else if (std.mem.startsWith(u8, key_buffer, "d")) {
        sizes.d_bit = charToDigit(value_buffer);
    } else if (std.mem.startsWith(u8, key_buffer, "w")) {
        sizes.w_bit = charToDigit(value_buffer);
    }
}

fn decodeBits(bits: []const u8) DecodedSizes {
    var result: DecodedSizes = .{};
    var key_buffer: [8]u8 = undefined;
    var value_buffer: u8 = undefined;
    var i: usize = 0;

    for (bits) |bit| {
        if (bit != ':') {
            if (isNumber(bit)) {
                value_buffer = bit;
            } else {
                key_buffer[i] = bit;
                i += 1;
            }
            continue;
        } else {
            populateSize(&result, &key_buffer, value_buffer);
            i = 0;
            key_buffer = undefined;
        }
    }

    populateSize(&result, &key_buffer, value_buffer);

    return result;
}

fn createMapOfOpcodes() !*std.AutoArrayHashMap(u8, encoding) {
    var map = std.AutoArrayHashMap(u8, encoding).init(std.heap.page_allocator);

    try map.put(0b100010_00, .{ .mnemonic = "mov", .bits_enc = "opcode6:d1:w1:mod2:reg3:rm3:disp-lo8:disp-hi8" });

    return &map;
}


fn decodeInstruction(buffer: []const u8, offset: u16, sizes: DecodedSizes) ?instruction.Instruction {
    // TODO(evgheni): populate the  structure.
    return .{
        .opcode = instruction.Opcode.Mov,
        .operand1 = .{
            .location = instruction.OperandType.Register,
            .register = instruction.Register.CX,
        },
        .operand2 = .{
            .location = instruction.OperandType.Register,
            .register = instruction.Register.BX,
        },
    };
}

pub fn decode(buffer: []const u8, offset: u16) !?instruction.Instruction {
    if (buffer.len > 0 and offset == 0) {
        const map = try createMapOfOpcodes();
        defer map.deinit();

        var iter = map.iterator();
        while (iter.next()) |map_entry| {
            const mask = map_entry.key_ptr.*;
            if (buffer[0] & mask == mask) {

                // TODO(evgheni): write a function to decode bits_enc
                std.log.warn("encoding: {s}", .{map_entry.value_ptr.*.bits_enc});
            }
        }
        return example;
    }

    return null;
}

test "Decoding sizes" {
    const test_enc = "opcode6:d1:w1:mod2:reg3:rm3:disp-lo8:disp-hi8";
    const bits = decodeBits(test_enc);
    try expect(bits.opcode == 6);
    try expect(bits.d_bit == 1);
    try expect(bits.w_bit == 1);
    try expect(bits.mod == 2);
    try expect(bits.reg == 3);
    try expect(bits.rm == 3);
    try expect(bits.disp_lo == 8);
    try expect(bits.disp_hi == 8);
}

test "decoding bits and sizes into instruction" {
    const bytes_buffer: [2]u8 = .{ 0b10001001, 0b11011001 };
    const bits: DecodedSizes = .{
        .opcode = 6,
        .d_bit = 1,
        .w_bit = 1,
        .mod = 2,
        .reg = 3,
        .rm = 3,
        .disp_lo = 8,
        .disp_hi = 8,
    };

    result = 



    try expect(result.?.opcode == instruction.Opcode.Mov);
}

test "string compare" {
    var key_buffer: [8]u8 = undefined;
    key_buffer[0] = 'o';
    key_buffer[1] = 'p';
    key_buffer[2] = 'p';
    key_buffer[3] = 'c';
    key_buffer[4] = 'o';
    key_buffer[5] = 'd';
    key_buffer[6] = 'e';
    const expected = "oppcode";

    //const result = std.mem.eql(u8, key_buffer[0..], expected[0..]);
    const result = std.mem.startsWith(u8, &key_buffer, expected);
    try expect(result == true);
}
