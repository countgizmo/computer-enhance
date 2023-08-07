const std = @import("std");
const math = std.math;
const expect = std.testing.expect;
const fmt = std.fmt;
const log = std.log;
const Allocator = std.mem.Allocator;
const Random = std.rand.Random;
const haversine_formula = @import("haversine_formula.zig");

const GeneratorError = error {
    InvalidNumberOfArgs,
    InvalidMethod,
};

const Coordinates = struct {
    x: f64,
    y: f64,
};

const Quadrant = struct {
    center: Coordinates,
    width: u16,
    height: u16,

    pub fn getStartX(self: Quadrant) i16 {
        return @as(i16, @intFromFloat(self.center.x)) - @as(i16, @bitCast(self.width / 2));
    }

    pub fn getStartY(self: Quadrant) i16 {
        return @as(i16, @intFromFloat(self.center.y)) - @as(i16, @bitCast(self.height / 2));
    }

    pub fn getEndX(self: Quadrant) i16 {
        return @as(i16, @intFromFloat(self.center.x)) + @as(i16, @bitCast(self.width / 2));
    }

    pub fn getEndY(self: Quadrant) i16 {
        return @as(i16, @intFromFloat(self.center.y)) + @as(i16, @bitCast(self.height / 2));
    }
};

const Method = enum {
    uniform,
    cluster,
};

const Args = struct {
    file_name: []u8 = undefined,
    method: Method = undefined,
    pairs: u64 = 0,
    seed: u64 = 0,
};

fn usage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Usage: zig run input_generator -- --method cluster/uniform --pairs <number> --file <file name> --seed <number>\n", .{});
}

fn methodFromString(method_str: []u8) !Method {
    if (std.mem.eql(u8, method_str, "uniform")) {
        return .uniform;
    } else if (std.mem.eql(u8, method_str, "cluster")) {
        return .cluster;
    }

    return error.InvalidMethod;
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
            result.method = try methodFromString(raw_args[i]);
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

    return temp + @as(f64, @floatFromInt(random.intRangeAtMost(i16, lo+1, hi-1)));
}

fn generateCoordinateUniform(random: Random) Coordinates {
    var coords = Coordinates {
        .x = generateRandomInRange(random, -180, 180),
        .y = generateRandomInRange(random, -90, 90),
    };
    return coords;
}

fn generateQuadrants(random: Random, comptime n: u16, x_start: i16, y_start: i16, x_end: i16, y_end: i16) [n]Quadrant {
    var quadrants: [n]Quadrant = undefined;
    const width: u16 = @as(u16, @intCast(@divFloor((x_end - x_start), n)));
    const height: u16 = @as(u16, @intCast(@divFloor((y_end - y_start), n)));
    var i: usize = 0;

    const half_width = @as(i16, @bitCast(width/2));
    const half_height = @as(i16, @bitCast(height/2));

    while (i < n) : (i += 1) {
        quadrants[i] = .{
            .center = .{
                .x = generateRandomInRange(random, x_start + half_width, x_end - half_width),
                .y = generateRandomInRange(random, y_start + half_height, y_end - half_height),
            },
            .width = width,
            .height = height,
        };
    }

    return quadrants;
}

fn generateCoordinateFromQuadrants(random: Random, quadrants: []Quadrant) Coordinates {
    const index = random.intRangeAtMost(usize, 0, 3);
    const quadrant = quadrants[index];
    const x_start = quadrant.getStartX();
    const y_start = quadrant.getStartY();
    const x_end = quadrant.getEndX();
    const y_end = quadrant.getEndY();

    var coords = Coordinates {
        .x = generateRandomInRange(random, x_start, x_end),
        .y = generateRandomInRange(random, y_start, y_end),
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

    log.debug("args: \nmethod: {any}\npairs: {d}\nfile: {s}\nseed: {d}", .{args.method, args.pairs, args.file_name, args.seed});

    const file = try std.fs.cwd().createFile(args.file_name, .{});
    defer file.close();

    var b_writer = std.io.bufferedWriter(file.writer());
    var writer = b_writer.writer();
    _ = try writer.write("{\"pairs\":[\n");

    var prng = std.rand.DefaultPrng.init(args.seed);
    const random = prng.random();

    var sum: f64 = 0;
    var i: usize = 0;
    var quadrants = generateQuadrants(random, 4, -180, -90, 180, 90);

    while (i < args.pairs) : (i += 1) {
        const last_pair = (i == args.pairs - 1);
        const coords0 = switch (args.method) {
            .uniform => generateCoordinateUniform(random),
            .cluster => generateCoordinateFromQuadrants(random, &quadrants),
        };
        const coords1 = switch (args.method) {
            .uniform => generateCoordinateUniform(random),
            .cluster => generateCoordinateFromQuadrants(random, &quadrants),
        };
        const separator = if (last_pair) "\n" else ",\n";

        const h = haversine_formula.referenceHaversine(coords0.x, coords0.y, coords1.x, coords1.y, 6372.8);
        sum += h;

        var buf: [128]u8 = undefined;
        var line = try std.fmt.bufPrint(
                &buf,
                "\t{{\"x0\":{d}, \"y0\":{d}, \"x1\":{d}, \"y1\":{d}}}{s}", 
                .{ coords0.x, coords0.y, coords1.x, coords1.y, separator });
        _ = try writer.write(line);
    }

    _ = try b_writer.write("]}");
    try b_writer.flush();

    const avg = sum / @as(f64, @floatFromInt(args.pairs));
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Avg Haversine: {d}\n", .{avg});
}

test "generating random quadrants" {
    var prng = std.rand.DefaultPrng.init(12345);
    const random = prng.random();
    const quadrants = generateQuadrants(random, 4, -180, -90, 180, 90);

    try expect(quadrants.len == 4);

    for (quadrants) |quadrant| {
        try expect(quadrant.width == 90);
        try expect(quadrant.height == 45);
        try expect(quadrant.center.x < 180 and quadrant.center.x > -180 and
                   quadrant.center.y < 90 and quadrant.center.y > -90);
    }
}

test "quadrant calculations" {
    var quadrant = Quadrant{
        .center = .{
            .x = -10.0,
            .y = 45.0,
        },
        .width = 90,
        .height = 45,
    };

    try expect(quadrant.getStartX() == -55);
    try expect(quadrant.getStartY() == 23);

    try expect(quadrant.getEndX() == 35);
    try expect(quadrant.getEndY() == 67);
}

test "generate from quadrants" {
    var prng = std.rand.DefaultPrng.init(12345);
    const random = prng.random();
    var quadrants = generateQuadrants(random, 4, -180, -90, 180, 90);
    const result = generateCoordinateFromQuadrants(random, &quadrants);

    try expect(result.x >= -180);
    try expect(result.x <= 180);
    try expect(result.y >= -90);
    try expect(result.y <= 90);
}
