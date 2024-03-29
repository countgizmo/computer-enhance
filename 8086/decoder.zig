const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const log = std.log;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const Register = @import("register_store.zig").Register;
const instruction = @import("instruction.zig");
const Instruction = instruction.Instruction;
const Opcode = instruction.Opcode;
const MemoryCalculationNoDisp = instruction.MemoryCalculationNoDisp;

const DecoderError = error {
    ModNotFound,
    DataNotFound,
    AddressNotFound,
    CouldNotDecodeOperand,
    InstructionPointerIncrementNotFound,
    DecoderNotFound,
};

const OperandPosition = enum {
    source,
    destination,
};

const decoderFunc = fn(decoding: Decoding, op_position: OperandPosition) DecoderError!?instruction.Operand;

const Encoding = struct {
    opcode: Opcode,
    bits_enc: []const u8,
    decoder_fn: ?*const decoderFunc = null,
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
    pad: ?u8 = null,
    ip_inc: ?i8 = null,
};

fn isNumber(ch: u8) bool {
    return (ch >= '0' and ch <= '9');
}

fn charToDigit(ch: u8) u8 {
    return @as(u8, @intCast(std.fmt.charToDigit(ch, 10) catch 0));
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
    ip_inc,
};

fn keyToIdentifier(key_buffer: []u8) Identifier {
    if (std.mem.startsWith(u8, key_buffer, "opcode")) {
        return .opcode;
    } else if (std.mem.startsWith(u8, key_buffer, "ip-inc")) {
        return .ip_inc;
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
    try map.put(.{ 0b100010_00, 0b11111_000 }, .{
        .opcode = .mov,
        .bits_enc = "opcode6:d1:w1:mod2:reg3:rm3:disp-lo8:disp-hi8",
        .decoder_fn = &decodeRegMemToFromRegMem
    });

    // Immediate to register
    try map.put(.{ 0b1011_0000, 0b1111_0000 }, .{
        .opcode = .mov,
        .bits_enc = "opcode4:w1:reg3:data8:dataw8",
        .decoder_fn = &decodeMovImmediateToRegister
    });

    // Immediate to register/memory
    try map.put(.{ 0b1100011_0, 0b1111111_0 }, .{
        .opcode = .mov, 
        .bits_enc = "opcode7:w1:mod2:pad3:rm3:disp-lo8:disp-hi8:data8:dataw8",
        .decoder_fn = &decodeImmediateToRegMem
    });

    // Memory to accumulator
    try map.put(.{ 0b1010000_0, 0b1111111_0 }, .{
        .opcode = .mov,
        .bits_enc = "opcode7:w1:addr-lo8:addr-hi8",
        .decoder_fn = &decodeMovMemoryToAcc
    });

    // Accumulator to memory
    try map.put(.{ 0b1010001_0, 0b1111111_0 }, .{
        .opcode = .mov,
        .bits_enc = "opcode7:w1:addr-lo8:addr-hi8",
        .decoder_fn = &decodeMovAccToMemory
    });

    //
    // add
    //

    // Reg/memory with register to either
    try map.put(.{ 0b000000_00, 0b111111_00 }, .{
        .opcode = .add,
        .bits_enc = "opcode6:d1:w1:mod2:reg3:rm3:disp-lo8:disp-hi8",
        .decoder_fn = &decodeRegMemToFromRegMem
    });

    // Immediate to accumulator
    try map.put(.{ 0b0000010_0, 0b1111111_0 }, .{
        .opcode = .add,
        .bits_enc = "opcode7:w1:data8:dataw8",
        .decoder_fn = &decodeImmediateToAcc
    });

    //
    // sub
    //

    // Reg/memory with register to either
    try map.put(.{ 0b001010_00, 0b111111_00 }, .{
        .opcode = .sub,
        .bits_enc = "opcode6:d1:w1:mod2:reg3:rm3:disp-lo8:disp-hi8",
        .decoder_fn = &decodeRegMemToFromRegMem
    });

    // Immediate to accumulator
    try map.put(.{ 0b0010110_0, 0b1111111_0 }, .{
        .opcode = .sub,
        .bits_enc = "opcode7:w1:data8:dataw8",
        .decoder_fn = &decodeImmediateToAcc
    });

    //
    // cmp
    //

    // Reg/memory with register to either
    try map.put(.{ 0b001110_00, 0b111111_00 }, .{
        .opcode = .cmp,
        .bits_enc = "opcode6:d1:w1:mod2:reg3:rm3:disp-lo8:disp-hi8",
        .decoder_fn = &decodeRegMemToFromRegMem
    });

    // Immediate to accumulator
    try map.put(.{ 0b0011110_0, 0b1111111_0 }, .{
        .opcode = .cmp,
        .bits_enc = "opcode7:w1:data8:dataw8",
        .decoder_fn = &decodeImmediateToAcc
    });


    //
    // Arithmetic sub-group
    //
    // Immediate to register/memory - use second byte to determine the opcode
    try map.put(.{ 0b100000_00, 0b111111_00 }, .{
        .opcode = .arithmetic,
        .bits_enc = "opcode6:s1:w1:mod2:pad3:rm3:disp-lo8:disp-hi8:data8:dataw8",
        .decoder_fn = &decodeImmediateToRegMem
    });


    //
    // Jumps
    //
    try map.put(.{ 0b01110100, 0b11111111 }, .{ .opcode = .je, .bits_enc = "opcode8:ip-inc8", .decoder_fn = &decodeJump });
    try map.put(.{ 0b01111100, 0b11111111 }, .{ .opcode = .jl, .bits_enc = "opcode8:ip-inc8", .decoder_fn = &decodeJump });
    try map.put(.{ 0b01111110, 0b11111111 }, .{ .opcode = .jle, .bits_enc = "opcode8:ip-inc8", .decoder_fn = &decodeJump });
    try map.put(.{ 0b01110010, 0b11111111 }, .{ .opcode = .jb, .bits_enc = "opcode8:ip-inc8", .decoder_fn = &decodeJump });
    try map.put(.{ 0b01110110, 0b11111111 }, .{ .opcode = .jbe, .bits_enc = "opcode8:ip-inc8", .decoder_fn = &decodeJump });
    try map.put(.{ 0b01111010, 0b11111111 }, .{ .opcode = .jp, .bits_enc = "opcode8:ip-inc8", .decoder_fn = &decodeJump });
    try map.put(.{ 0b01110000, 0b11111111 }, .{ .opcode = .jo, .bits_enc = "opcode8:ip-inc8", .decoder_fn = &decodeJump });
    try map.put(.{ 0b01111000, 0b11111111 }, .{ .opcode = .js, .bits_enc = "opcode8:ip-inc8", .decoder_fn = &decodeJump });
    try map.put(.{ 0b01110101, 0b11111111 }, .{ .opcode = .jnz, .bits_enc = "opcode8:ip-inc8", .decoder_fn = &decodeJump });
    try map.put(.{ 0b01111101, 0b11111111 }, .{ .opcode = .jnl, .bits_enc = "opcode8:ip-inc8", .decoder_fn = &decodeJump });
    try map.put(.{ 0b01111111, 0b11111111 }, .{ .opcode = .jnle, .bits_enc = "opcode8:ip-inc8", .decoder_fn = &decodeJump });
    try map.put(.{ 0b01110011, 0b11111111 }, .{ .opcode = .jnb, .bits_enc = "opcode8:ip-inc8", .decoder_fn = &decodeJump });
    try map.put(.{ 0b01110111, 0b11111111 }, .{ .opcode = .jnbe, .bits_enc = "opcode8:ip-inc8", .decoder_fn = &decodeJump });
    try map.put(.{ 0b01111011, 0b11111111 }, .{ .opcode = .jnp, .bits_enc = "opcode8:ip-inc8", .decoder_fn = &decodeJump });
    try map.put(.{ 0b01110001, 0b11111111 }, .{ .opcode = .jno, .bits_enc = "opcode8:ip-inc8", .decoder_fn = &decodeJump });
    try map.put(.{ 0b01111001, 0b11111111 }, .{ .opcode = .jns, .bits_enc = "opcode8:ip-inc8", .decoder_fn = &decodeJump });
    try map.put(.{ 0b11100010, 0b11111111 }, .{ .opcode = .loop, .bits_enc = "opcode8:ip-inc8", .decoder_fn = &decodeJump });
    try map.put(.{ 0b11100001, 0b11111111 }, .{ .opcode = .loopz, .bits_enc = "opcode8:ip-inc8", .decoder_fn = &decodeJump });
    try map.put(.{ 0b11100000, 0b11111111 }, .{ .opcode = .loopnz, .bits_enc = "opcode8:ip-inc8", .decoder_fn = &decodeJump });
    try map.put(.{ 0b11100011, 0b11111111 }, .{ .opcode = .jcxz, .bits_enc = "opcode8:ip-inc8", .decoder_fn = &decodeJump });


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
        start_bit.* -= @as(u3, @intCast(size));
        shift = start_bit.* + 1;
    }

    const shifted_num = current_byte >> shift;
    //log.warn("size = {d} shift  = {d}", .{ size, shift });

    var mask: u8 = 0;
    if (size == 8) {
        mask = 0b11111111;
    } else {
        mask = ((mask_base << @as(u3, @intCast(size))) - 1);
    }
    //log.warn("byte = {b} ; shifted num = {b} ; mask = {b} ; masked num = {b}", .{ current_byte, shifted_num, mask, shifted_num & mask });

    return shifted_num & mask;
}

