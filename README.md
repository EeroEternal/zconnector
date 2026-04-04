# zconnector

Zig LLM Connector is a lightweight, standard-library-first Zig SDK for OpenAI, Anthropic, and compatible gateways. The focus is a small public API, explicit allocation, and adapter-based protocol handling that stays close to Zig's control model.

## Status

This is v0.1.0 and currently targets Zig 0.15+. The code is structured for extension and includes:

- Unified chat API for OpenAI and Anthropic
- OpenAI Responses API with automatic fallback to Chat Completions on 404 and 405
- SSE streaming helpers for both providers
- Multimodal message support for text, image URLs, and file payloads
- Builder-based client configuration with custom headers and timeout fields
- Example programs for chat, streaming, reasoning, file upload, and multi-provider usage

## Install

Add the dependency:

```sh
zig fetch --save git+https://github.com/lipish/zconnector
```

Then wire the module into your build:

```zig
const dep = b.dependency("zconnector", .{
	.target = target,
	.optimize = optimize,
});

exe.root_module.addImport("zconnector", dep.module("zconnector"));
```

For local development in this repository:

```sh
zig build test
zig build
```

## Quick Start

```zig
const std = @import("std");
const zconnector = @import("zconnector");

pub fn main() !void {
	var gpa = std.heap.GeneralPurposeAllocator(.{}){};
	defer _ = gpa.deinit();

	const allocator = gpa.allocator();
	var stdout = std.fs.File.stdout().deprecatedWriter();
	var client = try zconnector.LlmClient.openai(
		allocator,
		std.posix.getenv("OPENAI_API_KEY") orelse return error.MissingApiKey,
		"https://api.openai.com",
	);
	defer client.deinit();

	var request = try zconnector.ChatRequest.new(allocator, "gpt-4.1-mini");
	defer request.deinit();

	_ = try request.addMessage(.system, "You are concise.");
	_ = try request.addMessage(.user, "Explain what Zig is in two sentences.");

	var response = try client.chat(&request);
	defer response.deinit();

	try stdout.print("{s}\n", .{response.content});
}
```

## Public API

```zig
pub const LlmClient = struct {
	pub fn builder(allocator: std.mem.Allocator) Builder;
	pub fn openai(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !LlmClient;
	pub fn anthropic(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !LlmClient;

	pub fn chat(self: *LlmClient, req: *const ChatRequest) !Response;
	pub fn chatStream(self: *LlmClient, req: *const ChatRequest, writer: anytype) !void;
	pub fn responses(self: *LlmClient, req: *const ChatRequest) !Response;
	pub fn deinit(self: *LlmClient) void;
};
```

## Supported Providers

- OpenAI-compatible endpoints via /v1/chat/completions and /v1/responses
- Anthropic-compatible endpoints via /v1/messages
- Custom gateways as long as they preserve one of the above wire protocols

## Environment Variables

- OPENAI_API_KEY: required for OpenAI-compatible examples and the demo binary
- OPENAI_BASE_URL: optional override for OpenAI-compatible gateways, defaults to https://api.openai.com
- ANTHROPIC_API_KEY: required for Anthropic examples
- ANTHROPIC_BASE_URL: optional override for Anthropic-compatible gateways, defaults to https://api.anthropic.com
- ZCONNECTOR_PROVIDER: optional selector for the reasoning example, supports openai and anthropic

## Examples

- `zig build simple_chat`
- `zig build streaming`
- `zig build reasoning`
- `zig build file_upload -- ./path/to/image.png`
- `zig build multi_provider`

The repository also includes a demo binary at `zig build run`.

## Verification

Use the repository root for all commands below:

```sh
zig build test
zig build
zig build run
```

For provider-specific smoke checks:

```sh
OPENAI_API_KEY=... zig build simple_chat
OPENAI_API_KEY=... zig build streaming
OPENAI_API_KEY=... zig build file_upload -- ./path/to/image.png
ANTHROPIC_API_KEY=... zig build multi_provider
```

## Design Notes

- No third-party Zig dependencies are required.
- The current codebase is verified against Zig 0.15.2.
- Request and response payloads are explicitly allocated and deinitialized by the caller.
- Timeout is part of the public client configuration and preserved across adapters.
- File payloads are currently expected to carry base64-encoded content when serialized as inline data URLs.
- SSE streaming is parsed line-by-line from `data:` frames.

## Compared With The Rust Version

Compared with `lipish/llm-connector`, this Zig version keeps the same adapter model but leans harder into:

- Explicit allocator ownership
- Minimal abstraction around `std.http.Client`
- Easily inspectable JSON serialization code
- Small-module organization for comptime-friendly extension

## License

MIT. See `LICENSE`.