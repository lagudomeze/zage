//! LLM client abstraction.
//!
//! Re-exports the ModelProvider vtable interface and concrete implementations.

pub const provider = @import("provider.zig");
pub const openai = @import("openai.zig");

pub const ModelProvider = provider.ModelProvider;
pub const LLMError = provider.LLMError;
pub const LLMResponse = provider.LLMResponse;
pub const OpenAI = openai.OpenAI;

test {
    _ = provider;
    _ = openai;
}
