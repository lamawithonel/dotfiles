---
paths:
  - "**/*.go"
  - "**/go.mod"
---

# Instructions for Writing Go

## Package Architecture & API Design

- Separate application entrypoints into `cmd/<binary>/main.go` and core domain logic into `internal/`.
- Name packages with short, single-word, lowercase identifiers without underscores or mixed caps.
- Accept interfaces, return structs; declare narrow, single-purpose interfaces at consumer call sites.
- Avoid repeating package names in exported types (e.g., use `user.Service`, not `user.UserService`).
- Avoid `init()` registration side effects and mutable package-level globals; use explicit dependency injection.

## Type Safety & Value Semantics

- Use value receivers for immutable types and small structs; use pointer receivers when mutating state or managing synchronization primitives.
- Always use the comma-ok idiom (`v, ok := val.(TargetType)`) or type switches for type assertions; never use bare type assertions.
- Use directional channel types (`<-chan T`, `chan<- T`) in function parameters to restrict read/write capabilities.
- Keep struct tags minimal, lowercase, and explicitly mapped to serialization contracts (e.g., `json:"fieldName"`).

## Concurrency & Resource Management

- Accept `context.Context` as the first parameter on all functions performing I/O, network calls, or cancellations.
- Do not store contexts in struct fields or pass `nil`; propagate caller contexts downstream.
- Manage goroutine lifecycles explicitly with `sync.WaitGroup` or context cancellation; never spawn un-tracked goroutines.
- Release resources immediately after acquisition using `defer` (e.g., `defer resp.Body.Close()`, `defer mu.Unlock()`).
- Prefer channels for data ownership transfer; use `sync.Mutex` only for localized struct state invariants.

## Error Handling

- Check all returned errors explicitly; never discard errors with bare `_ =` assignments without a documented reason.
- Wrap errors with context using `fmt.Errorf("operation failed: %w", err)` to preserve inspection chains.
- Combine concurrent or multi-step errors using `errors.Join()`.
- Declare sentinel errors as package variables using `errors.New` and custom error payloads as distinct struct types.
- Inspect errors using `errors.Is()` and `errors.As()` rather than string matching.
- Avoid `panic` in runtime application paths; reserve `panic` strictly for unrecoverable boot-time configuration errors.

## Imports & Standard Library

- Favor the Go standard library and official `golang.org/x/...` packages over external dependencies.
- Use `log/slog` for structured logging; include contextual log attributes with context-aware methods (`InfoContext`, `ErrorContext`).
- Use standard `net/http` constructs instead of heavyweight web frameworks for service boundaries.

## Testing

- Write table-driven tests in `*_test.go` files using slice-of-struct cases with `want` and `got` field names.
- Execute subtests with `t.Run(tt.name, func(t *testing.T) { ... })` and call `t.Parallel()` on independent test cases.
- Call `t.Helper()` at the start of test helper functions to maintain accurate failure line attribution.
- Use `httptest` for HTTP handler tests and mock interfaces with lightweight fakes instead of heavy mocking frameworks.

## Static Checks & Quality Gates

Run the verification battery after creating or editing any Go file.

### The Battery

    gofmt -d FILE
    go vet ./...
    go test -race ./...

### Pass Criteria & Exceptions

- **`gofmt -d`**: Diff must be empty (exit code 0).
- **`go vet`**: 0 diagnostics, exit code 0.
- **`go test -race`**: All tests PASS with 0 detected data races.
- **Serialization Exception**: `any` is permitted strictly for generic serialization contracts (`json.Marshal`), reflection boundaries, and structured log attributes (`slog`).

## Documentation

- Document all exported packages, types, functions, and methods with doc comments starting with the symbol name.
- Focus code comments on non-obvious business logic, domain constraints, and rationale rather than mechanics.
