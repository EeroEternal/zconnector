const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const stdout = init.io.getStdOut() catch null;
    
    if (stdout) |out| {
        const writer = out.writer();
        try writer.print("Hello from Zig 0.16.0 Init!\n", .{});
        
        if (init.environ_map.get("USER")) |user| {
            try writer.print("User: {s}\n", .{user});
        }
        
        var it = init.minimal.args.iterator();
        _ = it.next(); // skip exe name
        while (it.next()) |arg| {
            try writer.print("Arg: {s}\n", .{arg});
        }
    } else {
        std.debug.print("No stdout available\n", .{});
    }
}
