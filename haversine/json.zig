const std = @import("std");
const expect = std.testing.expect;
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;
const ArrayList = std.ArrayList;
const log = std.log;
const haversine_formula = @import("haversine_formula.zig");
const calculator = @import("calculator.zig");
const Coordinates = calculator.Coordinates;
const CoordPair = calculator.CoordPair;

const Result = struct {
    const Self = @This();
    pairs: ArrayList(CoordPair),
    sum: f64 = 0,
    pub fn avgHaversine(self: Self) f64 {
        return self.sum / @as(f64, @floatFromInt(self.pairs.items.len));
    }

    pub fn deinit(self: Self) void {
        self.pairs.deinit();
    }
};

const Parser = struct {
    const Self = @This();

    next_position: usize = 0,
    allocator: Allocator,

    fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    pub fn reset(self: *Self) void {
        self.next_position = 0;
    }


    pub fn parseFloat(self: *Self, buf: []u8) !f64 {
        const current_position = self.next_position;
        var ch = buf[self.next_position];
        while (self.next_position < buf.len and isNumber(ch)) {
            self.next_position += 1;
            ch = buf[self.next_position];
        }

        return std.fmt.parseFloat(f64, buf[current_position..self.next_position]); 
    }

    pub fn parseString(self: *Self, buf: []u8) []u8 {
        self.next_position += 1; //opening quotes
        const current_position = self.next_position;

        while (buf[self.next_position] != '"') {
            self.next_position += 1;
        }

        const result = buf[current_position..self.next_position];
        self.next_position += 1; //closing quotes
        return result;
    }

    // NOTE(evgheni): This is very task specific.
    // I know that the keys are strings and that the values are not strings (numbers).
    // So if there's a quote it means a key is starting.
    // This is not a generic JSON parser (just a reminder).
    pub fn parseMap(self: *Self, allocator: Allocator, buf: []u8) !StringHashMap(JsonValue) {
        var map = StringHashMap(JsonValue).init(allocator);
        var key: []u8 = undefined;
        var ch: u8 = undefined;

        while (self.next_position < buf.len) {
            ch = buf[self.next_position];
            if (ch == '{' or ch == ':' or std.ascii.isWhitespace(ch)) {
                self.next_position += 1;
                continue;
            }

            if (ch == '"') {
                key = self.parseString(buf);
            }

            if (ch == '}') {
                self.next_position += 1;
                return map;
            }

            if (ch == ',') {
                self.next_position += 1;
            }

            if (isNumber(ch)) {
                const number = self.parseFloat(buf) catch 0;
                try map.put(key, JsonValue{ .float = number });
            }
        }

        return JsonParseError.MapNotClosed;
    }
};

const JsonParseError = error {
    MapNotClosed,
};

const JsonValue = union(enum) {
    float: f64,
    map: StringHashMap(JsonValue),
};

fn isNumber(ch: u8) bool {
    return (ch == '-') or 
           (ch == '.') or
           (ch >= '0' and ch <= '9');
}

pub fn parseFile(allocator: Allocator, file_name: []const u8) !Result {
    var result = Result {
        .pairs = ArrayList(CoordPair).init(allocator),
    };
    const file = try std.fs.cwd().openFile(file_name, .{});
    defer file.close();

    var buffered_reader = std.io.bufferedReader(file.reader());
    var reader = buffered_reader.reader();

    var output: [1024]u8 = undefined;
    var output_fbs = std.io.fixedBufferStream(&output);
    const writer = output_fbs.writer();
    var parser = Parser.init(allocator);
    var json: StringHashMap(JsonValue) = undefined;

    while(reader.streamUntilDelimiter(writer, '\n', null)) {
        var b = output_fbs.getWritten();
        output_fbs.reset();
        if (std.mem.startsWith(u8, b, "{\"pairs\"")) {
            continue;
        }
        json = parser.parseMap(allocator, b) catch |err| {
            log.err("Coudn't parse JSON map: {any}\n", .{err});
            return err;
        };

        const pair = CoordPair.init(
            json.get("x0").?.float,
            json.get("y0").?.float,
            json.get("x1").?.float,
            json.get("y1").?.float);
        try result.pairs.append(pair);

        const h = haversine_formula.referenceHaversine(
            pair.coord1.x,
            pair.coord1.y,
            pair.coord2.x,
            pair.coord2.y, 
            haversine_formula.earth_radius_reference);

        result.sum += h;

        defer json.deinit();
        parser.reset();
    } else |err| {
        if (err != error.EndOfStream) {
            log.err("Unexpected error while parsing file: {any}\n", .{err});
        }
    }

    return result;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer _ = arena.deinit();
}



test "parse file" {
    var allocator = std.testing.allocator;
    var file_name = "data/cluster_10.json";
    var result = parseFile(allocator, file_name) catch undefined;
    defer result.deinit();
    log.warn("Avg Haversine: {d}", .{result.avgHaversine()});
}

test "parse float" {
    var allocator = std.testing.allocator;
    var parser = Parser.init(allocator);
    var data = "-123998.12;".*;
    const data_slice: []u8 = &data;

    const result = try parser.parseFloat(data_slice);
    try expect(result == -123998.12);
}

test "parse string" {
    var allocator = std.testing.allocator;
    var parser = Parser.init(allocator);
    var data = "\"potato\"".*;
    const data_slice: []u8 = &data;

    const result = parser.parseString(data_slice);
    try expect(std.mem.eql(u8, result, "potato"));
}

test "parse map" {
    var allocator = std.testing.allocator;
    var raw_json = "{\"x0\": 23.987987}".*;
    const json_buf: []u8 = &raw_json;
    var parser = Parser.init(allocator);
    var json = parser.parseMap(allocator, json_buf) catch undefined;
    defer json.deinit();

    try expect(json.count() == 1);
    try expect(json.get("x0").?.float == 23.987987);
}

test "parse coordinates" {
    var allocator = std.testing.allocator;
    var raw_json = "{\"x0\":-51.01558393732917, \"y0\":62.22122012449795, \"x1\":-0.09528121685555413, \"y1\":3.2393642490821737},".*;
    const json_buf: []u8 = &raw_json;
    var parser = Parser.init(allocator);
    var json = parser.parseMap(allocator, json_buf) catch undefined;
    defer json.deinit();

    try expect(json.count() == 4);
    try expect(json.get("x0").?.float == -51.01558393732917);
    try expect(json.get("y0").?.float == 62.22122012449795);
    try expect(json.get("x1").?.float == -0.09528121685555413);
    try expect(json.get("y1").?.float == 3.2393642490821737);
}

test "isNumber" {
    try expect(isNumber(':') == false);
    try expect(isNumber('2') == true);
    try expect(isNumber('.') == true);
    try expect(isNumber('-') == true);
}
