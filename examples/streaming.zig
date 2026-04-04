const std = @import("std");
const zconnector = @import("zconnector");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const api_key = std.posix.getenv("OPENAI_API_KEY") orelse return error.MissingApiKey;
    const base_url = std.posix.getenv("OPENAI_BASE_URL") orelse "https://api.openai.com";
    const model_name = if (args.len > 1) args[1] else "gpt-4.1-mini";

    var client = try zconnector.LlmClient.openai(allocator, api_key, base_url);
    defer client.deinit();

    var request = try zconnector.ChatRequest.new(allocator, model_name);
    defer request.deinit();

    _ = try request.addMessage(.user, "Stream a short haiku about systems programming.");

    var stdout = std.fs.File.stdout().deprecatedWriter();
    try client.chatStream(&request, stdout);
    try stdout.writeByte('\n');
}
