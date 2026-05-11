//! OpenAI API endpoint definitions.
//!
//! Each field in `registry` is an `api.Endpoint` that maps a logical name
//! to HTTP method, URL path, request body type, and response body type.
//! The enum `Ep` is derived automatically from the field names — compile
//! errors on typos, IDE autocomplete on values.
//!
//! Special endpoints (multipart uploads, SSE streaming, raw responses) are
//! handled as dedicated methods on `OpenAI`, not routed through `call()`.

const std = @import("std");
const api = @import("../../core/api.zig");
const core = @import("../../core/types.zig");

const Endpoint = api.Endpoint;

// -----------------------------------------------------------------------
// Endpoint registry — anonymous struct, field names → Ep enum values
// -----------------------------------------------------------------------

pub const registry = .{
    // -- Chat --
    .chat_completions = Endpoint{
        .method = .POST,
        .path = "/v1/chat/completions",
        .Request = ChatRequest,
        .Response = core.LLMResponse,
    },

    // -- Text completions (legacy) --
    .create_completion = Endpoint{
        .method = .POST,
        .path = "/v1/completions",
        .Request = core.CompletionRequest,
        .Response = core.CompletionResponse,
    },

    // -- Embeddings --
    .create_embedding = Endpoint{
        .method = .POST,
        .path = "/v1/embeddings",
        .Request = core.EmbeddingRequest,
        .Response = core.EmbeddingResponse,
    },

    // -- Images --
    .create_image = Endpoint{
        .method = .POST,
        .path = "/v1/images/generations",
        .Request = core.ImageGenerationRequest,
        .Response = core.ImageGenerationResponse,
    },

    // -- Moderations --
    .create_moderation = Endpoint{
        .method = .POST,
        .path = "/v1/moderations",
        .Request = core.ModerationRequest,
        .Response = core.ModerationResponse,
    },

    // -- Models --
    .list_models = Endpoint{
        .method = .GET,
        .path = "/v1/models",
        .Request = void,
        .Response = core.ModelList,
    },

    // -- Files --
    .list_files = Endpoint{
        .method = .GET,
        .path = "/v1/files",
        .Request = void,
        .Response = core.FileList,
    },
    .retrieve_file = Endpoint{
        .method = .GET,
        .path = "/v1/files/{id}",
        .Request = void,
        .Response = core.FileObject,
    },
    .delete_file = Endpoint{
        .method = .DELETE,
        .path = "/v1/files/{id}",
        .Request = void,
        .Response = core.FileDeleteResponse,
    },

    // -- Fine-tuning --
    .create_fine_tuning_job = Endpoint{
        .method = .POST,
        .path = "/v1/fine_tuning/jobs",
        .Request = core.FineTuningJobCreateRequest,
        .Response = core.FineTuningJob,
    },
    .list_fine_tuning_jobs = Endpoint{
        .method = .GET,
        .path = "/v1/fine_tuning/jobs",
        .Request = void,
        .Response = core.FineTuningJobList,
    },
    .retrieve_fine_tuning_job = Endpoint{
        .method = .GET,
        .path = "/v1/fine_tuning/jobs/{id}",
        .Request = void,
        .Response = core.FineTuningJob,
    },
    .cancel_fine_tuning_job = Endpoint{
        .method = .POST,
        .path = "/v1/fine_tuning/jobs/{id}/cancel",
        .Request = void,
        .Response = core.FineTuningJob,
    },
    .list_fine_tuning_job_events = Endpoint{
        .method = .GET,
        .path = "/v1/fine_tuning/jobs/{id}/events",
        .Request = void,
        .Response = core.FineTuningJobEventList,
    },
};

// -----------------------------------------------------------------------
// Derived enum — IDE autocomplete, compile-error on typos
// -----------------------------------------------------------------------

pub const Ep = api.EndpointEnum(registry);

// -----------------------------------------------------------------------
// Chat completion request body
// -----------------------------------------------------------------------

pub const ChatRequest = struct {
    model: []const u8,
    messages: []const core.ChatMessage,
    temperature: ?f32 = null,
    max_tokens: ?u32 = null,
    max_completion_tokens: ?u32 = null,
    top_p: ?f32 = null,
    stop: ?[]const []const u8 = null,
    seed: ?u32 = null,
    frequency_penalty: ?f32 = null,
    presence_penalty: ?f32 = null,
    n: ?u8 = null,
    stream: ?bool = null,
    response_format: ?core.GenerationOptions.ResponseFormat = null,
    tools: ?[]const core.ToolDef = null,
    tool_choice: ?[]const u8 = null,
    parallel_tool_calls: ?bool = null,
    user: ?[]const u8 = null,
};

/// Build a ChatRequest from model + messages + GenerationOptions.
pub fn chatRequest(
    model: []const u8,
    messages: []const core.ChatMessage,
    opts: core.GenerationOptions,
    stream: bool,
) ChatRequest {
    return .{
        .model = model,
        .messages = messages,
        .temperature = opts.temperature,
        .max_tokens = opts.max_tokens,
        .max_completion_tokens = opts.max_completion_tokens,
        .top_p = opts.top_p,
        .stop = opts.stop,
        .seed = opts.seed,
        .frequency_penalty = opts.frequency_penalty,
        .presence_penalty = opts.presence_penalty,
        .n = opts.n,
        .stream = stream,
        .response_format = opts.response_format,
        .tools = opts.tools,
        .tool_choice = opts.tool_choice,
        .parallel_tool_calls = opts.parallel_tool_calls,
        .user = opts.user,
    };
}

/// Serialize a chat request to JSON. Exposed for testing.
pub fn buildRequestBody(
    allocator: std.mem.Allocator,
    model: []const u8,
    messages: []const core.ChatMessage,
    opts: core.GenerationOptions,
) core.LLMError![]u8 {
    const payload = chatRequest(model, messages, opts, false);
    return std.json.Stringify.valueAlloc(allocator, payload, .{ .emit_null_optional_fields = false }) catch core.LLMError.InvalidInput;
}
