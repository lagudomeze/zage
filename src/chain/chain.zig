//! Chain abstraction for composable processing pipelines.
//!
//! Defines the Chain interface and concrete implementations like LLMChain.

const core = @import("../core/types.zig");
pub const LLMClient = core.LLMClient;
pub const LLMResponse = core.LLMResponse;

test {
    _ = core;
}
