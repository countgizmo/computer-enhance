const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const log = std.log;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const instruction = @import("instruction.zig");
const Instruction = instruction.Instruction;
const Opcode = instruction.Opcode;
const Register = instruction.Register;
const MemoryCalculationNoDisp = instruction.MemoryCalculationNoDisp;

const Encoding = struct {
    opcode: Opcode,
    bits_enc: []const u8,
};

const Decoding = struct {
    opcode: Opcode,
};

fn isNumber(ch: u8) bool {
    return (ch >= '0' and ch <= '9');
}

fn charToDigit(ch: u8) u8 {
    return @intCast(u8, std.fmt.charToDigit(ch, 10) catch 0);
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
    data,
    dataw,
};

fn keyToIdentifier(key_buffer: []u8) Identifier {
    if (std.mem.startsWith(u8, key_buffer, "opcode")) {
        return .opcode;
    } else if (std.mem.startsWith(u8, key_buffer, "disp-lo")) {
        return .disp_lo;
    } else if (std.mem.startsWith(u8, key_buffer, "disp-hi")) {
        return .disp_hi;
    } else if (std.mem.startsWith(u8, key_buffer, "dataw")) {
        return .dataw;
    } else if (std.mem.startsWith(u8, key_buffer, "data")) {
        return .data;
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

fn createMapOfOpcodes() !*std.AutoArrayHashMap([2]u8, Encoding) {
    var map = std.AutoArrayHashMap([2]u8, Encoding).init(std.heap.page_allocator);

    //
    // mov
    //

    // Register/memory to/from register/memory
    try map.put(.{ 0b100010_00, 0b11111_000 }, .{ .opcode = Opcode.mov, .bits_enc = "opcode6:d1:w1:mod2:reg3:rm3:disp-lo8:disp-hi8" });

    // Immediate to register
    try map.put(.{ 0b1011_0000, 0b1111_0000 }, .{ .opcode = Opcode.mov, .bits_enc = "opcode4:w1:reg3:data8:dataw8" });
    //try map.put(0b1100011_0, .{ .opcode = Opcode.mov, .bits_enc = "opcdoe7:d0:w1:mod2:reg3:rm3:disp-lo8:disp-hi8:data8:dataw8" });

    return &map;
}

const MOST_SIGNIFICANT_BIT_IDX = 7;

fn extractBits(bytes_buffer: []const u8, start_bit: *u3, offset: usize, size: u8) u8 {
    var current_byte = bytes_buffer[offset];

    const mask_base: u8 = 1;
    var shift: u3 = 0;

    if (start_bit.* < size or size == 8) {
        shift = 0;
        start_bit.* = MOST_SIGNIFICANT_BIT_IDX;
    } else {
        start_bit.* -= @intCast(u3, size);
        shift = start_bit.* + 1;
    }

    const shifted_num = current_byte >> shift;
    //log.warn("size = {d} shift  = {d}", .{ size, shift });

    var mask: u8 = 0;
    if (size == 8) {
        mask = 0b11111111;
    } else {
        mask = ((mask_base << @intCast(u3, size)) - 1);
    }
    //log.warn("byte = {b} ; shifted num = {b} ; mask = {b} ; masked num = {b}", .{ current_byte, shifted_num, mask, shifted_num & mask });

    return shifted_num & mask;
}

fn decodeDestination(mod: u8, reg: u8, rm: u8, d: u8, w: u8) instruction.Operand {
    if (mod == 0b11) {
        if (d == 1) {
            const register_idx: u8 = if (w == 1) reg + 8 else reg;
            return .{
                .register = @intToEnum(instruction.Register, register_idx),
            };
        } else {
            const register_idx: u8 = if (w == 1) rm + 8 else rm;
            return .{
                .register = @intToEnum(instruction.Register, register_idx),
            };
        }
    }

    //TODO(evgheni): provide sane default return or null or something
    // for now this is a dummy value to shut up the compiler cause I just want to test my code incrementally!
    const register_idx: u8 = if (w == 1) reg + 8 else reg;
    return .{
        .register = @intToEnum(instruction.Register, register_idx),
    };
}

fn decodeSource(mod: u8, reg: u8, rm: u8, d: u8, w: u8, data: ?u8, dataw: ?u8) instruction.Operand {
    if (mod == 0b11) {
        if (d == 0) {
            const register_idx: u8 = if (w == 1) reg + 8 else reg;
            return .{
                .register = @intToEnum(instruction.Register, register_idx),
            };
        } else {
            const register_idx: u8 = if (w == 1) rm + 8 else rm;
            return .{
                .register = @intToEnum(instruction.Register, register_idx),
            };
        }
    }

    if (mod == 0b00) {
        if (d == 0) {
            const calculation_idx: u8 = reg;
            return .{
                .memory_calculation_no_disp = .{ .registers = instruction.RegistersNoDisp[calculation_idx] },
            };
        } else {
            const calculation_idx: u8 = rm;
            log.warn("calc idx = {d} ", .{calculation_idx});

            return .{
                .memory_calculation_no_disp = .{ .registers = instruction.RegistersNoDisp[calculation_idx] },
            };
        }
    }

    if (data) |value_lo| {
        if (dataw) |value_hi| {
            return .{
                .immediate = @as(i16, value_hi) << 8 | value_lo,
            };
        } else {
            return .{
                .immediate = value_lo,
            };
        }
    }

    //TODO(evgheni): provide sane default return or null or something
    // for now this is a dummy value to shut up the compiler cause I just want to test my code incrementally!
    return .{
        .register = @intToEnum(instruction.Register, 0),
    };
}

fn decodeInstruction(buffer: []const u8, offset: u16, encoding: Encoding) ?instruction.Instruction {
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
    var data: ?u8 = null;
    var dataw: ?u8 = null;

    for (encoding.bits_enc, 0..) |bit, ch_idx| {
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
        }

        if ((bit == ':') or (ch_idx == encoding.bits_enc.len - 1)) {
            const id = keyToIdentifier(&key);
            const size = charToDigit(value);
            const bit_value = extractBits(buffer, &start_bit, current_offset, size);
            log.warn("id = {c} size {d} value = {b}", .{ @tagName(id), size, bit_value });

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
                .disp_lo => {
                    if (mod == 0b11 or mod == 0b00) {
                        break;
                    }
                },
                .disp_hi => {
                    if (mod == 0b11 or mod == 0b00) {
                        break;
                    }
                },
                .data => {
                    data = bit_value;
                },
                .dataw => {
                    if (w == 0) {
                        break;
                    }
                    dataw = bit_value;
                },
                else => {},
            }

            total_bits += size;
            if (@rem(total_bits, 8) == 0) {
                current_offset += 1;
            }

            i = 0;
            key = undefined;
        }
    }
    return .{
        .opcode = encoding.opcode,
        .operand1 = decodeDestination(mod, reg, rm, d, w),
        .operand2 = decodeSource(mod, reg, rm, d, w, data, dataw),
        .size = current_offset - offset,
    };
}

