const std = @import("std");
const giac_wrapper_lib = @import("giac_wrapper_lib");

const commands = &[_][]const u8{
    "3 + 7 / 2",
    "sin(1/x)",
    "sin(1/5)",
    "cos(x)*sin(x)",
    "cos(5)*sin(5)",
    "x",
};

pub fn main(init: std.process.Init) !void {
    var child = try giac_wrapper_lib.Process.openInstance(init.gpa, init.io);
    child.skipLines();

    _ = child.runCommand("x := 5") catch {};

    for (commands) |command| {
        const line = child.approximate(command, 4);
        std.debug.print("Command: {s}\nResult: {!s}\n", .{ command, line });
    }

    try child.closeInstance(init.gpa);
}
