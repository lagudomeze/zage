//! Prompt templating with variable interpolation.
//!
//! Accepts template strings with {variable} placeholders and produces
//! formatted chat messages.

const core = @import("../core/types.zig");
pub const ChatMessage = core.ChatMessage;
pub const ChatRole = core.ChatRole;

test {
    _ = core;
}
