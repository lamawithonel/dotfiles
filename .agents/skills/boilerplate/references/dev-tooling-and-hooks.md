# Developer Tooling & Git Hooks (jdx Stack)

Tooling configuration standards using the jdx suite (`mise`, `hk`, `fnox`, `pitchfork`).

---

## 1. Environment & Task Runner (`mise.toml`)

Standardize toolchain versions, environment variables, and lifecycle tasks
at repository root:

```toml
[tools]
# Pin exact compiler/runtime versions per project
# rust = "1.85.0"
# node = "22.14.0"
# python = "3.12.9"
# go = "1.24.0"
# zig = "0.14.0"

[env]
# Standard environment overrides
RUST_BACKTRACE = "1"
# Load encrypted secrets via fnox where applicable
# _.fnox.load = true

[tasks.check]
description = "Run Tier 1 turn-by-turn compiler and static analysis checks"
run = "cargo check && cargo clippy -- -D warnings"

[tasks.test]
description = "Execute automated test pyramid"
run = "cargo test"

[tasks.fmt]
description = "Check or apply canonical code formatting"
run = "cargo fmt -- --check"

[tasks.lint]
description = "Run linter battery"
run = "cargo clippy -- -D warnings"

[tasks.ci]
description = "Full CI verification battery"
depends = ["fmt", "check", "test"]
```

---

## 2. Fast Git Hooks (`hk.toml`)

Use `hk` (written in Rust by jdx) for instant, zero-dependency git hook
orchestration that directly bridges to language rule batteries:

```toml
# hk.toml

[hooks.pre-commit]
description = "Execute Tier 1 turn-by-turn checks before committing"
run = "mise run check"

[hooks.pre-push]
description = "Execute full test suite and milestone gates before pushing"
run = "mise run test"
```

### Hook Execution Rules

- **Pre-Commit**: Must execute in $< 2$ seconds.  Restricted to Tier 1
  fast linters and syntax checks on staged files.
- **Pre-Push**: May execute the broader test suite, integration tests, and
  Tier 2 milestone gates.

---

## 3. Secret Management (`fnox.toml`)

Avoid committing raw `.env` files containing secrets or API tokens.  Use
`fnox` for age-based local secret encryption:

```toml
# fnox.toml
[keys]
# Local developer age key
default = "age1..."

[secrets]
API_KEY = "encrypted:..."
DATABASE_URL = "encrypted:..."
```

---

## 4. Git Invariants (`.gitignore` & `.gitattributes`)

### Universal `.gitignore` Baseline

```gitignore
# Host-local and temporary agent workspaces
.local/
.cache/
*.tmp
*.bak

# Environment & Secrets (unencrypted)
.env
.env.*
!.env.example

# OS Metadata
.DS_Store
Thumbs.db
Desktop.ini

# Language Build Artifacts
target/
dist/
build/
node_modules/
__pycache__/
*.pyc
.zig-cache/
zig-out/
```

### Standard `.gitattributes` Baseline

```gitattributes
# Normalize line endings to LF across all platforms
* text=auto eol=lf

# Explicit binary files
*.png binary
*.jpg binary
*.ico binary
*.wasm binary
*.so binary
*.dylib binary
*.dll binary
```
