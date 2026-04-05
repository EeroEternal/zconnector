const std = @import("std");
const types = @import("../../types.zig");
const utils = @import("../../utils.zig");

pub const OpenAiEndpoint = enum {
    chat_completions,
    responses,
};

fn writeJson(writer: *std.Io.Writer, value: anytype) !void {
    try std.json.Stringify.value(value, .{}, writer);
}

fn writeRole(writer: *std.Io.Writer, role: types.Role) !void {
    try writeJson(writer, types.roleName(role));
}

fn writeOpenAiChatContent(allocator: std.mem.Allocator, writer: *std.Io.Writer, content: types.MessageContent) !void {
    switch (content) {
        .text => |value| try writeJson(writer, value),
        .image_url => |value| {
            try writer.writeAll("[");
            try writer.writeAll("{\"type\":\"image_url\",\"image_url\":{\"url\":");
            try writeJson(writer, value);
            try writer.writeAll("}}]");
        },
        .file => |value| {
            const data_url = try utils.buildDataUrl(allocator, value.mime, value.data);
            defer allocator.free(data_url);
            try writer.writeAll("[");
            try writer.writeAll("{\"type\":\"input_file\",\"filename\":");
            try writeJson(writer, value.name);
            try writer.writeAll(",\"file_data\":");
            try writeJson(writer, data_url);
            try writer.writeAll("}]");
        },
    }
}

fn writeOpenAiResponsesContent(allocator: std.mem.Allocator, writer: *std.Io.Writer, content: types.MessageContent) !void {
    switch (content) {
        .text => |value| {
            try writer.writeAll("[");
            try writer.writeAll("{\"type\":\"input_text\",\"text\":");
            try writeJson(writer, value);
            try writer.writeAll("}]");
        },
        .image_url => |value| {
            try writer.writeAll("[");
            try writer.writeAll("{\"type\":\"input_image\",\"image_url\":");
            try writeJson(writer, value);
            try writer.writeAll("}]");
        },
        .file => |value| {
            const data_url = try utils.buildDataUrl(allocator, value.mime, value.data);
            defer allocator.free(data_url);
            try writer.writeAll("[");
            try writer.writeAll("{\"type\":\"input_file\",\"filename\":");
            try writeJson(writer, value.name);
            try writer.writeAll(",\"file_data\":");
            try writeJson(writer, data_url);
            try writer.writeAll("}]");
        },
    }
}

fn writeOpenAiMessage(allocator: std.mem.Allocator, writer: *std.Io.Writer, message: types.Message) !void {
    try writer.writeByte('{');
    try writer.writeAll("\"role\":");
    try writeRole(writer, message.role);

    if (message.content != .text or (message.content == .text and message.content.text.len > 0) or (message.role != .assistant)) {
        try writer.writeAll(",\"content\":");
        try writeOpenAiChatContent(allocator, writer, message.content);
    } else if (message.role == .assistant and message.tool_calls != null) {
        try writer.writeAll(",\"content\":null");
    }

    if (message.name) |name| {
        try writer.writeAll(",\"name\":");
        try writeJson(writer, name);
    }

    if (message.tool_calls) |tool_calls| {
        try writer.writeAll(",\"tool_calls\":");
        try writer.writeByte('[');
        for (tool_calls.items, 0..) |tc, i| {
            if (i > 0) try writer.writeByte(',');
            try writer.writeByte('{');
            try writer.writeAll("\"id\":");
            try writeJson(writer, tc.id);
            try writer.writeAll(",\"type\":\"function\",\"function\":{\"name\":");
            try writeJson(writer, tc.function.name);
            try writer.writeAll(",\"arguments\":");
            try writeJson(writer, tc.function.arguments);
            try writer.writeAll("}}");
        }
        try writer.writeByte(']');
    }

    if (message.tool_call_id) |tcid| {
        try writer.writeAll(",\"tool_call_id\":");
        try writeJson(writer, tcid);
    }

    try writer.writeByte('}');
}

fn writeOpenAiResponsesMessage(allocator: std.mem.Allocator, writer: *std.Io.Writer, message: types.Message) !void {
    try writer.writeByte('{');
    try writer.writeAll("\"role\":");
    try writeRole(writer, message.role);
    try writer.writeAll(",\"content\":");
    try writeOpenAiResponsesContent(allocator, writer, message.content);
    try writer.writeByte('}');
}

