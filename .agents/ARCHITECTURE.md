# Agent Context & System Architecture

This document describes the multi-harness context architecture across
`~/.agents/`, `~/.claude/`, `~/.pi/`, and user configuration trees.

---

## 1. The 5-Layer Context Stack

The context architecture separates universal governance from runtime-specific
rules and project-level execution to prevent prompt bloat while guaranteeing
behavioral determinism:

```
+-----------------------------------------------------------------------------------+
| Layer 1: Harness Bootstrap                                                        |
|   - Claude Code: ~/.claude/CLAUDE.md (entrypoint, minimal routing pointers)       |
|   - Pi: ~/.pi/agent/settings.json & runtime environment configuration             |
+-----------------------------------------------------------------------------------+
                                       ↓
+-----------------------------------------------------------------------------------+
| Layer 2: Universal Governance & Policies                                          |
|   - ~/.agents/AGENTS.md (Scope containment, VCS directives, test pyramid)         |
|   - ~/.agents/AGENTS.local.md (Host/workplace overrides; takes strict precedence) |
+-----------------------------------------------------------------------------------+
                                       ↓
+-----------------------------------------------------------------------------------+
| Layer 3: On-Demand Agent Skills (Single Source of Truth)                          |
|   - ~/.agents/skills/* (code-rules, boilerplate, license-compliance, etc.)        |
|   - Harness skill directories are symlinks into ~/.agents/skills/                 |
+-----------------------------------------------------------------------------------+
                                       ↓
+-----------------------------------------------------------------------------------+
| Layer 4: Path-Gated Language Rules (Single Source of Truth)                       |
|   - ~/.agents/rules/*.md (rust.md, mojo.md, go.md, python.md, zig.md, etc.)       |
|   - Loaded reactively when matching file patterns enter the session context       |
+-----------------------------------------------------------------------------------+
                                       ↓
+-----------------------------------------------------------------------------------+
| Layer 5: Project-Local Execution & Configuration                                  |
|   - <project-root>/AGENTS.md (Local setup, test, and style commands)              |
|   - <project-root>/mise.toml & hk.toml (Devtools and static check hooks)          |
+-----------------------------------------------------------------------------------+
```

---

## 2. Harness Loading Contracts

Different coding agent harnesses load and process context through distinct
mechanisms.  The architecture bridges these differences without duplicating
files:

### A. Claude Code Harness Contract

- **Bootstrap**: Reads `~/.claude/CLAUDE.md` at session start.
- **Skill Resolution**: Discovers skills in `~/.claude/skills/`, which symlinks
  directly to `~/.agents/skills/`.
- **Rule Path-Gating**: Reads `.claude/rules/**/*.md` and `~/.claude/rules/*.md`.
  Files specify YAML frontmatter with `paths:` glob lists:
  ```yaml
  ---
  paths:
    - "**/*.rs"
  ---
  ```
  - When a file matching the glob enters the context window via a tool call
    (`Read`, `Edit`, etc.), Claude Code automatically injects the rule.
  - Rules with no `paths:` key load unconditionally at session start.

### B. Pi Harness Contract (`pi-rules` / Pi Coding Agent)

- **Bootstrap**: Reads `~/.agents/AGENTS.md` and system prompts configured in
  `~/.pi/agent/settings.json`.
- **Skill Resolution**: Dynamically loads registered skills from global and
  project skill catalogs.
- **Rule Injection**: Uses `@quandev104/pi-rules` reading `.pi/rules/**/*.md`:
  ```yaml
  ---
  paths:
    - "**/*.rs"
  summary: Rust idioms, Newtypes, thiserror/miette, and cargo battery
  alwaysApply: false
  ---
  ```
  - Supports static path matching, dynamic trigger-phrase matching, and
    status widgets (`--pi-rules-widget`).
  - Supports write guards (`--pi-rules-write-guard`) preventing file writes
    until matching rules have been acknowledged.

---

## 3. Dual-Layer Rule Ingestion (Belt & Suspenders)

To eliminate **cognitive anchoring** (where an LLM sketches an initial loose
plan from web-corpus priors before reading a language rule), the architecture
uses a dual-layer strategy:

1. **The Belt (Proactive / Pre-Planning Skill)**:
   - When a user asks to plan, architect, or write code in a language, the
     `/skill:code-rules` skill triggers **on Turn 1**.
   - It reads `~/.agents/rules/<lang>.md` *before* the first plan token is
     generated.
