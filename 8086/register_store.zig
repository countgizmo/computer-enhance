const std = @import("std");
const fm = std.fmt;

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

var mem_registers = [8]i16{0, 0, 0, 0, 0, 0, 0, 0};

pub fn write(register: Register, value: i16) void {
    switch (register) {
        .ax, .bx, .cx, .dx, .sp, .bp, .si, .di => |mem_reg| {
            const idx = @enumToInt(mem_reg) - 8;
            mem_registers[idx] = value;
        },
        else => {
        }
    }
}

pub fn writeFromRegister(destination: Register, source: Register) void {
    const value = read(source);
    return write(destination, value);
}

pub fn read(register: Register) i16 {
    switch (register) {
        .ax, .bx, .cx, .dx, .sp, .bp, .si, .di => |mem_reg| {
            const idx = @enumToInt(mem_reg) - 8;
            return mem_registers[idx];
        },
        else => {
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
        try stdout.print("{s}: {d} (0x{X})\n", 
            .{@tagName(reg), mem_registers[idx], mem_registers[idx]});
    }

    try stdout.print("=================\n", .{});
}
