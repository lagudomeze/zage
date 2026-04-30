# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build / Test

```sh
zig build                  # build the library and executable
zig build test             # run all test blocks (src/root.zig gathers them via `test { _ = ...; }`)
zig build run              # run the executable
zig build run -- arg1 arg2 # pass arguments to the executable
```

## Architecture

Zage is a LangChain-inspired AI Agent framework written in Zig 0.16+. Zero third-party dependencies — only the Zig standard library.

### Module layout

`src/root.zig` is the library entry point (module name: `"zage"`). It re-exports the four submodules and also re-exports key types at the top level (e.g. `zage.ChatMessage`, `zage.LLMClient`).

| Submodule | Source | Purpose |
| ---------- | ------ | ------- |
| `zage.core` | `src/core/types.zig` | Shared types: `ChatRole`, `ChatMessage`, `GenerationOptions`, `LLMClient` vtable interface, `LLMResponse`, `LLMError` |
| `zage.llm` | `src/llm/client.zig` | LLM client abstraction + concrete backends (`src/llm/openai.zig`) |
| `zage.prompt` | `src/prompt/template.zig` | Prompt templates with `{variable}` interpolation |
| `zage.chain` | `src/chain/chain.zig` | Chain interface + `LLMChain` |

`src/main.zig` is the executable entry — it imports `zage` and is separate from the library module.

### Key patterns

- **VTable polymorphism**: `LLMClient` follows the `std.mem.Allocator` pattern — a `{ ptr: *anyopaque, vtable: *const VTable }` struct. Implementations (e.g. OpenAI) provide a concrete vtable with a `complete` function pointer. The interface returns `LLMError!LLMResponse`.
- **Allocator discipline**: All functions that allocate take an explicit `std.mem.Allocator` parameter. The caller owns returned memory. Use `errdefer` for cleanup on error paths.
- **Named errors only**: The codebase uses `LLMError` (a named error set) — never `anyerror` in public APIs.
- **Zig 0.16+ idioms**: No deprecated constructs. `build.zig.zon` pins `minimum_zig_version = "0.16.0"`.
