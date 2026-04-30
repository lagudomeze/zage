//! Core interface definitions for the Zage framework.
//!
//! Each interface uses comptime assertions to validate implementations at
//! compile time. This is Tier 2 of the interface strategy (comptime checks),
//! used for types that users implement directly.
//!
//! For Tier 3 (runtime polymorphism), see `src/llm/provider.zig` for the
//! ModelProvider vtable and `src/memory/buffer.zig` for the Memory vtable.

const std = @import("std");
const types = @import("types.zig");

const ChatMessage = types.ChatMessage;
const GenerationOptions = types.GenerationOptions;
const LLMResponse = types.LLMResponse;
const LLMError = types.LLMError;
const AgentStep = types.AgentStep;

// ---------------------------------------------------------------------------
// ModelProvider — LLM backend interface
// ---------------------------------------------------------------------------

/// Validates that `T` satisfies the ModelProvider interface.
///
/// An implementation must provide:
/// - `complete(allocator, messages, opts) LLMError!LLMResponse`
pub fn assertIsModelProvider(comptime T: type) void {
    if (!@hasDecl(T, "complete")) {
        @compileError(@typeName(T) ++ " must declare a `complete` method");
    }

    // Validate complete function signature.
    const CompleteFn = @TypeOf(T.complete);
    const fn_info = @typeInfo(CompleteFn).@"fn";
    if (fn_info.params.len < 3) {
        @compileError(@typeName(T) ++ ".complete must accept at least 3 parameters: (self, allocator, messages, opts)");
    }
}

// ---------------------------------------------------------------------------
// Tool — executable tool interface
// ---------------------------------------------------------------------------

/// Validates that `T` satisfies the Tool interface.
///
/// An implementation must provide:
/// - `name: []const u8` — unique tool identifier
/// - `description: []const u8` — human-readable description
/// - `execute(allocator, input: []const u8) anyerror![]const u8` — tool logic
pub fn assertIsTool(comptime T: type) void {
    if (!@hasDecl(T, "name")) {
        @compileError(@typeName(T) ++ " must declare a `name` declaration");
    }
    if (!@hasDecl(T, "description")) {
        @compileError(@typeName(T) ++ " must declare a `description` declaration");
    }
    if (!@hasDecl(T, "execute")) {
        @compileError(@typeName(T) ++ " must declare an `execute` method");
    }
}

// ---------------------------------------------------------------------------
// Memory — conversation memory interface
// ---------------------------------------------------------------------------

/// Validates that `T` satisfies the Memory interface.
///
/// An implementation must provide:
/// - `add(message: ChatMessage) void` — append a message
/// - `get(allocator, limit: usize) []const ChatMessage` — retrieve recent messages
/// - `clear() void` — reset memory
pub fn assertIsMemory(comptime T: type) void {
    if (!@hasDecl(T, "add")) {
        @compileError(@typeName(T) ++ " must declare an `add` method");
    }
    if (!@hasDecl(T, "get")) {
        @compileError(@typeName(T) ++ " must declare a `get` method");
    }
    if (!@hasDecl(T, "clear")) {
        @compileError(@typeName(T) ++ " must declare a `clear` method");
    }
}

// ---------------------------------------------------------------------------
// AgentLoop — agent execution loop interface
// ---------------------------------------------------------------------------

/// Validates that `T` satisfies the AgentLoop interface.
///
/// An implementation must provide:
/// - `run(allocator, provider, tools, memory, input: []const u8) anyerror![]const u8`
///
/// The `provider` parameter uses anytype (Tier 1 duck typing) — any type
/// with a compatible `complete` method is accepted.
/// The `tools` parameter is a tuple or slice of Tool-compatible types.
/// The `memory` parameter is any type satisfying the Memory interface.
pub fn assertIsAgentLoop(comptime T: type) void {
    if (!@hasDecl(T, "run")) {
        @compileError(@typeName(T) ++ " must declare a `run` method");
    }
}

// ---------------------------------------------------------------------------
// Compile-time verification tests
// ---------------------------------------------------------------------------

test "assertIsModelProvider accepts valid implementation" {
    const ValidProvider = struct {
        pub fn complete(_: @This(), a: std.mem.Allocator, m: []const ChatMessage, o: GenerationOptions) LLMError!LLMResponse {
            _ = a;
            _ = m;
            _ = o;
            return LLMResponse{
                .choices = &.{.{ .message = .{ .content = "" }, .finish_reason = .stop }},
                .usage = null,
            };
        }
    };
    comptime assertIsModelProvider(ValidProvider);
}

test "assertIsTool accepts valid implementation" {
    const ValidTool = struct {
        pub const name = "test_tool";
        pub const description = "A test tool";
        pub fn execute(_: @This(), a: std.mem.Allocator, input: []const u8) ![]const u8 {
            _ = a;
            return input;
        }
    };
    comptime assertIsTool(ValidTool);
}

test "assertIsMemory accepts valid implementation" {
    const ValidMemory = struct {
        pub fn add(_: *@This(), msg: ChatMessage) void { _ = msg; }
        pub fn get(_: *@This(), a: std.mem.Allocator, limit: usize) []const ChatMessage {
            _ = a;
            _ = limit;
            return &.{};
        }
        pub fn clear(_: *@This()) void {}
    };
    comptime assertIsMemory(ValidMemory);
}

test "assertIsAgentLoop accepts valid implementation" {
    const ValidLoop = struct {
        pub fn run(_: @This(), a: std.mem.Allocator, provider: anytype, tools: anytype, memory: anytype, input: []const u8) ![]const u8 {
            _ = a;
            _ = provider;
            _ = tools;
            _ = memory;
            return input;
        }
    };
    comptime assertIsAgentLoop(ValidLoop);
}
