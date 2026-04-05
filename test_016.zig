const std = @import("std");

pub fn main() void {
    const has_init = @hasDecl(std.process, "Init");
    const has_reader = @hasDecl(std.http.Client.Response, "reader");
    std.debug.print("std.process.Init: {}\n", .{has_init});
    std.debug.print("std.http.Client.Response.reader: {}\n", .{has_reader});
}
