const std = @import("std");
const zconnector = @import("zconnector");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();
    const io: std.Io = .{};

    const provider = env_map.get("ZCONNECTOR_PROVIDER") orelse "openai";
    var stdout = std.fs.File.stdout().deprecatedWriter();

    if (std.mem.eql(u8, provider, "anthropic")) {
        const api_key = env_map.get("ANTHROPIC_API_KEY") orelse return error.MissingApiKey;
        const base_url = env_map.get("ANTHROPIC_BASE_URL") orelse "https://api.anthropic.com";

        var client = try zconnector.LlmClient.anthropic(allocator, api_key, base_url, io);
        defer client.deinit();

        var request = try zconnector.ChatRequest.new(allocator, "claude-3-7-sonnet-latest");
        defer request.deinit();
        _ = request.setThinking(true);
        _ = try request.addMessage(.user, "Think through whether a lock-free queue is needed for a two-thread producer-consumer setup.");

        var response = try client.chat(&request, .{ .io = io });
        defer response.deinit();
        try stdout.print("{s}\n", .{response.content});
        return;
    }

    const api_key = env_map.get("OPENAI_API_KEY") orelse return error.MissingApiKey;
    const base_url = env_map.get("OPENAI_BASE_URL") orelse "https://api.openai.com";

    var client = try zconnector.LlmClient.openai(allocator, api_key, base_url, io);
    defer client.deinit();

    var request = try zconnector.ChatRequest.new(allocator, "o1-mini");
    defer request.deinit();
    _ = try request.setReasoningEffort("medium");
    _ = try request.addMessage(.user, "Compare event loops and thread pools in three concise bullet points.");

    var response = try client.chat(&request, .{ .io = io });
    defer response.deinit();
    try stdout.print("{s}\n", .{response.content});
}
