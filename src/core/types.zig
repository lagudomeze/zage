//! Core types for the Zage AI Agent framework.
//!
//! Types mirror the OpenAI chat completions API — the de facto standard
//! across LLM providers (Anthropic, DeepSeek, Moonshot, Ollama, etc.).

const std = @import("std");

// ---------------------------------------------------------------------------
// Chat roles & messages
// ---------------------------------------------------------------------------

/// Maps to the `role` field in the OpenAI messages array.
pub const ChatRole = enum {
    system,
    user,
    assistant,
    tool,

    pub fn asStr(self: ChatRole) []const u8 {
        return switch (self) {
            .system => "system",
            .user => "user",
            .assistant => "assistant",
            .tool => "tool",
        };
    }
};

/// A single message in the chat conversation.
/// Mirrors the OpenAI message object with all optional fields.
pub const ChatMessage = struct {
    role: ChatRole,
    /// The text content. May be null when the message contains only tool_calls.
    content: []const u8,
    /// Required when `role` is `.tool` — identifies which tool call this
    /// result belongs to.
    tool_call_id: ?[]const u8 = null,
    /// When `role` is `.assistant` and the model wants to call tools.
    tool_calls: ?[]const ToolCall = null,
    /// An optional name for the participant. Helps distinguish between
    /// different speakers of the same role.
    name: ?[]const u8 = null,
};

// ---------------------------------------------------------------------------
// Tool calling
// ---------------------------------------------------------------------------

/// A tool call requested by the model in an assistant message.
pub const ToolCall = struct {
    /// Unique identifier for this tool call (e.g. "call_abc123").
    id: []const u8,
    /// Always "function" in the current API.
    @"type": []const u8 = "function",
    /// The function to call.
    function: Function,

    pub const Function = struct {
        /// Name of the function to call.
        name: []const u8,
        /// JSON-encoded arguments string (e.g. `{"city":"Beijing"}`).
        arguments: []const u8,
    };
};

/// Definition of a tool available to the model.
pub const ToolDef = struct {
    @"type": []const u8 = "function",
    function: FunctionDef,

    pub const FunctionDef = struct {
        /// The name of the function.
        name: []const u8,
        /// A human-readable description of what the function does.
        description: []const u8 = "",
        /// JSON Schema for the function's parameters.
        parameters: ?[]const u8 = null,
    };
};

// ---------------------------------------------------------------------------
// Generation options (request parameters)
// ---------------------------------------------------------------------------

/// Controls text generation behaviour. All fields are optional —
/// providers use sensible defaults for unspecified values.
pub const GenerationOptions = struct {
    /// Sampling temperature between 0 and 2. Higher = more random.
    temperature: ?f32 = null,
    /// Nucleus sampling: cumulative probability threshold.
    top_p: ?f32 = null,
    /// How many completion choices to generate.
    n: ?u8 = null,
    /// Whether to stream partial responses via SSE.
    stream: ?bool = null,
    /// Sequences where the model should stop generating.
    stop: ?[]const []const u8 = null,
    /// Maximum number of tokens to generate.
    max_tokens: ?u32 = null,
    /// Maximum number of completion tokens (alias for max_tokens).
    max_completion_tokens: ?u32 = null,
    /// Penalize new tokens based on their frequency so far (-2.0 to 2.0).
    frequency_penalty: ?f32 = null,
    /// Penalize new tokens based on whether they appear in the text so far
    /// (-2.0 to 2.0).
    presence_penalty: ?f32 = null,
    /// Random seed for deterministic generation.
    seed: ?u32 = null,
    /// Force the model to produce JSON output.
    response_format: ?ResponseFormat = null,
    /// Tools available to the model for function calling.
    tools: ?[]const ToolDef = null,
    /// Controls which tool (if any) is called. "none", "auto", "required",
    /// or a specific tool definition.
    tool_choice: ?[]const u8 = null,
    /// Whether to enable parallel tool calls.
    parallel_tool_calls: ?bool = null,
    /// A unique identifier for the end-user (for abuse monitoring).
    user: ?[]const u8 = null,

    pub const ResponseFormat = struct {
        @"type": []const u8 = "json_object",
    };
};

