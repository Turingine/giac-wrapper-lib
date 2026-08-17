const std = @import("std");
const builtin = @import("builtin");

const process_command: []const []const u8 = &[_][]const u8 { "giac" };
const millisecond = std.time.ns_per_ms;
const wait_time = 40 * millisecond;
const reserve_amount = 1024;
const debug = builtin.mode == .Debug;

const Channels = enum { stdout, stderr };

// subprocess: std.process.Child,
// poller: *std.Io.Poller(Channels),
// stdout: *std.Io.Reader,
// stderr: *std.Io.Reader,
multi_reader_buffer: std.Io.File.MultiReader.Buffer(2),
multi_reader: std.Io.File.MultiReader,
stdout_limit: std.Io.Limit = .limited(65536),
stderr_limit: std.Io.Limit = .limited(65536),

pub fn openInstance(gpa: std.mem.Allocator, io: std.Io) !@This() {
    const child = try std.process.spawn(io, .{
        .argv = &[_][]const u8 { "giac" },
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .pipe,
    });
    errdefer child.kill(io);

    var multi_reader_buffer: std.Io.File.MultiReader.Buffer(2) = undefined;
    var multi_reader: std.Io.File.MultiReader = undefined;
    multi_reader.init(gpa, io, multi_reader_buffer.toStreams(), &.{ child.stdout.?, child.stderr.? });
    errdefer multi_reader.deinit();

    // while (multi_reader.fill(reserve_amount, wait_time)) |_| {
    //     if (options.stdout_limit.toInt()) |limit| {
    //         if (stdout_reader.buffered().len > limit)
    //            return error.StreamTooLong;
    //    }
    //    if (options.stderr_limit.toInt()) |limit| {
    //        if (stderr_reader.buffered().len > limit)
    //            return error.StreamTooLong;
    //    }
    //} else |err| switch (err) {
    //    error.EndOfStream => {},
    //    else => |e| return e,
   // }

   // try multi_reader.checkAnyError();

//    const term = try child.wait(io);

//    const stdout_slice = try multi_reader.toOwnedSlice(0);
 //   errdefer gpa.free(stdout_slice);

//    const stderr_slice = try multi_reader.toOwnedSlice(1);
 //   errdefer gpa.free(stderr_slice);

//    return .{
 //       .stdout = stdout_slice,
 //       .stderr = stderr_slice,
 //       .term = term,
 //   };
    return .{
        .multi_reader = multi_reader,
        .multi_reader_buffer = multi_reader_buffer,
    };
}

const ReadMode = enum {
    // discards from the other stream to free memory
    stdout,
    stderr,
    // Returns a string without specifying the origin stream
    mixed,
    // return a tuple containing the origin stream and the read content
    both,

    // Returns a bool indicating if both channels match
    fn cmp(mode: ReadMode, origin: Channels) bool {
        return switch (mode) {
            .stdout => origin == .stdout,
            .stderr => origin == .stderr,
            else => true,
        };
    }
};

fn ReadReturnType(mode: ReadMode) type {
    return switch (mode) {
        .stdout, .stderr, .mixed => []const u8,
        .both => .{ Channels, []const u8 }, 
    };
}

fn wrapResult(comptime mode: ReadMode, origin: Channels, content: []const u8) ?ReadReturnType(mode) {
    return switch (mode) {
        .stdout, .stderr, .mixed => blk: {
            if (mode.cmp(origin)) {
                break :blk content;
            } else break :blk null;
        },
        .both => .{ origin, content },
    };
} 

