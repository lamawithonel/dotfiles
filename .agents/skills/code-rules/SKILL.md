---
name: code-rules
description: >-
  Defines coding rules and standards for use when programming or writing
  code.  Always use it **before** analyzing, planning, designing, refactoring,
  writing, reasoning about, or suggesting code or files for any supported
  language.  The supported languages are: Bash, POSIX shell, zsh, Rust, Mojo,
  Python, TypeScript, JavaScript, Go, and Zig.
license: Apache-2.0
---

# Code Rules & Language Standards

Read the language standard from @~/.agents/rules/ before you make a plan
or write code.

## Procedure

1. **Identify Language**: Determine target language(s), e.g., Rust, Mojo,
   Python, TypeScript, JavaScript, Go, Shell, etc.
2. **Read Standard**: Load `~/.agents/rules/<lang>.md` with the `read` tool.
   Do not plan or write code before loading the file.
3. **Apply Invariants**: Follow the types, error handling, lifecycles, and
   static check batteries defined in that rule file.
