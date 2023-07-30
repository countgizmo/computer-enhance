const std = @import("std");
const expect = std.testing.expect;
const log = std.log;

// Keeps the low 8 bits, throws away the rest.
pub fn u16ToU8(value: u16) u8 {
    return @as(u8, @intCast(value & 0b11111111));
}

const LoHiBytes = struct{u8, u8};

// Splits u16 into two u8 parts: lo and hi.
// Lo - first 8 bits
// Hi - second 8 bits
// Returns a tubple.
pub fn splitU16(value: u16) LoHiBytes {
    const low_part = @as(u8, @intCast(value & 0b11111111));
    const hi_part = @as(u8, @intCast(value >> 8));

    return .{low_part, hi_part};
}

pub fn combineU8(lo: u8, hi: u8) u16 {
    return (@as(u16, @intCast(hi)) * 256) + lo;
}

test "combine two u8" {
    var lo: u8 = 0b0000_0001;
    var hi: u8 = 0b0000_0000;
    var combined = combineU8(lo, hi);

    try expect(combined == 0b0000_0000_0000_0001);
}
