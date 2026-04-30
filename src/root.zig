//! Zage — AI Agent framework for Zig.
//!
//! Provides building blocks for LLM-powered applications:
//! - Core types for chat messages and generation options
//! - LLM client abstraction with OpenAI-compatible backends
//! - Prompt templating with variable interpolation
//! - Chain abstraction for composable processing pipelines

pub const core = @import("core/types.zig");
pub const llm = @import("llm/client.zig");
pub const prompt = @import("prompt/template.zig");
pub const chain = @import("chain/chain.zig");

// Re-export commonly used types for convenient top-level access.
pub const ChatRole = core.ChatRole;
pub const ChatMessage = core.ChatMessage;
pub const GenerationOptions = core.GenerationOptions;
pub const FinishReason = core.FinishReason;
pub const Usage = core.Usage;
pub const LLMResponse = core.LLMResponse;
pub const LLMError = core.LLMError;
pub const LLMClient = core.LLMClient;

test {
    _ = core;
    _ = llm;
    _ = prompt;
    _ = chain;
}
