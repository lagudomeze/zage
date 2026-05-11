//! LLM client — re-exports the OpenAI client.

pub const openai = @import("openai/root.zig");
pub const OpenAI = openai.OpenAI;
pub const Ep = openai.Ep;

test {
    _ = openai;
}
