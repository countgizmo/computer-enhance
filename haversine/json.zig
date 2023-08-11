const std = @import("std");
const expect = std.testing.expect;
const Allocator = std.mem.Allocator;
const AutoHashMap = std.AutoHashMap;
const StringHashMap = std.StringHashMap;
const log = std.log;

const Parser = struct {
    const Self = @This();

    next_position: usize = 0,
    allocator: Allocator,

    fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
        };
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

    fn parseString(self: *Self, buf: []u8) []u8 {
        self.next_position += 1; //opening quotes
        const current_position = self.next_position;

        while (buf[self.next_position] != '"') {
            self.next_position += 1;
        }

        const result = buf[current_position..self.next_position];
        self.next_position += 1; //closing quotes
        return result;
    }

    fn parseMap(self: *Self, allocator: Allocator, buf: []u8) !StringHashMap(JsonValue) {
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

pub fn parseFile(allocator: Allocator, file_name: []const u8) !StringHashMap(JsonValue) {
    var map = StringHashMap(JsonValue).init(allocator);
    defer map.deinit();

    const file = try std.fs.cwd().openFile(file_name, .{});
    defer file.close();

    var buffered_reader = std.io.bufferedReader(file.reader());
    var reader = buffered_reader.reader();

    var buffer: [1024]u8 = undefined;
    var read_bytes = try reader.read(&buffer);

    log.warn("Read bytes {d}", .{read_bytes});

    return map;
}


test "parse file" {
    var allocator = std.testing.allocator;
    var file_name = "data/cluster_10.json";
    const json = parseFile(allocator, file_name) catch undefined;
    try expect(json.count() == 0);
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

test "isNumber" {
    try expect(isNumber(':') == false);
    try expect(isNumber('2') == true);
    try expect(isNumber('.') == true);
    try expect(isNumber('-') == true);
}
