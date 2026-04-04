const std = @import("std");
const zconnector = @import("zconnector");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const api_key = std.posix.getenv("OPENAI_API_KEY") orelse return error.MissingApiKey;
    const base_url = std.posix.getenv("OPENAI_BASE_URL") orelse "https://api.openai.com";

    var client = try zconnector.LlmClient.openai(allocator, api_key, base_url);
    defer client.deinit();

    var request = try zconnector.ChatRequest.new(allocator, "gpt-4.1-mini");
    defer request.deinit();

    _ = try request.addMessage(.user, "Give me a one-line introduction to Zig.");

    var response = try client.chat(&request);
    defer response.deinit();

    var stdout = std.fs.File.stdout().deprecatedWriter();
    try stdout.print("{s}\n", .{response.content});
}
