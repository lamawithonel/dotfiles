---
paths:
  - "**/*.js"
  - "**/*.mjs"
  - "**/*.cjs"
  - "**/jsconfig.json"
  - "**/package.json"
---

# Instructions for Writing JavaScript

## Type Safety & Data Modeling

- Enable static type checking on JavaScript source files using `// @ts-check` at file headers or `checkJs: true` in `jsconfig.json` when permissible.
- Document function signatures, parameters, return types, and module constants using strict JSDoc annotations (`@param`, `@returns`, `@type`, `@typedef`).
- Make invalid states unrepresentable: model domain entities and state machines as discriminated unions using JSDoc `@typedef`; avoid bags of optional fields.
- Avoid loose dynamic types; type unknown external inputs as `unknown` and parse at ingress boundaries.
- Freeze lookup tables, static configurations, and tuple constants using `Object.freeze()` paired with `/** @type {const} */`.
- Standardize on `undefined` for optional values and missing lookups (Option pattern); restrict `null` strictly to external DOM and database boundaries.
- Treat parameters as immutable borrows: do not mutate objects or arrays passed into functions; return fresh copies or transformed structures.
- Enforce domain invariants via nominal branding (`/** @typedef {string & { readonly __brand: unique symbol }} UserId */`) instantiated through validating factory functions.

## Code Style & Architecture

- Use ES Modules (`import`/`export`) by default with `"type": "module"` in `package.json`; avoid CommonJS (`require`/`module.exports`) unless targeting legacy runners.
- Separate data from behavior: define domain models as plain data objects and write pure functions for operations; avoid class inheritance hierarchies.
- Write pure, composable functions by default; use classes only for stateful encapsulation, framework contracts, or `Disposable` resources.
- Use `async`/`await` for asynchronous control flow; avoid `.then()`/`.catch()` promise chains.
- Manage deterministic resource cleanup via TC39 Explicit Resource Management (`using` / `await using` with `Symbol.dispose` / `Symbol.asyncDispose`).
- Pass `AbortSignal` to asynchronous workflows that support cancellation or timeouts.
- Use `Promise.allSettled()` for concurrent operations where independent sub-task failures should not abort the batch.
- Use `const` for all variable declarations; use `let` only when reassignment is strictly required.
- Use object destructuring for functions accepting 4 or more configuration parameters.
- Use explicit unit suffixes for numeric values: `_count` (items), `_index` (position), `_size_bytes` (memory), `_ms` (duration).

## Error Handling

- Distinguish recoverable domain errors from fatal runtime defects:
  - Return discriminated value objects (`/** @type {Result<T, E>} */`) with `{ ok: true, value } | { ok: false, error }` for expected domain error branches.
  - Reserve `throw` strictly for unrecoverable infrastructure crashes and unhandled programmer invariant violations.
- When throwing, instantiate `Error` or custom domain subclasses; never throw strings or raw literals.
- Preserve causal stack traces using native error causes: `new DomainError("message", { cause: err })`.
- Treat caught errors in `catch (err)` as unknown; narrow types using `instanceof Error` before accessing properties.
- Avoid empty or silent catch blocks; log or handle every caught error explicitly.

## Naming & Organization

- Use `kebab-case` for file and directory names.
- Use `camelCase` for variables, functions, and methods.
- Prefix boolean variables and functions with auxiliary verbs (e.g., `isValid`, `hasPermission`, `canExecute`).
- Use `PascalCase` for classes and JSDoc typedef names.
- Use `UPPER_SNAKE_CASE` for immutable global constants.

## Testing

- Write test suites using native `node:test` and `node:assert/strict` (or `vitest`); follow the Arrange-Act-Assert (AAA) pattern with explicit assertions.
- Use `fast-check` property-based testing to verify algorithmic invariants, commutativity, and serialization round-trips.
- Mock external network and filesystem I/O at adapter boundaries; do not mock internal pure domain functions.

## Static Checks & Quality Gates

Run the verification battery after creating or editing any JavaScript file.

### 1. Turn-by-Turn Battery (Run on every edit)

    npx tsc --noEmit --allowJs --checkJs FILE
    npx eslint FILE --max-warnings 0

### 2. Pre-Commit Boundary Gates (Run before task completion)

    npx knip
    npx depcruise src --max-circular 0

### Pass Criteria & Exceptions

- **`tsc` / `eslint`**: 0 errors, 0 warnings, exit code 0.
- **Cyclomatic Complexity**: McCabe complexity <= 10, max nesting depth <= 3 (ESLint `complexity`, `max-depth`).
- **Promise Safety**: 0 floating promises or misused asynchronous predicates (`no-floating-promises`, `no-misused-promises`).
- **`knip` / `depcruise`**: 0 orphaned exports, unused files, or circular dependencies at project milestones.
- **Zero-Dependency Enhancements**: Non-invasive improvements (`// @ts-check` headers or JSDoc annotations on new/modified files) are encouraged when contributing to external codebases, provided they add zero dependencies and the project does not actively forbid them.
- **Active Project Restrictions**: If an external project explicitly forbids type comments or header directives, enforce invariants via defensive runtime guards (`typeof`, `instanceof`, `?.`, `??`) and match host repository conventions.
- **Ingress Parsing Exception**: Untyped payload unwrapping is permitted strictly at ingress schema boundaries (`ArkType`/`Valibot`/`Zod`); internal domain models must be 100% strongly typed via JSDoc.
- **Flat Dispatcher Exception**: Flat `switch` tables, AST tokenizers, and state dispatchers may reach CCN 20, provided branches have 0 nested conditionals and 100% test branch coverage.
- **Build-Free Scripts Exemption**: Standalone, single-file root automation scripts without `package.json` are exempt from `knip` and `depcruise` checks.

## Documentation

- Document exported symbols and public contracts using JSDoc `/** ... */`.
- Focus comments on business logic, domain constraints, and non-obvious invariants rather than repeating syntax.
