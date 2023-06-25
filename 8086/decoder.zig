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

const DecoderError = error {
    ModNotFound,
    DataNotFound,
    AddressNotFound,
};

const OperandPosition = enum {
    source,
    destination,
};

const Encoding = struct {
    opcode: Opcode,
    bits_enc: []const u8,
};

const Decoding = struct {
    opcode: Opcode,
    mod: ?u8 = null,
    reg: u8 = 0,
    rm: u8 = 0,
    d: u8 = 0,
    w: u8 = 0,
    s: u8 = 0,
    data: ?u8 = null,
    dataw: ?u8 = null,
    disp_lo: ?u8 = null,
    disp_hi: ?u8 = null,
    addr_lo: ?u8 = null,
    addr_hi: ?u8 = null,
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
    s,
    disp_lo,
    disp_hi,
    data,
    dataw,
    pad,
    addr_lo,
    addr_hi,
};

fn keyToIdentifier(key_buffer: []u8) Identifier {
    if (std.mem.startsWith(u8, key_buffer, "opcode")) {
        return .opcode;
    } else if (std.mem.startsWith(u8, key_buffer, "addr-lo")) {
        return .addr_lo;
    } else if (std.mem.startsWith(u8, key_buffer, "addr-hi")) {
        return .addr_hi;
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
    } else if (std.mem.startsWith(u8, key_buffer, "s")) {
        return .s;
    } else if (std.mem.startsWith(u8, key_buffer, "pad")) {
        return .pad;
    }

    return .none;
}

