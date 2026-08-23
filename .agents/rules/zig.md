---
paths:
  - "**/*.zig"
  - "**/build.zig"
  - "**/build.zig.zon"
---

# Instructions for Writing Zig

## Memory Management & Allocators

- Never allocate implicitly or rely on hidden global allocators; accept `std.mem.Allocator` as an explicit parameter in all allocating functions.
- Name allocator parameters semantically by ownership contract: `gpa` for caller-owned long-lived data, `arena` for batch/request scopes, and `scratch` for function-local temporaries.
- Use unmanaged containers by default (`std.ArrayList(T) = .empty`, `std.AutoHashMapUnmanaged = .empty`); pass the allocator at mutating call sites.
- Prefer stack-allocated buffers and `std.fmt.bufPrint` over heap allocations when maximum capacity is comptime-known.
- Invalidate instance memory in `deinit` methods with `self.* = undefined;` to turn use-after-free bugs into deterministic debug crashes.

## Resource Lifecycles & Error Handling

- Release internal temporary allocations with `defer allocator.free(...)` immediately after successful allocation.
- Use `errdefer allocator.free(...)` for rollback cleanup during multi-step struct initialization.
- Declare explicit, narrow error sets (e.g., `pub const ParseError = error{ InvalidToken, OutOfMemory };`) on public APIs rather than generic `anyerror`.
- Use checked numeric conversions (`std.math.cast(T, val)`) and enum casts (`std.meta.intToEnum(T, val)`) instead of unchecked `@intCast` or `@enumFromInt`.
- Unwrap optionals idiomatically with payload captures (`if (opt) |val|`) or defaults (`opt orelse default`); avoid unchecked `.?` unwraps.

## Type Safety & Comptime

- Use slices (`[]T`, `[]const T`) for bounds-checked data views; restrict many-item pointers (`[*]T`) strictly to C FFI boundaries.
- Pass read-only structs larger than 16 bytes by constant reference (`*const T`) to eliminate redundant copies.
- Evaluate lookup tables, type generators, and static assertions at compile time using `comptime` blocks and `comptime assert(...)`.
- Match tagged unions exhaustively using `switch (union_val) { .tag => |payload| ... }`.

## Naming & Style Conventions

- Use `TitleCase` for types and type-returning functions (`ArrayList`, `Parser`), `camelCase` for functions and methods (`parseJson`, `readU32`), and `snake_case` for variables, constants, and namespaces (`std.json`, `buffer_size`).
- Use explicit numeric suffixes to eliminate unit confusion: `_count` (items), `_index` (item position), `_size` (bytes), and `_offset` (byte position).
- Organize imports into distinct groups: standard library (`std`), third-party packages, and local files.

## Testing & Build System

- Use `std.testing.allocator` in all `test` blocks to automatically enforce leak-free execution.
- Use domain-specific test assertions (`expectEqualStrings`, `expectEqualSlices`) rather than raw equality.
- Expose `b.standardTargetOptions(.{})` and `b.standardOptimizeOption(.{})` in `build.zig`.

## Static Checks & Quality Gates

Run the verification battery after creating or editing any Zig source or build file.

### The Battery

    zig fmt --check FILE
    zig test FILE

### Pass Criteria & Exceptions

- **`zig fmt --check`**: Diff must be empty (exit code 0).
- **`zig test`**: All test blocks PASS with 0 memory leaks reported by `std.testing.allocator`.
- **C FFI Boundary Exception**: Many-item pointers (`[*]T`), `extern struct`, and raw `@ptrCast` are permitted strictly within C FFI wrapper modules.
- **Provably Infallible Exception**: `catch unreachable` is permitted only when an operation is statically proven incapable of failure (e.g., `bufPrint` into a comptime-sized stack buffer).

## Documentation

- Document public APIs using `///` doc comments starting with the symbol name, detailing parameters, errors, and memory ownership contracts.
- Focus code comments on non-obvious business logic, domain constraints, and rationale rather than mechanics.
