const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const print = std.debug.print;
const assert = std.debug.assert;

// First index is usually the w-bit = 00, 01
const registerEncoding = [2][8][]const u8{
    [_][]const u8{ "al", "cl", "dl", "bl", "ah", "ch", "dh", "bh" },
    [_][]const u8{ "ax", "cx", "dx", "bx", "sp", "bp", "si", "di" },
};

// First index is MOD = 00, 01, 10
// Second index is R/M
const registerMemoryEncoding = [3][8][]const u8{
    [_][]const u8{ "[bx + si]", "[bx + di]", "[bp + si]", "[bp + di]", "[si]", "[di]", "???", "[bx]" },
    [_][]const u8{ "bx + si", "bx + di", "bp + si", "bp + di", "si", "di", "bp", "bx" },
    [_][]const u8{ "bx + si", "bx + di", "bp + si", "bp + di", "si", "di", "bp", "bx" },
};

fn decodeRegMemToRegMem(slice: []const u8, mod: u8) []u8 {
    if (slice.len == 0) {
        return undefined;
    }

    var source: []const u8 = undefined;
    var destination: []const u8 = undefined;
    var outbuffer: [256]u8 = undefined;
    var result: []u8 = "";
    var reg: []const u8 = undefined;
    var rm: []const u8 = undefined;

    const w_bit = (slice[0] & 0b00000001);
    const d_bit = (slice[0] & 0b00000010) >> 1;
    const reg_bits = (slice[1] & 0b00_111_000) >> 3;
    const rm_bits = slice[1] & 0b00000_111;

    if (mod == 0b11) {
        if (d_bit == 0) {
            source = registerEncoding[w_bit][reg_bits];
            destination = registerEncoding[w_bit][rm_bits];
        } else if (d_bit == 1) {
            source = registerEncoding[w_bit][rm_bits];
            destination = registerEncoding[w_bit][reg_bits];
        }
        result = std.fmt.bufPrint(outbuffer[0..], "mov {s}, {s}", .{ destination, source }) catch undefined;
    } else if (mod == 0b00) {
        reg = registerEncoding[w_bit][reg_bits];
        rm = registerMemoryEncoding[mod][rm_bits];

        if (d_bit == 0) {
            source = reg;
            destination = rm;
        } else if (d_bit == 1) {
            source = rm;
            destination = reg;
        }

        var direct_address: u16 = 0;
        if (rm_bits == 0b110) {
            direct_address = @as(u16, slice[3]) << 8 | slice[2];
            result = std.fmt.bufPrint(outbuffer[0..], "mov {s}, [{d}]", .{ destination, direct_address }) catch undefined;
        } else {
            result = std.fmt.bufPrint(outbuffer[0..], "mov {s}, {s}", .{ destination, source }) catch undefined;
        }
    } else if (mod == 0b01) {
        const d8 = slice[2];
        reg = registerEncoding[w_bit][reg_bits];
        rm = registerMemoryEncoding[mod][rm_bits];
        if (d_bit == 0) {
            source = reg;
            destination = rm;
            if (d8 == 0) {
                result = std.fmt.bufPrint(outbuffer[0..], "mov [{s}], {s}", .{ destination, source }) catch undefined;
            } else {
                result = std.fmt.bufPrint(outbuffer[0..], "mov [{s} + {d}], {s}", .{ destination, @bitCast(i8, d8), source }) catch undefined;
            }
        } else if (d_bit == 1) {
            source = rm;
            destination = reg;
            if (d8 == 0) {
                result = std.fmt.bufPrint(outbuffer[0..], "mov {s}, [{s}]", .{ destination, source }) catch undefined;
            } else {
                result = std.fmt.bufPrint(outbuffer[0..], "mov {s}, [{s} + {d}]", .{ destination, source, @bitCast(i8, d8) }) catch undefined;
            }
        }
    } else if (mod == 0b10) {
        const d16: u16 = @as(u16, slice[3]) << 8 | slice[2];

        if (d_bit == 0) {
            source = registerEncoding[w_bit][reg_bits];
            destination = registerMemoryEncoding[mod][rm_bits];
            if (d16 == 0) {
                result = std.fmt.bufPrint(outbuffer[0..], "mov [{s}], {s}", .{ destination, source }) catch undefined;
            } else {
                result = std.fmt.bufPrint(outbuffer[0..], "mov [{s} + {d}], {s}", .{ destination, d16, source }) catch undefined;
            }
        } else if (d_bit == 1) {
            source = registerMemoryEncoding[mod][rm_bits];
            destination = registerEncoding[w_bit][reg_bits];
            if (d16 == 0) {
                result = std.fmt.bufPrint(outbuffer[0..], "mov {s}, [{s}]", .{ destination, source }) catch undefined;
            } else {
                result = std.fmt.bufPrint(outbuffer[0..], "mov {s}, [{s} + {d}]", .{ destination, source, d16 }) catch undefined;
            }
        }
    }

    var result_copy = std.heap.page_allocator.dupe(u8, result) catch undefined;
    return result_copy;
}

