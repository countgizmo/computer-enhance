const std = @import("std");
const utils = @import("utils.zig");

// Even though 8086 had 1MB of memory 
// to address it I will need to implement the segment registers.
// I don't want to do that yet so I'm sticking to 64 KB, which
// is addressable by 16 bit registers.
var memory: [64000]u8 = undefined;

pub fn store(address: u16, value: u8) void {
    memory[address] = value;
}

pub fn load(address: u16) u8 {
    return memory[address];
}

pub fn printStatus(start: u16, end: u16) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("\n====== Memory [{d}:{d}] ======= \n", .{start, end});
    var i: usize = start;
    while (i <= end) : (i += 2 ){
        const val = memory[i];
        const val2 = memory[i+1];
        const combined = utils.combineU8(val, val2);
        try stdout.print("[{d}:{d}] {b:0>8} {b:0>8} ({d})\n", .{i, i+1, val, val2, combined});
    }
    try stdout.print("=================\n", .{});
}

pub fn dump() !void {
    const file = try std.fs.cwd().createFile("dump.data", .{});
    defer file.close();

    try file.writeAll(&memory);
}
