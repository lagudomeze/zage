# Zage

> An AI Agent framework in Zig — built for performance, inspired by OpenClaw, NullClaw, and SemaClaw.

**Zage** (pronounced *zayj*) is a framework for building LLM-powered agent applications. It focuses on agent orchestration with the performance, memory control, and zero-dependency ethos of systems programming.

## Design

Zage adopts a **4+1 layer architecture**:

```
Harness          — runtime safety boundary, lifecycle, event routing (Phase 2)
  Session + Agent Loop — session state + ReAct cycle (Phase 1)
    ModelProvider — vtable-backed LLM backends (runtime-switchable)
    Tool          — comptime-checked tool interface
    Memory        — vtable-backed memory backend
```

### Interface Strategy

- **anytype duck typing** — internal hot paths, zero-cost static dispatch
- **comptime checks** — public interfaces (Tool, AgentLoop), compile-time validation
- **vtable dispatch** — runtime-switchable backends (ModelProvider, Memory)

### Principles

- **Zero dependencies** — built on the Zig standard library, no C libraries
- **Minimal overhead** — arena-friendly allocation, no hidden allocations
- **Zig 0.16+** — leverages latest Zig toolchain and idioms
- **Simple first** — no Rust-style GAT/associated types, no unnecessary abstraction

## Project Status

> **WIP** — this project is in early development and not yet usable. APIs will change without notice.

### Roadmap

- [x] Project skeleton & core types
- [x] OpenAI client (JSON + unit tests)
- [ ] Core interfaces (`ModelProvider`, `Tool`, `Memory`, `AgentLoop`)
- [ ] Agent Loop (ReAct cycle) + Session management
- [ ] Tool calling & Memory
- [ ] Harness runtime
- [ ] Multi-agent, streaming, production hardening

See [doc/ROADMAP.md](doc/ROADMAP.md) for the detailed plan.

## Quick Start

Requirements: **Zig 0.16.0** or later.

```sh
# Clone and test
git clone https://github.com/your-org/zage.git
cd zage
zig build test

# Run the basic chat example (requires API key)
OPENAI_API_KEY=sk-xxx zig build run
```

## Installation

```sh
zig fetch --save https://github.com/your-org/zage/archive/main.tar.gz
```

Then in `build.zig.zon`:

```zig
.zage = .{
    .url = "https://github.com/your-org/zage/archive/main.tar.gz",
    .hash = "...",
},
```

And in `build.zig`:

```zig
const zage = b.dependency("zage", .{}).module("zage");
exe.root_module.addImport("zage", zage);
```

## License

MIT
