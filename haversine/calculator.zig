const std = @import("std");
const mem = std.mem;


pub const Coordinates = struct {
    x: f64,
    y: f64,
};

pub const CoordPair = struct {
    const Self = @This();
    coord1: Coordinates,
    coord2: Coordinates,

    pub fn init(x0: f64, y0: f64, x1: f64, y1: f64) Self {
        return .{
            .coord1 = .{
                .x = x0,
                .y = y0,
            },
            .coord2 = .{
                .x = x1,
                .y = y1,
            },
        };
    }
};

test "save coordinates to binary" {
    const file = try std.fs.cwd().createFile("test.bin", .{});
    defer file.close();

    const pair = CoordPair.init(10, 20, 30, 40);

    try file.writeAll(&mem.toBytes(pair));

    const file_r = try std.fs.cwd().openFile("test.bin", .{});
    defer file_r.close();

    var buffer: [1024]u8 = undefined;
    const read_bytes = try file_r.readAll(&buffer);

    var meaningful_bytes: [32]u8 = undefined;
    mem.copy(u8, &meaningful_bytes, buffer[0..read_bytes]);

    const pair_r = mem.bytesAsValue(CoordPair, &meaningful_bytes);
    std.log.warn("{d} - {any}", .{read_bytes, pair_r});
}