// Comportement similaire a run, mais renvoie simplement une seule ligne de la sortie
// avec un timeout predefini
pub fn readLine(self: *@This(), comptime mode: ReadMode) !ReadReturnType(mode) {
    const stdout_reader = self.multi_reader.reader(0);
    const stderr_reader = self.multi_reader.reader(0);
    {
        const stdout: []const u8 = stdout_reader.buffered();
        const stderr: []const u8 = stderr_reader.buffered();

        if (std.mem.indexOfScalar(u8, stdout, '\n')) |index| {
            self.stdout.seek += index + 1;
            if (wrapResult(mode, .stdout, stdout[0..index])) |result| {
                return result;
            } else {}
        }

        if (std.mem.indexOfScalar(u8, stderr, '\n')) |index| {
            self.stderr.seek += index + 1;
            if (wrapResult(mode, .stderr, stderr[0..index])) |result| {
                return result;
            } else {}
        }
    }
    var timer = std.time.Timer.start() catch |err| {
        std.log.err("Couldn't access monotonic timer. Error: {t}\n", .{ err });
        return err;
    };

    while (self.multi_reader.fill(reserve_amount, wait_time)) |_| {
        if (self.stdout_limit.toInt()) |limit| {
            if (stdout_reader.buffered().len > limit)
                return error.StreamTooLong;
        }
        if (self.stderr_limit.toInt()) |limit| {
            if (stderr_reader.buffered().len > limit)
                return error.StreamTooLong;
        }

        const stdout: []const u8 = stdout_reader.buffer[self.stdout.seek..self.stdout.end];
        const stderr: []const u8 = stderr_reader.buffer[self.stderr.seek..self.stderr.end];

        if (std.mem.indexOfScalar(u8, stdout, '\n')) |index| {
            self.stdout.seek += index + 1;
            if (wrapResult(mode, .stdout, stdout[0..index])) |result| {
                return result;
            } else {}
        }

        if (std.mem.indexOfScalar(u8, stderr, '\n')) |index| {
            self.stderr.seek += index + 1;
            if (wrapResult(mode, .stderr, stderr[0..index])) |result| {
                return result;
            } else {}
        }
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => |e| return e,
    }

    return error.Timeout;
}

pub fn skipLines(self: *@This()) void {
    var line_count: if (debug) usize else u0 = 0;
    while (true) {
        _ = self.readLine(.mixed) catch |err| {
            if (debug) std.debug.print("Ended skip with error: {t}\n", .{ err });
            break;
        };
        if (debug) line_count += 1;
    }
    if (debug) std.debug.print("Lines skipped: {d}\n", .{ line_count });
}

pub fn filterResult(return_string: []const u8) bool {
    if (
    std.mem.startsWith(u8, return_string, "// ") or
    std.mem.startsWith(u8, return_string, "Warning")
) return true;

    return
    std.mem.indexOf(u8, return_string, ">> ") != null;
}

// Renvoie le resultat d'une commande fournie en entree
fn run(self: *@This()) ![]const u8 {
    while (true) {
        const line = self.readLine(.stdout) catch break;
        if (filterResult(line)) {
            if (debug) std.debug.print("Skipped line: {s}\n", .{ line });
        } else {
            if (debug) std.debug.print("Read line: {s}\n", .{ line });
            return line;
        }
    }
    return error.NoResult;
}

// The returned memory belongs to the poller, it is not guaranteed to remain valid after further reads
// User should clone if longer lived memory is needed
pub fn runCommand(self: *@This(), command: []const u8) ![]const u8 {
    _ = try self.subprocess.stdin.?.write(command);
    _ = try self.subprocess.stdin.?.write("\n");
    return self.run();
}

// Some expressions are known to badly work with this(ex: evalf(x:=5,4) considers x as a tuple)
pub fn approximate(self: *@This(), expression: []const u8, decimals: usize) ![]const u8 {
    var buffer: [256]u8 = undefined;
    var writer = self.subprocess.stdin.?.writer(&buffer);
    const interface = &writer.interface;
    try interface.print("evalf({s}, {d})\n", .{ expression, decimals });
    try interface.flush();
    return self.run();
}

pub fn closeInstance(self: *@This(), allocator: std.mem.Allocator) !void {
    const code = try self.subprocess.kill();
    self.poller.deinit();

    allocator.destroy(self.poller);

    std.debug.print("Result: {any}\n", .{ code });
}
