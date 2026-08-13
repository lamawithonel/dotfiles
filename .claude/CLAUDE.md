# Global Instructions

- Read @~/.claude/CLAUDE.local.md first if it is available.
- Read @~/.agents/AGENTS.md second.

## Code Repository Comprehension

When the user points you at a code repository or directory:

- Read `AGENTS.md` and `AGENTS.local.md` at the repo root first.
- If neither `AGENTS*.md` file exists, fall back to `README.md`.

## Execution Channels (Claude Code)

Claude Code is the primary coordinator for long-horizon work.  Model
work dispatches through exactly two channels; the shared invariants and
harness dispatch table live in `~/.agents/AGENTS.md`.

This file is environment-agnostic by design (it syncs across machines
via dotfiles): it names no models and assumes no CLI beyond Claude
Code itself.  Which models exist on THIS host, their `model`
parameter values, and their deployment-specific ids (consumer,
Enterprise, and Bedrock ids all differ for the same model) live only
in the host-local registry `~/.agents/models.json`.

### Native Channel: Claude Models

Dispatch via the `Agent` and `Workflow` tools, taking the `model`
parameter value from the registry entry's
`execution."claude-code".model_param`.

- Never delegate to a model whose registry `constraints.tier_4_only`
  is true unless the user explicitly orders it (a Tier 4 directive;
  see the `model-router` skill).

### External Channel: Non-Claude Models (where available)

Some hosts also have the Pi CLI fronting OpenRouter-hosted and local
`llama.cpp` (`llama-swap`) models; other hosts run Claude Code alone.
Probe, never assume: `command -v pi`.  Absent Pi, registry models
without a native Claude Code channel are unavailable here.

```
pi --model '<provider>/<model-id>' -p '<prompt>'
```

- The exact per-model command is the registry entry's
  `execution."claude-code".command`.
- Ignore Pi's stderr unless there is no stdout.
- Add `--no-session` for fire-and-forget calls that should not pollute
  Pi's session store.
- Wrap the distilled task payload per the `model-router` skill's
  `<subagent_task>` rules; never paste raw parent context into `-p`.

### Choosing a Model

Load the `model-router` skill (`~/.agents/skills/model-router/`) before
any delegation.  It scores candidates from `~/.agents/models.json`--
real benchmark metrics and live pricing.  Hardcoded model rankings and
model names are prohibited everywhere in this file and in
`~/.agents/AGENTS.md`; if you find either, it is a bug.
