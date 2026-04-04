const std = @import("std");
const zconnector = @import("zconnector");

fn runOpenAi(allocator: std.mem.Allocator) !void {
    const api_key = std.posix.getenv("OPENAI_API_KEY") orelse return error.MissingApiKey;
    const base_url = std.posix.getenv("OPENAI_BASE_URL") orelse "https://api.openai.com";

    var client = try zconnector.LlmClient.openai(allocator, api_key, base_url);
    defer client.deinit();

    var request = try zconnector.ChatRequest.new(allocator, "gpt-4.1-mini");
    defer request.deinit();
    _ = try request.addMessage(.user, "What does memory safety buy us in systems programming?");

    var response = try client.chat(&request);
    defer response.deinit();
    var stdout = std.fs.File.stdout().deprecatedWriter();
    try stdout.print("OpenAI: {s}\n", .{response.content});
}

fn runAnthropic(allocator: std.mem.Allocator) !void {
    const api_key = std.posix.getenv("ANTHROPIC_API_KEY") orelse return error.MissingApiKey;
    const base_url = std.posix.getenv("ANTHROPIC_BASE_URL") orelse "https://api.anthropic.com";

    var client = try zconnector.LlmClient.anthropic(allocator, api_key, base_url);
    defer client.deinit();

    var request = try zconnector.ChatRequest.new(allocator, "claude-3-5-sonnet-latest");
    defer request.deinit();
    _ = try request.addMessage(.user, "Summarize why predictable latency matters for backend services.");

    var response = try client.chat(&request);
    defer response.deinit();
    var stdout = std.fs.File.stdout().deprecatedWriter();
    try stdout.print("Anthropic: {s}\n", .{response.content});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    runOpenAi(allocator) catch |err| {
        var stderr = std.fs.File.stderr().deprecatedWriter();
        try stderr.print("OpenAI example skipped: {}\n", .{err});
    };

    runAnthropic(allocator) catch |err| {
        var stderr = std.fs.File.stderr().deprecatedWriter();
        try stderr.print("Anthropic example skipped: {}\n", .{err});
    };
}