// ---------------------------------------------------------------------------
// Usage
// ---------------------------------------------------------------------------

/// Token usage statistics for a completion request.
pub const Usage = struct {
    prompt_tokens: u32,
    completion_tokens: u32,
    total_tokens: u32,
    /// Breakdown of completion tokens (reasoning models, audio, etc.).
    completion_tokens_details: ?CompletionTokensDetails = null,

    pub const CompletionTokensDetails = struct {
        /// Tokens spent on internal reasoning (o1, o3 models).
        reasoning_tokens: ?u32 = null,
        /// Tokens spent on audio output.
        audio_tokens: ?u32 = null,
        /// Tokens from accepted speculative decoding predictions.
        accepted_prediction_tokens: ?u32 = null,
        /// Tokens from rejected speculative decoding predictions.
        rejected_prediction_tokens: ?u32 = null,
    };
};

// ---------------------------------------------------------------------------
// Finish reason
// ---------------------------------------------------------------------------

/// Why the model stopped generating.
pub const FinishReason = enum {
    stop,
    length,
    content_filter,
    tool_calls,
    /// The model refused to generate (safety).
    refusal,
    /// The response was cut off for another reason.
    unknown,
};

// ---------------------------------------------------------------------------
// LLMResponse — mirrors OpenAI chat completion response
// ---------------------------------------------------------------------------

/// A complete chat completion response.
pub const LLMResponse = struct {
    /// Unique identifier for this completion.
    id: []const u8,
    /// Always "chat.completion" for chat completions.
    object: []const u8,
    /// Unix timestamp (seconds) of when the completion was created.
    created: u64,
    /// The model used to generate the completion.
    model: []const u8,
    /// A fingerprint for the system configuration used.
    system_fingerprint: ?[]const u8 = null,
    /// The service tier: "auto", "default", or null.
    service_tier: ?[]const u8 = null,

    /// One entry per completion choice.
    choices: []const Choice,
    /// Token usage statistics.
    usage: ?Usage,

    pub const Choice = struct {
        /// Index of this choice in the list.
        index: u32,
        /// The message generated by the model.
        message: Message,
        /// Reason the model stopped generating.
        finish_reason: FinishReason,
        /// Log probabilities for the output tokens (if requested).
        logprobs: ?[]const u8 = null,

        pub const Message = struct {
            /// Always "assistant" for chat completions.
            role: []const u8,
            /// The text response. Null when the response is only tool calls.
            content: []const u8,
            /// Tool calls requested by the model (if any).
            tool_calls: ?[]const ToolCall = null,
            /// When the model refuses to answer for safety reasons.
            refusal: ?[]const u8 = null,
        };
    };

    /// The first choice's text content. Panics if choices is empty.
    pub fn text(self: LLMResponse) []const u8 {
        return self.choices[0].message.content;
    }

    /// Free all heap memory owned by this response.
    pub fn deinit(self: LLMResponse, allocator: std.mem.Allocator) void {
        for (self.choices) |c| {
            allocator.free(c.message.content);
            allocator.free(c.message.role);
            if (c.message.tool_calls) |tcs| {
                for (tcs) |tc| {
                    allocator.free(tc.id);
                    allocator.free(tc.@"type");
                    allocator.free(tc.function.name);
                    allocator.free(tc.function.arguments);
                }
                allocator.free(tcs);
            }
            if (c.message.refusal) |r| allocator.free(r);
            if (c.logprobs) |l| allocator.free(l);
        }
        allocator.free(self.choices);
        allocator.free(self.id);
        allocator.free(self.object);
        allocator.free(self.model);
        if (self.system_fingerprint) |s| allocator.free(s);
        if (self.service_tier) |s| allocator.free(s);
    }
};

// ---------------------------------------------------------------------------
// Embeddings
// ---------------------------------------------------------------------------

