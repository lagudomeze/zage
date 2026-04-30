# Zage

> An AI Agent framework in Zig — LangChain-inspired, systems-programming-powered.

**Zage** (pronounced *zayj*) is a framework for building LLM-powered agent applications. It focuses on agent orchestration with the performance, memory control, and zero-dependency ethos of systems programming.

## Design Goals

- **LangChain-like architecture** — chains, prompts, and LLM abstraction as first-class concepts
- **Zero dependencies** — built entirely on the Zig standard library, no C libraries required
- **Minimal overhead** — vtable-based polymorphism, arena-friendly allocation, no hidden allocations
- **Zig 0.16+** — leverages the latest Zig toolchain and idioms

## Project Status

> **WIP** — this project is in early development and not yet usable. APIs will change without notice.

### Roadmap

- [x] Project skeleton & core types (`ChatRole`, `ChatMessage`, `LLMClient` interface)
- [ ] OpenAI client (HTTPS + JSON via `std.http.Client`)
- [ ] Prompt templating (`{variable}` interpolation)
- [ ] Chain abstraction (`LLMChain` composing prompt + client)
- [ ] Streaming responses
- [ ] Tool use / function calling
- [ ] Multi-agent orchestration

## Quick Start

```zig
const zage = @import("zage");

// Coming soon — see examples/basic_chat.zig
```

### Requirements

- Zig 0.16.0 or later

## Installation

```sh
zig fetch --save https://github.com/your-org/zage/archive/main.tar.gz
```

Then in your `build.zig.zon`:

```zig
.zage = .{
    .url = "https://github.com/your-org/zage/archive/main.tar.gz",
    .hash = "...",
},
```

And in your `build.zig`:

```zig
const zage = b.dependency("zage", .{}).module("zage");
exe.root_module.addImport("zage", zage);
```

## License

MIT
