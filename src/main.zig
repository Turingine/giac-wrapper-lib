const std = @import("std");
const giac_wrapper_lib = @import("giac_wrapper");

const commands = &[_][]const u8{
    "3 + 7 / 2",
    "sin(1/x)",
    "sin(1/5)",
    "cos(x)*sin(x)",
    "cos(5)*sin(5)",
    "x",
};

pub fn main(init: std.process.Init) !void {
    for (commands) |command| {
        const result = giac_wrapper_lib.eval(init.gpa, command) catch |err| {
            std.debug.print("Command: {s} failed with: {t}\n", .{ command, err });
            continue;
        };
        defer init.gpa.free(result);
        std.debug.print("Command: {s}\nResult: {s}\n", .{ command, result });
    }
}
