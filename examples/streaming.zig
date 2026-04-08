const std = @import("std");
const zconnector = @import("zconnector");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();
    const io: std.Io = .{};

    var arg_it = try std.process.argsWithAllocator(allocator);
    defer arg_it.deinit();
    _ = arg_it.skip();
    var model_name: []const u8 = "gpt-4o-mini";
    while (arg_it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--model")) {
            model_name = arg_it.next() orelse model_name;
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            model_name = arg;
        }
    }

    const api_key = env_map.get("OPENAI_API_KEY") orelse return error.MissingApiKey;
    const base_url = env_map.get("OPENAI_BASE_URL") orelse "https://api.openai.com";

    var client = try zconnector.LlmClient.openai(allocator, api_key, base_url, io);
    defer client.deinit();

    var request = try zconnector.ChatRequest.new(allocator, model_name);
    defer request.deinit();

    _ = try request.addMessage(.user, "Write a short poem about the stars in the night sky, around 100 words.");

    var stdout = std.fs.File.stdout().deprecatedWriter();
    try client.chatStream(&request, &stdout, .{ .io = io });
    try stdout.writeByte('\n');
}
