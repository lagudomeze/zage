//! Zage — AI Agent framework for Zig.
//!
//! Provides building blocks for LLM-powered agent applications.
//! Architecture: Harness → Session + AgentLoop → ModelProvider/Tool/Memory.

pub const core = @import("core/types.zig");
pub const interfaces = @import("core/interfaces.zig");
pub const llm = @import("llm/client.zig");
pub const prompt = @import("prompt/template.zig");
pub const agent = @import("agent/loop.zig");
pub const memory = @import("memory/buffer.zig");
pub const tool = @import("tool/registry.zig");
pub const harness = @import("harness/runtime.zig");
pub const callback = @import("callback/events.zig");
// chain is an internal implementation detail, not part of the public API.

// Re-export commonly used types.
pub const ChatRole = core.ChatRole;
pub const ChatMessage = core.ChatMessage;
pub const ToolCall = core.ToolCall;
pub const AgentStep = core.AgentStep;
pub const GenerationOptions = core.GenerationOptions;
pub const FinishReason = core.FinishReason;
pub const Usage = core.Usage;
pub const LLMResponse = core.LLMResponse;
pub const LLMError = core.LLMError;
pub const ModelProvider = llm.ModelProvider;
pub const OpenAI = llm.OpenAI;

// Interface validation helpers.
pub const assertIsModelProvider = interfaces.assertIsModelProvider;
pub const assertIsTool = interfaces.assertIsTool;
pub const assertIsMemory = interfaces.assertIsMemory;
pub const assertIsAgentLoop = interfaces.assertIsAgentLoop;

test {
    _ = core;
    _ = interfaces;
    _ = llm;
    _ = prompt;
    _ = agent;
    _ = memory;
    _ = tool;
    _ = harness;
    _ = callback;
    _ = @import("chain/chain.zig");
}
