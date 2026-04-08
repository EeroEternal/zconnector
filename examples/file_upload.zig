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
    const file_path = arg_it.next() orelse {
        var stdout = std.fs.File.stdout().deprecatedWriter();
        try stdout.writeAll("usage: zig build file_upload -- <path-to-image>\n");
        return;
    };

    const api_key = env_map.get("OPENAI_API_KEY") orelse return error.MissingApiKey;
    const base_url = env_map.get("OPENAI_BASE_URL") orelse "https://api.openai.com";

    const bytes = try std.fs.cwd().readFileAlloc(allocator, file_path, 16 * 1024 * 1024);
    defer allocator.free(bytes);

    const encoder = std.base64.standard.Encoder;
    const encoded = try allocator.alloc(u8, encoder.calcSize(bytes.len));
    _ = encoder.encode(encoded, bytes);
    defer allocator.free(encoded);

    var client = try zconnector.LlmClient.openai(allocator, api_key, base_url, io);
    defer client.deinit();

    var request = try zconnector.ChatRequest.new(allocator, "gpt-4o-mini");
    defer request.deinit();
    _ = try request.addFile(.user, "input.png", "image/png", encoded);
    _ = try request.addMessage(.user, "Describe the uploaded image in one paragraph.");

    var response = try client.chat(&request, .{ .io = io });
    defer response.deinit();

    var stdout = std.fs.File.stdout().deprecatedWriter();
    try stdout.print("{s}\n", .{response.content});
}
