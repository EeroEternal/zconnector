const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    // Just check the methods on Response
    const Response = std.http.Client.Response;
    const has_reader = @hasDecl(Response, "reader");
    const has_take_delimiter = if (has_reader) blk: {
        // We can't easily get a real reader without a real connection, 
        // but we can check the return type of reader() if possible, 
        // or just check if std.io.AnyReader has takeDelimiter.
        break :blk @hasDecl(std.io.AnyReader, "takeDelimiter");
    } else false;

    std.debug.print("Response.reader: {}\n", .{has_reader});
    std.debug.print("AnyReader.takeDelimiter: {}\n", .{has_take_delimiter});
}
