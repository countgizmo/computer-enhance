// Keeps the low 8 bits, throws away the rest.
pub fn u16ToU8(value: u16) u8 {
    return @intCast(u8, value & 0b11111111);
}

const LoHiBytes = struct{u8, u8};

// Splits u16 into two u8 parts: lo and hi.
// Lo - first 8 bits
// Hi - second 8 bits
// Returns a tubple.
pub fn splitU16(value: u16) LoHiBytes {
    const low_part = @intCast(u8, value & 0b11111111);
    const hi_part = @intCast(u8, value >> 8);

    return .{low_part, hi_part};
}
