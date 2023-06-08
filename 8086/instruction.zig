pub const registerEncoding = [2][8][]const u8{
    [_][]const u8{ "al", "cl", "dl", "bl", "ah", "ch", "dh", "bh" },
    [_][]const u8{ "ax", "cx", "dx", "bx", "sp", "bp", "si", "di" },
};

pub const Register = enum {
    AL,
    CL,
    DL,
    BL,
    AH,
    CH,
    DH,
    BH,
    AX,
    CX,
    DX,
    BX,
    SP,
    BP,
    SI,
    DI,
};

pub const Opcode = enum {
    Mov,
};

pub const OperandType = enum {
    Memory,
    Register,
    Data,
    Address,
};

pub const Operand = struct {
    location: OperandType,
    register: ?Register = null,
};

pub const Instruction = struct {
    opcode: Opcode,
    operand1: Operand,
    operand2: ?Operand = null,
    size: u16 = 0,
};
