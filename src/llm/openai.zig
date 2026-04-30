//! OpenAI-compatible LLM client implementation.
//!
//! Uses only the Zig standard library for JSON serialization — no external
//! dependencies. Request JSON is streamed directly to the HTTP body writer;
//! response parsing uses `std.json.Parsed` for automatic arena management.

const std = @import("std");
const core = @import("../core/types.zig");
const ModelProvider = @import("provider.zig").ModelProvider;

const ChatMessage = core.ChatMessage;
const ChatRole = core.ChatRole;
const GenerationOptions = core.GenerationOptions;
const FinishReason = core.FinishReason;
const Usage = core.Usage;
const ToolCall = core.ToolCall;
const ToolDef = core.ToolDef;
const EmbeddingRequest = core.EmbeddingRequest;
const EmbeddingResponse = core.EmbeddingResponse;
const Embedding = core.Embedding;
const ModelList = core.ModelList;
const Model = core.Model;
const LLMResponse = core.LLMResponse;
const LLMError = core.LLMError;

/// Default OpenAI API base URL. The `/v1/chat/completions` path is appended
/// automatically in `complete()`.
pub const DEFAULT_BASE_URL = "https://api.openai.com";

/// Default model identifier.
pub const DEFAULT_MODEL = "gpt-4o";

/// OpenAI-compatible chat completions client.
pub const OpenAI = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
    model: []const u8,
    base_url: []const u8,

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        api_key: []const u8,
        model: ?[]const u8,
        base_url: ?[]const u8,
    ) OpenAI {
        return .{
            .allocator = allocator,
            .io = io,
            .api_key = api_key,
            .model = model orelse DEFAULT_MODEL,
            .base_url = base_url orelse DEFAULT_BASE_URL,
        };
    }

    pub fn deinit(_: *OpenAI) void {}

    /// Execute a chat completion request.
    pub fn complete(
        self: *OpenAI,
        allocator: std.mem.Allocator,
        messages: []const ChatMessage,
        opts: GenerationOptions,
    ) LLMError!LLMResponse {
        if (messages.len == 0) return LLMError.InvalidInput;

        const payload = RequestBody{
            .model = self.model,
            .messages = messages,
            .temperature = opts.temperature,
            .max_tokens = opts.max_tokens,
            .top_p = opts.top_p,
            .stop = opts.stop,
            .seed = opts.seed,
        };

        const body = try self.doPost(allocator, "/v1/chat/completions", payload);
        return parseResponse(allocator, body);
    }

    /// Create an embedding vector for the given input text.
    pub fn createEmbedding(
        self: *OpenAI,
        allocator: std.mem.Allocator,
        request: EmbeddingRequest,
    ) LLMError!EmbeddingResponse {
        const body = try self.doPost(allocator, "/v1/embeddings", request);
        return parseEmbeddingResponse(allocator, body);
    }

    /// List all available models.
    pub fn listModels(
        self: *OpenAI,
        allocator: std.mem.Allocator,
    ) LLMError!ModelList {
        const body = try self.doGet(allocator, "/v1/models");
        return parseModelList(allocator, body);
    }

    // -- internal HTTP helpers ------------------------------------------------

    fn doPost(self: *const OpenAI, allocator: std.mem.Allocator, path: []const u8, payload: anytype) LLMError![]u8 {
        const uri = buildUri(self.base_url, path) catch return LLMError.InvalidInput;
        const auth = buildAuthHeader(self.api_key) catch return LLMError.InvalidInput;

        var http: std.http.Client = .{ .allocator = allocator, .io = self.io };
        defer http.deinit();

        var req = http.request(.POST, uri, .{
            .headers = .{
                .authorization = .{ .override = &auth },
                .content_type = .{ .override = "application/json" },
            },
        }) catch return LLMError.NetworkError;
        defer req.deinit();

        req.transfer_encoding = .chunked;
        var io_buf: [4096]u8 = undefined;
        var bw = req.sendBodyUnflushed(&io_buf) catch return LLMError.NetworkError;
        std.json.Stringify.value(payload, .{ .emit_null_optional_fields = false }, &bw.writer) catch return LLMError.NetworkError;
        bw.end() catch return LLMError.NetworkError;
        req.connection.?.flush() catch return LLMError.NetworkError;

        return self.receiveResponse(allocator, &req);
    }

    fn doGet(self: *const OpenAI, allocator: std.mem.Allocator, path: []const u8) LLMError![]u8 {
        const uri = buildUri(self.base_url, path) catch return LLMError.InvalidInput;
        const auth = buildAuthHeader(self.api_key) catch return LLMError.InvalidInput;

        var http: std.http.Client = .{ .allocator = allocator, .io = self.io };
        defer http.deinit();

        var req = http.request(.GET, uri, .{
            .headers = .{ .authorization = .{ .override = &auth } },
        }) catch return LLMError.NetworkError;
        defer req.deinit();

        req.sendBodiless() catch return LLMError.NetworkError;

        return self.receiveResponse(allocator, &req);
    }

    fn receiveResponse(_: *const OpenAI, allocator: std.mem.Allocator, req: *std.http.Client.Request) LLMError![]u8 {
        var redirect_buf: [4096]u8 = undefined;
        var response = req.receiveHead(&redirect_buf) catch return LLMError.NetworkError;

        if (response.head.status != .ok) {
            var err_buf: [4096]u8 = undefined;
            var transfer_buf: [1024]u8 = undefined;
            const err_len = response.reader(&transfer_buf).readSliceShort(&err_buf) catch 0;
            std.log.warn("OpenAI HTTP {s}: {s}", .{ @tagName(response.head.status), err_buf[0..err_len] });
            return switch (response.head.status) {
                .unauthorized, .forbidden => LLMError.ApiError,
                .too_many_requests => LLMError.ApiError,
                .bad_request => LLMError.InvalidInput,
                else => LLMError.HttpError,
            };
        }

        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        var transfer_buf: [4096]u8 = undefined;
        return response.reader(&transfer_buf).allocRemaining(arena.allocator(), @enumFromInt(64 * 1024)) catch return LLMError.NetworkError;
    }
};

