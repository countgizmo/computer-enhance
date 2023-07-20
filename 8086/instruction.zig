const Register = @import("register_store.zig").Register;

const Displacement = union(enum) {
    byte: i8,
    word: i16,
};

pub const MemCalcWithDisp = struct {
    register1: Register,
    register2: ?Register = null,
    disp: Displacement,
};

pub const MemCalcNoDisp = struct {
    register1: Register,
    register2: ?Register = null,
};

pub const MemCalcTable = [_]MemCalcNoDisp {
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
    jnz,
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
    value: u16,
    size: ?DataSize = null,
};

pub const Operand = union(enum) {
    register: Register,
    immediate: Immediate,
    mem_calc_no_disp: MemCalcNoDisp,
    mem_calc_with_disp: MemCalcWithDisp,
    direct_address: u16,
    signed_inc_to_ip: i8,
};

pub const Instruction = struct {
    opcode: Opcode,
    operand1: Operand,
    operand2: ?Operand = null,
    size: u16 = 0,
};
