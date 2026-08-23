---
paths:
  - "**/*.py"
  - "**/pyproject.toml"
---

# Instructions for Writing Python

## Type Safety & Data Modeling

- Use Python 3.11+ built-in generic collections (`list[T]`, `dict[K, V]`, `tuple[T, ...]`) and union operators (`T | None`, `A | B`).
- Do not import legacy collections from `typing` (`typing.List`, `typing.Dict`, `typing.Optional`, `typing.Union`).
- Provide explicit type annotations for all function parameters, return values, and public module constants.
- Prefer abstract parameter types (`Sequence[T]`, `Mapping[K, V]`, `Iterable[T]`) for read-only arguments instead of concrete mutable types (`list[T]`, `dict[K, V]`).
- Use `typing.Protocol` for structural subtyping and interface minimization at consumer boundaries.
- Use `@dataclass(frozen=True, slots=True)` or `NamedTuple` for immutable domain models, value objects, and internal state.
- Use `typing.assert_never()` inside `match` default cases to enforce compile-time exhaustiveness checking over Enums and Union types.
- Restrict Pydantic models strictly to external boundaries (HTTP payloads, configuration, CLI parsing); use native types internally.

## Code Style & Architecture

- Format and lint all code with `ruff` following PEP 8 and PEP 257 standards.
- Avoid module-level execution side effects and mutable global state; guard entrypoints with `if __name__ == "__main__":`.
- Never use mutable default arguments in function definitions; use `None` and initialize inside the function body.
- Use `UPPER_SNAKE_CASE` typed with `Final` for constants, `lower_snake_case` for functions/variables, and `PascalCase` for classes.
- Manage resource lifetimes explicitly using context managers (`with` and `async with`).
- Use structured concurrency with `asyncio.TaskGroup` instead of unconstrained `asyncio.gather` or detached background tasks.

## Error Handling

- Catch specific exception types; never use bare `except:` or catch unconstrained `Exception` without re-raising.
- Define custom domain exception hierarchies inheriting from a shared base project exception.
- Preserve exception causality chains using `raise CustomError("context") from err`.
- Use `except*` when handling concurrent errors spawned from `ExceptionGroup` and `asyncio.TaskGroup`.
- Use `contextlib.suppress()` only when intentionally and safely ignoring specific, documented exceptions.

## Imports & Dependencies

- Manage dependencies and tool configurations in `pyproject.toml` (PEP 621).
- Place all imports at the top of the file; do not use wildcard imports (`from module import *`) or runtime lazy imports.
- Maintain standard import ordering: standard library, third-party packages, local application modules.

## Testing

- Write test suites with `pytest`; prefer fixtures and parameterized tests (`@pytest.mark.parametrize`) over `unittest.TestCase`.
- Follow the Arrange-Act-Assert pattern with explicit assertions.
- Type-annotate test helper functions and fixture signatures.
- Target deterministic execution by mocking external I/O boundaries rather than internal domain functions.

## Static Checks & Quality Gates

Run the verification battery after creating or editing any Python file.

### The Battery

    ruff check FILE
    ruff format --check FILE
    pyright FILE

### Pass Criteria & Exceptions

- **`ruff check` / `pyright`**: 0 errors, 0 warnings, exit code 0.
- **`ruff format --check`**: Diff must be empty (exit code 0).
- **Cyclomatic Complexity**: CCN <= 10 per function (enforced via `ruff` rule `C901` or `radon cc`).
- **Pattern Matching CCN Exception**: Functions consisting of a single flat `match` block or dispatch table may reach CCN 20, provided branches are <= 3 lines with zero nested conditionals.
- **Untyped Boundary Exception**: `Any` and `# type: ignore[code]` are permitted strictly at external package boundaries lacking type stubs; always specify the exact error code.

## Documentation

- Write concise docstrings (PEP 257) summarizing purpose and non-obvious invariants; omit type annotations from docstring prose.
- Keep comments focused on intent and edge cases rather than repeating obvious mechanics.