// -- standalone helpers -------------------------------------------------------

fn buildUri(base_url: []const u8, path: []const u8) !std.Uri {
    var url_buf: [2048]u8 = undefined;
    const endpoint = try std.fmt.bufPrint(&url_buf, "{s}{s}", .{ base_url, path });
    return std.Uri.parse(endpoint);
}

fn buildAuthHeader(api_key: []const u8) ![512]u8 {
    var auth_buf: [512]u8 = undefined;
    _ = try std.fmt.bufPrint(&auth_buf, "Bearer {s}", .{api_key});
    return auth_buf;
}

// ---------------------------------------------------------------------------
// JSON request body
// ---------------------------------------------------------------------------

const RequestBody = struct {
    model: []const u8,
    messages: []const ChatMessage,
    temperature: ?f32 = null,
    max_tokens: ?u32 = null,
    top_p: ?f32 = null,
    stop: ?[]const []const u8 = null,
    seed: ?u32 = null,
};

/// Serialize a chat completion request to JSON.
/// Exposed for testing; `complete()` streams JSON directly to the HTTP writer.
pub fn buildRequestBody(
    allocator: std.mem.Allocator,
    model: []const u8,
    messages: []const ChatMessage,
    opts: GenerationOptions,
) LLMError![]u8 {
    const payload = RequestBody{
        .model = model,
        .messages = messages,
        .temperature = opts.temperature,
        .max_tokens = opts.max_tokens,
        .top_p = opts.top_p,
        .stop = opts.stop,
        .seed = opts.seed,
    };
    return std.json.Stringify.valueAlloc(allocator, payload, .{ .emit_null_optional_fields = false }) catch return LLMError.InvalidInput;
}

// ---------------------------------------------------------------------------
// JSON response parsing
// ---------------------------------------------------------------------------

/// Matches the OpenAI chat completions response JSON.
const ResponseBody = struct {
    id: []const u8,
    object: []const u8,
    created: u64,
    model: []const u8,
    system_fingerprint: ?[]const u8 = null,
    service_tier: ?[]const u8 = null,
    choices: []struct {
        index: u32 = 0,
        message: struct {
            role: []const u8,
            content: []const u8,
            tool_calls: ?[]struct {
                id: []const u8,
                @"type": []const u8,
                function: struct {
                    name: []const u8,
                    arguments: []const u8,
                },
            } = null,
            refusal: ?[]const u8 = null,
        },
        finish_reason: []const u8 = "stop",
    },
    usage: ?struct {
        prompt_tokens: u32,
        completion_tokens: u32,
        total_tokens: u32,
    } = null,
};

