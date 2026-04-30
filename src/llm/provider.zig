//! ModelProvider — vtable-based LLM backend interface.
//!
//! Hand-written vtable because zig-interface is incompatible with Zig 0.16+
//! (it depends on `@Type` builtin, removed in 0.14+).
//!
//! The vtable pattern follows `std.mem.Allocator`: a `{ ptr, vtable }` pair.
//! Implementations just need a public `complete` method — `ModelProvider.init(&impl)`
//! handles the wrapping.

const std = @import("std");
const core = @import("../core/types.zig");

pub const ChatMessage = core.ChatMessage;
pub const GenerationOptions = core.GenerationOptions;
pub const LLMResponse = core.LLMResponse;
pub const LLMError = core.LLMError;

/// Runtime-polymorphic interface for LLM backends.
///
/// Zero boilerplate for implementors: just expose a `pub fn complete(...)` and
/// wrap with `ModelProvider.init(&your_impl)`.
pub const ModelProvider = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        complete: *const fn (*anyopaque, allocator: std.mem.Allocator, messages: []const ChatMessage, opts: GenerationOptions) LLMError!LLMResponse,
    };

    /// Wrap a concrete implementation as a ModelProvider.
    ///
    /// `impl` must have a `pub fn complete(self: *@This(), allocator, messages, opts) LLMError!LLMResponse`.
    /// Pass `&your_struct` (pointer) for `impl`.
    pub fn init(impl: anytype) ModelProvider {
        const T = @TypeOf(impl);

        return switch (@typeInfo(T)) {
            .pointer => |ptr_info| .{
                .ptr = @ptrCast(@alignCast(impl)),
                .vtable = &.{ .complete = makeCompleteFn(ptr_info.child) },
            },
            else => .{
                .ptr = @constCast(@ptrCast(impl)),
                .vtable = &.{ .complete = makeCompleteFn(T) },
            },
        };
    }

    fn makeCompleteFn(comptime ImplT: type) *const fn (*anyopaque, allocator: std.mem.Allocator, messages: []const ChatMessage, opts: GenerationOptions) LLMError!LLMResponse {
        return struct {
            fn complete(ptr: *anyopaque, allocator: std.mem.Allocator, messages: []const ChatMessage, opts: GenerationOptions) LLMError!LLMResponse {
                const self: *ImplT = @ptrCast(@alignCast(ptr));
                return self.complete(allocator, messages, opts);
            }
        }.complete;
    }

    /// Call the underlying LLM.
    /// Caller owns heap-allocated response fields.
    pub fn complete(self: ModelProvider, allocator: std.mem.Allocator, messages: []const ChatMessage, opts: GenerationOptions) LLMError!LLMResponse {
        return self.vtable.complete(self.ptr, allocator, messages, opts);
    }
};

// Backward-compatible alias.
pub const LLMClient = ModelProvider;

test {
    _ = core;
}
