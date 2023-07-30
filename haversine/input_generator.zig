const std = @import("std");
const fmt = std.fmt;
const log = std.log;
const Allocator = std.mem.Allocator;
const Random = std.rand.Random;

const GeneratorError = error {
    InvalidNumberOfArgs,
};

const Coordinates = struct {
    x: f64,
    y: f64,
};

const Args = struct {
    file_name: []u8 = undefined,
    method: []u8 = undefined,
    pairs: u64 = 0,
    seed: u64 = 0,
};

fn usage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Usage: zig run input_generator -- --method cluster/uniform --pairs <number> --file <file name> --seed <number>\n", .{});
}

fn parseArgs(raw_args: [][:0]u8) !Args {
    if (raw_args.len != 9) {
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
            result.pairs = try std.fmt.parseInt(u64, raw_args[i], 10);
        } else if (std.mem.eql(u8, raw_args[i], "--file")) {
            i += 1;
            result.file_name = raw_args[i];
        } else if (std.mem.eql(u8, raw_args[i], "--seed")) {
            i += 1;
            result.seed = try std.fmt.parseInt(u64, raw_args[i], 10);
        }
    }

    return result;
}

fn generateRandomInRange(random: Random, lo: i16, hi: i16) f64 {
    var temp: f64 = random.float(f64);

    return temp + @as(f64, @floatFromInt(random.intRangeAtMost(i16, lo, hi)));
}

fn generateCoordinateUniform(random: Random) Coordinates {
    var coords = Coordinates {
        .x = generateRandomInRange(random, -180, 180),
        .y = generateRandomInRange(random, -90, 90),
    };
    return coords;
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

    log.debug("args: \nmethod: {s}\npairs: {d}\nfile: {s}\nseed: {d}", .{args.method, args.pairs, args.file_name, args.seed});

    const file = try std.fs.cwd().createFile(args.file_name, .{});
    defer file.close();

    var b_writer = std.io.bufferedWriter(file.writer());
    var writer = b_writer.writer();
    _ = try writer.write("{\"pairs\":[\n");

    var prng = std.rand.DefaultPrng.init(args.seed);
    const random = prng.random();

    var i: usize = 0;
    while (i < args.pairs) : (i += 1) {
        const last_pair = (i == args.pairs - 1);
        const coords0 = generateCoordinateUniform(random);
        const coords1 = generateCoordinateUniform(random);
        const separator = if (last_pair) "\n" else ",\n";

        var buf: [128]u8 = undefined;
        _ = try std.fmt.bufPrint(
                &buf,
                "\t{{\"x0\":{d}, \"y0\":{d}, \"x1\":{d}, \"y1\":{d}}}{s}", 
                .{ coords0.x, coords0.y, coords1.x, coords1.y, separator });
        _ = try writer.write(&buf);
    }

    _ = try b_writer.write("]}");
    try b_writer.flush();
}

test "saving and reading binary file" {
    const file = try std.fs.cwd().createFile("test.bin", .{});
    defer file.close();
    file.write(@as([]u8, 10.1));

}
