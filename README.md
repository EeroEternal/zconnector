# zconnector

Zig LLM Connector (zconnector) is a lightweight, high-performance Zig SDK for OpenAI, Anthropic, and DeepSeek. Built for **Zig 0.16.0 (Nightly)**, it leverages the new **Colorless I/O** model for efficient, non-blocking streaming and network operations.

## Status

Version **0.3.0** is optimized for the latest Zig compiler. It features:

- **Colorless I/O**: Native support for Zig 0.16.0 `std.Io` and `std.http.Client`.
- **DeepSeek & OpenAI Compatibility**: Full support for reasoning models and SSE streaming.
- **Unified API**: One interface for Chat, Streaming, and Tool Calling across providers.
- **Explicit Ownership**: Zero-copy where possible, explicit allocators everywhere.

## Install

Add `zconnector` to your `build.zig.zon`:

```bash
zig fetch --save git+https://github.com/lipish/zconnector
```

## Setup

In your `build.zig`, import and wire the module:

```zig
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 1. Resolve the dependency
    const zconnector_dep = b.dependency("zconnector", .{
        .target = target,
        .optimize = optimize,
    });

    // 2. Add the import to your executable or library
    const exe = b.addExecutable(.{
        .name = "my-app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zconnector", zconnector_dep.module("zconnector"));
    
    b.installArtifact(exe);
}
```

## Quick Start

```zig
const std = @import("std");
const zc = @import("zconnector");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = zc.LlmClient.init(allocator, .{
        .provider = .openai,
        .api_key = "sk-...",
    });
    defer client.deinit();

    const response = try client.chat(.{
        .model = "gpt-4o",
        .messages = &.{
            .{ .role = .user, .content = "Hello, Zig!" },
        },
    });
    defer response.deinit();

    std.debug.print("AI: {s}\n", .{response.content.?});
}
```

## Examples

Run any example from the repository root:

```bash
# Set your API Key
export OPENAI_API_KEY=sk-...

# Run streaming demo
zig build streaming -- --model gpt-4o

# Run reasoning demo (DeepSeek/O1)
zig build reasoning -- --model deepseek-reasoner
```

Full list of examples available in the [examples/](examples/) directory.

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