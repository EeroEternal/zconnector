const std = @import("std");

pub fn main() !void {
    var buffer: [10]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    const reader = stream.reader();
    @compileLog(@TypeOf(reader));
}