fn decodeImmediateToRegister(slice: []const u8) []u8 {
    var outbuffer: [256]u8 = undefined;
    var result: []u8 = undefined;
    const reg_bits = slice[0] & 0b00000111;
    const w_bit = (slice[0] & 0b00001000) >> 3;
    const reg = registerEncoding[w_bit][reg_bits];

    if (slice.len == 3) {
        const word: u16 = @as(u16, slice[2]) << 8 | slice[1];
        result = std.fmt.bufPrint(outbuffer[0..], "mov {s}, {d}", .{ reg, word }) catch undefined;
    } else if (slice.len == 2) {
        result = std.fmt.bufPrint(outbuffer[0..], "mov {s}, {d}", .{ reg, slice[1] }) catch undefined;
    }

    var result_copy = std.heap.page_allocator.dupe(u8, result) catch undefined;
    return result_copy;
}

fn decodeImmediateToRegMem(byte1: u8, byte2: u8, data_lo: u8) []u8 {
    var outbuffer: [256]u8 = undefined;
    var result: []u8 = "";
    var rm: []const u8 = undefined;

    const w_bit = (byte1 & 0b00000001);
    const mod = (byte2 & 0b11_000000) >> 6;
    const rm_bits = byte2 & 0b00000_111;
    const keyword = if (w_bit == 1) "word" else "byte";

    rm = registerMemoryEncoding[mod][rm_bits];
    result = std.fmt.bufPrint(outbuffer[0..], "mov {s}, {s} {d}", .{ rm, keyword, data_lo }) catch undefined;

    var result_copy = std.heap.page_allocator.dupe(u8, result) catch undefined;
    return result_copy;
}

fn decodeImmediateToRegMem6(byte1: u8, byte2: u8, disp_lo: u8, disp_hi: u8, data_lo: u8, data_hi: u8) []u8 {
    var outbuffer: [256]u8 = undefined;
    var result: []u8 = "";
    var rm: []const u8 = undefined;

    const w_bit = (byte1 & 0b00000001);
    const mod = (byte2 & 0b11_000000) >> 6;
    const rm_bits = byte2 & 0b00000_111;
    const keyword = if (w_bit == 1) "word" else "byte";
    const displacement: u16 = @as(u16, disp_hi) << 8 | disp_lo;
    const data: u16 = @as(u16, data_hi) << 8 | data_lo;

    rm = registerMemoryEncoding[mod][rm_bits];
    result = std.fmt.bufPrint(outbuffer[0..], "mov [{s} + {d}], {s} {d}", .{ rm, displacement, keyword, data }) catch undefined;

    var result_copy = std.heap.page_allocator.dupe(u8, result) catch undefined;
    return result_copy;
}

fn decodeMemoryToAcc(byte1: u8, addr_lo: u8, addr_hi: u8) []u8 {
    var outbuffer: [256]u8 = undefined;
    var result: []u8 = "";

    const w_bit = (byte1 & 0b00000001);
    const addr: u16 = @as(u16, addr_hi) << 8 | addr_lo;
    const acc = if (w_bit == 1) "ax" else "al";

    result = std.fmt.bufPrint(outbuffer[0..], "mov {s}, [{d}]", .{ acc, addr }) catch undefined;

    var result_copy = std.heap.page_allocator.dupe(u8, result) catch undefined;
    return result_copy;
}

fn decodeAccToMemory(byte1: u8, addr_lo: u8, addr_hi: u8) []u8 {
    var outbuffer: [256]u8 = undefined;
    var result: []u8 = "";

    const w_bit = (byte1 & 0b00000001);
    const addr: u16 = @as(u16, addr_hi) << 8 | addr_lo;
    const acc = if (w_bit == 1) "ax" else "al";

    result = std.fmt.bufPrint(outbuffer[0..], "mov [{d}], {s}", .{ addr, acc }) catch undefined;

    var result_copy = std.heap.page_allocator.dupe(u8, result) catch undefined;
    return result_copy;
}

