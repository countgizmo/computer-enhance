const std = @import("std");
const expect = std.testing.expect;

const registerEncoding = [2][8][]const u8{
    [_][]const u8{ "al", "cl", "dl", "bl", "ah", "ch", "dh", "bh" },
    [_][]const u8{ "ax", "cx", "dx", "bx", "sp", "bp", "si", "di" },
};

fn extractDbit(b: u8) u8 {
    return (b & 0b00000010) >> 1;
}

fn extractWbit(b: u8) u8 {
    return (b & 0b00000001);
}

fn extractReg(w: u8, b: u8) []const u8 {
    const reg = (b & 0b00111000) >> 3;
    return registerEncoding[w][reg];
}

fn extractRM(w: u8, b: u8) []const u8 {
    const rm = (b & 0b00000111);
    return registerEncoding[w][rm];
}

fn decodeBytes(map: std.AutoHashMap(u8, []const u8), byte1: u8, byte2: u8) !void {
    const stdout = std.io.getStdOut().writer();
    const opcode = map.get(byte1 >> 2);
    if (opcode) |v| {
        try stdout.print("{s}", .{v});
    }

    const d_bit = extractDbit(byte1);
    const w_bit = extractWbit(byte1);
    var source: []const u8 = undefined;
    var destination: []const u8 = undefined;

    if (d_bit == 0) {
        source = extractReg(w_bit, byte2);
        destination = extractRM(w_bit, byte2);
    } else if (d_bit == 1) {
        source = extractRM(w_bit, byte2);
        destination = extractReg(w_bit, byte2);
    }

    try stdout.print(" {s}, {s}\n", .{ destination, source });
}

fn printHeader(file_name: []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("; FILE: {s}\n", .{file_name});
    try stdout.print("; bits 16\n\n", .{});
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const file = try std.fs.cwd().openFile(args[1], .{});
    defer file.close();

    try printHeader(args[1]);

    var map = std.AutoHashMap(u8, []const u8).init(allocator);
    defer map.deinit();
    try map.put(0b00100010, "mov");

    var buf: [1024]u8 = undefined;
    const bytes_read = try file.readAll(&buf);
    var i: usize = 0;
    while (i < bytes_read) {
        try decodeBytes(map, buf[i], buf[i + 1]);
        i += 2;
    }
}

test "bytes decoding" {}
