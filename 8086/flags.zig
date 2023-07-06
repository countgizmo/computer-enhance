const std = @import("std");

pub const Flag = enum {
    zf,
    sf,
};

var flags = [_]u2{0,0};

pub fn resetFlags() void {
    flags = [_]u2{0} ** flags.len;
}

pub fn setFlag(flag: Flag, value: u2) void {
    flags[@enumToInt(flag)] = value;
}

pub fn getFlag(flag: Flag) u2 {
    return flags[@enumToInt(flag)];
}

pub fn printStatus() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("\n=== FLAGS ===\n", .{});

    const display_flags = [_]Flag{.zf, .sf};
    for (display_flags) |flag| {
        try stdout.print("{s}: {d}\n",
            .{@tagName(flag), flags[@enumToInt(flag)]});
    }

    try stdout.print("=================\n", .{});
}
