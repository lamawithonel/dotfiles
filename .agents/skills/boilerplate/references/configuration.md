# Hierarchical Configuration & Policy Architecture

Standards for application configuration resolution, governance policies,
compile-time baked options, host-local overlays, serialization formats, and
runtime loading.

---

## 1. The Dual-Hierarchy Model

Applications, daemons, and developer tooling evaluate governance and runtime
settings through two distinct, opposing precedence models across the 9-layer
scope continuum:

```
[Broadest Scope / Highest Policy Authority]
  1. Built-in Defaults
  2. Compile-Time / Build-Time Options (baked policy & flags)
  3. System-Level (/etc)
  4. User-Level Base ($XDG_CONFIG_HOME)
  5. User-Level Host-Local Overlay (*.local.*)
  6. Project-Level Base ($(pwd))
  7. Project-Level Host-Local Overlay (*.local.*)
  8. Environment Variables
  9. Direct Command-Line Arguments
[Narrowest Scope / Highest Config Specialization]
```

---

## 2. Policy Hierarchy (Top-Down Precedence)

Policy governs security boundaries, operational constraints, allowed protocols,
and licensing mandates.  **Broadest scope takes priority**:

```
1. Compile-Time Hardened Policy        (Build-time security flags, baked enterprise policy)
      ↓
2. System / Enterprise Policy          (/etc/<app>/policy.toml, machine-wide policies)
      ↓
3. User Host-Local Policy              ($XDG_CONFIG_HOME/<app>/policy.local.toml)
      ↓
4. User Base Policy                    ($XDG_CONFIG_HOME/<app>/policy.toml)
      ↓
5. Project Host-Local Policy           (./policy.local.toml, ./AGENTS.local.md)
      ↓
6. Project Base Policy                 (./policy.toml, ./AGENTS.md)
      ↓
7. Runtime Execution Environment
```

### Policy Invariants

1. **Top-Down Constraint**: A local project config or runtime CLI flag can
   tighten policy but cannot loosen, bypass, or disable an upstream security
   or compliance policy.
2. **Baked Enterprise Policy**: In security-sensitive or read-only package
   installations (e.g. system immutable packages, hardened daemon builds),
   enterprise policies can be compiled directly into binary logic or package
   manifests as an unalterable baseline floor.

---

## 3. Configuration Hierarchy (Bottom-Up Precedence)

Configuration specifies runtime operational values (network ports, endpoints,
cache sizes, timeouts, log levels).  **Narrowest invocation scope takes priority**:

```
1. Direct CLI Arguments / Flags        (--port 8080, --config /custom/path.toml)
      ↓
2. Environment Variables               (APP_PORT=8080, APP_LOG_LEVEL=debug)
      ↓
3. Project Host-Local Overlay          (./<app>.local.toml, ./mise.local.toml)
      ↓
4. Project Base Config File            (./<app>.toml, ./mise.toml)
      ↓
5. User Host-Local Overlay             ($XDG_CONFIG_HOME/<app>/config.local.toml)
      ↓
6. User Base XDG Config File           ($XDG_CONFIG_HOME/<app>/config.toml)
      ↓
7. System XDG Config File              ($XDG_CONFIG_DIRS/<app>/config.toml)
      ↓
8. Compile-Time / Build Options        (Build-time feature flags & defaults)
      ↓
9. Built-in Defaults                   (Hardcoded fallback constants)
```

### Configuration Invariants

1. **Bottom-Up Specialization**: Narrower layers specialize and override
   general defaults from broader layers.
2. **Call-Site Precedence**: Direct CLI arguments and process environment
   variables take immediate precedence over on-disk configuration files.

---

## 4. Host-Local Overlay Invariants

1. **Gitignore Requirement**: All `*.local.*` and `*.local` files (e.g.,
   `config.local.toml`, `mise.local.toml`, `AGENTS.local.md`) must be listed in
   `.gitignore` and never committed to version control.
2. **Deep Merging**: Configuration loaders must deep-merge tables/objects from
   the host-local file over the base file rather than replacing entire sections.
3. **Absence Safety**: Host-local files are always optional; applications must
   operate seamlessly when no `*.local.*` file is present.

---

## 5. Serialization Format Standards

| Format | Role & Usage Policy |
| :--- | :--- |
| **TOML** | **Default format** for all user-facing, developer, and application configuration files (`config.toml`, `mise.toml`, `Cargo.toml`). |
| **JSON** | Standard for machine-generated state, cache indexes, and structured IPC exchange. |
| **YAML** | Restricted strictly to CI/CD workflows (GitHub Actions), container definitions, and tools requiring YAML natively. |

---

## 6. Runtime Loading Invariants

- **Parse, Don't Validate**: Deserialize untyped configuration text into
  strongly typed, immutable domain models at application bootstrap.
- **Fail Fast on Schema Errors**: Emit clear, human-readable errors with file
  path and line number when required configuration fields are invalid or
  missing.
- **Dynamic Reloading (`SIGHUP`)**: When receiving `SIGHUP`, re-evaluate
  configuration files and update mutable runtime state atomically.
