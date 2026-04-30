# Roadmap

## Phase 0 — Infrastructure & Core Interfaces (current)

- [x] Project skeleton & build configuration (Zig 0.16+)
- [x] Core types: `ChatRole`, `ChatMessage`, `GenerationOptions`, `LLMResponse`, `LLMError`
- [x] OpenAI client — JSON request/response, unit tests, `LLMClient` vtable
- [x] Tool role in `ChatRole`, `ToolCall` struct
- [ ] Core interface definitions (`ModelProvider`, `Tool`, `Memory`, `AgentLoop`) — comptime-checked
- [ ] `ModelProvider` vtable — extracted from `LLMClient`, generalized
- [ ] Prompt templating — `{variable}` interpolation with System/User message support
- [ ] `examples/basic_chat.zig` — end-to-end demo via `ModelProvider` interface

## Phase 1 — Agent Core

- [ ] **Agent Loop** — ReAct (Thought → Action → Observation) cycle as the primary abstraction
- [ ] **Session** — session state machine, conversation history holder, per-session config
- [ ] **Tool** registry & execution — tool interface, registration, call/response handling
- [ ] **Memory** — BufferMemory (sliding window), SummaryMemory, persistent store interface
- [ ] **OutputParser** — structured output extraction from LLM text
- [ ] `examples/agent_loop.zig` — agent loop with tool calling demo

## Phase 2 — Harness

- [ ] **Harness** runtime — agent lifecycle (start/pause/stop/timeout), event routing
- [ ] Tool permission control — allow/deny/confirm model inspired by SemaClaw's PermissionBridge
- [ ] Multi-agent coordination — Commander-Worker pattern, Agent-to-Agent messaging
- [ ] Session concurrency — single-writer semantics, lane queue

## Phase 3 — Production Readiness

- [ ] More LLM backends: Anthropic, Ollama, local (llama.cpp)
- [ ] Streaming response support
- [ ] Persistent memory — SQLite backend, vector store (in-memory, no external deps)
- [ ] Retry & backoff — configurable policy for LLM calls
- [ ] Observability — event hooks, token usage tracking, latency metrics
- [ ] Rate limiting
- [ ] Comprehensive test suite with mocked LLM backend
- [ ] API documentation generated from doc comments

## Future Ideas

- RAG pipeline (document loader → splitter → embedding → vector store → retrieval)
- Declarative agent composition (YAML/JSON-based config)
- AOT-compiled agent as a standalone binary
