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

fn decodeMemory(byte2: u8) []const u8 {
    const mod = (byte2 & 0b11_000000) >> 6;
    const rm_bits = byte2 & 0b00000_111;
    return registerMemoryEncoding[mod][rm_bits];
}

fn decodeRegMemToRegMem(slice: []const u8, mod: u8) !void {
    const stdout = std.io.getStdOut().writer();
    var source: []const u8 = undefined;
    var destination: []const u8 = undefined;
    var reg: []const u8 = undefined;
    var rm: []const u8 = undefined;

    const w_bit = (slice[0] & 0b00000001);
    const d_bit = (slice[0] & 0b00000010) >> 1;
    const reg_bits = (slice[1] & 0b00_111_000) >> 3;
    const rm_bits = slice[1] & 0b00000_111;

    if (mod == 0b11) {
        reg = registerEncoding[w_bit][reg_bits];
        rm = registerEncoding[w_bit][rm_bits];
        if (d_bit == 0) {
            try stdout.print("{s}, {s}\n", .{ rm, reg });
        } else if (d_bit == 1) {
            try stdout.print("{s}, {s}\n", .{ reg, rm });
        }
    } else if (mod == 0b00) {
        reg = registerEncoding[w_bit][reg_bits];
        rm = decodeMemory(slice[1]);

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
            try stdout.print("{s}, [{d}]\n", .{ destination, direct_address });
        } else {
            try stdout.print("{s}, {s}\n", .{ destination, source });
        }
    } else if (mod == 0b01) {
        const d8 = slice[2];
        reg = registerEncoding[w_bit][reg_bits];
        rm = decodeMemory(slice[1]);
        if (d_bit == 0) {
            if (d8 == 0) {
                try stdout.print("[{s}], {s}\n", .{ rm, reg });
            } else {
                try stdout.print("[{s} + {d}], {s}\n", .{ rm, @bitCast(i8, d8), reg });
            }
        } else if (d_bit == 1) {
            if (d8 == 0) {
                try stdout.print("{s}, [{s}]\n", .{ reg, rm });
            } else {
                try stdout.print("{s}, [{s} + {d}]\n", .{ reg, rm, @bitCast(i8, d8) });
            }
        }
    } else if (mod == 0b10) {
        const d16: u16 = @as(u16, slice[3]) << 8 | slice[2];
        reg = registerEncoding[w_bit][reg_bits];
        rm = decodeMemory(slice[1]);

        if (d_bit == 0) {
            if (d16 == 0) {
                try stdout.print("[{s}], {s}\n", .{ rm, reg });
            } else {
                try stdout.print("[{s} + {d}], {s}\n", .{ rm, d16, reg });
            }
        } else if (d_bit == 1) {
            if (d16 == 0) {
                try stdout.print("{s}, [{s}]\n", .{ reg, rm });
            } else {
                try stdout.print("{s}, [{s} + {d}]\n", .{ reg, rm, d16 });
            }
        }
    }
}

fn decodeImmediateToRegister(slice: []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    const reg_bits = slice[0] & 0b00000111;
    const w_bit = (slice[0] & 0b00001000) >> 3;
    const reg = registerEncoding[w_bit][reg_bits];

    if (slice.len == 3) {
        const word: u16 = @as(u16, slice[2]) << 8 | slice[1];
        try stdout.print("{s}, {d}\n", .{ reg, word });
    } else if (slice.len == 2) {
        try stdout.print("{s}, {d}\n", .{ reg, slice[1] });
    }
}

fn decodeImmediateToRegMem8(byte1: u8, byte2: u8, data_lo: u8, is_source_specified: bool) !void {
    const stdout = std.io.getStdOut().writer();
    const w_bit = (byte1 & 0b00000001);
    const keyword = if (w_bit == 1) "word" else "byte";
    const rm = decodeMemory(byte2);

    if (is_source_specified) {
        try stdout.print("{s}, {s} {d}\n", .{ rm, keyword, data_lo });
    } else {
        try stdout.print("{s}, {d}\n", .{ rm, data_lo });
    }
}

fn decodeImmediateToRegMem16(byte1: u8, byte2: u8, disp_lo: u8, disp_hi: u8, data_lo: u8, data_hi: u8, is_rm_specified: bool) !void {
    const stdout = std.io.getStdOut().writer();
    const w_bit = (byte1 & 0b00000001);
    const keyword = if (w_bit == 1) "word" else "byte";
    const displacement: u16 = @as(u16, disp_hi) << 8 | disp_lo;
    const data: u16 = @as(u16, data_hi) << 8 | data_lo;
    const rm = decodeMemory(byte2);

    if (is_rm_specified) {
        try stdout.print("[{s} + {d}] {s}, {d}\n", .{ rm, displacement, keyword, data });
    } else {
        try stdout.print("[{s} + {d}], {s} {d}\n", .{ rm, displacement, keyword, data });
    }
}

fn decodeMemoryToAcc(byte1: u8, addr_lo: u8, addr_hi: u8) !void {
    const stdout = std.io.getStdOut().writer();
    const w_bit = (byte1 & 0b00000001);
    const addr: u16 = @as(u16, addr_hi) << 8 | addr_lo;
    const acc = if (w_bit == 1) "ax" else "al";

    try stdout.print("{s}, [{d}]\n", .{ acc, addr });
}

fn decodeAccToMemory(byte1: u8, addr_lo: u8, addr_hi: u8) !void {
    const stdout = std.io.getStdOut().writer();
    const w_bit = (byte1 & 0b00000001);
    const addr: u16 = @as(u16, addr_hi) << 8 | addr_lo;
    const acc = if (w_bit == 1) "ax" else "al";

    try stdout.print("[{d}], {s}\n", .{ addr, acc });
}

