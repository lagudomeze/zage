# Zage

> 基于 Zig 的 AI Agent 框架 —— 对标 LangChain，释放系统编程的性能优势。

**Zage**（读音 */zeɪdʒ/*）是一个用于构建 LLM 驱动智能体应用的框架，专注于 Agent 编排，兼具系统编程的性能、内存可控和零依赖理念。

## 设计目标

- **LangChain 式架构** —— Chain、Prompt、LLM 抽象作为一等公民
- **零依赖** —— 完全基于 Zig 标准库，无需任何 C 库
- **极致轻量** —— 虚表多态、Arena 友好的内存分配、无隐式分配
- **Zig 0.16+** —— 使用最新的 Zig 工具链和惯用法

## 项目状态

> **WIP** —— 项目处于早期开发阶段，尚不可用。API 可能随时变动，恕不另行通知。

### 路线图

- [x] 项目骨架 & 核心类型（`ChatRole`、`ChatMessage`、`LLMClient` 接口）
- [ ] OpenAI 客户端（基于 `std.http.Client` 的 HTTPS + JSON 通信）
- [ ] Prompt 模板（`{variable}` 占位符插值）
- [ ] Chain 抽象（`LLMChain` 组合 Prompt + Client）
- [ ] 流式响应
- [ ] 工具调用 / Function Calling
- [ ] 多 Agent 编排

## 快速开始

```zig
const zage = @import("zage");

// 即将推出 —— 见 examples/basic_chat.zig
```

### 环境要求

- Zig 0.16.0 或更高版本

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
