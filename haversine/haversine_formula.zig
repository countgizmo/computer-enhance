const std = @import("std");
const expect = std.testing.expect;
const math = std.math;

pub const earth_radius_reference = 6371000;

fn square(n: f64) f64 {
    return n * n;
}

fn radiansFromDegrees(degrees: f64) f64 {
    return 0.01745329251994329577 * degrees;
}

pub fn referenceHaversine(x0: f64, y0: f64, x1: f64, y1: f64, earth_radius: f64) f64 {
    const lat1 = y0;
    const lat2 = y1;
    const d_lat = radiansFromDegrees(lat2 - lat1);

    const lon1 = x0;
    const lon2 = x1;
    const d_lon = radiansFromDegrees(lon2 - lon1);

    const lat1_radians = radiansFromDegrees(lat1);
    const lat2_radians = radiansFromDegrees(lat2);

    const a = square(math.sin(d_lat/2.0)) + math.cos(lat1_radians)*math.cos(lat2_radians)*square(math.sin(d_lon/2));
    const c = 2.0*math.asin(math.sqrt(a));

    return earth_radius * c;
}

test "Haversine calculation" {
    const result = referenceHaversine(-0.116773, 51.510357, -77.009003, 38.889931, earth_radius_reference);
    const tolerance = 0.001;
    var diff = math.fabs(result - 5897658.289);

    try expect(diff < tolerance);
    try expect(@round(result) == 5897658);
}
