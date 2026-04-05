const std = @import("std");
const zconnector = @import("zconnector");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    const api_key = init.environ_map.get("OPENAI_API_KEY") orelse {
        std.debug.print("Set OPENAI_API_KEY to run.\n", .{});
        return;
    };

    // 1. 通过 Builder 注入 I/O 后端
    var builder_obj = zconnector.LlmClient.builder(allocator);
    var client = try builder_obj
        .withProvider(.openai)
        .withApiKey(api_key)
        .withBaseUrl("https://api.openai.com")
        .withIo(io) // 关键点：注入 Evented I/O
        .build();
    defer client.deinit();

    var request = try zconnector.ChatRequest.new(allocator, "gpt-4o");
    defer request.deinit();
    _ = try request.addMessage(.user, "Hello! Tell me a very short joke.");

    const stdout = std.Io.File.stdout();
    var buffer: [4096]u8 = undefined;
    var writer = stdout.writer(io, &buffer);

    try writer.interface.print("Sending async request (Evented mode)...\n", .{});
    try writer.flush();

    // 2. 执行请求
    // 在 Evented 模式下，这个调用会在底层由 io_uring/GCD 调度
    // 如果你在一个 Fiber 中运行它，它会自动挂起并释放线程供其他 Fiber 使用
    var response = try client.chat(&request, .{ .io = io });
    defer response.deinit();

    try writer.interface.print("Response: {s}\n", .{response.content});
    try writer.flush();
}
