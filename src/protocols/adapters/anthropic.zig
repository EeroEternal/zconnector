const std = @import("std");
const types = @import("../../types.zig");
const http = @import("../common/http.zig");
const json = @import("../common/json.zig");

fn mapStatus(status: std.http.Status) types.LlmError {
    return switch (status) {
        .unauthorized, .forbidden => types.LlmError.ApiKeyInvalid,
        .too_many_requests => types.LlmError.RateLimitExceeded,
        .not_found => types.LlmError.ModelNotFound,
        .request_timeout, .gateway_timeout => types.LlmError.Timeout,
        else => types.LlmError.ProviderSpecific,
    };
}

fn ensureSuccess(status: std.http.Status) !void {
    const code = @intFromEnum(status);
    if (code >= 200 and code < 300) return;
    return mapStatus(status);
}

fn buildHeaders(allocator: std.mem.Allocator, extra_headers: *const std.StringHashMap([]const u8)) !std.StringHashMap([]const u8) {
    var output = std.StringHashMap([]const u8).init(allocator);

    var iterator = extra_headers.iterator();
    while (iterator.next()) |entry| {
        try output.put(entry.key_ptr.*, entry.value_ptr.*);
    }
    try output.put("anthropic-version", "2023-06-01");
    return output;
}

pub fn chat(
    allocator: std.mem.Allocator,
    client: *std.http.Client,
    api_key: []const u8,
    base_url: []const u8,
    timeout_ms: u32,
    extra_headers: *const std.StringHashMap([]const u8),
    request: *const types.ChatRequest,
    io: ?*std.Io,
) !types.Response {
    const body = try json.stringifyAnthropicRequest(allocator, request, false);
    defer allocator.free(body);

    var headers = try buildHeaders(allocator, extra_headers);
    defer headers.deinit();

    var response = try http.request(client, allocator, base_url, .{
        .path = "/v1/messages",
        .body = body,
        .auth = .{ .header = .{ .name = "x-api-key", .value = api_key } },
        .timeout_ms = timeout_ms,
        .extra_headers = &headers,
        .io = io,
    });
    defer response.deinit();

    try ensureSuccess(response.status);
    return json.parseAnthropicResponse(allocator, response.body);
}

pub fn chatStream(
    allocator: std.mem.Allocator,
    client: *std.http.Client,
    api_key: []const u8,
    base_url: []const u8,
    timeout_ms: u32,
    extra_headers: *const std.StringHashMap([]const u8),
    request: *const types.ChatRequest,
    writer: anytype,
    io: ?*std.Io,
) !void {
    const body = try json.stringifyAnthropicRequest(allocator, request, true);
    defer allocator.free(body);

    var headers = try buildHeaders(allocator, extra_headers);
    defer headers.deinit();

    const Context = struct {
        allocator: std.mem.Allocator,
        writer: @TypeOf(writer),
    };

    var context = Context{
        .allocator = allocator,
        .writer = writer,
    };

    try http.streamSse(client, allocator, base_url, .{
        .path = "/v1/messages",
        .body = body,
        .auth = .{ .header = .{ .name = "x-api-key", .value = api_key } },
        .timeout_ms = timeout_ms,
        .accept = "text/event-stream",
        .extra_headers = &headers,
        .io = io,
    }, &context, struct {
        fn onEvent(ctx: *Context, payload: []const u8) !bool {
            var chunk = try json.parseAnthropicStreamChunk(ctx.allocator, payload);
            defer chunk.deinit(ctx.allocator);

            if (chunk.content_delta.len != 0) {
                try ctx.writer.writeAll(chunk.content_delta);
            }

            return !chunk.done;
        }
    }.onEvent);
}
