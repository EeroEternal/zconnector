const std = @import("std");
const zconnector = @import("zconnector");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    var arg_it = std.process.Args.Iterator.init(init.minimal.args);
    _ = arg_it.next(); // skip exe name
    // 检查是否通过 --model 参数传入
    var model_name: []const u8 = "gpt-4o-mini";
    while (arg_it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--model")) {
            model_name = arg_it.next() orelse model_name;
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            model_name = arg;
        }
    }

    const api_key = init.environ_map.get("OPENAI_API_KEY") orelse return error.MissingApiKey;
    const base_url = init.environ_map.get("OPENAI_BASE_URL") orelse "https://api.openai.com";

    var client = try zconnector.LlmClient.openai(allocator, api_key, base_url, init.io);
    defer client.deinit();

    var request = try zconnector.ChatRequest.new(allocator, model_name);
    defer request.deinit();

    _ = try request.addMessage(.user, "Write a short poem about the stars in the night sky, around 100 words.");

    const stdout_file = std.Io.File.stdout();
    var buffer: [4096]u8 = undefined;
    var writer = stdout_file.writer(init.io, &buffer);

    try client.chatStream(&request, &writer.interface, .{ .io = init.io });
    try writer.interface.writeByte('\n');
    try writer.flush();
}
