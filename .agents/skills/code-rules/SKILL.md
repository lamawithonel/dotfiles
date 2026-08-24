---
name: code-rules
description: Load mandatory language standards from ~/.agents/rules/<lang>.md before planning or writing code in Rust, Mojo, Go, Python, Zig, TypeScript, JavaScript, or Shell.  Use when planning, designing, refactoring, or writing code in any supported language.
license: Apache-2.0
---

# Code Rules & Language Standards

Read the language standard from `~/.agents/rules/` before you make a plan
or write code.

## Procedure

1. **Identify Language**: Determine target languages (Rust, Mojo, Go, Python,
   Zig, TypeScript, JavaScript, Shell).
2. **Read Standard**: Load `~/.agents/rules/<lang>.md` with the `read` tool.
   Do not plan or write code before loading the file.
3. **Apply Invariants**: Follow the types, error handling, lifecycles, and
   static check batteries defined in that rule file.