/// Request for creating an embedding vector.
pub const EmbeddingRequest = struct {
    /// The model to use (e.g. "text-embedding-3-small").
    model: []const u8,
    /// Input text to embed — a single string or an array of strings.
    input: []const []const u8,
    /// The format of the output embeddings: "float" or "base64".
    encoding_format: ?[]const u8 = null,
    /// Number of dimensions the output should have (text-embedding-3 only).
    dimensions: ?u32 = null,
    /// A unique identifier for the end-user.
    user: ?[]const u8 = null,
};

/// A single embedding vector.
pub const Embedding = struct {
    /// The index of this embedding in the input array.
    index: u32,
    /// The embedding vector as float values.
    embedding: []const f32,
    /// Always "embedding".
    object: []const u8,
};

/// Response from the embeddings API.
pub const EmbeddingResponse = struct {
    /// Always "list".
    object: []const u8,
    /// The list of embedding vectors.
    data: []const Embedding,
    /// The model used.
    model: []const u8,
    /// Token usage.
    usage: Usage,

    pub fn deinit(self: EmbeddingResponse, allocator: std.mem.Allocator) void {
        for (self.data) |e| {
            allocator.free(e.embedding);
            allocator.free(e.object);
        }
        allocator.free(self.data);
        allocator.free(self.object);
        allocator.free(self.model);
    }
};

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

/// A single model descriptor returned by the Models API.
pub const Model = struct {
    /// The model identifier (e.g. "gpt-4o").
    id: []const u8,
    /// Always "model".
    object: []const u8,
    /// Unix timestamp of when the model was created.
    created: u64,
    /// The organization that owns the model.
    owned_by: []const u8,
};

/// Response listing all available models.
pub const ModelList = struct {
    /// Always "list".
    object: []const u8,
    /// The models available.
    data: []const Model,

    pub fn deinit(self: ModelList, allocator: std.mem.Allocator) void {
        for (self.data) |m| {
            allocator.free(m.id);
            allocator.free(m.object);
            allocator.free(m.owned_by);
        }
        allocator.free(self.data);
        allocator.free(self.object);
    }
};

// ---------------------------------------------------------------------------
// Agent step
// ---------------------------------------------------------------------------

/// A single step in an Agent loop (Thought → Action → Observation).
pub const AgentStep = struct {
    thought: ?[]const u8 = null,
    action: ?ToolCall = null,
    observation: ?[]const u8 = null,
};

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

pub const LLMError = error{
    NetworkError,
    HttpError,
    ParseError,
    ApiError,
    InvalidInput,
    UnexpectedResponse,
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "ChatRole asStr" {
    try std.testing.expectEqualStrings("system", ChatRole.system.asStr());
    try std.testing.expectEqualStrings("user", ChatRole.user.asStr());
    try std.testing.expectEqualStrings("assistant", ChatRole.assistant.asStr());
    try std.testing.expectEqualStrings("tool", ChatRole.tool.asStr());
}

test "ChatMessage defaults" {
    const msg = ChatMessage{ .role = .user, .content = "hello" };
    try std.testing.expectEqual(ChatRole.user, msg.role);
    try std.testing.expectEqualStrings("hello", msg.content);
    try std.testing.expect(msg.tool_call_id == null);
    try std.testing.expect(msg.tool_calls == null);
    try std.testing.expect(msg.name == null);
}

test "GenerationOptions defaults" {
    const opts: GenerationOptions = .{};
    try std.testing.expect(opts.temperature == null);
    try std.testing.expect(opts.max_tokens == null);
    try std.testing.expect(opts.top_p == null);
    try std.testing.expect(opts.stop == null);
    try std.testing.expect(opts.seed == null);
    try std.testing.expect(opts.frequency_penalty == null);
    try std.testing.expect(opts.presence_penalty == null);
    try std.testing.expect(opts.tools == null);
}

test "ToolCall fields" {
    const tc = ToolCall{
        .id = "call_1",
        .function = .{ .name = "get_weather", .arguments = "{\"city\":\"NYC\"}" },
    };
    try std.testing.expectEqualStrings("call_1", tc.id);
    try std.testing.expectEqualStrings("function", tc.@"type");
    try std.testing.expectEqualStrings("get_weather", tc.function.name);
}
