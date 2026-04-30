//! Core types for the Zage AI Agent framework.
//!
//! Defines the fundamental building blocks: chat messages, generation options,
//! LLM client interface, and response types.

const std = @import("std");

/// Represents the role of a chat participant.
pub const ChatRole = enum {
    system,
    user,
    assistant,
    tool,

    /// Returns the role name as expected by OpenAI-compatible APIs.
    pub fn asStr(self: ChatRole) []const u8 {
        return switch (self) {
            .system => "system",
            .user => "user",
            .assistant => "assistant",
            .tool => "tool",
        };
    }
};

/// A single message in a chat conversation.
pub const ChatMessage = struct {
    role: ChatRole,
    content: []const u8,
    /// Required when `role` is `.tool`. Identifies which tool call this result
    /// belongs to.
    tool_call_id: ?[]const u8 = null,
};

/// Controls text generation behaviour.
pub const GenerationOptions = struct {
    /// Sampling temperature between 0 and 2. Higher values produce more random outputs.
    temperature: ?f32 = null,
    /// Maximum number of tokens to generate.
    max_tokens: ?u32 = null,
    /// Nucleus sampling probability mass.
    top_p: ?f32 = null,
    /// Sequences where the model should stop generating.
    stop: ?[]const []const u8 = null,
    /// Random seed for deterministic generation.
    seed: ?u32 = null,
};

/// Why the model finished generating.
pub const FinishReason = enum {
    stop,
    length,
    content_filter,
    tool_calls,
    unknown,
};

/// Token usage statistics for a generation request.
pub const Usage = struct {
    prompt_tokens: u32,
    completion_tokens: u32,
    total_tokens: u32,
};

/// The response returned by an LLM completion call.
pub const LLMResponse = struct {
    content: []const u8,
    finish_reason: FinishReason,
    usage: ?Usage,
};

/// Represents a tool call requested by the LLM.
pub const ToolCall = struct {
    /// Unique identifier for this tool call (e.g. "call_abc123").
    id: []const u8,
    /// The name of the tool to invoke (e.g. "get_weather").
    name: []const u8,
    /// JSON-encoded arguments string (e.g. `{"city":"Beijing"}`).
    arguments: []const u8,
};

/// A single step in an Agent loop (Thought → Action → Observation).
pub const AgentStep = struct {
    /// The model's reasoning before taking an action (optional).
    thought: ?[]const u8 = null,
    /// The tool call chosen by the model (optional, absent when the model
    /// responds directly without invoking a tool).
    action: ?ToolCall = null,
    /// The result returned by the tool after execution (optional, absent
    /// before the tool has been executed).
    observation: ?[]const u8 = null,
};

/// Errors that can occur during LLM interactions.
pub const LLMError = error{
    /// The HTTP request could not be sent or completed.
    NetworkError,
    /// The server returned a non-200 status code.
    HttpError,
    /// The response body could not be parsed as JSON.
    ParseError,
    /// The API returned an error payload (e.g. invalid API key, rate limit).
    ApiError,
    /// The input to the LLM was invalid (e.g. empty messages).
    InvalidInput,
    /// The response was missing expected fields.
    UnexpectedResponse,
};

/// Virtual-table based interface for LLM clients.
///
/// Follows the same pattern as `std.mem.Allocator`: a thin wrapper around a
/// pointer and a vtable, allowing different implementations to share the same
/// interface without dynamic dispatch overhead in hot paths.
pub const LLMClient = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Send chat messages to the LLM and receive a completion.
        complete: *const fn (*anyopaque, allocator: std.mem.Allocator, messages: []const ChatMessage, opts: GenerationOptions) LLMError!LLMResponse,
    };

    /// Call the underlying LLM with the given messages and options.
    ///
    /// The caller owns the returned `LLMResponse.content` and must free it
    /// with the same allocator passed to this function.
    pub fn complete(self: LLMClient, allocator: std.mem.Allocator, messages: []const ChatMessage, opts: GenerationOptions) LLMError!LLMResponse {
        return self.vtable.complete(self.ptr, allocator, messages, opts);
    }
};

test "ChatRole asStr returns correct strings" {
    try std.testing.expectEqualStrings("system", ChatRole.system.asStr());
    try std.testing.expectEqualStrings("user", ChatRole.user.asStr());
    try std.testing.expectEqualStrings("assistant", ChatRole.assistant.asStr());
    try std.testing.expectEqualStrings("tool", ChatRole.tool.asStr());
}

test "GenerationOptions default values are null" {
    const opts: GenerationOptions = .{};
    try std.testing.expect(opts.temperature == null);
    try std.testing.expect(opts.max_tokens == null);
    try std.testing.expect(opts.top_p == null);
    try std.testing.expect(opts.stop == null);
    try std.testing.expect(opts.seed == null);
}

test "ChatMessage struct fields" {
    const msg = ChatMessage{ .role = .user, .content = "hello" };
    try std.testing.expectEqual(ChatRole.user, msg.role);
    try std.testing.expectEqualStrings("hello", msg.content);
}
