//! Zage — basic chat example.
//!
//! Usage:
//!   OPENAI_API_KEY=sk-xxx zig build run
//!
//! Optionally set OPENAI_BASE_URL and OPENAI_MODEL for compatible services.

const std = @import("std");
const zage = @import("zage");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();

    // Resolve config from environment (non-allocating lookup via environ_map).
    const api_key = init.environ_map.get("OPENAI_API_KEY") orelse {
        std.debug.print("Error: OPENAI_API_KEY environment variable is required.\n", .{});
        std.process.exit(1);
    };
    const model = init.environ_map.get("OPENAI_MODEL");
    const base_url = init.environ_map.get("OPENAI_BASE_URL");

    var openai = zage.llm.OpenAI.init(arena, init.io, api_key, model, base_url);
    const provider = zage.llm.ModelProvider.init(&openai);

    const messages = [_]zage.ChatMessage{
        .{ .role = .system, .content = "You are a helpful assistant. Answer concisely." },
        .{ .role = .user, .content = "Hello! Who are you, and what can you do?" },
    };

    std.debug.print("Sending request to {s} ...\n", .{openai.base_url});

    const response = try provider.complete(arena, &messages, .{ .max_tokens = 200 });
    defer arena.free(response.content);

    std.debug.print("\n--- Response ---\n{s}\n", .{response.content});

    if (response.usage) |usage| {
        std.debug.print("\n--- Usage ---\n", .{});
        std.debug.print("  prompt:     {d} tokens\n", .{usage.prompt_tokens});
        std.debug.print("  completion: {d} tokens\n", .{usage.completion_tokens});
        std.debug.print("  total:      {d} tokens\n", .{usage.total_tokens});
    }
}
