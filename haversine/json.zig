const std = @import("std");
const expect = std.testing.expect;
const Allocator = std.mem.Allocator;
const AutoHashMap = std.AutoHashMap;
const StringHashMap = std.StringHashMap;
const log = std.log;

const Parser = struct {
    current_position: usize = 0,
    next_position: usize = 0,

    fn parseFloat(self: *Parser, buf: []u8) !f64 {
        while (isNumber(buf[self.next_position])) {
            self.next_position += 1;
            if (self.next_position == buf.len) {
                break;
            }
        }

        const result = std.fmt.parseFloat(f64, buf[self.current_position..self.next_position]); 
        self.current_position = self.next_position;

        return result;
    }

    fn parseString(buf: []u8, offset: usize) []u8 {
        var result: []u8 = undefined;
        _ = offset;
        _ = buf;

        return result;
    }

    fn parseMap(self: *Parser, allocator: Allocator, buf: []u8, offset: usize) !StringHashMap(JsonValue) {
        var map = StringHashMap(JsonValue).init(allocator);
        var key: []u8 = undefined;
        var current_offset = offset;

        for (buf[offset..], 0..) |ch, idx| {
            current_offset = offset + idx;
            if (ch == '"') {
                key = parseString(buf, current_offset);
            }

            if (isNumber(ch)) {
                const number = self.parseFloat(buf) catch 0;
                try map.put("pairs", JsonValue{ .float = number });
            }

            if (ch == '}') {
                return map;
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
    var parser = Parser{};
    var data = "-123998.12".*;
    const data_slice: []u8 = &data;

    const result = try parser.parseFloat(data_slice);
    try expect(result == -123998.12);
}


test "parse map" {
    var allocator = std.testing.allocator;
    var raw_json = "{\"pairs\": 23.987987}".*;
    const json_buf: []u8 = &raw_json;
    var parser = Parser{};
    var json = parser.parseMap(allocator, json_buf, 0) catch undefined;
    defer json.deinit();

    log.warn("{d}", .{json.get("pairs").?.float});

    try expect(json.count() == 1);
    try expect(json.get("pairs").?.float == 23.987987);
}
