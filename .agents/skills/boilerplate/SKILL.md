---
name: boilerplate
description: Scaffold new projects or retrofit existing codebases with standard topologies, universal XDG Base Directory paths, dual policy and configuration hierarchy, secret management (fnox, OS keychains, KMS), cross-platform services (systemd, launchd, Windows, pitchfork), jdx devtools (mise, hk, fnox), and governance baselines.  Use when asked to scaffold, bootstrap, or initialize a project, retrofit an existing repo, make an application XDG-compliant, configure git hooks with hk, or manage secrets.
license: Apache-2.0
---

# Project Boilerplate & Scaffolding

A standardized system for scaffolding greenfield repositories and
retrofitting existing codebases with predictable topologies, robust
state/config paths, modern developer tooling, and governance baselines.

## Leading Words

- **`scaffold`**: Initialize a clean project skeleton from an archetype.
- **`retrofit`**: Upgrade an existing codebase non-destructively to standard
  paths, hooks, or governance baselines without disrupting business logic.
- **`archetype`**: The structural model of a project (CLI, Library, Daemon,
  Workspace).
- **`facet`**: A discrete operational layer (Topology, Paths, Devtools,
  Service, Configuration, Secrets, Governance).

## Universal Invariants

1. **Universal Path Default (XDG Base Directory v0.8)**: All applications,
   CLI tools, background services, developer utilities, and scripts on all
   platforms default to the XDG Base Directory specification.  The only
   exceptions are native GUI/OS application bundles (Win32/64 native apps,
   macOS `.app` bundles, mobile/embedded OS containers).
2. **jdx Tooling Spine**: Use `mise` for environment/task management, `hk`
   for fast git hooks, `fnox` for secret encryption, and `pitchfork` for
   local process orchestration.
3. **Language Rule Harmony**: All generated code, lint configs, and test
   harnesses must strictly match the relevant `~/.agents/rules/<lang>.md`
   specification without imposing foreign dogmatism.
4. **Non-Destructive Retrofitting**: When retrofitting, probe existing
   neighborhood conventions first; never overwrite working idioms or custom
   configurations without explicit instruction.
5. **Example File Isolation Guard**: The skill and its `references/`
   provide all authoritative defaults out of the box.  If active user
   overrides exist in `~/.config/boilerplate/` (e.g. `config.toml`,
   `*.toml`, `*.yml` without `.example.`), read only those active files.
   **DO NOT** read `*.example.*` files during routine project scaffolding
   or retrofitting; example files are reference templates reserved strictly
   for when the user explicitly asks to author or extend files inside
   `~/.config/boilerplate/`.

## Scaffolding & Retrofitting Protocol

### Step 1: Discovery & Archetype Classification

Identify the operating mode and project classification:

- **Mode**:
  - `Greenfield`: Creating a new project or module from scratch.
  - `Retrofit`: Aligning an existing codebase to standard facets.
- **Archetype**:
  - `CLI Tool`: Interactive or scriptable command-line binary.
  - `Library / Package`: Reusable component, SDK, or crate.
  - `Daemon / Service`: Long-running background process or server.
  - `Workspace / Monorepo`: Multi-package repository with shared tooling.

*Completion Criterion*: Archetype and mode selected; existing files surveyed.

---

### Step 2: Progressive Facet Scoping

Consult the relevant reference document before generating or modifying files:

| Facet | Description | Reference Document |
| :--- | :--- | :--- |
| **Topology** | Standard directory layouts by archetype | [references/topologies.md](references/topologies.md) |
| **Paths & XDG** | XDG v0.8 paths & native OS bundle exceptions | [references/paths-and-xdg.md](references/paths-and-xdg.md) |
| **Devtools & Hooks** | `mise`, `hk` git hooks, `fnox`, `.gitignore` | [references/dev-tooling-and-hooks.md](references/dev-tooling-and-hooks.md) |
| **Services** | `pitchfork`, `systemd`, `launchd`, Windows 11 | [references/service-management.md](references/service-management.md) |
| **Configuration** | Dual policy & config hierarchy, overlays, formats | [references/configuration.md](references/configuration.md) |
| **Secrets** | Hierarchical fnox, OS keychains, KMS, memory safety | [references/secrets-management.md](references/secrets-management.md) |
| **Governance** | `AGENTS.md`, SPDX licensing, CI baselines | [references/governance-and-meta.md](references/governance-and-meta.md) |

*Completion Criterion*: Required facets mapped to specific target files.

---

### Step 3: Execution & File Generation

1. **Metadata & Governance**: Lay down `AGENTS.md`, `LICENSE`, and
   `.gitignore` matching project needs.
2. **Toolchain & Tasks**: Initialize `mise.toml` with language runtimes and
   standard task targets (`check`, `test`, `lint`, `fmt`, `build`).
3. **Git Hooks**: Configure `.hk/` or `hk.toml` to bind pre-commit and
   pre-push hooks to Tier 1 static checks and test suites.
4. **Source Skeleton**: Generate source files, module boundaries, and tests
   aligned with the language's specific rule file.

*Completion Criterion*: All planned facet files authored and formatted.

---

### Step 4: Verification & Gate Check

Execute the verification battery through the devtool runner:

    mise run check || hk run pre-commit
    mise run test  || hk run pre-push

*Completion Criterion*: All Tier 1 static checks, formatting gates, and unit
tests pass with exit code 0.
