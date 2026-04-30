---
name: commit
description: Create well-structured git commits with conventional commit messages
---

# Git Commit Skill

## When to Use

Invoke this skill before creating any git commit. It ensures every commit follows project standards.

## Commit Standards

### Message Format

```text
<type>(<scope>): <concise title>

<detailed body — what changed and why>

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

### Types

| Type | Usage |
| ------ | ------- |
| `feat` | New feature or capability |
| `fix` | Bug fix |
| `refactor` | Code restructuring, no behavior change |
| `test` | Adding or updating tests |
| `docs` | Documentation only |
| `chore` | Build, dependencies, tooling |
| `perf` | Performance improvement |

### Scope

Use the module or area affected: `core`, `llm`, `prompt`, `agent`, `memory`, `tool`, `harness`, `build`, `examples`, `docs`.

### Rules

1. **Title**: ≤72 characters, imperative mood ("add" not "adds"/"added"), no trailing period
2. **Body**: Explain what changed AND why. Reference architectural decisions. Separate from title with blank line
3. **Scope**: Every commit must include a scope if it's not a repo-wide change
4. **Atomicity**: One logical change per commit. Don't bundle unrelated changes
5. **No WIP commits**: Every commit should represent a working state
6. **Test before commit**: Run `zig build test` before committing. Integration tests (`zig build integration-test`) are optional

### Examples

Good:

```text
feat(llm): add OpenAI client with serde JSON serialization

Replace hand-written JSON parsing with serde library for robust
request/response handling. Uses ArenaAllocator for response memory
management. All 28 unit tests and 3 integration tests pass.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

Bad:

```text
update stuff
```

```text
fixed bug
```

## Commit Process

1. **Run tests**: `zig build test` must pass. For changes touching HTTP/LLM code, also run `zig build integration-test`.
2. **Run lint** (if available): `zig fmt --check src/` to ensure formatting is correct.
3. Run `git status` to see all changed files
4. Run `git diff` to review changes
5. Draft the commit message following the format above
6. Stage specific files with `git add <file>` — never use `git add -A` or `git add .`
7. Create the commit using a heredoc for the message
8. Verify with `git status` after commit

### Pre-commit Checklist

- [ ] `zig build test` passes
- [ ] No unrelated files staged
- [ ] No secrets or credentials in staged files
- [ ] `.gitignore` covers build artifacts and local config

## Co-Authored-By

Every commit must include:

```text
Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```
