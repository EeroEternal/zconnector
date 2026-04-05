const std = @import("std");
const zconnector = @import("zconnector");

pub fn main() !void {
    const io = std.Io.get();
    const init = try std.process.init(io);
    defer init.deinit();
    const allocator = init.gpa;
    const stdout_file = std.Io.File.stdout();
    var buffer: [4096]u8 = undefined;
    var writer = stdout_file.writer(io, &buffer);

    const api_key = init.environ_map.get("OPENAI_API_KEY") orelse {
        try writer.interface.writeAll("Please set OPENAI_API_KEY environment variable.\n");
        try writer.flush();
        return;
    };

    const base_url = init.environ_map.get("OPENAI_BASE_URL") orelse "https://api.openai.com";

    var client = try zconnector.LlmClient.openai(allocator, api_key, base_url, io);
    defer client.deinit();

    var request = try zconnector.ChatRequest.new(allocator, "gpt-4o-mini");
    defer request.deinit();

    _ = try request.addMessage(.user, "What's the weather like in Beijing?");

    // Use the convenience method
    _ = try request.addTool("get_weather", "Get the current weather in a given location", "{\"type\":\"object\",\"properties\":{\"location\":{\"type\":\"string\"}}}");

    try writer.interface.writeAll("Sending request with tool definition...\n");
    try writer.flush();

    var response = try client.chat(&request, .{ .io = io });
    defer response.deinit();

    if (response.tool_calls) |tool_calls| {
        try writer.interface.print("Received {d} tool calls.\n", .{tool_calls.items.len});
        for (tool_calls.items) |tc| {
            try writer.interface.print("Tool Call ID: {s}\n", .{tc.id});
            try writer.interface.print("Function: {s}\n", .{tc.function.name});
            try writer.interface.print("Arguments: {s}\n", .{tc.function.arguments});

            // Simulate tool execution and add result to conversation
            // 1. Add assistant message with tool calls
            var assistant_msg = try request.addMessage(.assistant, "");
            assistant_msg.tool_calls = .empty;
            try assistant_msg.tool_calls.?.append(allocator, try tc.clone(allocator));

            // 2. Add tool output message
            const weather_json = "{\"location\": \"Beijing\", \"temperature\": 25, \"unit\": \"celsius\", \"description\": \"Sunny\"}";
            _ = try request.addToolOutput(tc.id, weather_json);
        }

        try writer.interface.writeAll("\nSending second request with tool results...\n");
        try writer.flush();
        var response2 = try client.chat(&request, .{ .io = io });
        defer response2.deinit();

        try writer.interface.print("Final response: {s}\n", .{response2.content});
    } else {
        try writer.interface.print("No tool calls received. Content: {s}\n", .{response.content});
    }
    try writer.flush();
}
