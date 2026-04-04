const std = @import("std");
const zconnector = @import("zconnector");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    var stdout = std.fs.File.stdout().deprecatedWriter();

    const api_key = std.posix.getenv("OPENAI_API_KEY") orelse {
        try stdout.writeAll("Set OPENAI_API_KEY and optionally OPENAI_BASE_URL to run the demo.\n");
        return;
    };
    const base_url = std.posix.getenv("OPENAI_BASE_URL") orelse "https://api.openai.com";

    var client = try zconnector.LlmClient.openai(allocator, api_key, base_url);
    defer client.deinit();

    var request = try zconnector.ChatRequest.new(allocator, "gpt-4.1-mini");
    defer request.deinit();

    _ = try request.addMessage(.system, "You are a concise assistant.");
    _ = try request.addMessage(.user, "Say hello from zconnector.");

    var response = try client.chat(&request);
    defer response.deinit();

    try stdout.print("model: {s}\n\n{s}\n", .{ response.model, response.content });
}
