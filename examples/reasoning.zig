const std = @import("std");
const zconnector = @import("zconnector");

pub fn main() !void {
    const io = std.Io.get();
    const init = try std.process.init(io);
    defer init.deinit();
    const allocator = init.gpa;
    const provider = init.environ_map.get("ZCONNECTOR_PROVIDER") orelse "openai";
    const stdout_file = std.Io.File.stdout();
    var buffer: [4096]u8 = undefined;
    var writer = stdout_file.writer(io, &buffer);
    const stdout = &writer.interface;

    if (std.mem.eql(u8, provider, "anthropic")) {
        const api_key = init.environ_map.get("ANTHROPIC_API_KEY") orelse return error.MissingApiKey;
        const base_url = init.environ_map.get("ANTHROPIC_BASE_URL") orelse "https://api.anthropic.com";

        var client = try zconnector.LlmClient.anthropic(allocator, api_key, base_url, io);
        defer client.deinit();

        var request = try zconnector.ChatRequest.new(allocator, "claude-3-7-sonnet-latest");
        defer request.deinit();
        _ = request.setThinking(true);
        _ = try request.addMessage(.user, "Think through whether a lock-free queue is needed for a two-thread producer-consumer setup.");

        var response = try client.chat(&request, .{ .io = io });
        defer response.deinit();
        try stdout.print("{s}\n", .{response.content});
        try writer.flush();
        return;
    }

    const api_key = init.environ_map.get("OPENAI_API_KEY") orelse return error.MissingApiKey;
    const base_url = init.environ_map.get("OPENAI_BASE_URL") orelse "https://api.openai.com";

    var client = try zconnector.LlmClient.openai(allocator, api_key, base_url, io);
    defer client.deinit();

    var request = try zconnector.ChatRequest.new(allocator, "o1-mini");
    defer request.deinit();
    _ = try request.setReasoningEffort("medium");
    _ = try request.addMessage(.user, "Compare event loops and thread pools in three concise bullet points.");

    var response = try client.chat(&request, .{ .io = io });
    defer response.deinit();
    try stdout.print("{s}\n", .{response.content});
    try writer.flush();
}
