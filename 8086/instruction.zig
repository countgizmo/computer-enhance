const Register = @import("register_store.zig").Register;

const Displacement = union(enum) {
    byte: i8,
    word: i16,
};

// TODO(evgheni): separate calculations with disp and without disp
// The MemCalc is a bit too generic at the moment and is used in
// MemCalcNoDisp, which is kinda weird, cause it might have a disp.
// MemCalcNoDisp can only have direct address or a calculation with two registers.
// MemCalc without displacement on the other hand cannot have dict address,
// always have a displacement and sometimes have a second register.
pub const MemCalc = struct {
    register1: Register,
    register2: ?Register = null,
    disp: ?Displacement = null,
};

pub const MemCalcNoDisp = union(enum) {
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
    mem_calc_with_disp: MemCalc,
    direct_address: u16,
    signed_inc_to_ip: i8,
};

pub const Instruction = struct {
    opcode: Opcode,
    operand1: Operand,
    operand2: ?Operand = null,
    size: u16 = 0,
};
