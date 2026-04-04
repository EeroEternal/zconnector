const std = @import("std");

pub const Role = enum {
    system,
    user,
    assistant,
    tool,
};

pub const LlmError = error{
    ApiKeyInvalid,
    RateLimitExceeded,
    ModelNotFound,
    Timeout,
    InvalidJson,
    NetworkError,
    ProviderSpecific,
};

pub const FilePayload = struct {
    name: []const u8,
    data: []const u8,
    mime: []const u8,

    pub fn clone(self: FilePayload, allocator: std.mem.Allocator) !FilePayload {
        return .{
            .name = try allocator.dupe(u8, self.name),
            .data = try allocator.dupe(u8, self.data),
            .mime = try allocator.dupe(u8, self.mime),
        };
    }

    pub fn deinit(self: *FilePayload, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.data);
        allocator.free(self.mime);
    }
};

pub const MessageContent = union(enum) {
    text: []const u8,
    image_url: []const u8,
    file: FilePayload,

    pub fn clone(self: MessageContent, allocator: std.mem.Allocator) !MessageContent {
        return switch (self) {
            .text => |value| .{ .text = try allocator.dupe(u8, value) },
            .image_url => |value| .{ .image_url = try allocator.dupe(u8, value) },
            .file => |value| .{ .file = try value.clone(allocator) },
        };
    }

    pub fn deinit(self: *MessageContent, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .text => |value| allocator.free(value),
            .image_url => |value| allocator.free(value),
            .file => |*value| value.deinit(allocator),
        }
    }
};

pub const Message = struct {
    role: Role,
    content: MessageContent,
    name: ?[]const u8 = null,

    pub fn clone(self: Message, allocator: std.mem.Allocator) !Message {
        return .{
            .role = self.role,
            .content = try self.content.clone(allocator),
            .name = if (self.name) |value| try allocator.dupe(u8, value) else null,
        };
    }

    pub fn deinit(self: *Message, allocator: std.mem.Allocator) void {
        self.content.deinit(allocator);
        if (self.name) |value| allocator.free(value);
    }
};

pub const ChatRequest = struct {
    allocator: std.mem.Allocator,
    model: []const u8,
    messages: std.ArrayList(Message),
    temperature: f32 = 0.7,
    max_tokens: ?u32 = null,
    top_p: f32 = 1.0,
    stream: bool = false,
    reasoning_effort: ?[]const u8 = null,
    thinking: bool = false,

    pub fn new(allocator: std.mem.Allocator, model: []const u8) !ChatRequest {
        return .{
            .allocator = allocator,
            .model = try allocator.dupe(u8, model),
            .messages = .empty,
        };
    }

    pub fn addMessage(self: *ChatRequest, role: Role, content: []const u8) !*ChatRequest {
        try self.messages.append(self.allocator, .{
            .role = role,
            .content = .{ .text = try self.allocator.dupe(u8, content) },
        });
        return self;
    }

    pub fn addImage(self: *ChatRequest, role: Role, image_url: []const u8) !*ChatRequest {
        try self.messages.append(self.allocator, .{
            .role = role,
            .content = .{ .image_url = try self.allocator.dupe(u8, image_url) },
        });
        return self;
    }

    pub fn addFile(self: *ChatRequest, role: Role, name: []const u8, mime: []const u8, data: []const u8) !*ChatRequest {
        try self.messages.append(self.allocator, .{
            .role = role,
            .content = .{ .file = .{
                .name = try self.allocator.dupe(u8, name),
                .data = try self.allocator.dupe(u8, data),
                .mime = try self.allocator.dupe(u8, mime),
            } },
        });
        return self;
    }

    pub fn setReasoningEffort(self: *ChatRequest, effort: ?[]const u8) !*ChatRequest {
        if (self.reasoning_effort) |current| self.allocator.free(current);
        self.reasoning_effort = if (effort) |value| try self.allocator.dupe(u8, value) else null;
        return self;
    }

    pub fn setThinking(self: *ChatRequest, enabled: bool) *ChatRequest {
        self.thinking = enabled;
        return self;
    }

    pub fn deinit(self: *ChatRequest) void {
        for (self.messages.items) |*message| {
            message.deinit(self.allocator);
        }
        self.messages.deinit(self.allocator);
        self.allocator.free(self.model);
        if (self.reasoning_effort) |value| self.allocator.free(value);
    }
};

pub const Usage = struct {
    prompt_tokens: u32 = 0,
    completion_tokens: u32 = 0,
};

pub const Response = struct {
    allocator: std.mem.Allocator,
    content: []const u8,
    model: []const u8,
    usage: Usage,
    finish_reason: []const u8,
    raw_json: ?[]const u8 = null,

    pub fn init(
        allocator: std.mem.Allocator,
        content: []const u8,
        model: []const u8,
        usage: Usage,
        finish_reason: []const u8,
        raw_json: ?[]const u8,
    ) !Response {
        return .{
            .allocator = allocator,
            .content = try allocator.dupe(u8, content),
            .model = try allocator.dupe(u8, model),
            .usage = usage,
            .finish_reason = try allocator.dupe(u8, finish_reason),
            .raw_json = if (raw_json) |value| try allocator.dupe(u8, value) else null,
        };
    }

    pub fn deinit(self: *Response) void {
        self.allocator.free(self.content);
        self.allocator.free(self.model);
        self.allocator.free(self.finish_reason);
        if (self.raw_json) |value| self.allocator.free(value);
    }
};

pub const StreamChunk = struct {
    content_delta: []const u8,
    done: bool,

    pub fn deinit(self: *StreamChunk, allocator: std.mem.Allocator) void {
        if (self.content_delta.len != 0) {
            allocator.free(self.content_delta);
        }
    }
};

pub fn roleName(role: Role) []const u8 {
    return switch (role) {
        .system => "system",
        .user => "user",
        .assistant => "assistant",
        .tool => "tool",
    };
}
