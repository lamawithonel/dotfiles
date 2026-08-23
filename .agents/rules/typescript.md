---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/tsconfig.json"
  - "**/tsconfig.*.json"
---

# Instructions for Writing TypeScript

## Type Safety & Data Modeling

- Make invalid states unrepresentable: model domain entities and state machines as discriminated unions with a literal tag (`kind`, `type`, or `status`); avoid bags of optional fields.
- Avoid `any` in production code; type unknown external inputs as `unknown` and parse at boundaries.
- Allow `any` in unit tests strictly for mocking complex dependencies where `Partial<T>` is insufficient.
- Use `type` for unions, intersections, ADTs, and primitives; use `interface` for structural object shapes intended for public extension or trait-like behavior.
- Use `satisfies` operator to validate value shapes against types without widening inferred literal types.
- Freeze lookup tables, static configurations, and tuple constants with `as const`.
- Enforce compile-time exhaustiveness on discriminated unions using `assertNever(x: never)` in `switch` default cases.
- Standardize on `undefined` (`T | undefined`) for optional values and missing lookups (Option pattern); restrict `null` strictly to external DOM/database boundaries.
- Use `readonly` for array, tuple, and object parameters that are not mutated by the callee (`Readonly<T>`, `readonly T[]`).
- Enforce domain invariants via nominal branding (`type UserId = string & { readonly __brand: unique symbol }`) instantiated through validating smart constructors.

## Code Style & Architecture

- Separate data from behavior: define domain models as plain data types/interfaces and write pure functions for operations; avoid class inheritance hierarchies.
- Use pure, composable functions by default; use classes only for stateful encapsulation, framework contracts, or `Disposable` resources.
- Use `async`/`await` for asynchronous control flow; avoid `.then()`/`.catch()` promise chains.
- Manage deterministic resource cleanup via TC39 Explicit Resource Management (`using` / `await using` with `Symbol.dispose` / `Symbol.asyncDispose`).
- Pass `AbortSignal` to asynchronous workflows that support cancellation or timeouts.
- Use `Promise.allSettled()` for concurrent operations where independent sub-task failures should not abort the batch.
- Use `const` for all variable declarations; use `let` only when reassignment is strictly required.
- Use object destructuring for functions accepting 4 or more configuration parameters.
- Use `import type { ... }` for type-only imports to eliminate circular dependency runtime locks and optimize tree-shaking.
- Use explicit unit suffixes for numeric values to simplify fixed-width type mapping: `_count` (items), `_index` (position), `_size_bytes` (memory), `_ms` (duration).

## Error Handling

- Distinguish recoverable domain errors from fatal runtime defects:
  - Return discriminated value unions (`type Result<T, E = Error> = { ok: true; value: T } | { ok: false; error: E }`) for expected domain error branches.
  - Reserve `throw` strictly for unrecoverable infrastructure crashes and unhandled programmer invariant violations.
- When throwing, instantiate `Error` or custom domain subclasses; never throw strings or raw literals.
- Preserve causal stack traces using native error causes: `new DomainError("message", { cause: err })`.
- Annotate `catch (err: unknown)` variables as `unknown` and narrow types using `instanceof` or type predicates before property access.
- Avoid empty or silent catch blocks; log or handle every caught error explicitly.

## Naming & Organization

- Use `kebab-case` for file and directory names.
- Use `camelCase` for variables, functions, and methods.
- Prefix boolean variables and functions with auxiliary verbs (e.g., `isValid`, `hasPermission`, `canExecute`).
- Use `PascalCase` for classes, interfaces, types, and enums.
- Do not use Hungarian `I` prefixes for interfaces (`User`, not `IUser`).
- Use `UPPER_SNAKE_CASE` for immutable global constants.

## Testing

- Write test suites with `vitest` or `node:test`; follow the Arrange-Act-Assert (AAA) pattern with explicit assertions.
- Use `fast-check` property-based testing to verify algorithmic invariants, commutativity, and serialization round-trips.
- Mock external network and filesystem I/O at adapter boundaries; do not mock internal pure domain functions.

## Static Checks & Quality Gates

Run the verification battery after creating or editing any TypeScript file.

### 1. Turn-by-Turn Battery (Run on every edit)

    npx tsc --noEmit
    npx eslint FILE --max-warnings 0

### 2. Pre-Commit Boundary Gates (Run before task completion)

    npx knip
    npx depcruise src --max-circular 0

### Pass Criteria & Exceptions

- **`tsc --noEmit` / `eslint`**: 0 errors, 0 warnings, exit code 0.
- **Cyclomatic Complexity**: McCabe complexity <= 10, max nesting depth <= 3 (ESLint `complexity`, `max-depth`).
- **Promise Safety**: 0 floating promises or misused asynchronous predicates (`no-floating-promises`, `no-misused-promises`).
- **`knip` / `depcruise`**: 0 orphaned exports, unused files, or circular dependencies at project milestones.
- **Generic Constraint Exception**: `(...args: any[]) => unknown` is permitted strictly in generic parameter constraints (`<F extends (...args: any[]) => unknown>`) to preserve caller argument inference.
- **Ingress Parsing Exception**: Untyped payload unwrapping is permitted strictly at ingress schema boundaries (`ArkType`/`Valibot`/`Zod`); internal domain models must be 100% strongly typed.
- **Flat Dispatcher Exception**: Flat `switch` tables, AST tokenizers, and state dispatchers may reach CCN 20, provided branches have 0 nested conditionals and 100% test branch coverage.
- **Untyped Module Exception**: Missing third-party type definitions must be contained in an isolated adapter module with a local `declare module` ambient declaration.

## Documentation

- Document exported symbols and public contracts using JSDoc `/** ... */`.
- Focus comments on business logic, domain constraints, and non-obvious invariants rather than repeating syntax.
