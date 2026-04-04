const std = @import("std");
const zconnector = @import("zconnector");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    var arg_it = std.process.Args.Iterator.init(init.minimal.args);
    _ = arg_it.next(); // skip exe name
    const file_path = arg_it.next() orelse {
        const stdout_file = std.Io.File.stdout();
        var buffer: [1024]u8 = undefined;
        var writer = stdout_file.writer(init.io, &buffer);
        try writer.interface.writeAll("usage: zig build file_upload -- <path-to-image>\n");
        try writer.flush();
        return;
    };

    const api_key = init.environ_map.get("OPENAI_API_KEY") orelse return error.MissingApiKey;
    const base_url = init.environ_map.get("OPENAI_BASE_URL") orelse "https://api.openai.com";

    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, file_path, allocator, @enumFromInt(16 * 1024 * 1024));
    defer allocator.free(bytes);

    const encoder = std.base64.standard.Encoder;
    const encoded = try allocator.alloc(u8, encoder.calcSize(bytes.len));
    _ = encoder.encode(encoded, bytes);
    defer allocator.free(encoded);

    var client = try zconnector.LlmClient.openai(allocator, api_key, base_url, init.io);
    defer client.deinit();

    var request = try zconnector.ChatRequest.new(allocator, "gpt-4o-mini");
    defer request.deinit();
    _ = try request.addFile(.user, "input.png", "image/png", encoded);
    _ = try request.addMessage(.user, "Describe the uploaded image in one paragraph.");

    var response = try client.chat(&request, .{ .io = init.io });
    defer response.deinit();

    const stdout_file = std.Io.File.stdout();
    var buffer: [4096]u8 = undefined;
    var writer = stdout_file.writer(init.io, &buffer);
    try writer.interface.print("{s}\n", .{response.content});
    try writer.flush();
}