fn getRegisterOperand(decoding: Decoding, op_position: OperandPosition) instruction.Operand {
    var register_idx: u8 = undefined;

    if (decoding.mod != null) {
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
    } else {
        register_idx = if (decoding.w == 1) decoding.reg + 8 else decoding.reg;
    }

    return .{
        .register = @enumFromInt(register_idx),
    };
}

fn getAddressCalculationOperand(decoding: Decoding) DecoderError!instruction.Operand {
    if (decoding.mod.? == 0b00) {
        return .{
            .mem_calc_no_disp = instruction.MemCalcTable[decoding.rm],
        };
    }

    if (decoding.mod.? == 0b01) {
        var mem_calc = instruction.MemCalcTable[decoding.rm];
        return .{
            .mem_calc_with_disp = .{
                .register1 = mem_calc.register1,
                .register2 = mem_calc.register2,
                .disp = .{
                    .byte = @as(i8, @bitCast(decoding.disp_lo.?)),
                }
            },
        };
    }

    if (decoding.mod.? == 0b10) {
        var mem_calc = instruction.MemCalcTable[decoding.rm];
        const word = @as(u16, decoding.disp_hi.?) << 8 | decoding.disp_lo.?;
        return .{
            .mem_calc_with_disp = .{
                .register1 = mem_calc.register1,
                .register2 = mem_calc.register2,
                .disp = .{
                    .word = @as(i16, @bitCast(word)),
                }
            },
        };
    }

    return DecoderError.ModNotFound;
}

