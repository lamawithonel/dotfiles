---
paths:
  - "**/*.rs"
  - "**/Cargo.toml"
---

# Rust Code Style

- All files MUST have `#![deny(warnings)]`
- All files MUST have `#![deny(unsafe_code)]` **unless** the file
  appears in the project's unsafe allowlist (below)
- All public items MUST have doc comments
- Use snake_case for all Rust file names

Project rules may extend this file with domain-scoped requirements
(embedded logging backends, crate-naming schemes, dependency
preference orders); where a project rule and this file conflict, the
project rule wins inside that project.

## Unsafe Code Isolation Policy

Isolating `unsafe` to specific files enables `#![deny(unsafe_code)]`
as a linter and early compiler check across the vast majority of the
codebase.

Each project maintains its own allowlist table -- file path plus a
one-line justification -- in its project rules.  A project with no
table has an empty allowlist.

**Rules:**

- Allowed files MUST be minimal-- only the code that *requires*
  `unsafe` belongs there.  Business logic, protocol handling, and
  other safe code must live in separate modules that `use` the unsafe
  files.
- Every `unsafe` block or `unsafe fn` MUST have a `// SAFETY:`
  comment documenting why it is sound.
- When a safe module (`#![deny(unsafe_code)]`) must call an
  `unsafe fn` from an allowed file, use a **function-level**
  `#[allow(unsafe_code)]` on the narrowest possible scope:

  ```rust
  #![deny(unsafe_code)]

  #[allow(unsafe_code)]
  fn get_buffers() -> (&'static mut [u8], &'static mut [u8]) {
      // SAFETY: called once during init; no concurrent access
      unsafe { ccmram::tls_buffers() }
  }
  ```

- **Adding a new file to an allowlist requires explicit user
  approval.**  Ask before creating a new `#![allow(unsafe_code)]`
  file, and update the project's allowlist table when approved.