pub fn stringifyOpenAiRequest(
    allocator: std.mem.Allocator,
    request: *const types.ChatRequest,
    endpoint: OpenAiEndpoint,
    force_stream: bool,
) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();

    const writer = &output.writer;
    try writer.writeByte('{');
    try writer.writeAll("\"model\":");
    try writeJson(writer, request.model);

    const stream_enabled = force_stream or request.stream;

    switch (endpoint) {
        .chat_completions => {
            try writer.writeAll(",\"messages\":[");
            for (request.messages.items, 0..) |message, index| {
                if (index != 0) try writer.writeByte(',');
                try writeOpenAiMessage(allocator, writer, message);
            }
            try writer.writeByte(']');

            if (request.tools) |tools| {
                try writer.writeAll(",\"tools\":");
                try writer.writeByte('[');
                for (tools.items, 0..) |tool, i| {
                    if (i > 0) try writer.writeByte(',');
                    try writer.writeByte('{');
                    try writer.writeAll("\"type\":\"function\",\"function\":{");
                    try writer.writeAll("\"name\":");
                    try writeJson(writer, tool.function.name);
                    try writer.writeAll(",\"description\":");
                    try writeJson(writer, tool.function.description);
                    try writer.writeAll(",\"parameters\":");
                    try writeJson(writer, tool.function.parameters);
                    if (tool.function.strict) {
                        try writer.writeAll(",\"strict\":true");
                    }
                    try writer.writeAll("}}");
                }
                try writer.writeByte(']');
            }

            if (request.tool_choice) |choice| {
                try writer.writeAll(",\"tool_choice\":");
                switch (choice) {
                    .string => |s| try writeJson(writer, s),
                    .tool => |t| {
                        try writer.writeByte('{');
                        try writer.writeAll("\"type\":\"function\",\"function\":{\"name\":");
                        try writeJson(writer, t.function.name);
                        try writer.writeAll("}}");
                    },
                }
            }
        },
        .responses => {
            try writer.writeAll(",\"input\":[");
            for (request.messages.items, 0..) |message, index| {
                if (index != 0) try writer.writeByte(',');
                try writeOpenAiResponsesMessage(allocator, writer, message);
            }
            try writer.writeByte(']');
            try writer.writeAll(",\"store\":false");
        },
    }

    try writer.print(",\"temperature\":{d}", .{request.temperature});
    try writer.print(",\"top_p\":{d}", .{request.top_p});
    try writer.writeAll(",\"stream\":");
    try writer.writeAll(if (stream_enabled) "true" else "false");

    if (request.max_tokens) |max_tokens| {
        try writer.print(",\"max_tokens\":{}", .{max_tokens});
    }

    if (request.reasoning_effort) |effort| {
        switch (endpoint) {
            .chat_completions => {
                try writer.writeAll(",\"reasoning_effort\":");
                try writeJson(writer, effort);
            },
            .responses => {
                try writer.writeAll(",\"reasoning\":{\"effort\":");
                try writeJson(writer, effort);
                try writer.writeByte('}');
            },
        }
    }

    if (request.response_format) |format| {
        try writer.writeAll(",\"response_format\":");
        switch (format) {
            .text => try writer.writeAll("{\"type\":\"text\"}"),
            .json_object => try writer.writeAll("{\"type\":\"json_object\"}"),
            .json_schema => |schema| {
                try writer.writeAll("{\"type\":\"json_schema\",\"json_schema\":{");
                try writer.writeAll("\"name\":");
                try writeJson(writer, schema.name);
                // description is not in our struct currently, skip or add if needed
                try writer.writeAll(",\"schema\":");
                try writeJson(writer, schema.schema);
                if (schema.strict) {
                    try writer.writeAll(",\"strict\":true");
                }
                try writer.writeAll("}}");
            },
        }
    }

    if (request.presence_penalty != 0) {
        try writer.print(",\"presence_penalty\":{d}", .{request.presence_penalty});
    }
    if (request.frequency_penalty != 0) {
        try writer.print(",\"frequency_penalty\":{d}", .{request.frequency_penalty});
    }

    try writer.writeByte('}');
    return output.toOwnedSlice();
}

fn anthropicRole(role: types.Role) []const u8 {
    return switch (role) {
        .assistant => "assistant",
        else => "user",
    };
}

fn appendSystemText(allocator: std.mem.Allocator, buffer: *std.ArrayList(u8), content: types.MessageContent) !void {
    switch (content) {
        .text => |value| {
            if (buffer.items.len != 0) {
                try buffer.appendSlice(allocator, "\n\n");
            }
            try buffer.appendSlice(allocator, value);
        },
        else => {},
    }
}

