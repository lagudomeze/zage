//! Integration tests for the OpenAI client.
//!
//! Reads configuration from a JSON file specified by `ZAGE_TEST_CONFIG` env var
//! (default: `.env.test.json`). Copy `.env.test.example.json` and fill in keys.
//!
//! Example config:
//! ```json
//! {
//!     "api_key": "sk-xxx",
//!     "base_url": "https://api.deepseek.com",
//!     "model": "deepseek-chat"
//! }
//! ```
//! `base_url` and `model` are optional — defaults to `https://api.openai.com` and "gpt-4o".
//! The path `/v1/chat/completions` is appended automatically.

const std = @import("std");
const zage = @import("zage");

const OpenAI = zage.llm.OpenAI;
const ModelProvider = zage.llm.ModelProvider;
const ChatMessage = zage.ChatMessage;
const ChatRole = zage.ChatRole;
const FinishReason = zage.FinishReason;

const TestConfig = struct {
    api_key: []const u8,
    base_url: ?[]const u8,
    model: ?[]const u8,
};

/// Load test configuration from the file specified by `ZAGE_TEST_CONFIG`
/// env var, defaulting to `.env.test.json` in the project root.
/// Returns null if the file is missing or unreadable — tests are skipped.
fn loadTestConfig(allocator: std.mem.Allocator) ?TestConfig {
    const config_path = if (std.testing.environ.getAlloc(allocator, "ZAGE_TEST_CONFIG")) |p| p else |_| allocator.dupe(u8, ".env.test.json") catch return null;
    defer allocator.free(config_path);

    const dir = std.Io.Dir.cwd();
    const content = dir.readFileAlloc(std.testing.io, config_path, allocator, @enumFromInt(8192)) catch return null;
    defer allocator.free(content);

    var parsed = std.json.parseFromSlice(std.json.Value, allocator, content, .{}) catch return null;
    defer parsed.deinit();

    const root = parsed.value.object;

    const api_key_val = root.get("api_key") orelse return null;
    const api_key = allocator.dupe(u8, api_key_val.string) catch return null;

    var base_url: ?[]const u8 = null;
    if (root.get("base_url")) |v| {
        base_url = allocator.dupe(u8, v.string) catch return null;
    }

    var model: ?[]const u8 = null;
    if (root.get("model")) |v| {
        model = allocator.dupe(u8, v.string) catch return null;
    }

    return TestConfig{
        .api_key = api_key,
        .base_url = base_url,
        .model = model,
    };
}

/// Free all strings allocated by loadTestConfig.
fn freeTestConfig(allocator: std.mem.Allocator, cfg: TestConfig) void {
    allocator.free(cfg.api_key);
    if (cfg.base_url) |u| allocator.free(u);
    if (cfg.model) |m| allocator.free(m);
}

test "integration - simple chat completion" {
    const allocator = std.testing.allocator;
    const cfg = loadTestConfig(allocator) orelse return;
    defer freeTestConfig(allocator, cfg);

    var openai = OpenAI.init(allocator, std.testing.io, cfg.api_key, cfg.model, cfg.base_url);
    const provider = ModelProvider.init(&openai);

    const messages = [_]ChatMessage{
        .{ .role = .system, .content = "You are a helpful assistant. Answer briefly." },
        .{ .role = .user, .content = "What is the capital of France?" },
    };

    const response = try provider.complete(allocator, &messages, .{ .max_tokens = 50 });
    defer response.deinit(allocator);

    try std.testing.expect(response.choices[0].message.content.len > 0);
    try std.testing.expectEqual(FinishReason.stop, response.choices[0].finish_reason);
    try std.testing.expect(response.usage != null);
    try std.testing.expect(response.usage.?.total_tokens > 0);
}

test "integration - system prompt influences response" {
    const allocator = std.testing.allocator;
    const cfg = loadTestConfig(allocator) orelse return;
    defer freeTestConfig(allocator, cfg);

    var openai = OpenAI.init(allocator, std.testing.io, cfg.api_key, cfg.model, cfg.base_url);
    const provider = ModelProvider.init(&openai);

    // System prompt constrains the assistant's behavior.
    const messages = [_]ChatMessage{
        .{ .role = .system, .content = "You only speak French. Always respond in French." },
        .{ .role = .user, .content = "What is the capital of China?" },
    };

    const response = try provider.complete(allocator, &messages, .{ .max_tokens = 120 });
    defer response.deinit(allocator);

    try std.testing.expect(response.choices.len > 0);
    try std.testing.expect(response.choices[0].message.content.len > 0);
}

test "integration - low temperature produces deterministic output" {
    const allocator = std.testing.allocator;
    const cfg = loadTestConfig(allocator) orelse return;
    defer freeTestConfig(allocator, cfg);

    var openai = OpenAI.init(allocator, std.testing.io, cfg.api_key, cfg.model, cfg.base_url);
    const provider = ModelProvider.init(&openai);

    const messages = [_]ChatMessage{
        .{ .role = .user, .content = "Reply with exactly: hello world" },
    };

    const response = try provider.complete(allocator, &messages, .{
        .temperature = 0.0,
        .max_tokens = 50,
    });
    defer response.deinit(allocator);

    try std.testing.expect(response.choices[0].message.content.len > 0);
}
