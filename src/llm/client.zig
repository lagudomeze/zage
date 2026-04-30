//! LLM client abstraction.
//!
//! Re-exports the LLMClient interface from core types and provides
//! concrete implementations (e.g. OpenAI).

pub const types = @import("../core/types.zig");
pub const LLMClient = types.LLMClient;
pub const LLMError = types.LLMError;
pub const LLMResponse = types.LLMResponse;

test {
    _ = types;
}
