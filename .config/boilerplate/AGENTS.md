# AGENTS.md (Boilerplate User Configuration & Templates)

## Directory Overview

This directory (`$XDG_CONFIG_HOME/boilerplate/` or `~/.config/boilerplate/`)
serves as the user-level customization layer and template registry for the
`boilerplate` skill (`~/.agents/skills/boilerplate/`).

It allows users and organizations to maintain custom project archetypes,
internal CI workflows, proprietary copyright headers, and developer tooling
presets that override or augment the default skill references.

---

## Agent Access Rules & Isolation Guard

- **Routine Usage (Everyday Scaffolding / Retrofitting)**:
  - Agents executing project scaffolding or retrofitting must read **only
    active, production-grade files** (e.g. `config.toml`, `presets/ci.yml`).
  - Agents **MUST NEVER** read `*.example.*` files during routine project
    scaffolding turns.
- **Extension Tasks (Infrequent Authoring)**:
  - Agents may read `*.example.*` files **only** when the user explicitly
    requests creating, customizing, or extending configuration files within
    `~/.config/boilerplate/`.

---

## Directory Topology & File Naming Conventions

```
~/.config/boilerplate/
├── AGENTS.md                         # This instruction document
├── config.example.toml               # Global user defaults & tool preferences
├── archetypes/
│   ├── cli.example.toml              # Custom CLI project archetype skeleton
│   └── microservice.example.toml     # Custom microservice daemon skeleton
└── presets/
    ├── ci.example.yml                # Default CI workflow template
    ├── license.example.txt           # Custom/enterprise license header template
    ├── mise.example.toml             # Custom mise toolchain & task definitions
    ├── hk.example.toml               # Custom hk git hook orchestration
    ├── service.example.service       # Linux systemd user service template
    └── launchd.example.plist         # macOS launchd user agent template
```

- **Reference Skeletons**: Kept with `*.example.*` in their filename.
- **Active Files**: Created by copying an example file and stripping `.example`
  (e.g., `cp config.example.toml config.toml`).

---

## Authoring Guidelines for New Presets

- All configuration files must use valid TOML, YAML, or XML conforming to their
  respective parser specifications.
- Keep templates token-efficient, omitting redundant comments and boilerplate
  explanations.
- Use Mustache-style placeholders (`{{project_name}}`, `{{author_name}}`,
  `{{organization}}`) for dynamic substitutions.