fn writeAnthropicContent(writer: *std.Io.Writer, content: types.MessageContent) !void {
    switch (content) {
        .text => |value| {
            try writer.writeAll("[{\"type\":\"text\",\"text\":");
            try writeJson(writer, value);
            try writer.writeAll("}]");
        },
        .image_url => |value| {
            if (utils.parseDataUrl(value)) |data_url| {
                try writer.writeAll("[{\"type\":\"image\",\"source\":{\"type\":\"base64\",\"media_type\":");
                try writeJson(writer, data_url.mime);
                try writer.writeAll(",\"data\":");
                try writeJson(writer, data_url.data);
                try writer.writeAll("}}]");
            } else {
                try writer.writeAll("[{\"type\":\"text\",\"text\":");
                try writeJson(writer, value);
                try writer.writeAll("}]");
            }
        },
        .file => |value| {
            try writer.writeAll("[{\"type\":\"document\",\"title\":");
            try writeJson(writer, value.name);
            try writer.writeAll(",\"source\":{\"type\":\"base64\",\"media_type\":");
            try writeJson(writer, value.mime);
            try writer.writeAll(",\"data\":");
            try writeJson(writer, value.data);
            try writer.writeAll("}}]");
        },
    }
}

pub fn stringifyAnthropicRequest(
    allocator: std.mem.Allocator,
    request: *const types.ChatRequest,
    force_stream: bool,
) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();

    var system_text: std.ArrayList(u8) = .empty;
    defer system_text.deinit(allocator);

    for (request.messages.items) |message| {
        if (message.role == .system) {
            try appendSystemText(allocator, &system_text, message.content);
        }
    }

    const writer = &output.writer;
    try writer.writeByte('{');
    try writer.writeAll("\"model\":");
    try writeJson(writer, request.model);
    try writer.writeAll(",\"messages\":[");

    var written_non_system = false;
    for (request.messages.items) |message| {
        if (message.role == .system) continue;
        if (written_non_system) try writer.writeByte(',');
        written_non_system = true;

        try writer.writeByte('{');
        try writer.writeAll("\"role\":");
        try writeJson(writer, anthropicRole(message.role));
        try writer.writeAll(",\"content\":");
        try writeAnthropicContent(writer, message.content);
        try writer.writeByte('}');
    }

    try writer.writeByte(']');
    try writer.print(",\"max_tokens\":{}", .{request.max_tokens orelse 1024});
    try writer.print(",\"temperature\":{d}", .{request.temperature});
    try writer.print(",\"top_p\":{d}", .{request.top_p});
    try writer.writeAll(",\"stream\":");
    try writer.writeAll(if (force_stream or request.stream) "true" else "false");

    if (system_text.items.len != 0) {
        try writer.writeAll(",\"system\":");
        try writeJson(writer, system_text.items);
    }

    if (request.thinking) {
        try writer.writeAll(",\"thinking\":{\"type\":\"enabled\",\"budget_tokens\":1024}");
    }

    try writer.writeByte('}');
    return output.toOwnedSlice();
}

fn objectField(value: std.json.Value, key: []const u8) ?std.json.Value {
    return switch (value) {
        .object => |object| object.get(key),
        else => null,
    };
}

fn stringValue(value: std.json.Value) ?[]const u8 {
    return switch (value) {
        .string => |text| text,
        else => null,
    };
}

fn u32Value(value: std.json.Value) ?u32 {
    return switch (value) {
        .integer => |number| if (number >= 0 and number <= std.math.maxInt(u32)) @intCast(number) else null,
        .float => |number| if (number >= 0 and number <= @as(f64, @floatFromInt(std.math.maxInt(u32)))) @intFromFloat(number) else null,
        else => null,
    };
}

fn appendIfPresent(allocator: std.mem.Allocator, buffer: *std.ArrayList(u8), maybe_text: ?[]const u8) !void {
    if (maybe_text) |text| {
        try buffer.appendSlice(allocator, text);
    }
}

fn firstArrayItem(value: std.json.Value) ?std.json.Value {
    return switch (value) {
        .array => |array| if (array.items.len == 0) null else array.items[0],
        else => null,
    };
}