fn createMapOfOpcodes(allocator: Allocator) !std.AutoArrayHashMap([2]u8, Encoding) {
    var map = std.AutoArrayHashMap([2]u8, Encoding).init(allocator);

    //
    // mov
    //

    // Register/memory to/from register/memory
    try map.put(.{ 0b100010_00, 0b11111_000 }, .{ .opcode = .mov, .bits_enc = "opcode6:d1:w1:mod2:reg3:rm3:disp-lo8:disp-hi8" });

    // Immediate to register
    try map.put(.{ 0b1011_0000, 0b1111_0000 }, .{ .opcode = .mov, .bits_enc = "opcode4:w1:reg3:data8:dataw8" });

    // Immediate to register/memory
    try map.put(.{ 0b1100011_0, 0b1111111_0 }, .{ .opcode = .mov, .bits_enc = "opcode7:w1:mod2:pad3:rm3:disp-lo8:disp-hi8:data8:dataw8" });

    // Memory to accumulator
    // Note(evgheni): there's actually no d-bit, but there's a bit after w-bit that's 0 if mem->acc and 1 if acc->mem
    // so we can use that as a "direction".
    // Means the opcode part is not correct but I don't use it anyway.
    try map.put(.{ 0b1010000_0, 0b1111111_0 }, .{ .opcode = .mov, .bits_enc = "opcode6:d1:w1:addr-lo8:addr-hi8"});
    try map.put(.{ 0b1010001_0, 0b1111111_0 }, .{ .opcode = .mov, .bits_enc = "opcode6:d1:w1:addr-lo8:addr-hi8"});

    //
    // add
    //

    // Reg/memory with register to either
    try map.put(.{ 0b000000_00, 0b111111_00 }, .{ .opcode = .add, .bits_enc = "opcode6:d1:w1:mod2:reg3:rm3:disp-lo8:disp-hi8"});

    // Immediate to register/memory
    try map.put(.{ 0b100000_00, 0b111111_00 }, .{ .opcode = .add, .bits_enc = "opcode6:s1:w1:mod2:pad3:rm3:disp-lo8:disp-hi8:data8:dataw8"});

    // Immediate to accumulator
    try map.put(.{ 0b0000010_0, 0b1111111_0 }, .{ .opcode = .add, .bits_enc = "opcode7:w1:data8:dataw8"});

    return map;
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

fn getRegister(decoding: Decoding, op_position: OperandPosition) Register {
    var register_idx: u8 = undefined;

    switch (op_position) {
        .source => {
            if (decoding.d == 0) {
                register_idx = if (decoding.w == 1) decoding.reg + 8 else decoding.reg;
            } else {
                register_idx = if (decoding.w == 1) decoding.rm + 8 else decoding.rm;
            }
        },
        .destination=> {
            if (decoding.d == 1) {
                register_idx = if (decoding.w == 1) decoding.reg + 8 else decoding.reg;
            } else {
                register_idx = if (decoding.w == 1) decoding.rm + 8 else decoding.rm;
            }
        },
    }

    return @intToEnum(instruction.Register, register_idx);
}

fn getAddressCalculationOperand(decoding: Decoding) DecoderError!instruction.Operand {
    if (decoding.mod.? == 0b00) {
        const mem_calc = instruction.MemCalcTable[decoding.rm];
        return .{
            .mem_calc_no_disp = .{ .mem_calc = mem_calc },
        };
    }

    if (decoding.mod.? == 0b01) {
        var mem_calc = instruction.MemCalcTable[decoding.rm];
        mem_calc.disp = .{
            .byte = @bitCast(i8, decoding.disp_lo.?),
        };

        return .{
            .mem_calc_with_disp = mem_calc,
        };
    }

    if (decoding.mod.? == 0b10) {
        var mem_calc = instruction.MemCalcTable[decoding.rm];
        const word = @as(u16, decoding.disp_hi.?) << 8 | decoding.disp_lo.?;
        mem_calc.disp = .{
            .word = @bitCast(i16, word),
        };

        return .{
            .mem_calc_with_disp = mem_calc,
        };
    }

    return DecoderError.ModNotFound;
}

fn getDataOperand(decoding: Decoding) !instruction.Operand {
    if (decoding.data) |data_lo| {
        var operand: instruction.Operand = undefined;

        if (decoding.dataw) |data_hi| {
            operand = .{
                .immediate = .{ .value = @as(i16, data_hi) << 8 | data_lo },
            };
        } else {
            operand = .{
                .immediate = .{ .value = @bitCast(i8, data_lo) },
            };
        }

        // Checking if we're not in the register mode
        if (decoding.mod) |mod| {
            if (mod != 0b11 and decoding.w == 0) {
                operand.immediate.size = .byte;
            }

            if (mod != 0b11 and decoding.w == 1) {
                operand.immediate.size = .word;
            }
        }

        return operand;
    }

    return DecoderError.DataNotFound;
}

fn isDirectAddress(decoding: Decoding) bool {
    if (decoding.mod) |mod| {
        return (mod == 0b00 and decoding.rm == 0b110);
    }

    return false;
}

fn getDirectAddressDispOperand(decoding: Decoding) instruction.Operand {
    return .{
        .direct_address = @as(u16, decoding.disp_hi.?) << 8 | decoding.disp_lo.?,
    };
}

fn getDirectAddress(decoding: Decoding) !instruction.Operand {
    if (decoding.addr_lo) |addr_lo| {
        var operand: instruction.Operand = undefined;

        if (decoding.addr_hi) |addr_hi| {
            operand = .{
                .direct_address = @as(u16, addr_hi) << 8 | addr_lo,
            };
        } else {
            operand = .{
                .direct_address = addr_lo,
            };
        }

        return operand;
    }

    return DecoderError.AddressNotFound;
}

fn decodeOperand(decoding: Decoding, op_position: OperandPosition) !instruction.Operand {
    if (op_position == .source and decoding.data != null) {
        return try getDataOperand(decoding);
    }


    if (decoding.addr_lo != null) {
        if ((decoding.d == 0 and op_position == .destination) or
            (decoding.d == 1 and op_position == .source)){
            return .{
                .register = .ax,
            };
        } else {
            return try getDirectAddress(decoding);
        }
    }

    if (decoding.mod) |mod| {
        if (mod == 0b11) {
            return .{
                .register = getRegister(decoding, op_position),
            };
        } else if (isDirectAddress(decoding) and op_position == .source) {
            return getDirectAddressDispOperand(decoding);
        } else {
            if (op_position == .source) {
                if (decoding.d == 0) {
                    return .{
                        .register = getRegister(decoding, op_position),
                    };
                } else {
                    return try getAddressCalculationOperand(decoding);
                }
            }

            if (op_position == .destination) {
                if (decoding.d == 1) {
                    return .{
                        .register = getRegister(decoding, op_position),
                    };
                } else {
                    return try getAddressCalculationOperand(decoding);
                }
            }
        }
    }


    //TODO(evgheni): provide sane default return or null or something
    // for now this is a dummy value to shut up the compiler cause I just want to test my code incrementally!
    const register_idx: u8 = if (decoding.w == 1) decoding.reg + 8 else decoding.reg;
    return .{
        .register = @intToEnum(instruction.Register, register_idx),
    };
}

fn decodeInstruction(buffer: []const u8, offset: u16, encoding: Encoding) !?instruction.Instruction {
    var current_offset = offset;
    var key: [8]u8 = undefined;
    var value: u8 = undefined;
    var i: usize = 0;
    var total_bits: u8 = 0;
    var start_bit: u3 = MOST_SIGNIFICANT_BIT_IDX;
    var decoding: Decoding = .{
        .opcode = encoding.opcode,
    };

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
            //log.warn("id = {c} size {d} value = {b}", .{ @tagName(id), size, bit_value });

            switch (id) {
                .mod => {
                    decoding.mod = bit_value;
                },
                .reg => {
                    decoding.reg = bit_value;
                },
                .rm => {
                    decoding.rm = bit_value;
                },
                .d => {
                    decoding.d = bit_value;
                },
                .w => {
                    decoding.w = bit_value;
                },
                .s => {
                    decoding.s = bit_value;
                },
                .disp_lo => {
                    if (decoding.mod) |mod| {
                        if ((mod == 0b11 or mod == 0b00) and !isDirectAddress(decoding)) {
                            i = 0;
                            continue;
                        }
                    }
                    decoding.disp_lo = bit_value;
                },
                .disp_hi => {
                    if (decoding.mod) |mod| {
                        if ((mod == 0b11 or mod == 0b00 or mod == 0b01) and !isDirectAddress(decoding)) {
                            i = 0;
                            continue;
                        }
                    }
                    decoding.disp_hi = bit_value;
                },
                .data => {
                    decoding.data = bit_value;
                },
                .dataw => {
                    if (decoding.s == 0 and decoding.w == 1) {
                        decoding.dataw = bit_value;
                    } else {
                        i = 0;
                        continue;
                    }
                },
                .addr_lo => {
                    decoding.addr_lo = bit_value;
                },
                .addr_hi => {
                    decoding.addr_hi = bit_value;
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
        .operand1 = try decodeOperand(decoding, OperandPosition.destination),
        .operand2 = try decodeOperand(decoding, OperandPosition.source),
        .size = current_offset - offset,
    };
}

pub fn decode(allocator: Allocator, buffer: []const u8, buffer_len: usize, offset: u16) !?[]Instruction {
    var map = try createMapOfOpcodes(allocator);
    var iterator = map.iterator();

    defer {
        map.deinit();
    }
    var instructions = ArrayList(Instruction).init(allocator);
    var current_offset = offset;

    while (current_offset < buffer_len) {
        while (iterator.next()) |entry| {
            const key = entry.key_ptr.*;
            if (buffer[current_offset] & key[1] == key[0]) {
                if (try decodeInstruction(buffer, current_offset, entry.value_ptr.*)) |inst| {
                    try instructions.append(inst);
                    current_offset += inst.size;
                    break; //Note(evgheni): don't need to continue checking the map of opcodee
                }
            }
        }
        iterator.reset();
    }

    return  try instructions.toOwnedSlice();
}

test "decoding many instructions" {
    var allocator = std.testing.allocator;
    const bytes = [_]u8{ 0b10001001, 0b11011001, 0b10001000, 0b11100101, 0b10001001, 0b11011010 };
    const instructions = try decode(allocator, &bytes, bytes.len, 0);
    allocator.free(instructions.?);
    try expect(instructions.?.len == 3);
}

test "decoding instruction" {
    const bytes_buffer: [2]u8 = .{ 0b10001001, 0b11011001 };
    const encoding: Encoding = .{
        .opcode = Opcode.mov,
        .bits_enc = "opcode6:d1:w1:mod2:reg3:rm3:disp-lo8:disp-hi8",
    };
    const result = try decodeInstruction(&bytes_buffer, 0, encoding);

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

    const result = try decodeInstruction(&bytes_buffer, 0, encoding);
    try expect(result.?.opcode == Opcode.mov);
    try expectEqual(instruction.Register.cl, result.?.operand1.register);
    try expect(result.?.operand2.?.immediate.value == 12);
}

test "decoding instruction - 16-bit immediate" {
    const encoding: Encoding = .{
        .opcode = Opcode.mov,
        .bits_enc = "opcode4:w1:reg3:data8:dataw8",
    };
    const bytes_buffer = [3]u8{ 0b10111010, 0b01101100, 0b00001111 };

    const result = try decodeInstruction(&bytes_buffer, 0, encoding);
    try expect(result.?.opcode == Opcode.mov);
    try expectEqual(instruction.Register.dx, result.?.operand1.register);
    try expect(result.?.operand2.?.immediate.value == 3948);
}

test "decoding effective memory address calculation to register" {
    const encoding: Encoding = .{
        .opcode = Opcode.mov,
        .bits_enc = "opcode6:d1:w1:mod2:reg3:rm3:disp-lo8:disp-hi8",
    };
    const bytes_buffer = [2]u8{ 0b10001010, 0b00000000 };
    const result = try decodeInstruction(&bytes_buffer, 0, encoding);

    try expect(result.?.opcode == Opcode.mov);
    try expect(result.?.size == 2);
    try expectEqual(instruction.Register.al, result.?.operand1.register);
    try expect(result.?.operand2.?.mem_calc_no_disp.mem_calc.register1 == Register.bx);
    try expect(result.?.operand2.?.mem_calc_no_disp.mem_calc.register2 == Register.si);
}

test "decoding effective memory address calculation with 8-bit displacement" {
    const encoding: Encoding = .{
        .opcode = Opcode.mov,
        .bits_enc = "opcode6:d1:w1:mod2:reg3:rm3:disp-lo8:disp-hi8",
    };
    const bytes_buffer = [3]u8 { 0b10001011, 0b01010110, 0b00000000 };
    const result = try decodeInstruction(&bytes_buffer, 0, encoding);

    // mov dx, [bp]

    try expect(result.?.opcode == Opcode.mov);
    try expectEqual(Register.dx, result.?.operand1.register);
    try expectEqual(Register.bp, result.?.operand2.?.mem_calc_with_disp.register1);
    try expect(result.?.operand2.?.mem_calc_with_disp.disp.?.byte == 0);

    // mov ah, [bx + si + 4]

    const bytes_buffer_2 = [3]u8 { 0b10001010, 0b01100000, 0b00000100 };
    const result_2 = try decodeInstruction(&bytes_buffer_2, 0, encoding);

    try expect(result_2.?.opcode == Opcode.mov);
    try expectEqual(Register.ah, result_2.?.operand1.register);
    try expectEqual(Register.bx, result_2.?.operand2.?.mem_calc_with_disp.register1);
    try expectEqual(Register.si, result_2.?.operand2.?.mem_calc_with_disp.register2.?);
    try expect(result_2.?.operand2.?.mem_calc_with_disp.disp.?.byte == 4);
}


test "decoding effective memory address calculation with 16-bit displacement" {
    const encoding: Encoding = .{
        .opcode = Opcode.mov,
        .bits_enc = "opcode6:d1:w1:mod2:reg3:rm3:disp-lo8:disp-hi8",
    };

    // mov al, [bx + si + 4999]

    const bytes_buffer = [4]u8 { 0b10001010, 0b10000000, 0b10000111, 0b00010011 };
    const result = try decodeInstruction(&bytes_buffer, 0, encoding);

    try expect(result.?.opcode == Opcode.mov);
    try expectEqual(Register.al, result.?.operand1.register);
    try expectEqual(Register.bx, result.?.operand2.?.mem_calc_with_disp.register1);
    try expectEqual(Register.si, result.?.operand2.?.mem_calc_with_disp.register2.?);
    try expect(result.?.operand2.?.mem_calc_with_disp.disp.?.word == 4999);
}

test "decoding memory address calculation in destination" {
    const encoding: Encoding = .{
        .opcode = Opcode.mov,
        .bits_enc = "opcode6:d1:w1:mod2:reg3:rm3:disp-lo8:disp-hi8",
    };

    // mov [bx + di], cx

    const bytes_buffer = [2]u8 { 0b10001001, 0b00001001 };
    const result = try decodeInstruction(&bytes_buffer, 0, encoding);

    try expect(result.?.opcode == Opcode.mov);
    try expectEqual(Register.bx, result.?.operand1.mem_calc_no_disp.mem_calc.register1);
    try expectEqual(Register.di, result.?.operand1.mem_calc_no_disp.mem_calc.register2.?);
    try expectEqual(Register.cx, result.?.operand2.?.register);
}

test "decoding multiple source address calculations" {
    var allocator = std.testing.allocator;

    // mov ah, [bx + si + 4]
    // mov al, [bx + si + 4999]
    const bytes_buffer = [7]u8 {
        0b10001010, 0b01100000, 0b00000100,
        0b10001010, 0b10000000, 0b10000111, 0b00010011
    };

    const instructions = try decode(allocator, &bytes_buffer, bytes_buffer.len, 0);
    allocator.free(instructions.?);
    try expect(instructions.?.len == 2);
}

test "decoding signed displacement" {
    const encoding: Encoding = .{
        .opcode = Opcode.mov,
        .bits_enc = "opcode6:d1:w1:mod2:reg3:rm3:disp-lo8:disp-hi8",
    };

    // mov ax, [bx + di - 37]

    const bytes_buffer = [3]u8 { 0b10001011, 0b01000001, 0b11011011 };
    const result = try decodeInstruction(&bytes_buffer, 0, encoding);

    try expect(result.?.opcode == Opcode.mov);
    try expectEqual(Register.ax, result.?.operand1.register);
    try expectEqual(Register.bx, result.?.operand2.?.mem_calc_with_disp.register1);
    try expectEqual(Register.di, result.?.operand2.?.mem_calc_with_disp.register2.?);
    try expect(result.?.operand2.?.mem_calc_with_disp.disp.?.byte == -37);

    // mov [si - 300], cx

    const bytes_buffer_2 = [4]u8 { 0b10001001, 0b10001100, 0b11010100, 0b11111110 };
    const result_2 = try decodeInstruction(&bytes_buffer_2, 0, encoding);

    try expect(result_2.?.opcode == Opcode.mov);

    try expectEqual(Register.si, result_2.?.operand1.mem_calc_with_disp.register1);
    try expect(result_2.?.operand1.mem_calc_with_disp.disp.?.word == -300);

    try expectEqual(Register.cx, result_2.?.operand2.?.register);
}

test "decoding explicit sizes" {
    const encoding: Encoding = .{
        .opcode = Opcode.mov,
        .bits_enc = "opcode7:w1:mod2:pad3:rm3:disp-lo8:disp-hi8:data8:dataw8",
    };

    // mov [bp + di], byte 7

    const bytes_buffer = [3]u8 { 0b11000110, 0b00000011, 0b00000111 };
    if (try decodeInstruction(&bytes_buffer, 0, encoding)) |result| {
        try expect(result.opcode == Opcode.mov);
        try expectEqual(Register.bp, result.operand1.mem_calc_no_disp.mem_calc.register1);
        try expectEqual(Register.di, result.operand1.mem_calc_no_disp.mem_calc.register2.?);

        try expect(result.operand2.?.immediate.value == 7);
        try expectEqual(instruction.DataSize.byte, result.operand2.?.immediate.size.?);
    }

    //mov [di + 901], word 347
    const bytes_buffer_2 = [6]u8 { 0b11000111, 0b10000101, 0b10000101, 0b00000011, 0b01011011, 0b00000001 };
    if (try decodeInstruction(&bytes_buffer_2, 0, encoding)) |result| {
        try expect(result.opcode == Opcode.mov);
        try expectEqual(Register.di, result.operand1.mem_calc_with_disp.register1);
        try expect(result.operand1.mem_calc_with_disp.disp.?.word == 901);

        try expect(result.operand2.?.immediate.value == 347);
        try expectEqual(instruction.DataSize.word, result.operand2.?.immediate.size.?);
    }
}

test "decoding direct address" {
    const encoding: Encoding = .{
        .opcode = Opcode.mov,
        .bits_enc = "opcode6:d1:w1:mod2:reg3:rm3:disp-lo8:disp-hi8",
    };

    // mov bp, [5]
    const bytes_buffer = [_]u8 { 0b10001011, 0b00101110, 0b00000101, 0b00000000 };
    if (try decodeInstruction(&bytes_buffer, 0, encoding)) |result| {
        try expect(result.opcode == Opcode.mov);
        try expectEqual(Register.bp, result.operand1.register);

        try expect(result.operand2.?.direct_address == 5);
    }

    // mov bx, [3458]
    const bytes_buffer_2 = [_]u8 { 0b10001011, 0b00011110, 0b10000010, 0b00001101 };
    if (try decodeInstruction(&bytes_buffer_2, 0, encoding)) |result| {
        try expect(result.opcode == Opcode.mov);
        try expectEqual(Register.bx, result.operand1.register);

        try expect(result.operand2.?.direct_address == 3458);
    }
}

test "decoding memory to accumulator" {
    const encoding: Encoding = .{
        .opcode = Opcode.mov,
        .bits_enc = "opcode6:d1:w1:addr-lo8:addr-hi8",
    };

    // mov ax, [2555]
    const bytes_buffer = [_]u8 { 0b10100001, 0b11111011, 0b00001001 };
    if (try decodeInstruction(&bytes_buffer, 0, encoding)) |result| {
        try expect(result.opcode == Opcode.mov);
        try expectEqual(Register.ax, result.operand1.register);
        try expect(result.operand2.?.direct_address == 2555);
    }

    // mov ax, [16]
    const bytes_buffer_2 = [_]u8 { 0b10100001, 0b00010000, 0b00000000 };
    if (try decodeInstruction(&bytes_buffer_2, 0, encoding)) |result| {
        try expect(result.opcode == Opcode.mov);
        try expectEqual(Register.ax, result.operand1.register);
        try expect(result.operand2.?.direct_address == 16);
    }
}

test "decoding accumulator to memory" {
    const encoding: Encoding = .{
        .opcode = Opcode.mov,
        .bits_enc = "opcode6:d1:w1:addr-lo8:addr-hi8",
    };

    // mov [2554], ax
    const bytes_buffer = [_]u8 { 0b10100011, 0b11111010, 0b00001001 };
    if (try decodeInstruction(&bytes_buffer, 0, encoding)) |result| {
        try expect(result.opcode == Opcode.mov);
        try expect(result.operand1.direct_address == 2554);
        try expectEqual(Register.ax, result.operand2.?.register);
    }

    // mov [15], ax
    const bytes_buffer_2 = [_]u8 { 0b10100011, 0b00001111, 0b00000000 };
    if (try decodeInstruction(&bytes_buffer_2, 0, encoding)) |result| {
        try expect(result.opcode == Opcode.mov);
        try expect(result.operand1.direct_address == 15);
        try expectEqual(Register.ax, result.operand2.?.register);
    }
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

test "decoding add reg-mem" {
    const encoding: Encoding = .{
        .opcode = Opcode.add,
        .bits_enc = "opcode6:d1:w1:mod2:reg3:rm3:disp-lo8:disp-hi8",
    };

    // add bx, [bx+si]
    const bytes_buffer = [_]u8 { 0b00000011, 0b00011000 };
    if (try decodeInstruction(&bytes_buffer, 0, encoding)) |result| {
        try expectEqual(Opcode.add, result.opcode);
        try expectEqual(Register.bx, result.operand1.register);
        try expectEqual(Register.bx, result.operand2.?.mem_calc_no_disp.mem_calc.register1);
        try expectEqual(Register.si, result.operand2.?.mem_calc_no_disp.mem_calc.register2.?);
    }
}

test "decode add immediate" {
    const encoding: Encoding = .{
        .opcode = .add,
        .bits_enc = "opcode6:s1:w1:mod2:pad3:rm3:disp-lo8:disp-hi8:data8:dataw8",
    };

    // add si, 2
    const bytes_buffer = [_]u8 { 0b10000011, 0b11000110, 0b00000010 };
    if (try decodeInstruction(&bytes_buffer, 0, encoding)) |result| {
        try expectEqual(Opcode.add, result.opcode);
        try expectEqual(Register.si, result.operand1.register);
        try expect(result.operand2.?.immediate.value == 2);
    }
}
