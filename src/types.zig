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

pub const ToolFunction = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    parameters: ?[]const u8 = null, // JSON string of parameters schema
    strict: bool = false,

    pub fn clone(self: ToolFunction, allocator: std.mem.Allocator) !ToolFunction {
        return .{
            .name = try allocator.dupe(u8, self.name),
            .description = if (self.description) |d| try allocator.dupe(u8, d) else null,
            .parameters = if (self.parameters) |p| try allocator.dupe(u8, p) else null,
            .strict = self.strict,
        };
    }

    pub fn deinit(self: *ToolFunction, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.description) |d| allocator.free(d);
        if (self.parameters) |p| allocator.free(p);
    }
};

pub const Tool = struct {
    type: []const u8 = "function",
    function: ToolFunction,

    pub fn clone(self: Tool, allocator: std.mem.Allocator) !Tool {
        return .{
            .type = try allocator.dupe(u8, self.type),
            .function = try self.function.clone(allocator),
        };
    }

    pub fn deinit(self: *Tool, allocator: std.mem.Allocator) void {
        allocator.free(self.type);
        self.function.deinit(allocator);
    }
};

pub const ToolCall = struct {
    id: []const u8,
    type: []const u8 = "function",
    function: struct {
        name: []const u8,
        arguments: []const u8,
    },

    pub fn clone(self: ToolCall, allocator: std.mem.Allocator) !ToolCall {
        return .{
            .id = try allocator.dupe(u8, self.id),
            .type = try allocator.dupe(u8, self.type),
            .function = .{
                .name = try allocator.dupe(u8, self.function.name),
                .arguments = try allocator.dupe(u8, self.function.arguments),
            },
        };
    }

    pub fn deinit(self: *ToolCall, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.type);
        allocator.free(self.function.name);
        allocator.free(self.function.arguments);
    }
};

pub const ResponseFormat = union(enum) {
    text,
    json_object,
    json_schema: struct {
        name: []const u8,
        strict: bool = false,
        schema: []const u8, // JSON string of schema
    },

    pub fn deinit(self: *ResponseFormat, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .json_schema => |val| {
                allocator.free(val.name);
                allocator.free(val.schema);
            },
            else => {},
        }
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
    tool_calls: ?std.ArrayList(ToolCall) = null,
    tool_call_id: ?[]const u8 = null,

    pub fn clone(self: Message, allocator: std.mem.Allocator) !Message {
        var tc: ?std.ArrayList(ToolCall) = null;
        if (self.tool_calls) |calls| {
            tc = std.ArrayList(ToolCall).init(allocator);
            for (calls.items) |call| {
                try tc.?.append(try call.clone(allocator));
            }
        }

        return .{
            .role = self.role,
            .content = try self.content.clone(allocator),
            .name = if (self.name) |value| try allocator.dupe(u8, value) else null,
            .tool_calls = tc,
            .tool_call_id = if (self.tool_call_id) |value| try allocator.dupe(u8, value) else null,
        };
    }

    pub fn deinit(self: *Message, allocator: std.mem.Allocator) void {
        self.content.deinit(allocator);
        if (self.name) |value| allocator.free(value);
        if (self.tool_calls) |*calls| {
            for (calls.items) |*call| call.deinit(allocator);
            calls.deinit(allocator);
        }
        if (self.tool_call_id) |value| allocator.free(value);
    }
};

pub const TextMessageInit = struct {
    role: Role,
    content: []const u8,
};

pub const ToolChoice = union(enum) {
    string: []const u8, // "none", "auto", "required"
    tool: Tool,

    pub fn deinit(self: *ToolChoice, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .string => |s| allocator.free(s),
            .tool => |*t| t.deinit(allocator),
        }
    }
};