fn collectOpenAiContent(allocator: std.mem.Allocator, root: std.json.Value) ![]u8 {
    if (objectField(root, "output_text")) |output_text| {
        if (stringValue(output_text)) |text| {
            return allocator.dupe(u8, text);
        }
    }

    var buffer: std.ArrayList(u8) = .empty;
    errdefer buffer.deinit(allocator);

    if (objectField(root, "output")) |output| {
        switch (output) {
            .array => |array| {
                for (array.items) |item| {
                    if (objectField(item, "content")) |content| {
                        switch (content) {
                            .array => |parts| {
                                for (parts.items) |part| {
                                    try appendIfPresent(allocator, &buffer, if (objectField(part, "text")) |text_value| stringValue(text_value) else null);
                                }
                            },
                            else => {},
                        }
                    }
                }
            },
            else => {},
        }
    }

    if (buffer.items.len == 0) {
        if (objectField(root, "choices")) |choices| {
            switch (choices) {
                .array => |choice_array| {
                    if (choice_array.items.len != 0) {
                        const first_choice = choice_array.items[0];
                        if (objectField(first_choice, "message")) |message| {
                            if (objectField(message, "content")) |content| {
                                switch (content) {
                                    .string => |text| try buffer.appendSlice(allocator, text),
                                    .array => |parts| {
                                        for (parts.items) |part| {
                                            try appendIfPresent(allocator, &buffer, if (objectField(part, "text")) |text_value| stringValue(text_value) else null);
                                        }
                                    },
                                    else => {},
                                }
                            }
                        }
                    }
                },
                else => {},
            }
        }
    }

    return buffer.toOwnedSlice(allocator);
}

fn collectAnthropicContent(allocator: std.mem.Allocator, root: std.json.Value) ![]u8 {
    var buffer: std.ArrayList(u8) = .empty;
    errdefer buffer.deinit(allocator);

    if (objectField(root, "content")) |content| {
        switch (content) {
            .array => |array| {
                for (array.items) |item| {
                    if (objectField(item, "type")) |type_value| {
                        if (stringValue(type_value)) |type_name| {
                            if (std.mem.eql(u8, type_name, "text")) {
                                try appendIfPresent(allocator, &buffer, if (objectField(item, "text")) |text_value| stringValue(text_value) else null);
                            }
                        }
                    }
                }
            },
            else => {},
        }
    }

    return buffer.toOwnedSlice(allocator);
}

pub fn parseOpenAiResponse(allocator: std.mem.Allocator, body: []const u8) !types.Response {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        return types.LlmError.InvalidJson;
    };
    defer parsed.deinit();

    const model = if (objectField(parsed.value, "model")) |value|
        (stringValue(value) orelse "")
    else
        "";

    const content = try collectOpenAiContent(allocator, parsed.value);
    errdefer allocator.free(content);

    var tool_calls: ?std.ArrayList(types.ToolCall) = null;
    if (objectField(parsed.value, "choices")) |choices| {
        if (firstArrayItem(choices)) |choice| {
            if (objectField(choice, "message")) |message| {
                if (objectField(message, "tool_calls")) |tc_array| {
                    switch (tc_array) {
                        .array => |array| {
                            tool_calls = .empty;
                            for (array.items) |tc_item| {
                                const id = if (objectField(tc_item, "id")) |v| stringValue(v) else null;
                                const func_obj = objectField(tc_item, "function");
                                const name = if (func_obj) |v| (if (objectField(v, "name")) |n| stringValue(n) else null) else null;
                                const args = if (func_obj) |v| (if (objectField(v, "arguments")) |a| stringValue(a) else null) else null;

                                if (id != null and name != null and args != null) {
                                    try tool_calls.?.append(allocator, .{
                                        .id = try allocator.dupe(u8, id.?),
                                        .function = .{
                                            .name = try allocator.dupe(u8, name.?),
                                            .arguments = try allocator.dupe(u8, args.?),
                                        },
                                    });
                                }
                            }
                        },
                        else => {},
                    }
                }
            }
        }
    }

    var finish_reason: []const u8 = "stop";
    if (objectField(parsed.value, "status")) |status_value| {
        if (stringValue(status_value)) |status| finish_reason = status;
    }
    if (objectField(parsed.value, "choices")) |choices| {
        if (firstArrayItem(choices)) |choice| {
            if (objectField(choice, "finish_reason")) |value| {
                if (stringValue(value)) |reason| finish_reason = reason;
            }
        }
    }

    var usage = types.Usage{};
    if (objectField(parsed.value, "usage")) |usage_value| {
        if (objectField(usage_value, "prompt_tokens")) |value| {
            usage.prompt_tokens = u32Value(value) orelse 0;
        }
        if (objectField(usage_value, "completion_tokens")) |value| {
            usage.completion_tokens = u32Value(value) orelse 0;
        }
        if (objectField(usage_value, "output_tokens")) |value| {
            usage.completion_tokens = u32Value(value) orelse usage.completion_tokens;
        }
    }

    return .{
        .allocator = allocator,
        .content = content,
        .model = try allocator.dupe(u8, model),
        .usage = usage,
        .tool_calls = tool_calls,
        .finish_reason = try allocator.dupe(u8, finish_reason),
        .raw_json = try allocator.dupe(u8, body),
    };
}

