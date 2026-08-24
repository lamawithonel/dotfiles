# Governance, Metadata & CI Baselines

Standards for licensing, `AGENTS.md`, automated dependency updates, and CI
pipelines.

---

## 1. Licensing & SPDX Compliance

Adhere strictly to `/skill:license-compliance`:

- **Permissive License Default**: Use **Apache-2.0**, **MIT**, or **BSD-3-Clause**
  for all new repositories.
- **SPDX Headers**: Include a standard SPDX header at the top of every new
  source file:

```rust
// SPDX-License-Identifier: Apache-2.0
```

```python
# SPDX-License-Identifier: Apache-2.0
```

```shell
# SPDX-License-Identifier: Apache-2.0
```

- **Root `LICENSE`**: Ensure the full license text is placed at the repository
  root.

---

## 2. Root `AGENTS.md` Baseline

Every repository must maintain an `AGENTS.md` file at the root to guide coding
agents:

```markdown
# AGENTS.md

## Project Overview
[1-2 sentences describing repository purpose, architecture, and core language]

## Setup & Toolchain Commands
- Install tools: `mise install`
- Build project: `mise run build`

## Development & Test Workflow
- Run static checks: `mise run check`
- Run test suite: `mise run test`
- Format code: `mise run fmt`

## Coding Style & Invariants
- Refer to `~/.agents/rules/<lang>.md` for language idioms and type safety.
- Keep McCabe complexity <= 10 per function.
- All errors handled as explicit values; zero unhandled panics or bare catches.

## Pull Request Guidelines
- Branch naming: `feat/<name>`, `fix/<name>`
- Commits: Conventional Commits adhering to `/skill:git-commit`
```

---

## 3. Dependabot v2 Baseline (`.github/dependabot.yml`)

Automate security and dependency updates with grouped pull requests:

```yaml
version: 2
updates:
  # Package ecosystems (uncomment applicable ecosystems)
  # - package-ecosystem: "cargo"
  #   directory: "/"
  #   schedule:
  #     interval: "weekly"
  #   groups:
  #     minor-and-patch:
  #       patterns: ["*"]
  #       update-types: ["minor", "patch"]

  # - package-ecosystem: "npm"
  #   directory: "/"
  #   schedule:
  #     interval: "weekly"

  # - package-ecosystem: "pip"
  #   directory: "/"
  #   schedule:
  #     interval: "weekly"

  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
```

---

## 4. GitHub Actions CI Baseline (`.github/workflows/ci.yml`)

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - name: Run Verification Battery
        run: mise run ci
```
