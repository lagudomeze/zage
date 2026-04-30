//! OpenAI-compatible LLM client implementation.
//!
//! JSON serialization uses the `serde` library for robust parsing and
//! zero-copy borrowed deserialization of response content.

const std = @import("std");
const serde = @import("serde");
const core = @import("../core/types.zig");
const ModelProvider = @import("provider.zig").ModelProvider;

const ChatMessage = core.ChatMessage;
const ChatRole = core.ChatRole;
const GenerationOptions = core.GenerationOptions;
const FinishReason = core.FinishReason;
const Usage = core.Usage;
const LLMResponse = core.LLMResponse;
const LLMError = core.LLMError;
/// Default OpenAI API base URL. The `/v1/chat/completions` path is appended
/// automatically in `complete()`.
pub const DEFAULT_BASE_URL = "https://api.openai.com";

/// Default model identifier.
pub const DEFAULT_MODEL = "gpt-4o";

/// OpenAI-compatible chat completions client.
///
/// Wraps `std.http.Client` to communicate with OpenAI or any API that
/// implements the same chat completions protocol (e.g. local vLLM, Ollama
/// with the OpenAI compatibility layer).
pub const OpenAI = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
    model: []const u8,
    base_url: []const u8,

    /// Create a new OpenAI client.
    ///
    /// In tests, pass `std.testing.io`. In production, pass `init.io`
    /// from `std.process.Init`.
    /// `model` defaults to "gpt-4o". `base_url` defaults to the official
    /// OpenAI API endpoint. Pass a custom URL to target compatible services.
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

    /// No-op; the HTTP client is created per-request.
    pub fn deinit(_: *OpenAI) void {}

    /// Execute a chat completion request.
    ///
    /// Satisfies the `ModelProvider` vtable interface. Use
    /// `ModelProvider.init(&openai)` to get a runtime-polymorphic wrapper.
    pub fn complete(
        self: *OpenAI,
        allocator: std.mem.Allocator,
        messages: []const ChatMessage,
        opts: GenerationOptions,
    ) LLMError!LLMResponse {
        if (messages.len == 0) return LLMError.InvalidInput;

        // Build JSON request body.
        const req_json = try buildRequestBody(allocator, self.model, messages, opts);
        defer allocator.free(req_json);

        // Construct the full endpoint URL: {base_url}/v1/chat/completions.
        var url_buf: [2048]u8 = undefined;
        const endpoint = std.fmt.bufPrint(&url_buf, "{s}/v1/chat/completions", .{self.base_url}) catch return LLMError.InvalidInput;
        const uri = std.Uri.parse(endpoint) catch return LLMError.InvalidInput;

        // Build the Authorization header.
        var auth_buf: [512]u8 = undefined;
        const bearer = std.fmt.bufPrint(&auth_buf, "Bearer {s}", .{self.api_key}) catch return LLMError.InvalidInput;

        // Send HTTP request.
        var http: std.http.Client = .{ .allocator = allocator, .io = self.io };
        defer http.deinit();

        var req = http.request(.POST, uri, .{
            .headers = .{
                .authorization = .{ .override = bearer },
                .content_type = .{ .override = "application/json" },
            },
        }) catch return LLMError.NetworkError;
        defer req.deinit();

        req.sendBodyComplete(req_json) catch return LLMError.NetworkError;

        var redirect_buf: [4096]u8 = undefined;
        var response = req.receiveHead(&redirect_buf) catch return LLMError.NetworkError;

        if (response.head.status != .ok) {
            // Read error body into a stack buffer for logging.
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

        // Read the response body and parse it. Use an arena for the HTTP
        // buffer and serde's temporary allocations, then dupe the result
        // into the caller's allocator.
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const arena_alloc = arena.allocator();

        const max_body: usize = if (response.head.content_length) |cl|
            @intCast(cl)
        else
            64 * 1024;
        var resp_body: std.ArrayList(u8) = .empty;
        defer resp_body.deinit(arena_alloc);
        resp_body.ensureTotalCapacityPrecise(arena_alloc, max_body) catch return LLMError.NetworkError;

        var transfer_buf: [4096]u8 = undefined;
        var body_reader = response.reader(&transfer_buf);
        while (true) {
            const n = body_reader.readSliceShort(resp_body.unusedCapacitySlice()) catch return LLMError.NetworkError;
            if (n == 0) break;
            resp_body.items.len += n;
        }

        return parseResponse(allocator, arena_alloc, resp_body.items);
    }
};

// ---------------------------------------------------------------------------
// JSON — request serialization (serde)
// ---------------------------------------------------------------------------

/// Shape of the chat completion request body sent to the API.
const RequestBody = struct {
    model: []const u8,
    messages: []const ChatMessage,
    temperature: ?f32 = null,
    max_tokens: ?u32 = null,
    top_p: ?f32 = null,
    stop: ?[]const []const u8 = null,
    seed: ?u32 = null,
};

/// Serialize a chat completion request to JSON using serde.
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
    return serde.json.toSlice(allocator, payload) catch return LLMError.InvalidInput;
}

// ---------------------------------------------------------------------------
// JSON — response deserialization (serde)
// ---------------------------------------------------------------------------

/// Matches the "usage" object in OpenAI responses.
const ResponseUsage = struct {
    prompt_tokens: u32,
    completion_tokens: u32,
    total_tokens: u32,
};

/// Matches a single "choice" in OpenAI responses.
const ResponseChoice = struct {
    message: struct {
        content: []const u8,
    },
    finish_reason: []const u8 = "stop",
};

