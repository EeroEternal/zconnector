const std = @import("std");
const zconnector = @import("zconnector");

fn runOpenAi(init: std.process.Init) !void {
    const api_key = init.environ_map.get("OPENAI_API_KEY") orelse return error.MissingApiKey;
    const base_url = init.environ_map.get("OPENAI_BASE_URL") orelse "https://api.openai.com";

    var client = try zconnector.LlmClient.openai(init.gpa, api_key, base_url, init.io);
    defer client.deinit();

    var request = try zconnector.ChatRequest.new(init.gpa, "gpt-4o-mini");
    defer request.deinit();
    _ = try request.addMessage(.user, "What does memory safety buy us in systems programming?");

    var response = try client.chat(&request, .{ .io = init.io });
    defer response.deinit();

    const stdout_file = std.Io.File.stdout();
    var buffer: [4096]u8 = undefined;
    var writer = stdout_file.writer(init.io, &buffer);
    try writer.interface.print("OpenAI: {s}\n", .{response.content});
    try writer.flush();
}

fn runAnthropic(init: std.process.Init) !void {
    const api_key = init.environ_map.get("ANTHROPIC_API_KEY") orelse return error.MissingApiKey;
    const base_url = init.environ_map.get("ANTHROPIC_BASE_URL") orelse "https://api.anthropic.com";

    var client = try zconnector.LlmClient.anthropic(init.gpa, api_key, base_url, init.io);
    defer client.deinit();

    var request = try zconnector.ChatRequest.new(init.gpa, "claude-3-5-sonnet-latest");
    defer request.deinit();
    _ = try request.addMessage(.user, "Summarize why predictable latency matters for backend services.");

    var response = try client.chat(&request, .{ .io = init.io });
    defer response.deinit();

    const stdout_file = std.Io.File.stdout();
    var buffer: [4096]u8 = undefined;
    var writer = stdout_file.writer(init.io, &buffer);
    try writer.interface.print("Anthropic: {s}\n", .{response.content});
    try writer.flush();
}

pub fn main(init: std.process.Init) !void {
    runOpenAi(init) catch |err| {
        const stderr_file = std.Io.File.stderr();
        var buffer: [1024]u8 = undefined;
        var writer = stderr_file.writer(init.io, &buffer);
        try writer.interface.print("OpenAI example skipped: {}\n", .{err});
        try writer.flush();
    };

    runAnthropic(init) catch |err| {
        const stderr_file = std.Io.File.stderr();
        var buffer: [1024]u8 = undefined;
        var writer = stderr_file.writer(init.io, &buffer);
        try writer.interface.print("Anthropic example skipped: {}\n", .{err});
        try writer.flush();
    };
}
