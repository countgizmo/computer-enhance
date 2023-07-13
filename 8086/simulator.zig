const std = @import("std");
const log = std.log;
const printer = @import("printer.zig");
const decoder = @import("decoder.zig");
const cpu = @import("cpu.zig");
const register_store = @import("register_store.zig");
const flags = @import("flags.zig");
const memory = @import("memory.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer _ = arena.deinit();

    const args = try std.process.argsAlloc(arena.allocator());
    defer std.process.argsFree(arena.allocator(), args);

    const file = try std.fs.cwd().openFile(args[1], .{});
    defer file.close();

    const file_name = args[1];

    var buffer: [1024]u8 = undefined;
    const bytes_read = try file.readAll(&buffer);
    const instructions = try decoder.decode(arena.allocator(), &buffer, bytes_read, 0);

    if (instructions) |insts| {
        try printer.printListing(arena.allocator(), file_name, insts);
        try cpu.execInstrucitons(insts);
        try register_store.printStatus();
        try register_store.printIP();
        try flags.printStatus();
        try memory.printStatus(1000, 1008);
    }
}
