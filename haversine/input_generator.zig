const std = @import("std");
const log = std.log;

const GeneratorError = error {
    InvalidNumberOfArgs,
};

const Args = struct {
    file_name: []u8 = undefined,
    method: []u8 = undefined,
    pairs: []u8 = undefined,
};

fn usage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Usage: zig run input_generator -- --method cluster/uniform --pairs <number> --file <file name>\n", .{});
}

fn parseArgs(raw_args: [][:0]u8) !Args {
    if (raw_args.len != 7) {
        return error.InvalidNumberOfArgs;
    }

    var result = Args{};
    var i: usize = 0;

    while (i < raw_args.len) : (i += 1) {
        if (std.mem.eql(u8, raw_args[i], "--method")) {
            i += 1;
            result.method = raw_args[i];
        } else if (std.mem.eql(u8, raw_args[i], "--pairs")) {
            i += 1;
            result.pairs = raw_args[i];
        } else if (std.mem.eql(u8, raw_args[i], "--file")) {
            i += 1;
            result.file_name = raw_args[i];
        }
    }

    return result;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer _ = arena.deinit();

    const raw_args = try std.process.argsAlloc(arena.allocator());
    defer std.process.argsFree(arena.allocator(), raw_args);

    const args = parseArgs(raw_args) catch {
        try usage();
        return;
    };

    const file = try std.fs.cwd().createFile(args.file_name, .{});
    defer file.close();

    const written = try file.write("{\"pairs\":");
    log.debug("wrote {d} bytes", .{written});
    log.debug("args: \nmethod: {s}\npairs: {s}\nfile: {s}", .{args.method, args.pairs, args.file_name});
}
