# zconnector

zconnector is a Zig LLM SDK for OpenAI-compatible APIs, Anthropic, and DeepSeek-style gateways.

## Compatibility

- Minimum Zig version: `0.15.2`
- CI is pinned to Zig `0.15.2`
- The current API is built around `std.Io` and explicit allocators

## Features

- Unified chat API for OpenAI and Anthropic providers
- OpenAI Responses API with fallback to Chat Completions
- SSE streaming helpers for real-time token output
- Tool calling and structured output support
- File and multimodal payload support

## Install

Add the dependency from GitHub:

```bash
zig fetch --save git+https://github.com/EeroEternal/zconnector#v0.3.0
```

Then wire it into your `build.zig`:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zconnector_dep = b.dependency("zconnector", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "my-app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.root_module.addImport("zconnector", zconnector_dep.module("zconnector"));
    b.installArtifact(exe);
}
```

## Quick Start

```zig
const std = @import("std");
const zconnector = @import("zconnector");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const api_key = env_map.get("OPENAI_API_KEY") orelse return error.MissingApiKey;
    const io: std.Io = .{};

    var client = try zconnector.LlmClient.openai(
        allocator,
        api_key,
        "https://api.openai.com",
        io,
    );
    defer client.deinit();

    var request = try zconnector.ChatRequest.new(allocator, "gpt-4o-mini");
    defer request.deinit();

    _ = try request.addMessage(.user, "Give me a one-line introduction to Zig.");

    var response = try client.chat(&request, .{ .io = io });
    defer response.deinit();

    var stdout = std.fs.File.stdout().deprecatedWriter();
    try stdout.print("{s}\n", .{response.content});
}
```

## Examples

From the repository root:

```bash
export OPENAI_API_KEY=sk-...
zig build simple_chat
zig build streaming -- --model deepseek-chat
zig build reasoning
```

## Local Development

```bash
zig build test
zig build
```

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