/// Parse a successful (HTTP 200) OpenAI response body into an `LLMResponse`.
pub fn parseResponse(allocator: std.mem.Allocator, body: []const u8) LLMError!LLMResponse {
    var parsed = std.json.parseFromSlice(ResponseBody, allocator, body, .{ .ignore_unknown_fields = true }) catch {
        return LLMError.ParseError;
    };
    defer parsed.deinit();

    const v = parsed.value;
    if (v.choices.len == 0) return LLMError.UnexpectedResponse;

    var result_choices = allocator.alloc(LLMResponse.Choice, v.choices.len) catch return LLMError.ParseError;
    for (v.choices, 0..) |c, i| {
        const content = allocator.dupe(u8, c.message.content) catch return LLMError.ParseError;
        const role = allocator.dupe(u8, c.message.role) catch return LLMError.ParseError;

        var tool_calls: ?[]const ToolCall = null;
        if (c.message.tool_calls) |tcs| {
            var result_tcs = allocator.alloc(ToolCall, tcs.len) catch return LLMError.ParseError;
            for (tcs, 0..) |tc, j| {
                result_tcs[j] = .{
                    .id = allocator.dupe(u8, tc.id) catch return LLMError.ParseError,
                    .@"type" = allocator.dupe(u8, tc.@"type") catch return LLMError.ParseError,
                    .function = .{
                        .name = allocator.dupe(u8, tc.function.name) catch return LLMError.ParseError,
                        .arguments = allocator.dupe(u8, tc.function.arguments) catch return LLMError.ParseError,
                    },
                };
            }
            tool_calls = result_tcs;
        }

        result_choices[i] = .{
            .index = c.index,
            .message = .{
                .role = role,
                .content = content,
                .tool_calls = tool_calls,
                .refusal = if (c.message.refusal) |r| allocator.dupe(u8, r) catch return LLMError.ParseError else null,
            },
            .finish_reason = parseFinishReason(c.finish_reason),
        };
    }

    return LLMResponse{
        .id = allocator.dupe(u8, v.id) catch return LLMError.ParseError,
        .object = allocator.dupe(u8, v.object) catch return LLMError.ParseError,
        .created = v.created,
        .model = allocator.dupe(u8, v.model) catch return LLMError.ParseError,
        .system_fingerprint = if (v.system_fingerprint) |s| allocator.dupe(u8, s) catch return LLMError.ParseError else null,
        .service_tier = if (v.service_tier) |s| allocator.dupe(u8, s) catch return LLMError.ParseError else null,
        .choices = result_choices,
        .usage = if (v.usage) |u| Usage{
            .prompt_tokens = u.prompt_tokens,
            .completion_tokens = u.completion_tokens,
            .total_tokens = u.total_tokens,
        } else null,
    };
}

// ---------------------------------------------------------------------------
// Embedding response parsing
// ---------------------------------------------------------------------------

const EmbeddingResponseBody = struct {
    object: []const u8,
    data: []struct {
        index: u32,
        embedding: []const f32,
        object: []const u8,
    },
    model: []const u8,
    usage: struct {
        prompt_tokens: u32,
        total_tokens: u32,
    },
};

fn parseEmbeddingResponse(allocator: std.mem.Allocator, body: []const u8) LLMError!EmbeddingResponse {
    var parsed = std.json.parseFromSlice(EmbeddingResponseBody, allocator, body, .{ .ignore_unknown_fields = true }) catch {
        return LLMError.ParseError;
    };
    defer parsed.deinit();

    const v = parsed.value;
    var data = allocator.alloc(Embedding, v.data.len) catch return LLMError.ParseError;
    for (v.data, 0..) |e, i| {
        const emb = allocator.alloc(f32, e.embedding.len) catch return LLMError.ParseError;
        @memcpy(emb, e.embedding);
        data[i] = .{
            .index = e.index,
            .embedding = emb,
            .object = allocator.dupe(u8, e.object) catch return LLMError.ParseError,
        };
    }

    return EmbeddingResponse{
        .object = allocator.dupe(u8, v.object) catch return LLMError.ParseError,
        .data = data,
        .model = allocator.dupe(u8, v.model) catch return LLMError.ParseError,
        .usage = .{
            .prompt_tokens = v.usage.prompt_tokens,
            .completion_tokens = 0,
            .total_tokens = v.usage.total_tokens,
        },
    };
}

