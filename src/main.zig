const std = @import("std");
const zconnector = @import("zconnector");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();
    const io: std.Io = .{};

    const api_key = env_map.get("OPENAI_API_KEY") orelse "sk-placeholder";
    const base_url = env_map.get("OPENAI_BASE_URL") orelse "https://api.openai.com";
    const model_name = env_map.get("OPENAI_MODEL_NAME") orelse "gpt-4o-mini";

    var client = try zconnector.LlmClient.openai(allocator, api_key, base_url, io);
    defer client.deinit();

    var request = try zconnector.ChatRequest.new(allocator, model_name);
    defer request.deinit();

    _ = try request.addMessage(.system, "You are a concise assistant.");
    _ = try request.addMessage(.user, "Say hello from zconnector.");

    var response = try client.chat(&request, .{ .io = io });
    defer response.deinit();

    var stdout = std.fs.File.stdout().deprecatedWriter();
    try stdout.print("model: {s}\n\n{s}\n", .{ response.model, response.content });
}
