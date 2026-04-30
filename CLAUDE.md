# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build / Test

```sh
zig build                  # build the library and executable
zig build test             # run unit tests (no network, no config needed)
zig build run              # run the executable (needs OPENAI_API_KEY env var)
# Integration tests — reads .env.test.json (copy from .env.test.example.json)
zig build integration-test
```

## Architecture

Zage is an AI Agent framework in Zig 0.16+, referencing OpenClaw (layered architecture), NullClaw (vtable + Zig-native performance), and SemaClaw (Harness engineering).

### 4+1 Layer Model

```
Harness (Phase 2)         — runtime safety boundary, lifecycle, event routing
  Session + Agent Loop     — session state + think-act-observe cycle
    ModelProvider           — vtable-backed LLM backend (runtime polymorphic)
    Tool                    — comptime-checked tool interface
    Memory                  — vtable-backed memory backend
      PromptTemplate, OutputParser, Callbacks — supporting modules
```

### Interface Strategy (Three Tiers)

| Tier | When | Mechanism |
| ---- | ---- | --------- |
| 1 — anytype duck typing | Internal hot paths (chain calls, tool execution) | `fn(anytype)` static dispatch, zero-cost |
| 2 — comptime interface checks | Public types users implement (Tool, AgentLoop) | `@hasDecl` + `@hasField` + `@typeInfo` compile-time asserts |
| 3 — vtable runtime dispatch | Backend switching at runtime (ModelProvider, Memory) | `{ ptr: *anyopaque, vtable: *const VTable }` pattern |

### Module Layout

| Submodule | Source | Purpose |
| ---------- | ------ | ------- |
| `zage.core` | `src/core/types.zig` | Shared types: `ChatRole`, `ChatMessage`, `GenerationOptions`, `ToolCall`, `AgentStep`, `LLMResponse`, `LLMError` |
| `zage.core.interfaces` | `src/core/interfaces.zig` | Four comptime-checked interface definitions: `ModelProvider`, `Tool`, `Memory`, `AgentLoop` |
| `zage.llm` | `src/llm/provider.zig` | `ModelProvider` vtable + `src/llm/openai.zig` implementation |
| `zage.prompt` | `src/prompt/template.zig` | Prompt templates with `{variable}` interpolation |
| `zage.agent` | `src/agent/loop.zig` | Agent Loop skeleton (ReAct) |
| `zage.memory` | `src/memory/buffer.zig` | Buffer memory implementation |
| `zage.tool` | `src/tool/registry.zig` | Tool registry |
| `zage.harness` | `src/harness/runtime.zig` | Harness runtime (Phase 2) |
| `zage.callback` | `src/callback/events.zig` | Event hooks |

`src/main.zig` is the executable entry. `src/chain/` exists as an internal implementation detail, not a public interface.

### Key Patterns

- **VTable polymorphism**: `ModelProvider` follows `std.mem.Allocator` pattern. Used for runtime-switchable backends (OpenAI vs local).
- **Comptime interface checks**: `Tool`, `AgentLoop` use compile-time assertions. Tools are known at compile time; no vtable overhead.
- **Allocator discipline**: All allocating functions take explicit `std.mem.Allocator`. Caller owns returned memory. Use `errdefer`.
- **Named error sets**: Never `anyerror` in public APIs.
- **Zig 0.16+**: `minimum_zig_version = "0.16.0"`, uses `std.Io`, `std.json.Stringify`, `Environ`.