fn getDataOperand(decoding: Decoding) !instruction.Operand {
    if (decoding.data) |data_lo| {
        var operand: instruction.Operand = undefined;

        if (decoding.dataw) |data_hi| {
            operand = .{
                .immediate = .{ .value = @as(u16, data_hi) << 8 | data_lo },
            };
        } else {
            operand = .{
                .immediate = .{ .value = @as(u8, @bitCast(data_lo)) },
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

fn decodeRegMemToFromRegMem(decoding: Decoding, op_position: OperandPosition) !?instruction.Operand {
    if (decoding.mod) |mod| {
        if (mod == 0b11) {
            return getRegisterOperand(decoding, op_position);
        } else if (isDirectAddress(decoding) and op_position == .source) {
            return getDirectAddressDispOperand(decoding);
        } else {
            if (op_position == .source) {
                if (decoding.d == 0) {
                    return getRegisterOperand(decoding, op_position);
                } else {
                    return try getAddressCalculationOperand(decoding);
                }
            }

            if (op_position == .destination) {
                if (decoding.d == 1) {
                    return getRegisterOperand(decoding, op_position);
                } else {
                    return try getAddressCalculationOperand(decoding);
                }
            }
        }
    }

    const register_idx: u8 = if (decoding.w == 1) decoding.reg + 8 else decoding.reg;
    return .{
        .register = @enumFromInt(register_idx),
    };
}

fn decodeImmediateToRegMem(decoding: Decoding, op_position: OperandPosition) !?instruction.Operand {
    if (decoding.data == null) {
        return error.DataNotFound;
    }

    if (op_position == .source) {
        return try getDataOperand(decoding);
    }

    if (decoding.mod) |mod| {
        if (mod == 0b11) {
            return getRegisterOperand(decoding, op_position);
        } else if (isDirectAddress(decoding) and op_position == .destination) {
            return getDirectAddressDispOperand(decoding);
        } else {
            return try getAddressCalculationOperand(decoding);
        }
    }

    return error.CouldNotDecodeOperand;
}

fn decodeMovImmediateToRegister(decoding: Decoding, op_position: OperandPosition) !?instruction.Operand {
    if (decoding.data == null) {
        return error.DataNotFound;
    }

    if (op_position == .source) {
        return try getDataOperand(decoding);
    }

    return getRegisterOperand(decoding, op_position);
}

fn decodeImmediateToAcc(decoding: Decoding, op_position: OperandPosition) !?instruction.Operand {
    if (decoding.data == null) {
        return error.DataNotFound;
    }

    if (op_position == .destination) {
        return .{
            .register = .ax,
        };
    }

    return try getDataOperand(decoding);
}

fn decodeMovMemoryToAcc(decoding: Decoding, op_position: OperandPosition) !?instruction.Operand {
    if (op_position == .destination) {
        return .{
            .register = .ax,
        };
    }

    return try getDirectAddress(decoding);
}

fn decodeMovAccToMemory(decoding: Decoding, op_position: OperandPosition) !?instruction.Operand {
    if (op_position == .source) {
        return .{
            .register = .ax,
        };
    }

    return try getDirectAddress(decoding);
}

fn decodeJump(decoding: Decoding, op_position: OperandPosition) !?instruction.Operand {
    if (decoding.ip_inc == null) {
        return error.InstructionPointerIncrementNotFound;
    }

    if (op_position == .destination) {
        return .{
            .signed_inc_to_ip = decoding.ip_inc.?,
        };
    }

    // NOTE(evgheni): there's no source in jumps
    return null;
}

fn getOpCode(encoding: Encoding, decoding: Decoding) Opcode {
    if (encoding.opcode == .arithmetic and decoding.pad != null) {
        switch (decoding.pad.?) {
            0 => {
                return .add;
            },
            0b101 => {
                return .sub;
            },
            0b111 => {
                return .cmp;
            },
            else => {
                return encoding.opcode;
            }
        }
    }

    return encoding.opcode;
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
                .pad => {
                    decoding.pad = bit_value;
                },
                .ip_inc => {
                    decoding.ip_inc = @as(i8, @bitCast(bit_value));
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

    var operand1: instruction.Operand = undefined;
    var decoder: *const decoderFunc = undefined;

    if (encoding.decoder_fn) |decoder_fn| {
        decoder = decoder_fn;
    } else {
        return error.DecoderNotFound;
    }

    if (decoder(decoding, OperandPosition.destination)) |op1| {
        operand1 = op1.?;
    } else |err| {
        return err;
    }
    
    return .{
        .opcode = getOpCode(encoding, decoding),
        .operand1 = operand1,
        .operand2 = try decoder(decoding, OperandPosition.source),
        .size = current_offset - offset,
    };
}

pub fn decode(allocator: Allocator, buffer: []const u8, buffer_len: usize, offset: u16) !?[]Instruction {
    var map = try createMapOfOpcodes(allocator);
    defer map.deinit();
    var iterator = map.iterator();

    var instructions = ArrayList(Instruction).init(allocator);
    var current_offset = offset;

    while (current_offset < buffer_len) {
        while (iterator.next()) |entry| {
            const key = entry.key_ptr.*;
            if (buffer[current_offset] & key[1] == key[0]) {
                if (try decodeInstruction(buffer, current_offset, entry.value_ptr.*)) |inst| {
                    try instructions.append(inst);
                    current_offset += inst.size;
                    break; //Note(evgheni): don't need to continue checking the map of opcodes
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
    var allocator = std.testing.allocator;
    var map = try createMapOfOpcodes(allocator);
    defer map.deinit();
    const encoding = map.get(.{ 0b100010_00, 0b11111_000 }).?;
    const bytes_buffer: [2]u8 = .{ 0b10001001, 0b11011001 };
    const result = try decodeInstruction(&bytes_buffer, 0, encoding);

    try expect(result.?.opcode == Opcode.mov);
    try expectEqual(Register.cx, result.?.operand1.register);
    try expectEqual(Register.bx, result.?.operand2.?.register);
    try expect(result.?.size == 2);
}

test "decoding instruction - 8-bit immediate" {
    var allocator = std.testing.allocator;
    var map = try createMapOfOpcodes(allocator);
    defer map.deinit();
    const encoding = map.get(.{ 0b1011_0000, 0b1111_0000 }).?;
    const bytes_buffer = [2]u8{ 0b10110001, 0b00001100 };

    const result = try decodeInstruction(&bytes_buffer, 0, encoding);
    try expect(result.?.opcode == Opcode.mov);
    try expectEqual(Register.cl, result.?.operand1.register);
    try expect(result.?.operand2.?.immediate.value == 12);
    try expect(result.?.size == 2);
}

test "decoding instruction - 16-bit immediate" {
    var allocator = std.testing.allocator;
    var map = try createMapOfOpcodes(allocator);
    defer map.deinit();
    const encoding = map.get(.{ 0b1011_0000, 0b1111_0000 }).?;
    const bytes_buffer = [3]u8{ 0b10111010, 0b01101100, 0b00001111 };

    const result = try decodeInstruction(&bytes_buffer, 0, encoding);
    try expect(result.?.opcode == Opcode.mov);
    try expectEqual(Register.dx, result.?.operand1.register);
    try expect(result.?.operand2.?.immediate.value == 3948);
}

test "decoding effective memory address calculation to register" {
    var allocator = std.testing.allocator;
    var map = try createMapOfOpcodes(allocator);
    defer map.deinit();
    const encoding = map.get(.{ 0b100010_00, 0b11111_000 }).?;
    const bytes_buffer = [2]u8{ 0b10001010, 0b00000000 };
    const result = try decodeInstruction(&bytes_buffer, 0, encoding);

    try expect(result.?.opcode == Opcode.mov);
    try expect(result.?.size == 2);
    try expectEqual(Register.al, result.?.operand1.register);
    try expect(result.?.operand2.?.mem_calc_no_disp.register1 == Register.bx);
    try expect(result.?.operand2.?.mem_calc_no_disp.register2 == Register.si);
}

test "decoding effective memory address calculation with 8-bit displacement" {
    var allocator = std.testing.allocator;
    var map = try createMapOfOpcodes(allocator);
    defer map.deinit();
    const encoding = map.get(.{ 0b100010_00, 0b11111_000 }).?;
    const bytes_buffer = [3]u8 { 0b10001011, 0b01010110, 0b00000000 };
    const result = try decodeInstruction(&bytes_buffer, 0, encoding);

    // mov dx, [bp]

    try expect(result.?.opcode == Opcode.mov);
    try expectEqual(Register.dx, result.?.operand1.register);
    try expectEqual(Register.bp, result.?.operand2.?.mem_calc_with_disp.register1);
    try expect(result.?.operand2.?.mem_calc_with_disp.disp.byte == 0);

    // mov ah, [bx + si + 4]

    const bytes_buffer_2 = [3]u8 { 0b10001010, 0b01100000, 0b00000100 };
    const result_2 = try decodeInstruction(&bytes_buffer_2, 0, encoding);

    try expect(result_2.?.opcode == Opcode.mov);
    try expectEqual(Register.ah, result_2.?.operand1.register);
    try expectEqual(Register.bx, result_2.?.operand2.?.mem_calc_with_disp.register1);
    try expectEqual(Register.si, result_2.?.operand2.?.mem_calc_with_disp.register2.?);
    try expect(result_2.?.operand2.?.mem_calc_with_disp.disp.byte == 4);
}


test "decoding effective memory address calculation with 16-bit displacement" {
    var allocator = std.testing.allocator;
    var map = try createMapOfOpcodes(allocator);
    defer map.deinit();
    const encoding = map.get(.{ 0b100010_00, 0b11111_000 }).?;

    // mov al, [bx + si + 4999]

    const bytes_buffer = [4]u8 { 0b10001010, 0b10000000, 0b10000111, 0b00010011 };
    const result = try decodeInstruction(&bytes_buffer, 0, encoding);

    try expect(result.?.opcode == Opcode.mov);
    try expectEqual(Register.al, result.?.operand1.register);
    try expectEqual(Register.bx, result.?.operand2.?.mem_calc_with_disp.register1);
    try expectEqual(Register.si, result.?.operand2.?.mem_calc_with_disp.register2.?);
    try expect(result.?.operand2.?.mem_calc_with_disp.disp.word == 4999);
}

test "decoding memory address calculation in destination" {
    var allocator = std.testing.allocator;
    var map = try createMapOfOpcodes(allocator);
    defer map.deinit();
    const encoding = map.get(.{ 0b100010_00, 0b11111_000 }).?;

    // mov [bx + di], cx

    const bytes_buffer = [2]u8 { 0b10001001, 0b00001001 };
    const result = try decodeInstruction(&bytes_buffer, 0, encoding);

    try expect(result.?.opcode == Opcode.mov);
    try expectEqual(Register.bx, result.?.operand1.mem_calc_no_disp.register1);
    try expectEqual(Register.di, result.?.operand1.mem_calc_no_disp.register2.?);
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
    var allocator = std.testing.allocator;
    var map = try createMapOfOpcodes(allocator);
    defer map.deinit();
    const encoding = map.get(.{ 0b100010_00, 0b11111_000 }).?;

    // mov ax, [bx + di - 37]

    const bytes_buffer = [3]u8 { 0b10001011, 0b01000001, 0b11011011 };
    const result = try decodeInstruction(&bytes_buffer, 0, encoding);

    try expect(result.?.opcode == Opcode.mov);
    try expectEqual(Register.ax, result.?.operand1.register);
    try expectEqual(Register.bx, result.?.operand2.?.mem_calc_with_disp.register1);
    try expectEqual(Register.di, result.?.operand2.?.mem_calc_with_disp.register2.?);
    try expect(result.?.operand2.?.mem_calc_with_disp.disp.byte == -37);

    // mov [si - 300], cx

    const bytes_buffer_2 = [4]u8 { 0b10001001, 0b10001100, 0b11010100, 0b11111110 };
    const result_2 = try decodeInstruction(&bytes_buffer_2, 0, encoding);

    try expect(result_2.?.opcode == Opcode.mov);

    try expectEqual(Register.si, result_2.?.operand1.mem_calc_with_disp.register1);
    try expect(result_2.?.operand1.mem_calc_with_disp.disp.word == -300);

    try expectEqual(Register.cx, result_2.?.operand2.?.register);
}

test "decoding explicit sizes" {
    var allocator = std.testing.allocator;
    var map = try createMapOfOpcodes(allocator);
    defer map.deinit();
    const encoding = map.get(.{ 0b1100011_0, 0b1111111_0 }).?;

    // mov [bp + di], byte 7

    const bytes_buffer = [3]u8 { 0b11000110, 0b00000011, 0b00000111 };
    if (try decodeInstruction(&bytes_buffer, 0, encoding)) |result| {
        try expect(result.opcode == Opcode.mov);
        try expectEqual(Register.bp, result.operand1.mem_calc_no_disp.register1);
        try expectEqual(Register.di, result.operand1.mem_calc_no_disp.register2.?);

        try expect(result.operand2.?.immediate.value == 7);
        try expectEqual(instruction.DataSize.byte, result.operand2.?.immediate.size.?);
    }

    //mov [di + 901], word 347
    const bytes_buffer_2 = [6]u8 { 0b11000111, 0b10000101, 0b10000101, 0b00000011, 0b01011011, 0b00000001 };
    if (try decodeInstruction(&bytes_buffer_2, 0, encoding)) |result| {
        try expect(result.opcode == Opcode.mov);
        try expectEqual(Register.di, result.operand1.mem_calc_with_disp.register1);
        try expect(result.operand1.mem_calc_with_disp.disp.word == 901);

        try expect(result.operand2.?.immediate.value == 347);
        try expectEqual(instruction.DataSize.word, result.operand2.?.immediate.size.?);
    }
}

test "decoding direct address" {
    var allocator = std.testing.allocator;
    var map = try createMapOfOpcodes(allocator);
    defer map.deinit();
    const encoding = map.get(.{ 0b100010_00, 0b11111_000 }).?;

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
    var allocator = std.testing.allocator;
    var map = try createMapOfOpcodes(allocator);
    defer map.deinit();
    const encoding = map.get(.{ 0b1010000_0, 0b1111111_0 }).?;

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
    var allocator = std.testing.allocator;
    var map = try createMapOfOpcodes(allocator);
    defer map.deinit();
    const encoding = map.get(.{ 0b1010001_0, 0b1111111_0 }).?;

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
    var allocator = std.testing.allocator;
    var map = try createMapOfOpcodes(allocator);
    defer map.deinit();
    const encoding = map.get(.{ 0b000000_00, 0b111111_00 }).?;

    // add bx, [bx+si]
    const bytes_buffer = [_]u8 { 0b00000011, 0b00011000 };
    if (try decodeInstruction(&bytes_buffer, 0, encoding)) |result| {
        try expectEqual(Opcode.add, result.opcode);
        try expectEqual(Register.bx, result.operand1.register);
        try expectEqual(Register.bx, result.operand2.?.mem_calc_no_disp.register1);
        try expectEqual(Register.si, result.operand2.?.mem_calc_no_disp.register2.?);
    }
}

test "decode add immediate" {
    var allocator = std.testing.allocator;
    var map = try createMapOfOpcodes(allocator);
    defer map.deinit();
    const encoding = map.get(.{ 0b100000_00, 0b111111_00 }).?;

    // add si, 2
    const bytes_buffer = [_]u8 { 0b10000011, 0b11000110, 0b00000010 };
    if (try decodeInstruction(&bytes_buffer, 0, encoding)) |result| {
        try expectEqual(Opcode.add, result.opcode);
        try expectEqual(Register.si, result.operand1.register);
        try expect(result.operand2.?.immediate.value == 2);
    }
}

test "decode add immediate to accumulator" {
    var allocator = std.testing.allocator;
    var map = try createMapOfOpcodes(allocator);
    defer map.deinit();
    const encoding = map.get(.{ 0b0000010_0, 0b1111111_0 }).?;

    // add ax, 1000
    const bytes_buffer = [_]u8 { 0b00000101, 0b11101000, 0b00000011 };
    if (try decodeInstruction(&bytes_buffer, 0, encoding)) |result| {
        try expectEqual(Opcode.add, result.opcode);
        try expectEqual(Register.ax, result.operand1.register);
        try expect(result.operand2.?.immediate.value == 1000);
    }
}

test "decode sub immediate" {
    var allocator = std.testing.allocator;
    var map = try createMapOfOpcodes(allocator);
    defer map.deinit();
    const encoding = map.get(.{ 0b100000_00, 0b111111_00 }).?;

    // sub si, 2
    const bytes_buffer = [_]u8 { 0b10000011, 0b11101110, 0b00000010 };
    if (try decodeInstruction(&bytes_buffer, 0, encoding)) |result| {
        try expectEqual(Opcode.sub, result.opcode);
        try expectEqual(Register.si, result.operand1.register);
        try expect(result.operand2.?.immediate.value == 2);
        try expect(result.size == 3);
    }
}

test "decode sub immediate to accumulator" {
    var allocator = std.testing.allocator;
    var map = try createMapOfOpcodes(allocator);
    defer map.deinit();
    const encoding = map.get(.{ 0b0010110_0, 0b1111111_0 }).?;

    // add ax, 1000
    const bytes_buffer = [_]u8 { 0b00101101, 0b11101000, 0b00000011 };
    if (try decodeInstruction(&bytes_buffer, 0, encoding)) |result| {
        try expectEqual(Opcode.sub, result.opcode);
        try expectEqual(Register.ax, result.operand1.register);
        try expect(result.operand2.?.immediate.value == 1000);
    }
}


test "decode jump" {
    var allocator = std.testing.allocator;
    var map = try createMapOfOpcodes(allocator);
    defer map.deinit();
    const encoding = map.get(.{ 0b01110100, 0b11111111 }).?;

    // test_label0:
    // jz test_label0

    const bytes_buffer = [_]u8 {0b01110100, 0b11111110};
    if (try decodeInstruction(&bytes_buffer, 0, encoding)) |result| {
        try expectEqual(Opcode.je, result.opcode);
        try expect(result.operand1.signed_inc_to_ip == -2);
    }
}

test "move to memory" {
    var allocator = std.testing.allocator;
    var map = try createMapOfOpcodes(allocator);
    defer map.deinit();
    const encoding = map.get(.{ 0b1100011_0, 0b1111111_0 }).?;

    // mov word [1000], 1
    // seems to be generating the same binary as
    // mov [1000], word 1
    const bytes_buffer = [_]u8 { 0b11000111, 0b00000110, 0b11101000, 0b00000011, 0b00000001, 0b00000000 };

    if (try decodeInstruction(&bytes_buffer, 0, encoding)) |result| {
        try expectEqual(Opcode.mov, result.opcode);
        try expect(result.size == 6);
        try expect(result.operand1.direct_address ==  1000);
        try expect(result.operand2.?.immediate.value == 1);
        try expect(result.operand2.?.immediate.size.? == .word);
    }
}
