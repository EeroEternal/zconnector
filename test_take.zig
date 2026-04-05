const std = @import("std");

pub fn main() !void {
    const reader = std.io.getStdIn().reader();
    @compileLog("has streamUntilDelimiter:", @hasDecl(@TypeOf(reader), "streamUntilDelimiter"));
}
