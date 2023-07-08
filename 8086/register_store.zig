const std = @import("std");
const fm = std.fmt;
const log = std.log;

pub const Register = enum {
    al,
    cl,
    dl,
    bl,
    ah,
    ch,
    dh,
    bh,
    ax,
    cx,
    dx,
    bx,
    sp,
    bp,
    si,
    di,
};

var mem_registers = [_]u16{0, 0, 0, 0, 0, 0, 0, 0};


fn writeLow(register: Register, low_byte: u8) void {
    const value = @as(i16, low_byte << 8);
    write(register, value);
}

pub fn resetRegisters() void {
    mem_registers = [_]u16{0} ** mem_registers.len;
}

pub fn write(register: Register, value: u16) void {
    switch (register) {
        .ax, .bx, .cx, .dx, .sp, .bp, .si, .di => |mem_reg| {
            const idx = @enumToInt(mem_reg) - 8;
            mem_registers[idx] = value;
        },
        .al, .bl, .cl, .dl => |low_reg| {
            const idx = @enumToInt(low_reg);
            const combined_val = mem_registers[idx] ^ ((mem_registers[idx] ^ value) & 0b11111111);
            mem_registers[idx] = combined_val;
        },
        .ah, .bh, .ch, .dh => |high_reg| {
            const idx = @enumToInt(high_reg) - 4;
            const combined_val = mem_registers[idx] ^ ((mem_registers[idx] ^ (value << 8)) & 0b1111111100000000);
            mem_registers[idx] = combined_val;
        }
    }
}

pub fn writeFromRegister(destination: Register, source: Register) void {
    const value = read(source);
    return write(destination, value);
}

pub fn read(register: Register) u16 {
    switch (register) {
        .ax, .bx, .cx, .dx, .sp, .bp, .si, .di => |mem_reg| {
            const idx = @enumToInt(mem_reg) - 8;
            return mem_registers[idx];
        },
        .al, .bl, .cl, .dl => |low_reg| {
            const idx = @enumToInt(low_reg);
            const val = mem_registers[idx] & 0b11111111;
            return val;
        },
        .ah, .bh, .ch, .dh => |high_reg| {
            const idx = @enumToInt(high_reg) - 4;
            const val = mem_registers[idx] >> 8;
            return val;
        }
    }

    return 0;
}

pub fn printStatus() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("\n=== REGISTERS ===\n", .{});

    const registers = [_]Register {.ax, .bx, .cx, .dx, .sp, .bp, .si, .di};

    for (registers) |reg| {
        const idx = @enumToInt(reg) - 8;
        const value = @bitCast(i16, mem_registers[idx]);
        try stdout.print("{s}: {d} (0x{X})\n", 
            .{@tagName(reg), value, value});
    }


    try stdout.print("=================\n", .{});
}


var ip: u16 = 0;

pub fn readIP() u16 {
    return ip;
}

pub fn writeIP(value: u16) void {
    ip = value;
}

pub fn printIP() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("\n====== IP ======= \n", .{});
    try stdout.print("{d}\n", .{ip});
    try stdout.print("=================\n", .{});
}
