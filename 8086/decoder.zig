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

fn isNumber(ch: u8) bool {
    return (ch >= '0' and ch <= '9');
}

fn charToDigit(ch: u8) u3 {
    return @intCast(u3, std.fmt.charToDigit(ch, 7) catch 0);
}

const Identifier = enum {
    none,
    opcode,
    mod,
    reg,
    rm,
    d,
    w,
    disp_lo,
    disp_hi,
};

fn keyToIdentifier(key_buffer: []u8) Identifier {
    if (std.mem.startsWith(u8, key_buffer, "opcode")) {
        return .opcode;
    } else if (std.mem.startsWith(u8, key_buffer, "disp-lo")) {
        return .disp_lo;
    } else if (std.mem.startsWith(u8, key_buffer, "disp-hi")) {
        return .disp_hi;
    } else if (std.mem.startsWith(u8, key_buffer, "mod")) {
        return .mod;
    } else if (std.mem.startsWith(u8, key_buffer, "reg")) {
        return .reg;
    } else if (std.mem.startsWith(u8, key_buffer, "rm")) {
        return .rm;
    } else if (std.mem.startsWith(u8, key_buffer, "d")) {
        return .d;
    } else if (std.mem.startsWith(u8, key_buffer, "w")) {
        return .w;
    }

    return .none;
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
    //log.warn("size = {d} shift  = {d}", .{ size, shift });

    var mask: u8 = ((mask_base << size) - 1);
    //log.warn("byte = {b} ; shifted num = {b} ; mask = {b} ; masked num = {b}", .{ current_byte, shifted_num, mask, shifted_num & mask });

    return shifted_num & mask;
}

fn decodeDestination(mod: u8, reg: u8, rm: u8, d: u8, w: u8) instruction.Operand {
    if (mod == 0b11) {
        if (d == 1) {
            const register_idx: u8 = if (w == 1) reg * 2 else reg;
            return .{
                .location = instruction.OperandType.Register,
                .register = @intToEnum(instruction.Register, register_idx),
            };
        } else {
            const register_idx: u8 = if (w == 1) rm * 2 else rm;
            return .{
                .location = instruction.OperandType.Register,
                .register = @intToEnum(instruction.Register, register_idx),
            };
        }
    }

    //TODO(evgheni): provide sane default return or null or something
    // for now this is a dummy value to shut up the compiler cause I just want to test my code incrementally!
    return .{
        .location = instruction.OperandType.Memory,
        .register = @intToEnum(instruction.Register, 0),
    };
}

fn decodeInstruction(buffer: []const u8, offset: u16, bits: []const u8) ?instruction.Instruction {
    var current_offset = offset;
    var key: [8]u8 = undefined;
    var value: u8 = undefined;
    var i: usize = 0;
    var total_bits: u8 = 0;
    var start_bit: u3 = MOST_SIGNIFICANT_BIT_IDX;
    var mod: u8 = 0;
    var reg: u8 = 0;
    var rm: u8 = 0;
    var d: u8 = 0;
    var w: u8 = 0;

    for (bits) |bit| {
        // We have less bytes than can be encoded
        if (current_offset >= buffer.len) {
            break;
        }

        if (bit != ':') {
            if (isNumber(bit)) {
                value = bit;
            } else {
                key[i] = bit;
                i += 1;
            }
            continue;
        } else {
            const id = keyToIdentifier(&key);
            const size = charToDigit(value);
            const bit_value = extractBits(buffer, &start_bit, current_offset, size);
            total_bits += size;
            log.warn("id = {c} size {d}", .{ @tagName(id), size });
            if (@rem(total_bits, 8) == 0) {
                current_offset += 1;
            }

            switch (id) {
                .mod => {
                    mod = bit_value;
                },
                .reg => {
                    reg = bit_value;
                },
                .rm => {
                    rm = bit_value;
                },
                .d => {
                    d = bit_value;
                },
                .w => {
                    w = bit_value;
                },
                else => {},
            }
            i = 0;
            key = undefined;
        }
    }
    return .{
        .opcode = Opcode.Mov,
        .operand1 = decodeDestination(mod, reg, rm, d, w),
        .operand2 = .{
            .location = instruction.OperandType.Register,
            .register = instruction.Register.BX,
        },
        .size = current_offset - offset,
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
