const std = @import("std");
const giac_wrapper_lib = @import("giac_wrapper_lib");

const commands = &[_][]const u8 {
    "x:=5",
    "3 + 7 / 2",
    "sin(1/x)",
    "sin(1/5)",
    "cos(x)*sin(x)",
    "cos(5)*sin(5)",
};

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();

    var child = try giac_wrapper_lib.Process.openInstance(allocator);
    child.skipLines();

    for (commands) |command| {
        const line = try child.approximate(command, 4);
        std.debug.print("Command: {s}\nResult: {s}\n", .{ command, line });
    }
    
    try child.closeInstance(allocator);
}