// ---------------------------------------------------------------------------
// Model list response parsing
// ---------------------------------------------------------------------------

const ModelListBody = struct {
    object: []const u8,
    data: []struct {
        id: []const u8,
        object: []const u8,
        created: u64,
        owned_by: []const u8,
    },
};

fn parseModelList(allocator: std.mem.Allocator, body: []const u8) LLMError!ModelList {
    var parsed = std.json.parseFromSlice(ModelListBody, allocator, body, .{ .ignore_unknown_fields = true }) catch {
        return LLMError.ParseError;
    };
    defer parsed.deinit();

    const v = parsed.value;
    var data = allocator.alloc(Model, v.data.len) catch return LLMError.ParseError;
    for (v.data, 0..) |m, i| {
        data[i] = .{
            .id = allocator.dupe(u8, m.id) catch return LLMError.ParseError,
            .object = allocator.dupe(u8, m.object) catch return LLMError.ParseError,
            .created = m.created,
            .owned_by = allocator.dupe(u8, m.owned_by) catch return LLMError.ParseError,
        };
    }

    return ModelList{
        .object = allocator.dupe(u8, v.object) catch return LLMError.ParseError,
        .data = data,
    };
}

// ---------------------------------------------------------------------------

fn parseFinishReason(raw: []const u8) FinishReason {
    if (std.mem.eql(u8, raw, "stop")) return .stop;
    if (std.mem.eql(u8, raw, "length")) return .length;
    if (std.mem.eql(u8, raw, "content_filter")) return .content_filter;
    if (std.mem.eql(u8, raw, "tool_calls")) return .tool_calls;
    if (std.mem.eql(u8, raw, "refusal")) return .refusal;
    return .unknown;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "buildRequestBody - minimal" {
    const allocator = std.testing.allocator;
    const json = try buildRequestBody(allocator, "gpt-4o", &.{}, .{});
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"model\":\"gpt-4o\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"messages\":[]") != null);
}

test "buildRequestBody - full options" {
    const allocator = std.testing.allocator;
    const msgs = [_]ChatMessage{
        .{ .role = .system, .content = "You are a bot." },
        .{ .role = .user, .content = "Hi!" },
    };
    const opts = GenerationOptions{
        .temperature = 0.7,
        .max_tokens = 256,
        .top_p = 0.9,
        .seed = 42,
    };
    const json = try buildRequestBody(allocator, "gpt-4o", &msgs, opts);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"model\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"temperature\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"max_tokens\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"top_p\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"seed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"system\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"user\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"stop\"") == null);
}

test "buildRequestBody - with stop sequences" {
    const allocator = std.testing.allocator;
    const stop = [_][]const u8{ "\n", "END" };
    const opts = GenerationOptions{ .stop = &stop };
    const json = try buildRequestBody(allocator, "gpt-4o", &.{}, opts);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"stop\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"\\n\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"END\"") != null);
}

test "parseResponse - valid response" {
    const allocator = std.testing.allocator;
    const body =
        \\{
        \\  "id": "chatcmpl-xxx",
        \\  "object": "chat.completion",
        \\  "created": 1234567890,
        \\  "model": "gpt-4o",
        \\  "choices": [
        \\    {
        \\      "index": 0,
        \\      "message": {
        \\        "role": "assistant",
        \\        "content": "Hello! How can I help?"
        \\      },
        \\      "finish_reason": "stop"
        \\    }
        \\  ],
        \\  "usage": {
        \\    "prompt_tokens": 10,
        \\    "completion_tokens": 5,
        \\    "total_tokens": 15
        \\  }
        \\}
    ;

    const resp = try parseResponse(allocator, body);
    defer resp.deinit(allocator);

    try std.testing.expectEqualStrings("Hello! How can I help?", resp.choices[0].message.content);
    try std.testing.expectEqual(FinishReason.stop, resp.choices[0].finish_reason);
    try std.testing.expect(resp.usage != null);
    try std.testing.expectEqual(@as(u32, 10), resp.usage.?.prompt_tokens);
    try std.testing.expectEqual(@as(u32, 5), resp.usage.?.completion_tokens);
    try std.testing.expectEqual(@as(u32, 15), resp.usage.?.total_tokens);
}

