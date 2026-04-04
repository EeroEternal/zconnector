const std = @import("std");
const utils = @import("../../utils.zig");
const types = @import("../../types.zig");

pub const Auth = union(enum) {
    bearer: []const u8,
    header: struct {
        name: []const u8,
        value: []const u8,
    },
};

pub const RequestOptions = struct {
    method: std.http.Method = .POST,
    path: []const u8,
    body: []const u8 = "",
    auth: ?Auth = null,
    timeout_ms: u32 = 120_000,
    content_type: []const u8 = "application/json",
    accept: []const u8 = "application/json",
    max_body_bytes: usize = 16 * 1024 * 1024,
    extra_headers: ?*const std.StringHashMap([]const u8) = null,
};

pub const Response = struct {
    allocator: std.mem.Allocator,
    status: std.http.Status,
    body: []u8,

    pub fn deinit(self: *Response) void {
        self.allocator.free(self.body);
    }
};

fn appendHeaders(allocator: std.mem.Allocator, headers: *std.ArrayList(std.http.Header), options: RequestOptions) !void {
    try headers.append(allocator, .{ .name = "content-type", .value = options.content_type });
    try headers.append(allocator, .{ .name = "accept", .value = options.accept });

    if (options.auth) |auth| {
        switch (auth) {
            .bearer => |api_key| {
                const value = try std.fmt.allocPrint(allocator, "Bearer {s}", .{api_key});
                errdefer allocator.free(value);
                try headers.append(allocator, .{ .name = "authorization", .value = value });
            },
            .header => |header| {
                try headers.append(allocator, .{ .name = header.name, .value = header.value });
            },
        }
    }

    if (options.extra_headers) |extra_headers| {
        var iterator = extra_headers.iterator();
        while (iterator.next()) |entry| {
            try headers.append(allocator, .{ .name = entry.key_ptr.*, .value = entry.value_ptr.* });
        }
    }
}

fn freeTemporaryHeaders(allocator: std.mem.Allocator, headers: *std.ArrayList(std.http.Header)) void {
    for (headers.items) |header| {
        if (std.mem.eql(u8, header.name, "authorization")) {
            allocator.free(header.value);
        }
    }
    headers.deinit(allocator);
}

pub fn request(
    client: *std.http.Client,
    allocator: std.mem.Allocator,
    base_url: []const u8,
    options: RequestOptions,
) !Response {
    const url = try utils.joinUrl(allocator, base_url, options.path);
    defer allocator.free(url);

    const uri = try std.Uri.parse(url);

    var headers: std.ArrayList(std.http.Header) = .empty;
    defer freeTemporaryHeaders(allocator, &headers);
    try appendHeaders(allocator, &headers, options);

    var response_writer: std.Io.Writer.Allocating = .init(allocator);
    errdefer response_writer.deinit();

    const result = try client.fetch(.{
        .location = .{ .uri = uri },
        .method = options.method,
        .payload = if (options.body.len == 0) null else options.body,
        .extra_headers = headers.items,
        .keep_alive = true,
        .response_writer = &response_writer.writer,
    });
    const body = response_writer.toOwnedSlice() catch {
        return types.LlmError.NetworkError;
    };

    _ = options.timeout_ms;

    return .{
        .allocator = allocator,
        .status = result.status,
        .body = body,
    };
}

pub fn streamSse(
    client: *std.http.Client,
    allocator: std.mem.Allocator,
    base_url: []const u8,
    options: RequestOptions,
    context: anytype,
    comptime on_event: fn (@TypeOf(context), []const u8) anyerror!bool,
) !void {
    const url = try utils.joinUrl(allocator, base_url, options.path);
    defer allocator.free(url);

    const uri = try std.Uri.parse(url);

    var headers: std.ArrayList(std.http.Header) = .empty;
    defer freeTemporaryHeaders(allocator, &headers);
    try appendHeaders(allocator, &headers, options);

    var request_handle = try client.request(options.method, uri, .{
        .extra_headers = headers.items,
    });
    defer request_handle.deinit();

    if (options.body.len != 0) {
        request_handle.transfer_encoding = .{ .content_length = options.body.len };
        var request_body = try request_handle.sendBodyUnflushed(&.{});
        try request_body.writer.writeAll(options.body);
        try request_body.end();
        try request_handle.connection.?.flush();
    } else {
        try request_handle.sendBodiless();
    }

    var response = try request_handle.receiveHead(&.{});
    const status_code = @intFromEnum(response.head.status);
    if (status_code < 200 or status_code >= 300) {
        const body_reader = response.reader(&.{});
        var error_body: std.Io.Writer.Allocating = .init(allocator);
        defer error_body.deinit();
        _ = try body_reader.streamRemaining(&error_body.writer);
        const body = try error_body.toOwnedSlice();
        defer allocator.free(body);
        return types.LlmError.ProviderSpecific;
    }

    var transfer_buffer: [4 * 1024]u8 = undefined;
    const reader = response.reader(&transfer_buffer);
    while (true) {
        const maybe_line = try reader.takeDelimiter('\n');
        if (maybe_line == null) break;

        const line = std.mem.trimRight(u8, maybe_line.?, "\r\n");
        if (line.len == 0) continue;
        if (!std.mem.startsWith(u8, line, "data:")) continue;

        const payload = std.mem.trimLeft(u8, line[5..], " ");
        const keep_going = try on_event(context, payload);
        if (!keep_going) break;
    }

    _ = options.timeout_ms;
}
