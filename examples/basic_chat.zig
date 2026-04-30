//! Zage — multi-turn agent loop with simulated tool calling.
//!
//! Demonstrates how an agent loop works:
//!   1. User sends a query
//!   2. LLM responds
//!   3. Agent feeds conversation history back for follow-up
//!
//! Usage:
//!   zig build -Dexample=basic_chat run
//!   OPENAI_API_KEY=sk-xxx zig run examples/basic_chat.zig
//!
//! This file reads OPENAI_API_KEY from the environment.
