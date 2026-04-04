const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const stdout = std.Io.File.stdout();
    var buffer: [4096]u8 = undefined;
    const writer = stdout.writer(init.io, &buffer);
    
    try writer.print("Hello from Zig 0.16.0 Init with Writer!\n", .{});
    
    if (init.environ_map.get("USER")) |user| {
        try writer.print("User: {s}\n", .{user});
    }
    
    var it = init.minimal.args.iterator();
    _ = it.next(); // skip exe name
    while (it.next()) |arg| {
        try writer.print("Arg: {s}\n", .{arg});
    }
}
