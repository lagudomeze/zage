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
    completion_tokens: u32 = 0,
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
        /// Reason the model stopped generating (raw JSON string).
        finish_reason: []const u8 = "stop",
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

        /// Convert the raw finish_reason string to the typed enum.
        pub fn finishReason(self: Choice) FinishReason {
            return parseFinishReason(self.finish_reason);
        }
    };

    /// The first choice's text content. Panics if choices is empty.
    pub fn text(self: LLMResponse) []const u8 {
        return self.choices[0].message.content;
    }
};

fn parseFinishReason(raw: []const u8) FinishReason {
    if (std.mem.eql(u8, raw, "stop")) return .stop;
    if (std.mem.eql(u8, raw, "length")) return .length;
    if (std.mem.eql(u8, raw, "content_filter")) return .content_filter;
    if (std.mem.eql(u8, raw, "tool_calls")) return .tool_calls;
    if (std.mem.eql(u8, raw, "refusal")) return .refusal;
    return .unknown;
}

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

};

// ---------------------------------------------------------------------------
// Text completions (legacy)
// ---------------------------------------------------------------------------

/// Request for the legacy text completions API.
pub const CompletionRequest = struct {
    /// ID of the model to use.
    model: []const u8,
    /// The prompt(s) to generate completions for.
    prompt: []const u8,
    /// The suffix that comes after a completion of inserted text.
    suffix: ?[]const u8 = null,
    /// Maximum number of tokens to generate.
    max_tokens: ?u32 = null,
    /// Sampling temperature (0-2).
    temperature: ?f32 = null,
    /// Nucleus sampling threshold.
    top_p: ?f32 = null,
    /// Number of completions to generate.
    n: ?u8 = null,
    /// Whether to stream back partial progress.
    stream: ?bool = null,
    /// Include log probabilities of output tokens.
    logprobs: ?u8 = null,
    /// Echo back the prompt in addition to the completion.
    echo: ?bool = null,
    /// Sequences where the API will stop generating.
    stop: ?[]const []const u8 = null,
    /// Penalize tokens based on their frequency so far.
    frequency_penalty: ?f32 = null,
    /// Penalize tokens based on whether they appear in the text so far.
    presence_penalty: ?f32 = null,
    /// Generates `best_of` completions server-side and returns the best.
    best_of: ?u8 = null,
    /// Modify the likelihood of specified tokens appearing.
    logit_bias: ?[]const u8 = null,
    /// A unique identifier for the end-user.
    user: ?[]const u8 = null,
    /// Random seed for deterministic generation.
    seed: ?u32 = null,
};

/// Response from the legacy text completions API.
pub const CompletionResponse = struct {
    /// Unique identifier for this completion.
    id: []const u8,
    /// Always "text_completion".
    object: []const u8,
    /// Unix timestamp (seconds) of when the completion was created.
    created: u64,
    /// The model used.
    model: []const u8,
    /// The list of completion choices.
    choices: []const CompletionChoice,
    /// Token usage statistics.
    usage: ?Usage,

    pub const CompletionChoice = struct {
        /// The generated text.
        text: []const u8,
        /// The index of this completion.
        index: u32,
        /// Log probabilities (if requested).
        logprobs: ?[]const u8 = null,
        /// Reason the model stopped generating.
        finish_reason: []const u8,
    };
};

// ---------------------------------------------------------------------------
// Audio (transcriptions & translations)
// ---------------------------------------------------------------------------

/// Request for creating an audio transcription.
pub const AudioRequest = struct {
    /// Path to the audio file on disk.
    file_path: []const u8,
    /// The filename to send (e.g. "audio.mp3").
    filename: []const u8,
    /// ID of the model to use (e.g. "whisper-1").
    model: []const u8,
    /// Optional language in ISO-639-1 format.
    language: ?[]const u8 = null,
    /// An optional prompt to guide the transcription style.
    prompt: ?[]const u8 = null,
    /// The format of the response: "json", "text", "srt", "verbose_json", "vtt".
    response_format: ?[]const u8 = null,
    /// Sampling temperature (0-1).
    temperature: ?f32 = null,
};

