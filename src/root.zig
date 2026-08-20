const std = @import("std");
const builtin = @import("builtin");

extern fn caseval(input: [*:0]const u8) [*:0]const u8;

pub fn evalZ(gpa: std.mem.Allocator, expression: [:0]const u8) ![]const u8 {
    const result = caseval(expression);
    return gpa.dupe(u8, std.mem.span(result));
}

pub fn eval(gpa: std.mem.Allocator, expression: []const u8) ![]const u8 {
    const in = try gpa.dupeSentinel(u8, expression, 0);
    defer gpa.free(in);
    return evalZ(gpa, in);
}
