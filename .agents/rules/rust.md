---
paths:
  - "**/*.rs"
  - "**/Cargo.toml"
  - "**/Cargo.lock"
---

# Instructions for Writing Rust

## Type Safety & Data Modeling

- Make invalid states unrepresentable: model domain entities and state machines as tagged `enum` variants; avoid structs with ambiguous optional fields.
- Use the Newtype pattern (`struct UserId(u64)`) to enforce type-level domain boundaries and eliminate primitive obsession.
- Use `NonZero*` numeric types (`NonZeroU32`, `NonZeroUsize`) where zero is invalid to enable compiler `Option` niche layout optimization.
- Mark all functions returning values that must not be silently ignored with `#[must_use]`.
- Accept borrowed views (`&str`, `&[T]`, `impl AsRef<Path>`) in function parameters; use `Cow<'a, T>` for conditionally borrowed/owned data.
- Derive standard traits aggressively: `#[derive(Debug, Clone, PartialEq, Eq)]`; implement `Default` instead of parameterless `new()`.

## Code Style & Architecture

- All files MUST have `#![deny(warnings)]`.
- All files MUST have `#![deny(unsafe_code)]` unless explicitly allowlisted (see Unsafe Policy below).
- Separate data from behavior: define clean `struct` and `enum` data models and implement traits for operations.
- Prefer iterator pipelines (`.iter().filter().map()`) over manual loop indexing to eliminate boundary checks and indexing bugs.
- Emulate RAII via the `Drop` trait for deterministic teardown of handles, sockets, and lock guards.
- Use `const fn` for compile-time lookup tables, conversions, and pure static evaluations.
- Use `snake_case` for file and module names, `PascalCase` for types and traits, and `SCREAMING_SNAKE_CASE` for statics and constants.

## Embedded & #![no_std] Disciplines

- Maintain strict `#![no_std]` compatibility on bare-metal and embedded targets:
  - Rely exclusively on `core` types; do not import `std` or `alloc` unless a global allocator is explicitly configured.
  - Use fixed-capacity stack containers (`heapless::Vec`, `heapless::String`, `[u8; N]`) instead of dynamic heap allocations.
- Zero-allocation domain errors: define lightweight `core`-only error enums deriving `defmt::Format` (for RTT) or `core::fmt::Debug`.
- Peripheral & Register Safety: isolate memory-mapped I/O (MMIO), PAC register accesses, and interrupt handlers behind `embedded-hal` drivers or dedicated unsafe modules with explicit `// SAFETY:` proofs.
- Embedded Logging: use `defmt` or `rtt-target` for deferred binary logging over SWD/RTT; never use standard `println!`.
- Flashing & Hardware Operations: per global rules, use `cargo build`, `cargo embed`, and `probe-rs` for build and flash operations.

## Error Handling

- Treat errors as values and distinguish domain libraries from binaries:
  - For standard `std` libraries: define strongly typed domain error enums using `thiserror` with `#[source]` causality attributes.
  - For standard CLI tools/applications: use `miette` or `anyhow` for rich user-facing error reporting.
  - For `#![no_std]` embedded crates: use zero-allocation enums implementing `core::fmt::Display` and `defmt::Format`.
- Propagate errors idiomatically using the `?` operator; never use raw `.unwrap()` or `.expect()` in production code.
- Mark panics and preconditions explicitly in documentation comments under a `# Panics` section.

## Unsafe Code Isolation Policy

Isolating `unsafe` to specific files enables `#![deny(unsafe_code)]` as a compiler gate across the vast majority of the codebase.

Each project maintains its own allowlist table -- file path plus a one-line justification -- in its project rules.  A project with no table has an empty allowlist.

**Rules:**
- Allowed files MUST be minimal: only the code that *requires* `unsafe` (e.g., MMIO, FFI, raw pointers, SIMD) belongs there; domain logic must live in safe modules.
- Every `unsafe` block or `unsafe fn` MUST have a `// SAFETY:` comment documenting why the operation is sound and invariants hold.
- When a safe module must call an `unsafe fn`, use a function-level `#[allow(unsafe_code)]` on the narrowest possible scope:
  ```rust
  #![deny(unsafe_code)]

  #[allow(unsafe_code)]
  fn get_buffers() -> (&'static mut [u8], &'static mut [u8]) {
      // SAFETY: called once during init; no concurrent access
      unsafe { ccmram::tls_buffers() }
  }
  ```
- Adding a new file to an allowlist requires explicit user approval.

## Testing & Verification

- Organize test suites into unit tests (inline `mod tests` with `#[cfg(test)]`) and integration tests in `tests/`.
- Follow the Arrange-Act-Assert (AAA) pattern.
- Use `proptest` for property-based invariant verification and round-trip serialization tests.
- When formal verification is required on safety-critical algorithms or unsafe blocks, write Kani proof harnesses (`cargo kani`).
- Run `cargo miri test` when validating isolated unsafe data structures for undefined behavior.
- For embedded crates: test logic on host via `cargo test --lib`; test on target via `defmt-test` or `probe-rs test`.

## Static Checks & Quality Gates

Run the verification battery after creating or editing any Rust source or manifest file.

### The Battery

    cargo check --all-targets
    cargo clippy --all-targets --all-features -- -D warnings
    cargo test --all-targets --all-features
    cargo fmt --check

### Pass Criteria & Exceptions

- **`cargo check`**: 0 compiler diagnostics (exit code 0).
- **`cargo clippy`**: 0 errors, 0 warnings with `-D warnings`.
- **`cargo test`**: All unit, integration, and doc tests PASS.
- **`cargo fmt`**: Diff must be empty (exit code 0).
- **Embedded Target Checks**: For `#![no_std]` targets, run `cargo clippy --target <target-triple>`.
- **Unsafe Allowlist Exception**: Unsafe code is permitted strictly in modules designated in the project allowlist, guarded by `// SAFETY:` proofs.

## Documentation

- All public items (modules, structs, enums, traits, functions) MUST have `///` doc comments.
- Structure documentation comments with standard sections: `# Errors`, `# Panics`, and `# Examples` (tested via `cargo test --doc`).
- Focus comments on invariants, safety boundaries, and rationale rather than repeating syntax.