fn decodeImmediateToAcc8(w_bit: u8, data_lo: u8) !void {
    const stdout = std.io.getStdOut().writer();
    const acc = if (w_bit == 1) "ax" else "al";

    try stdout.print("{s}, {d}\n", .{ acc, data_lo });
}

fn decodeImmediateToAcc16(w_bit: u8, data_lo: u8, data_hi: u8) !void {
    const stdout = std.io.getStdOut().writer();
    const data: u16 = @as(u16, data_hi) << 8 | data_lo;
    const acc = if (w_bit == 1) "ax" else "al";

    try stdout.print("{s}, {d}\n", .{ acc, data });
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
        if ((buffer[i] & 0b1011_0000) == 0b1011_0000) {
            // MOV: immediate to register
            const slice = switch (buffer[0] & 0b0000_1_000) {
                0b0000_0_000 => buffer[i .. i + 2],
                0b0000_1_000 => buffer[i .. i + 3],
                else => buffer[i .. i + 1],
            };
            try stdout.print("mov ", .{});
            try decodeImmediateToRegister(slice);
            i += slice.len - 1;
        } else if ((buffer[i] & 0b100010_00) == 0b100010_00) {
            // MOV: R/M to R/M
            const mod = (buffer[i + 1] & 0b11_000000) >> 6;
            const rm_bits = (buffer[i + 1] & 0b00000_111);

            var slice: []u8 = undefined;

            if (mod == 0b11) {
                // Regisnter mode; no displacement
                slice = buffer[i .. i + 2];
            } else if (mod == 0b00 and rm_bits != 0b110) {
                slice = buffer[i .. i + 2];
            } else if (mod == 0b00 and rm_bits == 0b110) {
                slice = buffer[i .. i + 4];
            } else if (mod == 0b01) {
                // Mem mode; 8-bit signed displacement
                slice = buffer[i .. i + 3];
            } else if (mod == 0b10) {
                slice = buffer[i .. i + 4];
            } else {
                slice = buffer[i..];
            }

            try stdout.print("mov ", .{});
            try decodeRegMemToRegMem(slice, mod);
            i += slice.len - 1;
        } else if ((buffer[i] & 0b1100011_0) == 0b1100011_0) {
            const w_bit = (buffer[i] & 0b0000000_1);
            const mod = (buffer[i + 1] & 0b11_000000) >> 6;
            const rm_bits = (buffer[i + 1] & 0b00000_111);

            // NOTE(evgheni): This is incomplete, just enough to
            // finish the homework. For completeness more conditions
            // are needed.

            if (mod == 0b00 and rm_bits != 0b110 and w_bit == 0) {
                // no displacement; 8-bit data
                try stdout.print("mov ", .{});
                try decodeImmediateToRegMem8(buffer[i], buffer[i + 1], buffer[i + 2], true);
                i += 2;
            } else if (mod == 0b10 and rm_bits != 0b110 and w_bit == 1) {
                // 16-bit displacement; 16-bit data
                try stdout.print("mov ", .{});
                try decodeImmediateToRegMem16(buffer[i], buffer[i + 1], buffer[i + 2], buffer[i + 3], buffer[i + 4], buffer[i + 5], true);
                i += 5;
            }
        } else if ((buffer[i] & 0b1010001_0) == 0b1010001_0) {
            try stdout.print("mov ", .{});
            try decodeAccToMemory(buffer[i], buffer[i + 1], buffer[i + 2]);
            i += 2;
        } else if ((buffer[i] & 0b101000_00) == 0b101000_00) {
            try stdout.print("mov ", .{});
            try decodeMemoryToAcc(buffer[i], buffer[i + 1], buffer[i + 2]);
            i += 2;
        } else if ((buffer[i] & 0b00000_1_00) == 0b00000_1_00) {
            // Immediate to accumulator
            const w_bit = (buffer[i] & 0b0000000_1);

            switch (buffer[i] & 0b00_111_000) {
                0b00_000_000 => try stdout.print("add ", .{}),
                0b00_101_000 => try stdout.print("sub ", .{}),
                0b00_111_000 => try stdout.print("cmp ", .{}),
                else => unreachable,
            }

            if (w_bit == 0) {
                try decodeImmediateToAcc8(w_bit, buffer[i + 1]);
                i += 1;
            } else {
                try decodeImmediateToAcc16(w_bit, buffer[i + 1], buffer[i + 2]);
                i += 2;
            }
        } else if ((buffer[i] & 0b100000_00) == 0b100000_00) {
            // Immediate to register/memory
            const w_bit = buffer[i] & 0b0000000_1;

            switch (buffer[i] & 0b00_111_000) {
                0b00_000_000 => try stdout.print("add ", .{}),
                0b00_101_000 => try stdout.print("sub ", .{}),
                0b00_111_000 => try stdout.print("cmp ", .{}),
                else => unreachable,
            }

            if (w_bit == 0) {
                try stdout.print("byte ", .{});
                try decodeImmediateToRegMem8(buffer[i], buffer[i + 1], buffer[i + 2], false);
                i += 2;
            } else {
                try stdout.print("word ", .{});
                try decodeImmediateToRegMem16(buffer[i], buffer[i + 1], buffer[i + 2], buffer[i + 3], buffer[i + 4], buffer[i + 5], false);
                i += 5;
            }
        }
        i += 1;
    }
}