/// Top-level OpenAI chat completion response.
const ResponseBody = struct {
    choices: []const ResponseChoice,
    usage: ?ResponseUsage = null,
};

/// Parse a successful (HTTP 200) OpenAI response body into an `LLMResponse`.
///
/// `scratch_alloc` is used for serde's internal allocations (freed by the
/// caller after this function returns). `result_alloc` owns the returned
/// `LLMResponse` fields.
pub fn parseResponse(
    result_alloc: std.mem.Allocator,
    scratch_alloc: std.mem.Allocator,
    body: []const u8,
) LLMError!LLMResponse {
    const parsed = serde.json.fromSlice(ResponseBody, scratch_alloc, body) catch {
        return LLMError.ParseError;
    };

    if (parsed.choices.len == 0) return LLMError.UnexpectedResponse;

    var choices = result_alloc.alloc(LLMResponse.Choice, parsed.choices.len) catch return LLMError.ParseError;
    for (parsed.choices, 0..) |c, i| {
        const content = result_alloc.dupe(u8, c.message.content) catch return LLMError.ParseError;
        choices[i] = .{
            .message = .{ .content = content },
            .finish_reason = parseFinishReason(c.finish_reason),
        };
    }

    return LLMResponse{
        .choices = choices,
        .usage = if (parsed.usage) |u| Usage{
            .prompt_tokens = u.prompt_tokens,
            .completion_tokens = u.completion_tokens,
            .total_tokens = u.total_tokens,
        } else null,
    };
}

/// Map a string finish reason to the enum.
fn parseFinishReason(raw: []const u8) FinishReason {
    if (std.mem.eql(u8, raw, "stop")) return .stop;
    if (std.mem.eql(u8, raw, "length")) return .length;
    if (std.mem.eql(u8, raw, "content_filter")) return .content_filter;
    if (std.mem.eql(u8, raw, "tool_calls")) return .tool_calls;
    return .unknown;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "buildRequestBody - minimal" {
    const allocator = std.testing.allocator;
    const json = try buildRequestBody(allocator, "gpt-4o", &.{}, .{});
    defer allocator.free(json);

    // Should contain the model field.
    try std.testing.expect(std.mem.indexOf(u8, json, "\"model\":\"gpt-4o\"") != null);
    // Should contain empty messages array.
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
    // With serde, null optional fields appear as "field":null in the JSON.
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

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const resp = try parseResponse(allocator, arena.allocator(), body);
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
        \\  "choices": [
        \\    {
        \\      "message": { "content": "Hi" },
        \\      "finish_reason": "length"
        \\    }
        \\  ]
        \\}
    ;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const resp = try parseResponse(allocator, arena.allocator(), body);
    defer resp.deinit(allocator);

    try std.testing.expectEqualStrings("Hi", resp.choices[0].message.content);
    try std.testing.expectEqual(FinishReason.length, resp.choices[0].finish_reason);
    try std.testing.expect(resp.usage == null);
}

test "parseResponse - empty choices" {
    const allocator = std.testing.allocator;
    const body = "{\"choices\":[]}";

    var arena2 = std.heap.ArenaAllocator.init(allocator);
    defer arena2.deinit();
    try std.testing.expectError(LLMError.UnexpectedResponse, parseResponse(allocator, arena2.allocator(), body));
}

test "parseResponse - invalid JSON" {
    const allocator = std.testing.allocator;

    var arena_invalid = std.heap.ArenaAllocator.init(allocator);
    defer arena_invalid.deinit();
    try std.testing.expectError(LLMError.ParseError, parseResponse(allocator, arena_invalid.allocator(), "not json"));
}

test "parseResponse - finish_reason mapping" {
    const allocator = std.testing.allocator;

    {
        const body =
            \\{"choices":[{"message":{"content":"x"},"finish_reason":"stop"}]}
        ;
        var arena1 = std.heap.ArenaAllocator.init(allocator);
        defer arena1.deinit();
        const resp = try parseResponse(allocator, arena1.allocator(), body);
        defer resp.deinit(allocator);
        try std.testing.expectEqual(FinishReason.stop, resp.choices[0].finish_reason);
    }
    {
        const body =
            \\{"choices":[{"message":{"content":"x"},"finish_reason":"tool_calls"}]}
        ;
        var arena2 = std.heap.ArenaAllocator.init(allocator);
        defer arena2.deinit();
        const resp = try parseResponse(allocator, arena2.allocator(), body);
        defer resp.deinit(allocator);
        try std.testing.expectEqual(FinishReason.tool_calls, resp.choices[0].finish_reason);
    }
    {
        const body =
            \\{"choices":[{"message":{"content":"x"},"finish_reason":"content_filter"}]}
        ;
        var arena3 = std.heap.ArenaAllocator.init(allocator);
        defer arena3.deinit();
        const resp = try parseResponse(allocator, arena3.allocator(), body);
        defer resp.deinit(allocator);
        try std.testing.expectEqual(FinishReason.content_filter, resp.choices[0].finish_reason);
    }
    {
        const body =
            \\{"choices":[{"message":{"content":"x"},"finish_reason":"random_new"}]}
        ;
        var arena4 = std.heap.ArenaAllocator.init(allocator);
        defer arena4.deinit();
        const resp = try parseResponse(allocator, arena4.allocator(), body);
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

    // Verify the vtable wraps the correct pointer.
    try std.testing.expect(@intFromPtr(provider.ptr) == @intFromPtr(&oa));
}

// Integration tests moved to src/llm/openai_integration.zig.
// Run with: zig build integration-test -Dapi-key=sk-xxx