pub fn decode(allocator: Allocator, buffer: []const u8, buffer_len: usize, offset: u16) !?[]Instruction {
    const map = try createMapOfOpcodes();
    var instructions = ArrayList(Instruction).init(allocator);
    var current_offset = offset;

    var iterator = map.iterator();

    while (current_offset < buffer_len) {
        while (iterator.next()) |entry| {
            const key = entry.key_ptr.*;
            if (buffer[current_offset] & key[1] == key[0]) {
                if (decodeInstruction(buffer, current_offset, entry.value_ptr.*)) |inst| {
                    try instructions.append(inst);
                    current_offset += inst.size;
                    break; //Note(evgheni): don't need to continue checking the map of opcodee
                }
            }
        }
        iterator.reset();
    }
    return instructions.items;
}

test "decoding many instructions" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer _ = arena.deinit();
    const bytes = [_]u8{ 0b10001001, 0b11011001, 0b10001000, 0b11100101, 0b10001001, 0b11011010 };
    const instructions = try decode(arena.allocator(), &bytes, bytes.len, 0);
    try expect(instructions.?.len == 3);
}

test "decoding instruction" {
    const bytes_buffer: [2]u8 = .{ 0b10001001, 0b11011001 };
    const encoding: Encoding = .{
        .opcode = Opcode.mov,
        .bits_enc = "opcode6:d1:w1:mod2:reg3:rm3:disp-lo8:disp-hi8",
    };
    const result = decodeInstruction(&bytes_buffer, 0, encoding);

    try expect(result.?.opcode == Opcode.mov);
    try expectEqual(instruction.Register.cx, result.?.operand1.register);
    try expectEqual(instruction.Register.bx, result.?.operand2.?.register);
}

test "decoding instruction - 8-bit immediate" {
    const encoding: Encoding = .{
        .opcode = Opcode.mov,
        .bits_enc = "opcode4:w1:reg3:data8:dataw8",
    };
    const bytes_buffer = [2]u8{ 0b10110001, 0b00001100 };

    const result = decodeInstruction(&bytes_buffer, 0, encoding);
    try expect(result.?.opcode == Opcode.mov);
    try expectEqual(instruction.Register.cl, result.?.operand1.register);
    try expect(result.?.operand2.?.immediate == 12);
}

test "decoding instruction - 16-bit immediate" {
    const encoding: Encoding = .{
        .opcode = Opcode.mov,
        .bits_enc = "opcode4:w1:reg3:data8:dataw8",
    };
    const bytes_buffer = [3]u8{ 0b10111010, 0b01101100, 0b00001111 };

    const result = decodeInstruction(&bytes_buffer, 0, encoding);
    try expect(result.?.opcode == Opcode.mov);
    try expectEqual(instruction.Register.dx, result.?.operand1.register);
    try expect(result.?.operand2.?.immediate == 3948);
}

test "decoding effective memory address calculation to register" {
    const encoding: Encoding = .{
        .opcode = Opcode.mov,
        .bits_enc = "opcode6:d1:w1:mod2:reg3:rm3:disp-lo8:disp-hi8",
    };
    const bytes_buffer = [2]u8{ 0b10001010, 0b00000000 };
    const result = decodeInstruction(&bytes_buffer, 0, encoding);

    try expect(result.?.opcode == Opcode.mov);
    try expect(result.?.size == 2);
    try expectEqual(instruction.Register.al, result.?.operand1.register);
    try expect(result.?.operand2.?.memory_calculation_no_disp.registers[0] == Register.bx);
    try expect(result.?.operand2.?.memory_calculation_no_disp.registers[1] == Register.si);
}

test "decoding effective memory address calculation with displacement" {
    const encoding: Encoding = .{
        .opcode = Opcode.mov,
        .bits_enc = "opcode6:d1:w1:mod2:reg3:rm3:disp-lo8:disp-hi8",
    };
    const bytes_buffer = [3]u8 { 0b10001011, 0b01010110, 0b00000000 };
    const result = decodeInstruction(&bytes_buffer, 0, encoding);

    try expect(result.?.opcode == Opcode.mov);
    //TODO(evhgni): add memory calculation with disp-8
    //In this case the disp-8 is present but is 0. A case for printer "__
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
    log.warn("mask unshifted {b}", .{(1 << 8) - 1});
}