/// Verbose JSON response from the audio API.
pub const AudioVerboseResponse = struct {
    /// Detected or specified language.
    language: []const u8,
    /// Duration of the audio in seconds.
    duration: f64,
    /// The full transcribed/translated text.
    text: []const u8,
    /// Word-level timestamps (only in verbose_json mode with timestamp_granularities).
    words: ?[]const AudioWord = null,
    /// Segment-level details (verbose_json mode).
    segments: ?[]const AudioSegment = null,

    pub const AudioWord = struct {
        word: []const u8,
        start: f64,
        end: f64,
    };

    pub const AudioSegment = struct {
        id: u32,
        seek: u32,
        start: f64,
        end: f64,
        text: []const u8,
        tokens: []const u32,
        temperature: f32,
        avg_logprob: f32,
        compression_ratio: f32,
        no_speech_prob: f32,
    };

};

// ---------------------------------------------------------------------------
// Images
// ---------------------------------------------------------------------------

/// Request for creating an image generation.
pub const ImageGenerationRequest = struct {
    /// A text description of the desired image(s).
    prompt: []const u8,
    /// The model to use (e.g. "dall-e-3", "dall-e-2").
    model: []const u8 = "dall-e-3",
    /// Number of images to generate (1-10, dall-e-3 only supports 1).
    n: ?u8 = null,
    /// Quality: "standard" or "hd" (dall-e-3 only).
    quality: ?[]const u8 = null,
    /// Response format: "url" or "b64_json".
    response_format: ?[]const u8 = null,
    /// Image size: "256x256", "512x512", "1024x1024", "1792x1024", "1024x1792".
    size: ?[]const u8 = null,
    /// Style: "vivid" or "natural" (dall-e-3 only).
    style: ?[]const u8 = null,
    /// A unique identifier for the end-user.
    user: ?[]const u8 = null,
};

/// An image result from the API.
pub const ImageData = struct {
    /// URL of the generated image (when response_format is "url").
    url: ?[]const u8 = null,
    /// Base64-encoded image (when response_format is "b64_json").
    b64_json: ?[]const u8 = null,
    /// Revised prompt used for generation (dall-e-3 only).
    revised_prompt: ?[]const u8 = null,
};

/// Response from the image generations API.
pub const ImageGenerationResponse = struct {
    /// Unix timestamp of creation.
    created: u64,
    /// The generated images.
    data: []const ImageData,

};

// ---------------------------------------------------------------------------
// Moderations
// ---------------------------------------------------------------------------

/// Request for creating a moderation check.
pub const ModerationRequest = struct {
    /// The input text to classify.
    input: []const u8,
    /// The model to use (defaults to "omni-moderation-latest").
    model: ?[]const u8 = null,
};

/// A single moderation result.
pub const ModerationResult = struct {
    /// Whether the content was flagged.
    flagged: bool,
    /// Category flags.
    categories: ModerationCategories,
    /// Category confidence scores (0-1).
    category_scores: ModerationCategoryScores,
};

/// Category flags for moderation.
pub const ModerationCategories = struct {
    harassment: bool = false,
    harassment_threatening: bool = false,
    hate: bool = false,
    hate_threatening: bool = false,
    self_harm: bool = false,
    self_harm_intent: bool = false,
    self_harm_instructions: bool = false,
    sexual: bool = false,
    sexual_minors: bool = false,
    violence: bool = false,
    violence_graphic: bool = false,
};

/// Category confidence scores.
pub const ModerationCategoryScores = struct {
    harassment: f32 = 0,
    harassment_threatening: f32 = 0,
    hate: f32 = 0,
    hate_threatening: f32 = 0,
    self_harm: f32 = 0,
    self_harm_intent: f32 = 0,
    self_harm_instructions: f32 = 0,
    sexual: f32 = 0,
    sexual_minors: f32 = 0,
    violence: f32 = 0,
    violence_graphic: f32 = 0,
};

/// Response from the moderations API.
pub const ModerationResponse = struct {
    /// Unique identifier for this request.
    id: []const u8,
    /// The model used.
    model: []const u8,
    /// The list of moderation results.
    results: []const ModerationResult,

};

// ---------------------------------------------------------------------------
// Files
// ---------------------------------------------------------------------------

