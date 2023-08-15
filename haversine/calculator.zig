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