test "parseResponse - missing usage" {
    const allocator = std.testing.allocator;
    const body =
        \\{
        \\  "id": "chatcmpl-xxx",
        \\  "object": "chat.completion",
        \\  "created": 1,
        \\  "model": "gpt-4o",
        \\  "choices": [
        \\    {
        \\      "message": { "role": "assistant", "content": "Hi" },
        \\      "finish_reason": "length"
        \\    }
        \\  ]
        \\}
    ;

    const resp = try parseResponse(allocator, body);
    defer resp.deinit(allocator);

    try std.testing.expectEqualStrings("Hi", resp.choices[0].message.content);
    try std.testing.expectEqual(FinishReason.length, resp.choices[0].finish_reason);
    try std.testing.expect(resp.usage == null);
}

test "parseResponse - empty choices" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(LLMError.UnexpectedResponse, parseResponse(allocator,
        \\{"id":"x","object":"chat.completion","created":1,"model":"x","choices":[]}
    ));
}

test "parseResponse - invalid JSON" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(LLMError.ParseError, parseResponse(allocator, "not json"));
}

test "parseResponse - finish_reason mapping" {
    const allocator = std.testing.allocator;

    {
        const body = "{\"id\":\"x\",\"object\":\"chat.completion\",\"created\":1,\"model\":\"x\",\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"x\"},\"finish_reason\":\"stop\"}]}";
        const resp = try parseResponse(allocator, body);
        defer resp.deinit(allocator);
        try std.testing.expectEqual(FinishReason.stop, resp.choices[0].finish_reason);
    }
    {
        const body = "{\"id\":\"x\",\"object\":\"chat.completion\",\"created\":1,\"model\":\"x\",\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"x\"},\"finish_reason\":\"tool_calls\"}]}";
        const resp = try parseResponse(allocator, body);
        defer resp.deinit(allocator);
        try std.testing.expectEqual(FinishReason.tool_calls, resp.choices[0].finish_reason);
    }
    {
        const body = "{\"id\":\"x\",\"object\":\"chat.completion\",\"created\":1,\"model\":\"x\",\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"x\"},\"finish_reason\":\"content_filter\"}]}";
        const resp = try parseResponse(allocator, body);
        defer resp.deinit(allocator);
        try std.testing.expectEqual(FinishReason.content_filter, resp.choices[0].finish_reason);
    }
    {
        const body = "{\"id\":\"x\",\"object\":\"chat.completion\",\"created\":1,\"model\":\"x\",\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"x\"},\"finish_reason\":\"random_new\"}]}";
        const resp = try parseResponse(allocator, body);
        defer resp.deinit(allocator);
        try std.testing.expectEqual(FinishReason.unknown, resp.choices[0].finish_reason);
    }
}

test "OpenAI.init defaults" {
    const allocator = std.testing.allocator;
    const oa = OpenAI.init(allocator, std.testing.io, "sk-test-key", null, null);
    try std.testing.expectEqualStrings("sk-test-key", oa.api_key);
    try std.testing.expectEqualStrings(DEFAULT_MODEL, oa.model);
    try std.testing.expectEqualStrings(DEFAULT_BASE_URL, oa.base_url);
}

test "OpenAI.init custom model and url" {
    const allocator = std.testing.allocator;
    const oa = OpenAI.init(allocator, std.testing.io, "sk-custom", "gpt-3.5-turbo", "https://custom.api/v1");
    try std.testing.expectEqualStrings("gpt-3.5-turbo", oa.model);
    try std.testing.expectEqualStrings("https://custom.api/v1", oa.base_url);
}

test "ModelProvider.init wraps OpenAI correctly" {
    const allocator = std.testing.allocator;
    var oa = OpenAI.init(allocator, std.testing.io, "sk-test", null, null);
    const provider = ModelProvider.init(&oa);
    try std.testing.expect(@intFromPtr(provider.ptr) == @intFromPtr(&oa));
}

// Integration tests: src/llm/openai_integration.zig
// Run: zig build integration-test
