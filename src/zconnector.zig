const std = @import("std");
const types = @import("types.zig");
const utils = @import("utils.zig");
const openai_adapter = @import("protocols/adapters/openai.zig");
const anthropic_adapter = @import("protocols/adapters/anthropic.zig");

pub const Role = types.Role;
pub const Message = types.Message;
pub const TextMessageInit = types.TextMessageInit;
pub const MessageContent = types.MessageContent;
pub const ChatRequest = types.ChatRequest;
pub const Response = types.Response;
pub const StreamChunk = types.StreamChunk;
pub const Usage = types.Usage;
pub const LlmError = types.LlmError;
pub const FilePayload = types.FilePayload;
pub const Tool = types.Tool;
pub const ToolCall = types.ToolCall;
pub const ToolFunction = types.ToolFunction;
pub const ResponseFormat = types.ResponseFormat;

pub const Provider = enum {
    openai,
    anthropic,
};

pub const LlmClient = struct {
    pub const LlmConfig = struct {
        api_key: []const u8,
        base_url: []const u8,
        timeout_ms: u32 = 120_000,
        extra_headers: std.StringHashMap([]const u8),
    };

    allocator: std.mem.Allocator,
    http_client: std.http.Client,
    config: LlmConfig,
    provider: Provider,
    io: ?std.Io = null, // 注入 I/O 后端实现

    pub fn builder(allocator: std.mem.Allocator) Builder {
        return Builder.init(allocator);
    }

    pub fn openai(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8, io: std.Io) !LlmClient {
        var build_state = Builder.init(allocator);
        _ = build_state.withProvider(.openai).withApiKey(api_key).withBaseUrl(base_url).withIo(io);
        return build_state.build();
    }

    pub fn anthropic(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8, io: std.Io) !LlmClient {
        var build_state = Builder.init(allocator);
        _ = build_state.withProvider(.anthropic).withApiKey(api_key).withBaseUrl(base_url).withIo(io);
        return build_state.build();
    }

    pub fn chat(self: *LlmClient, request: *const ChatRequest, options: anytype) !Response {
        var io_val = if (@hasField(@TypeOf(options), "io")) options.io else self.io.?;
        const io = &io_val;
        return switch (self.provider) {
            .openai => if (request.reasoning_effort != null)
                try self.responses(request, options)
            else
                try openai_adapter.chat(
                    self.allocator,
                    &self.http_client,
                    self.config.api_key,
                    self.config.base_url,
                    self.config.timeout_ms,
                    &self.config.extra_headers,
                    request,
                    io,
                ),
            .anthropic => try anthropic_adapter.chat(
                self.allocator,
                &self.http_client,
                self.config.api_key,
                self.config.base_url,
                self.config.timeout_ms,
                &self.config.extra_headers,
                request,
                io,
            ),
        };
    }

    pub fn chatStream(self: *LlmClient, request: *const ChatRequest, writer: anytype, options: anytype) !void {
        var io_val = if (@hasField(@TypeOf(options), "io")) options.io else self.io.?;
        const io = &io_val;
        return switch (self.provider) {
            .openai => try openai_adapter.chatStream(
                self.allocator,
                &self.http_client,
                self.config.api_key,
                self.config.base_url,
                self.config.timeout_ms,
                &self.config.extra_headers,
                request,
                writer,
                io,
            ),
            .anthropic => try anthropic_adapter.chatStream(
                self.allocator,
                &self.http_client,
                self.config.api_key,
                self.config.base_url,
                self.config.timeout_ms,
                &self.config.extra_headers,
                request,
                writer,
                io,
            ),
        };
    }

    pub fn responses(self: *LlmClient, request: *const ChatRequest, options: anytype) !Response {
        var io_val = if (@hasField(@TypeOf(options), "io")) options.io else self.io.?;
        const io = &io_val;
        return switch (self.provider) {
            .openai => try openai_adapter.responses(
                self.allocator,
                &self.http_client,
                self.config.api_key,
                self.config.base_url,
                self.config.timeout_ms,
                &self.config.extra_headers,
                request,
                io,
            ),
            else => LlmError.ProviderSpecific,
        };
    }

    pub fn deinit(self: *LlmClient) void {
        self.http_client.deinit();
        utils.deinitOwnedStringMap(self.allocator, &self.config.extra_headers);
        self.allocator.free(self.config.api_key);
        self.allocator.free(self.config.base_url);
    }
};

pub const Builder = struct {
    allocator: std.mem.Allocator,
    provider: Provider = .openai,
    api_key: ?[]const u8 = null,
    base_url: ?[]const u8 = null,
    timeout_ms: u32 = 120_000,
    extra_headers: std.StringHashMap([]const u8),
    io: ?std.Io = null,

    pub fn init(allocator: std.mem.Allocator) Builder {
        return .{
            .allocator = allocator,
            .extra_headers = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Builder) void {
        self.extra_headers.deinit();
    }

    pub fn withIo(self: *Builder, io: std.Io) *Builder {
        self.io = io;
        return self;
    }

    pub fn withProvider(self: *Builder, provider: Provider) *Builder {
        self.provider = provider;
        return self;
    }

    pub fn withApiKey(self: *Builder, api_key: []const u8) *Builder {
        self.api_key = api_key;
        return self;
    }

    pub fn withBaseUrl(self: *Builder, base_url: []const u8) *Builder {
        self.base_url = base_url;
        return self;
    }

    pub fn withTimeout(self: *Builder, timeout_ms: u32) *Builder {
        self.timeout_ms = timeout_ms;
        return self;
    }

    pub fn header(self: *Builder, name: []const u8, value: []const u8) !*Builder {
        try self.extra_headers.put(name, value);
        return self;
    }

    pub fn build(self: *Builder) !LlmClient {
        const api_key = self.api_key orelse return error.InvalidConfiguration;
        const base_url = self.base_url orelse return error.InvalidConfiguration;
        const io = self.io orelse return error.InvalidConfiguration;

        var headers = std.StringHashMap([]const u8).init(self.allocator);
        var iterator = self.extra_headers.iterator();
        while (iterator.next()) |entry| {
            const key = try self.allocator.dupe(u8, entry.key_ptr.*);
            errdefer self.allocator.free(key);

            const value = try self.allocator.dupe(u8, entry.value_ptr.*);
            errdefer self.allocator.free(value);

            try headers.put(key, value);
        }

        return .{
            .allocator = self.allocator,
            .http_client = .{ .allocator = self.allocator },
            .provider = self.provider,
            .io = io,
            .config = .{
                .api_key = try self.allocator.dupe(u8, api_key),
                .base_url = try self.allocator.dupe(u8, base_url),
                .timeout_ms = self.timeout_ms,
                .extra_headers = headers,
            },
        };
    }
};

test "chat request builder stores messages" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var request = try ChatRequest.new(arena.allocator(), "gpt-4.1-mini");
    defer request.deinit();

    _ = try request.addMessage(.user, "hello");
    try std.testing.expectEqual(@as(usize, 1), request.messages.items.len);
}
