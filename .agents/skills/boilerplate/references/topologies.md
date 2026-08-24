# Standard Project Topologies

Directory structures categorized by project archetype.

---

## 1. CLI Tool Archetype

For command-line utilities, developer tools, and binaries.

```
project-root/
├── .gitignore
├── .gitattributes
├── AGENTS.md
├── LICENSE
├── README.md
├── mise.toml                  # Devtools and lifecycle tasks
├── hk.toml                    # Fast git hooks (or .hk/)
├── src/
│   ├── main.*                 # Thin entrypoint: CLI parse, error exit
│   ├── cli.*                  # Flag parsing, subcommands, help definitions
│   ├── commands/              # Subcommand handlers (one file per command)
│   ├── config.*               # Hierarchical configuration loader
│   └── lib.*                  # Domain logic (or core/ module)
└── tests/
    └── cli_integration_test.* # End-to-end binary execution tests
```

---

## 2. Library / Package Archetype

For reusable libraries, SDKs, modules, and crates.

```
project-root/
├── .gitignore
├── .gitattributes
├── AGENTS.md
├── LICENSE
├── README.md
├── mise.toml
├── hk.toml
├── src/
│   ├── lib.*                  # Public API root exports
│   └── internal/              # Private implementation details
├── tests/
│   ├── unit/                  # Isolated logic unit tests
│   └── integration/           # Public API integration tests
├── examples/                  # Runnable usage examples
└── benches/                   # Performance benchmarks (where applicable)
```

---

## 3. Daemon / Service Archetype

For long-running background processes, API servers, and workers.

```
project-root/
├── .gitignore
├── .gitattributes
├── AGENTS.md
├── LICENSE
├── README.md
├── mise.toml
├── hk.toml
├── pitchfork.toml             # Local dev process supervisor
├── src/
│   ├── main.*                 # Process bootstrap, signal trapping
│   ├── server.*               # Network/socket listener lifecycle
│   ├── worker.*               # Task execution loop
│   ├── config.*               # Hierarchical configuration loader
│   └── health.*               # Health/readiness probes
├── systemd/                   # Optional systemd unit templates
└── tests/
    ├── integration/           # Server lifecycle & endpoint tests
    └── mocks/                 # External service test doubles
```

---

## 4. Workspace / Monorepo Archetype

For multi-package or multi-crate projects sharing tooling.

```
project-root/
├── .gitignore
├── .gitattributes
├── AGENTS.md
├── LICENSE
├── README.md
├── mise.toml                  # Root task runner orchestrating all packages
├── hk.toml                    # Root git hooks
├── packages/                  # or crates/, apps/, libs/
│   ├── core/                  # Shared domain types and logic
│   ├── cli/                   # CLI binary package
│   └── server/                # Service daemon package
└── docs/                      # Project-wide architectural documentation
```
