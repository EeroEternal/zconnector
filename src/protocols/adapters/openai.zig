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
    const body = try json.stringifyOpenAiRequest(allocator, request, .chat_completions, false);
    defer allocator.free(body);

    var response = try http.request(client, allocator, base_url, .{
        .path = "/v1/chat/completions",
        .body = body,
        .auth = .{ .bearer = api_key },
        .timeout_ms = timeout_ms,
        .extra_headers = extra_headers,
        .io = io,
    });
    defer response.deinit();

    try ensureSuccess(response.status);
    return json.parseOpenAiResponse(allocator, response.body);
}

pub fn responses(
    allocator: std.mem.Allocator,
    client: *std.http.Client,
    api_key: []const u8,
    base_url: []const u8,
    timeout_ms: u32,
    extra_headers: *const std.StringHashMap([]const u8),
    request: *const types.ChatRequest,
    io: ?*std.Io,
) !types.Response {
    const body = try json.stringifyOpenAiRequest(allocator, request, .responses, false);
    defer allocator.free(body);

    var response = try http.request(client, allocator, base_url, .{
        .path = "/v1/responses",
        .body = body,
        .auth = .{ .bearer = api_key },
        .timeout_ms = timeout_ms,
        .extra_headers = extra_headers,
        .io = io,
    });
    defer response.deinit();

    switch (response.status) {
        .not_found, .method_not_allowed => return chat(allocator, client, api_key, base_url, timeout_ms, extra_headers, request, io),
        else => try ensureSuccess(response.status),
    }

    return json.parseOpenAiResponse(allocator, response.body);
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
    const body = try json.stringifyOpenAiRequest(allocator, request, .chat_completions, true);
    defer allocator.free(body);

    const Context = struct {
        allocator: std.mem.Allocator,
        writer: @TypeOf(writer),
    };

    var context = Context{
        .allocator = allocator,
        .writer = writer,
    };

    try http.streamSse(client, allocator, base_url, .{
        .path = "/v1/chat/completions",
        .body = body,
        .auth = .{ .bearer = api_key },
        .timeout_ms = timeout_ms,
        .extra_headers = extra_headers,
        .io = io,
    }, &context, struct {
        fn onEvent(ctx: *Context, payload: []const u8) !bool {
            if (std.mem.eql(u8, payload, "[DONE]")) return false;
            const chunk = try json.parseOpenAiStreamChunk(ctx.allocator, payload);
            defer ctx.allocator.free(chunk.content_delta);
            try ctx.writer.writeAll(chunk.content_delta);
            return !chunk.done;
        }
    }.onEvent);
}
