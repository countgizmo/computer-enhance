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

pub const RegistersNoDisp = [_][2]Register{
    [2]Register{ Register.bx, Register.si },
};

pub const MemoryCalculationNoDisp = union {
    registers: [2]Register,
    direct_address: u16,
};

pub const Opcode = enum {
    mov,
};

pub const OperandType = enum {
    register,
    immediate,
    memory_calculation_no_disp,
};

pub const Operand = union(OperandType) {
    register: Register,
    immediate: i16,
    memory_calculation_no_disp: MemoryCalculationNoDisp,
};

pub const Instruction = struct {
    opcode: Opcode,
    operand1: Operand,
    operand2: ?Operand = null,
    size: u16 = 0,
};
