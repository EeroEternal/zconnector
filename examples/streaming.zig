const std = @import("std");
const zconnector = @import("zconnector");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    var arg_it = std.process.Args.Iterator.init(init.minimal.args);
    _ = arg_it.next(); // skip exe name
    const model_name = arg_it.next() orelse "gpt-4o-mini";

    const api_key = init.environ_map.get("OPENAI_API_KEY") orelse return error.MissingApiKey;
    const base_url = init.environ_map.get("OPENAI_BASE_URL") orelse "https://api.openai.com";

    var client = try zconnector.LlmClient.openai(allocator, api_key, base_url, init.io);
    defer client.deinit();

    var request = try zconnector.ChatRequest.new(allocator, model_name);
    defer request.deinit();

    _ = try request.addMessage(.user, "Stream a short haiku about systems programming.");

    const stdout_file = std.Io.File.stdout();
    var buffer: [4096]u8 = undefined;
    var writer = stdout_file.writer(init.io, &buffer);

    try client.chatStream(&request, &writer.interface, .{ .io = init.io });
    try writer.interface.writeByte('\n');
    try writer.flush();
}
