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
    byte: i8,
    word: i16,
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
    .{ .register1 = .bp, .register2 = .di, },
    .{ .register1 = .si, },
    .{ .register1 = .di, },
    .{ .register1 = .bp, },
    .{ .register1 = .bx, },
};

pub const Opcode = enum {
    mov,
    add,
    sub,
    cmp,
    arithmetic,
    je,
    jl,
    jle,
    jb,
    jbe,
    jp,
    jo,
    js,
    jne,
    jnl,
    jnle,
    jnb,
    jnbe,
    jnp,
    jno,
    jns,
    loop,
    loopz,
    loopnz,
    jcxz,
};

pub const DataSize = enum {
    byte,
    word,
};

const Immediate = struct {
    value: i16,
    size: ?DataSize = null,
};

pub const Operand = union(enum) {
    register: Register,
    immediate: Immediate,
    mem_calc_no_disp: MemCalcNoDisp,
    mem_calc_with_disp: MemCalc,
    direct_address: u16,
    signed_inc_to_inst: i8,
};

pub const Instruction = struct {
    opcode: Opcode,
    operand1: Operand,
    operand2: ?Operand = null,
    size: u16 = 0,
};
