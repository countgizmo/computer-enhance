const std = @import("std");
const log = std.log;
const printer = @import("printer.zig");
const decoder = @import("decoder.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer _ = arena.deinit();

    const args = try std.process.argsAlloc(arena.allocator());
    defer std.process.argsFree(arena.allocator(), args);

    const file = try std.fs.cwd().openFile(args[1], .{});
    defer file.close();

    try printer.printHeader(args[1]);

    var buffer: [1024]u8 = undefined;
    const bytes_read = try file.readAll(&buffer);
    const instructions = try decoder.decode(arena.allocator(), &buffer, bytes_read, 0);

    if (instructions) |insts| {
        for (insts) |inst| {
            try printer.printInstruction(inst);
        }
    }
}