/// A file object returned by the Files API.
pub const FileObject = struct {
    /// The file identifier.
    id: []const u8,
    /// Always "file".
    object: []const u8,
    /// File size in bytes.
    bytes: u64,
    /// Unix timestamp of creation.
    created_at: u64,
    /// The filename.
    filename: []const u8,
    /// The intended purpose: "fine-tune", "assistants", etc.
    purpose: []const u8,
    /// Status: "uploaded", "processed", "error".
    status: []const u8,
    /// Error details if status is "error".
    status_details: ?[]const u8 = null,

};

/// Response listing files.
pub const FileList = struct {
    /// Always "list".
    object: []const u8,
    /// The files.
    data: []const FileObject,

};

/// Response for file deletion.
pub const FileDeleteResponse = struct {
    /// The file identifier.
    id: []const u8,
    /// Always "file".
    object: []const u8,
    /// Whether the file was deleted.
    deleted: bool,

};

// ---------------------------------------------------------------------------
// Fine-tuning
// ---------------------------------------------------------------------------

/// Hyperparameters for fine-tuning.
pub const FineTuningHyperparams = struct {
    /// Number of epochs (or "auto").
    n_epochs: ?u32 = null,
    /// Batch size (or "auto").
    batch_size: ?u32 = null,
    /// Learning rate multiplier (or "auto").
    learning_rate_multiplier: ?f32 = null,
};

/// Request for creating a fine-tuning job.
pub const FineTuningJobCreateRequest = struct {
    /// The model to fine-tune (e.g. "gpt-4o-mini-2024-07-18").
    model: []const u8,
    /// The ID of an uploaded file containing training data.
    training_file: []const u8,
    /// Optional hyperparameters.
    hyperparameters: ?FineTuningHyperparams = null,
    /// A suffix to append to the fine-tuned model name.
    suffix: ?[]const u8 = null,
    /// The ID of a file containing validation data.
    validation_file: ?[]const u8 = null,
    /// Integrations for the fine-tuning job.
    integrations: ?[]const u8 = null,
    /// Random seed for reproducibility.
    seed: ?u32 = null,
};

/// A fine-tuning job returned by the API.
pub const FineTuningJob = struct {
    /// The job identifier.
    id: []const u8,
    /// Always "fine_tuning.job".
    object: []const u8,
    /// Unix timestamp of creation.
    created_at: u64,
    /// Unix timestamp when the job finished, or null.
    finished_at: ?u64 = null,
    /// The name of the fine-tuned model (once complete).
    fine_tuned_model: ?[]const u8 = null,
    /// The organization ID.
    organization_id: []const u8,
    /// The filename of the result files.
    result_files: []const []const u8,
    /// Status: "validating_files", "queued", "running", "succeeded", "failed", "cancelled".
    status: []const u8,
    /// The model being fine-tuned.
    model: []const u8,
    /// The ID of the training file.
    training_file: []const u8,
    /// Hyperparameters used.
    hyperparameters: ?FineTuningHyperparams = null,
    /// The ID of the validation file, if any.
    validation_file: ?[]const u8 = null,
    /// Number of tokens in the training file.
    trained_tokens: ?u64 = null,
    /// For failed jobs, the error details.
    @"error": ?FineTuningJobError = null,
    /// The seed used.
    seed: ?u32 = null,

    pub const FineTuningJobError = struct {
        code: []const u8,
        message: []const u8,
        param: ?[]const u8 = null,
    };

};

/// Response listing fine-tuning jobs.
pub const FineTuningJobList = struct {
    /// Always "list".
    object: []const u8,
    /// The list of jobs.
    data: []const FineTuningJob,
    /// Whether there are more jobs to retrieve.
    has_more: bool,

};

/// A fine-tuning job event.
pub const FineTuningJobEvent = struct {
    /// The event identifier.
    id: []const u8,
    /// Always "fine_tuning.job.event".
    object: []const u8,
    /// Unix timestamp of the event.
    created_at: u64,
    /// The event level: "info", "warn", "error".
    level: []const u8,
    /// The event message.
    message: []const u8,

};

/// Response listing fine-tuning job events.
pub const FineTuningJobEventList = struct {
    /// Always "list".
    object: []const u8,
    /// The list of events.
    data: []const FineTuningJobEvent,
    /// Whether there are more events.
    has_more: bool,

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

pub const LLMError = @import("api.zig").ApiError;

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
