const std = @import("std");
const zconnector = @import("zconnector");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    const api_key = init.environ_map.get("OPENAI_API_KEY") orelse "sk-placeholder";
    const base_url = init.environ_map.get("OPENAI_BASE_URL") orelse "https://api.openai.com";
    const model_name = init.environ_map.get("OPENAI_MODEL_NAME") orelse "gpt-4o-mini";

    var client = try zconnector.LlmClient.openai(allocator, api_key, base_url, init.io);
    defer client.deinit();

    var request = try zconnector.ChatRequest.new(allocator, model_name);
    defer request.deinit();

    _ = try request.addMessage(.system, "You are a concise assistant.");
    _ = try request.addMessage(.user, "Say hello from zconnector.");

    var response = try client.chat(&request, .{ .io = init.io });
    defer response.deinit();

    const stdout = std.Io.File.stdout();
    var buffer: [4096]u8 = undefined;
    var writer = stdout.writer(init.io, &buffer);

    try writer.interface.print("model: {s}\n\n{s}\n", .{ response.model, response.content });
    try writer.flush();
}
