const std = @import("std");

pub fn main() !void {
    const reader = std.io.getStdIn().reader();
    @compileLog(@TypeOf(reader));
}