2. **The Suspenders (Reactive / Path-Gating Safety Net)**:
   - If a prompt does not name the language explicitly (e.g. "fix bug in
     issue #12"), the harness path-gating rule automatically fires the moment
     the agent reads or edits a source file.

---

## 4. Directory Inventory & Invariants

### `~/.agents/` (Core Repository)
- `AGENTS.md`: Universal governance, scope containment boundaries, VCS
  directives, and style guide pointers.
- `AGENTS.local.md`: Uncommitted, host-local overrides taking strict precedence.
- `ARCHITECTURE.md`: This document.
- `models.json` & `benchmarks.json`: Model router scoring and pricing registry.
- `rules/`: Authoritative language specifications (`rust.md`, `mojo.md`,
  `go.md`, `python.md`, `zig.md`, `typescript.md`, `javascript.md`, `shell.md`).
- `skills/`: Authoritative skill definitions conforming to the Agent Skills
  Specification.

### `~/.config/boilerplate/` (User Scaffolding Registry)
- `AGENTS.md`: Instruction document governing template usage and extension.
- `config.example.toml`: Global user defaults (license, author, runner).
- `archetypes/*.example.toml`: Skeleton layouts for CLI tools, services, etc.
- `presets/*.example.*`: Templates for CI, SPDX licenses, `mise.toml`,
  `hk.toml`, `systemd` user units, and `launchd` plists.
- **Isolation Guard**: Agents executing routine project scaffolding read only
  active files (e.g. `config.toml`) and **never** read `*.example.*` files
  unless explicitly asked to author or extend the configuration directory.

---

## 5. Core Architectural Invariants

1. **Rust / Mojo Center of Gravity with Polyglot Harmony**: Rust is the
   primary target for production systems and tooling; Mojo for high-performance
   scripting and compute.  All other languages follow Rust-isomorphic patterns
   (ADTs, explicit error values, RAII lifecycles, parse-don't-validate) where
   naturally aligned, without imposing foreign dogmatism.
2. **Two-Tier Static Battery Discipline**:
   - *Tier 1 (Turn-by-Turn)*: Fast, zero-friction native compiler/linter checks
     (`cargo check/clippy`, `tsc` + `eslint`, `ruff` + `pyright`, `gofmt`).
   - *Tier 2 (Pre-Commit / Milestone)*: Heavy project-wide graph and dead-code
     audits (`knip`, `depcruise`, `cargo audit`, `bats-core`).
3. **Scope Containment**: Diff-bounded verification restricts fixes strictly
   to the active changeset (zero unsolicited churn on legacy code).
4. **Universal XDG Default (v0.8)**: All CLI tools, backend daemons, and scripts
   on all operating systems default to XDG Base Directory paths.  Exceptions
   are strictly for native OS GUI application bundles (Win32/64 native apps,
   macOS `.app` bundles, mobile OS containers).
5. **Plain Language Standards**: All operational instructions follow direct,
   controlled technical English (ASD-STE100 principles) to ensure predictable
   LLM execution.

---

## 6. Policy vs. Configuration Hierarchy (Dual-Hierarchy Model)

The context and runtime system strictly distinguishes between **Policy**
(top-down governance) and **Configuration** (bottom-up specialization) across a
9-layer scope continuum:

```
[Broadest Scope / Highest Policy Authority]
  1. Built-in Defaults
  2. Compile-Time / Build-Time Options (hardened compiler flags, baked enterprise policy)
  3. System-Level (/etc, machine-wide governance)
  4. User-Level Base ($XDG_CONFIG_HOME, ~/.config, ~/.agents/AGENTS.md)
  5. User-Level Host-Local Overlay (*.local.*, ~/.agents/AGENTS.local.md)
  6. Project-Level Base ($(pwd)/config.toml, $(pwd)/AGENTS.md, mise.toml)
  7. Project-Level Host-Local Overlay (*.local.*, AGENTS.local.md)
  8. Environment Variables ($APP_*, $XDG_*)
  9. Direct Command-Line Arguments (--flag, runtime CLI options)
[Narrowest Scope / Highest Config Specialization]
```

### A. Policy Hierarchy (Top-Down Governance)
- **Authority**: System / enterprise policy and compile-time hardened constraints
  set the baseline floor.  User-level host governance (`AGENTS.local.md` →
  `AGENTS.md`) and project policies can tighten constraints but **cannot** relax
  or disable upstream security or compliance rules.
- **Baked Policy Pattern**: In security-hardened or read-only deployments,
  enterprise policy may be baked directly into the binary at compile time or
  packaged in read-only manifests as an immutable ceiling.

### B. Configuration Hierarchy (Bottom-Up Specialization)
- **Specialization**: Closer, narrower invocation layers specialize and override
  broader default layers (`CLI args` > `Environment variables` > `Project files`
  > `User files` > `System files` > `Built-in defaults`).
- **Host-Local Overlays (`*.local.*` / `*.local`)**: Uncommitted, gitignored
  host-local overlay files at user and project scopes merge with and deeply
  override keys from their corresponding base files without dirtying shared
  repository state.

