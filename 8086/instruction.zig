pub const registerEncoding = [2][8][]const u8{
    [_][]const u8{ "al", "cl", "dl", "bl", "ah", "ch", "dh", "bh" },
    [_][]const u8{ "ax", "cx", "dx", "bx", "sp", "bp", "si", "di" },
};

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


const Displacement = union(enum) {
    byte: u8,
    word: u16,
};

pub const MemCalc = struct {
    register1: Register,
    register2: ?Register = null,
    disp: ?Displacement = null,
};

pub const MemCalcNoDisp = union {
    mem_calc: MemCalc,
    direct_address: u16,
};

pub const MemCalcTable = [_]MemCalc {
    .{ .register1 = .bx, .register2 = .si, },
    .{ .register1 = .bx, .register2 = .di, },
    .{ .register1 = .bp, .register2 = .si, },
    .{ .register1 = .bp, .register2 = .si, },
    .{ .register1 = .si, },
    .{ .register1 = .di, },
    .{ .register1 = .bp, },
    .{ .register1 = .bx, },
};

pub const Opcode = enum {
    mov,
};

pub const OperandType = enum {
    register,
    immediate,
    mem_calc_no_disp,
    mem_calc_with_disp,
};

pub const Operand = union(OperandType) {
    register: Register,
    immediate: i16,
    mem_calc_no_disp: MemCalcNoDisp,
    mem_calc_with_disp: MemCalc,
};

pub const Instruction = struct {
    opcode: Opcode,
    operand1: Operand,
    operand2: ?Operand = null,
    size: u16 = 0,
};
