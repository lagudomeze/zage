# Zage

> 基于 Zig 的 AI Agent 框架 —— 参考 OpenClaw、NullClaw、SemaClaw 的设计理念，释放系统编程的性能优势。

**Zage**（读音 */zeɪdʒ/*）是一个用于构建 LLM 驱动智能体应用的框架，专注于 Agent 编排，兼具系统编程的性能、内存可控和零依赖理念。

## 设计

Zage 采用 **4+1 层架构**：

```
Harness          — 运行时管控层：安全边界、生命周期、事件路由（Phase 2）
  Session + Agent Loop — 会话状态 + ReAct 思考-行动-观察循环（Phase 1）
    ModelProvider — 虚表驱动的 LLM 后端（运行时可切换）
    Tool          — 编译期检查的工具接口
    Memory        — 虚表驱动的记忆后端
```

### 接口策略（三层次）

- **anytype Duck Typing** — 内部热路径，零开销静态分发
- **编译期检查** — 对外接口（Tool、AgentLoop），编译时验证
- **虚表分发** — 运行时切换的后端（ModelProvider、Memory）

### 设计原则

- **零依赖** — 完全基于 Zig 标准库，无需任何 C 库
- **极致轻量** — Arena 友好的内存分配、无隐式分配
- **Zig 0.16+** — 使用最新的 Zig 工具链和惯用法
- **简单优先** — 不引入 Rust 式的 GAT/关联类型等复杂抽象

## 项目状态

> **WIP** —— 项目处于早期开发阶段，尚不可用。API 可能随时变动，恕不另行通知。

### 路线图

- [x] 项目骨架 & 核心类型
- [x] OpenAI 客户端（JSON 序列化 + 单元测试）
- [ ] 核心接口定义（`ModelProvider`、`Tool`、`Memory`、`AgentLoop`）
- [ ] Agent Loop（ReAct 循环）+ Session 管理
- [ ] 工具调用 & 记忆
- [ ] Harness 运行时
- [ ] 多 Agent、流式、生产就绪

详细路线图见 [doc/ROADMAP.md](doc/ROADMAP.md)。

## 快速开始

环境要求：**Zig 0.16.0** 或更高版本。

```sh
# 克隆并测试
git clone https://github.com/your-org/zage.git
cd zage
zig build test

# 运行基础聊天示例（需要 API key）
OPENAI_API_KEY=sk-xxx zig build run
```

## 安装

```sh
zig fetch --save https://github.com/your-org/zage/archive/main.tar.gz
```

然后在 `build.zig.zon` 中：

```zig
.zage = .{
    .url = "https://github.com/your-org/zage/archive/main.tar.gz",
    .hash = "...",
},
```

在 `build.zig` 中：

```zig
const zage = b.dependency("zage", .{}).module("zage");
exe.root_module.addImport("zage", zage);
```

## 许可证

MIT