fn printHeader(file_name: []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("; FILE: {s}\n", .{file_name});
    try stdout.print("; bits 16\n\n", .{});
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const stdout = std.io.getStdOut().writer();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const file = try std.fs.cwd().openFile(args[1], .{});
    defer file.close();

    try printHeader(args[1]);

    var buffer: [1024]u8 = undefined;
    const bytes_read = try file.readAll(&buffer);
    var i: usize = 0;
    while (i < bytes_read) {
        if ((buffer[i] & 0b1011_0000) == 0b1011_0000) { // MOV: immediate to register
            const slice = switch (buffer[0] & 0b0000_1_000) {
                0b0000_0_000 => buffer[i .. i + 2],
                0b0000_1_000 => buffer[i .. i + 3],
                else => buffer[i .. i + 1],
            };
            const result = decodeImmediateToRegister(slice);
            try stdout.print("{s}\n", .{result});
            i += slice.len - 1;
        } else if ((buffer[i] & 0b100010_00) == 0b100010_00) { // MOV: R/M to R/M
            const mod = (buffer[i + 1] & 0b11_000000) >> 6;
            const rm_bits = (buffer[i + 1] & 0b00000_111);

            var slice: []u8 = undefined;

            if (mod == 0b11) {
                slice = buffer[i .. i + 2];
            } else if (mod == 0b00 and rm_bits != 0b110) {
                slice = buffer[i .. i + 2];
            } else if (mod == 0b00 and rm_bits == 0b110) {
                slice = buffer[i .. i + 4];
            } else if (mod == 0b01) {
                slice = buffer[i .. i + 3];
            } else if (mod == 0b10) {
                slice = buffer[i .. i + 4];
            } else {
                slice = buffer[i..];
            }

            const result = decodeRegMemToRegMem(slice, mod);
            try stdout.print("{s}\n", .{result});
            i += slice.len - 1;
        } else if ((buffer[i] & 0b1100011_0) == 0b1100011_0) {
            const w_bit = (buffer[i] & 0b0000000_1);
            const mod = (buffer[i + 1] & 0b11_000000) >> 6;
            const rm_bits = (buffer[i + 1] & 0b00000_111);
            var result: []u8 = undefined;

            if (mod == 0b00 and rm_bits != 0b110 and w_bit == 0) {
                // no displacement; 8-bit data
                result = decodeImmediateToRegMem(buffer[i], buffer[i + 1], buffer[i + 2]);
                try stdout.print("{s}\n", .{result});
                i += 2;
            } else if (mod == 0b10 and rm_bits != 0b110 and w_bit == 1) {
                // 16-bit displacement; 16-bit data
                result = decodeImmediateToRegMem6(buffer[i], buffer[i + 1], buffer[i + 2], buffer[i + 3], buffer[i + 4], buffer[i + 5]);
                try stdout.print("{s}\n", .{result});
                i += 5;
            }
        } else if ((buffer[i] & 0b1010001_0) == 0b1010001_0) {
            const result = decodeAccToMemory(buffer[i], buffer[i + 1], buffer[i + 2]);
            try stdout.print("{s}\n", .{result});
            i += 2;
        } else if ((buffer[i] & 0b101000_00) == 0b101000_00) {
            const result = decodeMemoryToAcc(buffer[i], buffer[i + 1], buffer[i + 2]);
            try stdout.print("{s}\n", .{result});
            i += 2;
        }
        i += 1;
    }
}

test "immediate to register w = 1" {
    const buffer = [_]u8{ 0b10111001, 0b00001100, 0b00000000 };
    //const buffer = [_]u8{ 0b10111001, 0b11110100, 0b11111111 };
    if ((buffer[0] & 0b1011_0000) == 0b1011_0000) {
        const slice = switch (buffer[0] & 0b0000_1_000) {
            0b0000_0_000 => buffer[0..2],
            0b0000_1_000 => buffer[0..3],
            else => buffer[0],
        };

        const result = decodeImmediateToRegister(slice);
        std.debug.print("\nRESULT: {s} \n", .{result});
        try expectEqualStrings("mov cx, 12", result);
        try expectEqual(3, slice.len);
    }
}

test "immediate to register w = 0" {
    const buffer = [_]u8{ 0b10110001, 0b00001100 };
    if ((buffer[0] & 0b1011_0000) == 0b1011_0000) {
        const slice = switch (buffer[0] & 0b0000_1_000) {
            0b0000_0_000 => buffer[0..2],
            0b0000_1_000 => buffer[0..3],
            else => buffer[0],
        };

        const result = decodeImmediateToRegister(slice);
        std.debug.print("\nRESULT: {s} \n", .{result});
        try expectEqualStrings("mov cl, 12", result);
        try expectEqual(2, slice.len);
    }
}
