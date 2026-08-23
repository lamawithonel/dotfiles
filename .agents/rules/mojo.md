---
paths:
  - "**/*.mojo"
  - "**/*.🔥"
---

# Instructions for Writing Mojo

## Syntax & Core Constraints

- Use `def` exclusively for all functions, methods, and closures; `fn` is removed and causes compilation errors.
- Declare all new variables explicitly with `var name: Type = value`; bare variable assignments without `var` are invalid.
- Mark functions that can raise with `raises` before the return type arrow (e.g., `def parse(s: String) raises -> Int:`).
- Use `comptime` for compile-time constants, type aliases, branches (`comptime if`), loops (`comptime for`), and assertions (`comptime assert`).
- Place `comptime assert` statements inside function bodies, not at root module scope.

## Memory Safety & Value Semantics

- Apply argument conventions explicitly when departing from default immutable borrow (`imm`): `mut` (mutable reference), `var` (owned value), `out` (uninitialized output), and `deinit` (consuming ownership).
- Use `@fieldwise_init` and declare trait conformances (`Copyable`, `Movable`, `Writable`) on structs.
- Qualify generic struct parameter references inside struct definitions with `Self.T` (e.g., `var data: Self.T`).
- Transfer ownership with `^` or invoke `.copy()` explicitly on types that do not implement `ImplicitlyCopyable` (e.g., `List`, `Dict`).
- Use bracket literals for collections (`[1, 2, 3]`, `{"k": "v"}`); `List` has no variadic positional constructor.
- Access strings by byte index (`s[byte=i]`) or codepoints (`s.codepoint_slices()`); slice ranges on `String` are invalid.
- Implement `Writable` (`write_to`) for string representations instead of deprecated `Stringable`.

## Python Interoperability

- Import Python runtime modules via `from std.python import Python, PythonObject`.
- Pass the `py=` keyword argument when converting `PythonObject` to native Mojo scalar types (e.g., `Int(py=obj)`, `String(py=obj)`).
- Build Python collections explicitly using `Python.list()`, `Python.tuple()`, and `Python.dict()`.
- Export Python extension modules using `@export def PyInit_<name>() abi("C") -> PythonObject` and `PythonModuleBuilder`.  Do not include `main()` in extension module files.
- Align domain struct shapes and value object definitions with `python.md` models for bidirectional interop.

## Imports & Standard Library

- Prefix all explicit standard library imports with `std.` (e.g., `from std.os import getenv`, `from std.collections import List`).
- Rely on standard prelude types (`Int`, `String`, `Bool`, `List`, `Dict`, `Optional`, `Pointer`, `UnsafePointer`) without explicit imports.

## Testing

- Write unit tests using `std.testing` assertions (`assert_equal`, `assert_true`, `assert_raises`).
- Execute test discovery using `TestSuite.discover_tests[__functions_in_module()]().run()` in test module `main()`.

## Static Checks & Quality Gates

Run the verification battery after creating or editing any Mojo file.

### The Battery

    mojo format --check FILE
    mojo run FILE

### Pass Criteria & Exceptions

- **`mojo format --check`**: Diff must be empty (exit code 0).
- **`mojo run`**: Clean compilation with 0 syntax/type errors and 100% test pass in `TestSuite`.
- **Python FFI Boundary Exception**: Dynamic `PythonObject` manipulation is permitted strictly inside adapter functions immediately prior to converting to native Mojo types via `Type(py=obj)`.
- **Low-Level Container Exception**: `UnsafePointer` and `MutUntrackedOrigin` are permitted strictly within internal memory container structs that expose safe, leak-free public APIs.
