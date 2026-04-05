const std = @import("std");

pub fn main() !void {
    var fs = std.io.fixedBufferStream("hello\nworld\n");
    const reader = fs.reader();
    @compileLog("Reader has readUntilDelimiterOrEof:", @hasDecl(@TypeOf(reader), "readUntilDelimiterOrEof"));
}
