const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const stdout = std.Io.File.stdout();
    var buffer: [4096]u8 = undefined;
    var writer = stdout.writer(init.io, &buffer);
    
    try writer.interface.print("Hello from Zig 0.16.0 Init with Writer.interface!\n", .{});
    
    if (init.environ_map.get("USER")) |user| {
        try writer.interface.print("User: {s}\n", .{user});
    }
    
    try writer.flush();
}
