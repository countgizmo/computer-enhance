const std = @import("std");
const log = std.log;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const instruction = @import("instruction.zig");
const Instruction = instruction.Instruction;
const Opcode = instruction.Opcode;

const example = Instruction{
    .opcode = Opcode.Mov,
    .operand1 = .{
        .location = instruction.OperandType.Register,
        .register = instruction.Register.CX,
    },
    .operand2 = .{
        .location = instruction.OperandType.Register,
        .register = instruction.Register.BX,
    },
};

const Encoding = struct {
    mnemonic: []const u8,
    bits_enc: []const u8,
};

const Decoding = struct {
    opcode: Opcode,
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

fn createMapOfOpcodes() !*std.AutoArrayHashMap(u8, Encoding) {
    var map = std.AutoArrayHashMap(u8, Encoding).init(std.heap.page_allocator);

    try map.put(0b100010_00, .{ .mnemonic = "mov", .bits_enc = "opcode6:d1:w1:mod2:reg3:rm3:disp-lo8:disp-hi8" });

    return &map;
}

const MOST_SIGNIFICANT_BIT_IDX = 7;

fn extractBits(bytes_buffer: []const u8, start_bit: *u3, offset: usize, size: u3) u8 {
    var current_byte = bytes_buffer[offset];

    const mask_base: u8 = 1;
    var shift: u3 = 0;

    if (start_bit.* < size) {
        shift = 0;
        start_bit.* = MOST_SIGNIFICANT_BIT_IDX;
    } else {
        start_bit.* -= size;
        shift = start_bit.* + 1;
    }

    const shifted_num = current_byte >> shift;
    log.warn("size = {d} shift  = {d}", .{ size, shift });

    var mask: u8 = ((mask_base << size) - 1);
    log.warn("byte = {b} ; shifted num = {b} ; mask = {b} ; masked num = {b}", .{ current_byte, shifted_num, mask, shifted_num & mask });

    return shifted_num & mask;
}

fn decodeInstruction(buffer: []const u8, offset: u16, bits: []const u8) ?instruction.Instruction {
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
            _ = buffer[offset..];
            i = 0;
            key_buffer = undefined;
        }
    }
    return .{
        .opcode = Opcode.Mov,
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
    const map = try createMapOfOpcodes();
    defer map.deinit();

    var iter = map.iterator();
    while (iter.next()) |map_entry| {
        const mask = map_entry.key_ptr.*;
        if (buffer[offset] & mask == mask) {

            // TODO(evgheni): write a function to decode bits_enc
            std.log.warn("Encoding: {s}", .{map_entry.value_ptr.*.bits_enc});
        }
    }
    return example;
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
    const test_enc = "opcode6:d1:w1:mod2:reg3:rm3:disp-lo8:disp-hi8";
    const result = decodeInstruction(&bytes_buffer, 0, test_enc);

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

test "extract bits" {
    const bytes_buffer: [2]u8 = .{ 0b10001001, 0b11011001 };
    const sizes = [_]u3{ 6, 1, 1, 2, 3, 3 };
    const expected = [_]u8{ 0b100010, 0, 1, 0b11, 0b011, 0b001 };

    var offset: usize = 0;
    var start_bit: u3 = MOST_SIGNIFICANT_BIT_IDX;
    var total_bits: u8 = 0;

    for (sizes, 0..) |size, i| {
        total_bits += size;
        try expect(extractBits(&bytes_buffer, &start_bit, offset, size) == expected[i]);
        if (@rem(total_bits, 8) == 0) {
            offset += 1;
        }
    }
}

test "shifting" {
    const test_size = 6;
    const num: u8 = 0b10001001;
    const shifted_num = num >> (8 - test_size);
    const mask: u8 = (1 << test_size) - 1;

    log.warn("original {b} shifted {b} masked {b}", .{ num, shifted_num, shifted_num & mask });
}
