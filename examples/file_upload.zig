const std = @import("std");
const zconnector = @import("zconnector");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        var stdout = std.fs.File.stdout().deprecatedWriter();
        try stdout.writeAll("usage: zig build file_upload -- <path-to-image>\n");
        return;
    }

    const api_key = std.posix.getenv("OPENAI_API_KEY") orelse return error.MissingApiKey;
    const base_url = std.posix.getenv("OPENAI_BASE_URL") orelse "https://api.openai.com";

    const bytes = try std.fs.cwd().readFileAlloc(allocator, args[1], 16 * 1024 * 1024);
    defer allocator.free(bytes);

    const encoder = std.base64.standard.Encoder;
    const encoded = try allocator.alloc(u8, encoder.calcSize(bytes.len));
    _ = encoder.encode(encoded, bytes);
    defer allocator.free(encoded);

    var client = try zconnector.LlmClient.openai(allocator, api_key, base_url);
    defer client.deinit();

    var request = try zconnector.ChatRequest.new(allocator, "gpt-4.1-mini");
    defer request.deinit();
    _ = try request.addFile(.user, "input.png", "image/png", encoded);
    _ = try request.addMessage(.user, "Describe the uploaded image in one paragraph.");

    var response = try client.responses(&request);
    defer response.deinit();

    var stdout = std.fs.File.stdout().deprecatedWriter();
    try stdout.print("{s}\n", .{response.content});
}
