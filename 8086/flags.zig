pub const Flag = enum {
    zf,
    sf,
};

var flags = [_]u2{0,0};

pub fn setFlag(flag: Flag, value: u2) void {
    flags[@enumToInt(flag)] = value;
}

pub fn getFlag(flag: Flag) u2 {
    return flags[@enumToInt(flag)];
}
