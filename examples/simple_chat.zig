const std = @import("std");
const zconnector = @import("zconnector");

pub fn main() !void {
    const io = std.Io.get();
    const init = try std.process.init(io);
    defer init.deinit();
    const allocator = init.gpa;
    const api_key = init.environ_map.get("OPENAI_API_KEY") orelse return error.MissingApiKey;
    const base_url = init.environ_map.get("OPENAI_BASE_URL") orelse "https://api.openai.com";

    var client = try zconnector.LlmClient.openai(allocator, api_key, base_url, io);
    defer client.deinit();

    var request = try zconnector.ChatRequest.new(allocator, "gpt-4o-mini");
    defer request.deinit();

    _ = try request.addMessage(.user, "Give me a one-line introduction to Zig.");

    var response = try client.chat(&request, .{ .io = io });
    defer response.deinit();

    const stdout = std.Io.File.stdout();
    var buffer: [4096]u8 = undefined;
    var writer = stdout.writer(io, &buffer);

    try writer.interface.print("{s}\n", .{response.content});
    try writer.flush();
}