pub fn parseAnthropicResponse(allocator: std.mem.Allocator, body: []const u8) !types.Response {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        return types.LlmError.InvalidJson;
    };
    defer parsed.deinit();

    const content = try collectAnthropicContent(allocator, parsed.value);
    errdefer allocator.free(content);

    const model = if (objectField(parsed.value, "model")) |value|
        (stringValue(value) orelse "")
    else
        "";
    const finish_reason = if (objectField(parsed.value, "stop_reason")) |value|
        (stringValue(value) orelse "stop")
    else
        "stop";

    var usage = types.Usage{};
    if (objectField(parsed.value, "usage")) |usage_value| {
        if (objectField(usage_value, "input_tokens")) |value| {
            usage.prompt_tokens = u32Value(value) orelse 0;
        }
        if (objectField(usage_value, "output_tokens")) |value| {
            usage.completion_tokens = u32Value(value) orelse 0;
        }
    }

    return .{
        .allocator = allocator,
        .content = content,
        .model = try allocator.dupe(u8, model),
        .usage = usage,
        .finish_reason = try allocator.dupe(u8, finish_reason),
        .raw_json = try allocator.dupe(u8, body),
    };
}

pub fn parseOpenAiStreamChunk(allocator: std.mem.Allocator, payload: []const u8) !types.StreamChunk {
    if (std.mem.eql(u8, payload, "[DONE]")) {
        return .{ .content_delta = "", .done = true };
    }

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, payload, .{}) catch {
        return types.LlmError.InvalidJson;
    };
    defer parsed.deinit();

    var done = false;
    var delta: []const u8 = "";

    if (objectField(parsed.value, "type")) |type_value| {
        if (stringValue(type_value)) |type_name| {
            if (std.mem.eql(u8, type_name, "response.completed")) {
                done = true;
            }
        }
    }

    if (objectField(parsed.value, "choices")) |choices| {
        if (firstArrayItem(choices)) |choice| {
            if (objectField(choice, "finish_reason")) |fr| {
                if (stringValue(fr)) |reason| {
                    if (reason.len > 0) done = true;
                } else if (fr != .null) {
                    done = true;
                }
            }
            if (objectField(choice, "delta")) |delta_value| {
                if (objectField(delta_value, "content")) |content_value| {
                    switch (content_value) {
                        .string => |text| delta = text,
                        .array => |parts| {
                            if (parts.items.len != 0) {
                                if (objectField(parts.items[0], "text")) |text_value| {
                                    delta = stringValue(text_value) orelse "";
                                }
                            }
                        },
                        .null => {},
                        else => {},
                    }
                }
            }
        }
    }

    if (delta.len == 0) {
        if (objectField(parsed.value, "delta")) |delta_value| {
            if (objectField(delta_value, "text")) |text_value| {
                delta = stringValue(text_value) orelse "";
            }
        }
    }

    return .{
        .content_delta = if (delta.len == 0) "" else try allocator.dupe(u8, delta),
        .done = done,
    };
}

pub fn parseAnthropicStreamChunk(allocator: std.mem.Allocator, payload: []const u8) !types.StreamChunk {
    if (std.mem.eql(u8, payload, "[DONE]")) {
        return .{ .content_delta = "", .done = true };
    }

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, payload, .{}) catch {
        return types.LlmError.InvalidJson;
    };
    defer parsed.deinit();

    const type_name = if (objectField(parsed.value, "type")) |type_value|
        (stringValue(type_value) orelse "")
    else
        "";

    if (std.mem.eql(u8, type_name, "message_stop")) {
        return .{ .content_delta = "", .done = true };
    }

    var delta: []const u8 = "";
    if (std.mem.eql(u8, type_name, "content_block_delta")) {
        if (objectField(parsed.value, "delta")) |delta_value| {
            if (objectField(delta_value, "text")) |text_value| {
                delta = stringValue(text_value) orelse "";
            }
        }
    }

    return .{
        .content_delta = if (delta.len == 0) "" else try allocator.dupe(u8, delta),
        .done = false,
    };
}
