const std = @import("std");
const log = std.log;
const printer = @import("printer.zig");
const decoder = @import("decoder.zig");
const cpu = @import("cpu.zig");
const register_store = @import("register_store.zig");
const flags = @import("flags.zig");
const memory = @import("memory.zig");
const estimator = @import("estimator.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer _ = arena.deinit();

    const args = try std.process.argsAlloc(arena.allocator());
    defer std.process.argsFree(arena.allocator(), args);

    var file_name: []u8 = undefined;
    var should_dump = false;
    var show_clocks = false;

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--dump")) {
            should_dump = true;
        } else if (std.mem.eql(u8, arg, "--showClocks")) {
            show_clocks = true;
        } else {
            file_name = arg;
        }
    }

    const file = try std.fs.cwd().openFile(file_name, .{});
    defer file.close();

    var buffer: [1024]u8 = undefined;
    const bytes_read = try file.readAll(&buffer);
    const instructions = try decoder.decode(arena.allocator(), &buffer, bytes_read, 0);

    if (instructions) |insts| {
        try printer.printListing(arena.allocator(), file_name, insts);
        if (show_clocks) {
            try estimator.printClocks(arena.allocator(), insts);
        }
        try cpu.execInstrucitons(insts);
        try register_store.printStatus();
        try register_store.printIP();
        try flags.printStatus();
    }

    if (should_dump) {
        try memory.dump();
    }
}
