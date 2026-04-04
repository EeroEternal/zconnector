const std = @import("std");
const zconnector = @import("zconnector");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const stdout = std.fs.File.stdout().deprecatedWriter();

    const api_key = std.posix.getenv("OPENAI_API_KEY") orelse {
        try stdout.writeAll("Please set OPENAI_API_KEY environment variable.\n");
        return;
    };

    const base_url = std.posix.getenv("OPENAI_BASE_URL") orelse "https://api.openai.com";

    var client = try zconnector.LlmClient.openai(allocator, api_key, base_url);
    defer client.deinit();

    var request = try zconnector.ChatRequest.new(allocator, "gpt-4o");
    defer request.deinit();

    _ = try request.addMessage(.user, "What's the weather like in Beijing?");

    // Use the convenience method
    _ = try request.addTool("get_weather", "Get the current weather in a given location", "{\"type\":\"object\",\"properties\":{\"location\":{\"type\":\"string\"}}}");

    try stdout.writeAll("Sending request with tool definition...\n");

    var response = try client.chat(&request);
    defer response.deinit();

    if (response.tool_calls) |tool_calls| {
        try stdout.print("Received {d} tool calls.\n", .{tool_calls.items.len});
        for (tool_calls.items) |tc| {
            try stdout.print("Tool Call ID: {s}\n", .{tc.id});
            try stdout.print("Function: {s}\n", .{tc.function.name});
            try stdout.print("Arguments: {s}\n", .{tc.function.arguments});

            // Simulate tool execution and add result to conversation
            // 1. Add assistant message with tool calls
            var assistant_msg = try request.addMessage(.assistant, "");
            assistant_msg.tool_calls = .empty;
            try assistant_msg.tool_calls.?.append(allocator, try tc.clone(allocator));

            // 2. Add tool output message
            const weather_json = "{\"location\": \"Beijing\", \"temperature\": 25, \"unit\": \"celsius\", \"description\": \"Sunny\"}";
            _ = try request.addToolOutput(tc.id, weather_json);
        }

        try stdout.writeAll("\nSending second request with tool results...\n");
        var response2 = try client.chat(&request);
        defer response2.deinit();

        try stdout.print("Final response: {s}\n", .{response2.content});
    } else {
        try stdout.print("No tool calls received. Content: {s}\n", .{response.content});
    }
}