pub const ChatRequest = struct {
    allocator: std.mem.Allocator,
    model: []const u8,
    messages: std.ArrayList(Message),
    tools: ?std.ArrayList(Tool) = null,
    tool_choice: ?ToolChoice = null,
    response_format: ?ResponseFormat = null,
    temperature: f32 = 0.7,
    max_tokens: ?u32 = null,
    top_p: f32 = 1.0,
    stream: bool = false,
    reasoning_effort: ?[]const u8 = null,
    thinking: bool = false,
    presence_penalty: f32 = 0.0,
    frequency_penalty: f32 = 0.0,
    seed: ?i64 = null,
    user_id: ?[]const u8 = null,

    pub fn new(allocator: std.mem.Allocator, model: []const u8) !ChatRequest {
        return .{
            .allocator = allocator,
            .model = try allocator.dupe(u8, model),
            .messages = .empty,
        };
    }

    pub fn fromTextMessages(
        allocator: std.mem.Allocator,
        model: []const u8,
        messages: []const TextMessageInit,
    ) !ChatRequest {
        var request = try ChatRequest.new(allocator, model);
        errdefer request.deinit();

        for (messages) |message| {
            _ = try request.addMessage(message.role, message.content);
        }

        return request;
    }

    pub fn addMessage(self: *ChatRequest, role: Role, content: []const u8) !*Message {
        try self.messages.append(self.allocator, .{
            .role = role,
            .content = .{ .text = try self.allocator.dupe(u8, content) },
        });
        return &self.messages.items[self.messages.items.len - 1];
    }

    pub fn addToolOutput(self: *ChatRequest, tool_call_id: []const u8, content: []const u8) !*Message {
        try self.messages.append(self.allocator, .{
            .role = .tool,
            .content = .{ .text = try self.allocator.dupe(u8, content) },
            .tool_call_id = try self.allocator.dupe(u8, tool_call_id),
        });
        return &self.messages.items[self.messages.items.len - 1];
    }

    pub fn addTool(self: *ChatRequest, name: []const u8, description: ?[]const u8, parameters: ?[]const u8) !*ChatRequest {
        if (self.tools == null) {
            self.tools = .empty;
        }
        try self.tools.?.append(self.allocator, .{
            .function = .{
                .name = try self.allocator.dupe(u8, name),
                .description = if (description) |d| try self.allocator.dupe(u8, d) else null,
                .parameters = if (parameters) |p| try self.allocator.dupe(u8, p) else null,
            },
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

    pub fn setResponseFormat(self: *ChatRequest, format: ResponseFormat) !*ChatRequest {
        if (self.response_format) |*current| current.deinit(self.allocator);
        self.response_format = format;
        return self;
    }

    pub fn deinit(self: *ChatRequest) void {
        for (self.messages.items) |*message| {
            message.deinit(self.allocator);
        }
        self.messages.deinit(self.allocator);

        if (self.tools) |*t_list| {
            for (t_list.items) |*t| t.deinit(self.allocator);
            t_list.deinit(self.allocator);
        }

        if (self.tool_choice) |*tc| tc.deinit(self.allocator);
        if (self.response_format) |*rf| rf.deinit(self.allocator);

        self.allocator.free(self.model);
        if (self.reasoning_effort) |value| self.allocator.free(value);
        if (self.user_id) |uid| self.allocator.free(uid);
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
    tool_calls: ?std.ArrayList(ToolCall) = null,
    raw_json: ?[]const u8 = null,

    pub fn init(
        allocator: std.mem.Allocator,
        content: []const u8,
        model: []const u8,
        usage: Usage,
        finish_reason: []const u8,
        tool_calls: ?std.ArrayList(ToolCall),
        raw_json: ?[]const u8,
    ) !Response {
        return .{
            .allocator = allocator,
            .content = try allocator.dupe(u8, content),
            .model = try allocator.dupe(u8, model),
            .usage = usage,
            .finish_reason = try allocator.dupe(u8, finish_reason),
            .tool_calls = tool_calls,
            .raw_json = if (raw_json) |value| try allocator.dupe(u8, value) else null,
        };
    }

    pub fn deinit(self: *Response) void {
        self.allocator.free(self.content);
        self.allocator.free(self.model);
        self.allocator.free(self.finish_reason);
        if (self.tool_calls) |*calls| {
            for (calls.items) |*call| call.deinit(self.allocator);
            calls.deinit(self.allocator);
        }
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

test "chat request fromTextMessages owns copied text" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var system_text = [_]u8{ 's', 'y', 's' };
    var user_text = [_]u8{ 'u', 's', 'e', 'r' };

    var request = try ChatRequest.fromTextMessages(allocator, "test-model", &.{
        .{ .role = .system, .content = system_text[0..] },
        .{ .role = .user, .content = user_text[0..] },
    });
    defer request.deinit();

    system_text[0] = 'X';
    user_text[0] = 'Y';

    try std.testing.expectEqual(@as(usize, 2), request.messages.items.len);
    try std.testing.expectEqualStrings("sys", request.messages.items[0].content.text);
    try std.testing.expectEqualStrings("user", request.messages.items[1].content.text);
}
