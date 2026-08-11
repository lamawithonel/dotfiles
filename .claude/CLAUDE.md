# Global Instructions

Read @~/.agents/AGENTS.md first.

## Code Repository Comprehension

When the user points you at a code repository or directory:

- Read `AGENTS.md` at the repo root first if it exists.
- If `AGENTS.md` does NOT exist, fall back to `README.md`.

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

## API Limit Outages (5-hour and weekly)

Hard provider limits (the rolling 5-hour window and the weekly cap)
cut off API access entirely: the session hangs up mid-task, and
in-band recovery (heartbeat wakeups, scheduled routines) fails too,
because it consumes the same quota.  Handle proactively first, with
crash-only recovery as the backstop, in every project:

- **Proactive pause-and-sleep (primary).**  On a nearing-limit
  warning, do not work until the hangup.  Immediately: pause all
  API-consuming sub-agents and workflow runs (stop them; interrupted
  workflows resume later from the run cache), flush durable state
  with an explicit NEXT action, launch any pending long host-side
  operations (builds, renders) so the outage wastes no wall-clock
  time, then start one background sleep sized to return one minute
  after the reset time given in the warning.  Make no further
  API-consuming moves; the sleep's completion re-invokes the session
  exactly when quota is back, and work resumes from durable state.
- **Crash-only design (backstop).**  Progress truth must live on
  disk (git commits, task-list checkboxes, a journal file), never
  only in conversation memory, so a hangup at any instant is just
  another crash and is already resumable.  No work unit should hold
  unjournaled critical state longer than one turn.
- **Host processes outlive the session.**  Long-running builds, VMs,
  and their log files keep running and accumulating during an
  outage.  A limit hit does not waste that wall-clock time; on
  resume, adopt running or finished work from the journal (task IDs,
  container names, log paths) instead of restarting it.
- **Use project infra if it exists, don't assume it does.**  Some
  projects have a journal file, a resumable workflow runner, or a
  cron/daemon fallback that recovers a killed session out-of-band at
  no API cost -- use it when present.  When a project has none of
  that, degrade gracefully: just pause, report the stopping point in
  plain text to the user, and wait -- don't invent infra unasked.
- **Weekly pacing.**  Schedule token-heavy phases (fan-out reviews,
  large migrations) early in the weekly window; reserve the tail for
  supervision-only heartbeats and host-side builds.

## Model Cutover Protocol

Whenever a model you depend on (in this session or a sub-agent) has
a known future deprecation or cutoff date, treat it like a scheduled
API outage (see above) but with one extra requirement: the model
about to go dark authors its own handoff before it does, because it
understands its own unfinished reasoning better than whatever picks
up afterward.

### Known Cutover Dates

This table is the trigger condition for the whole protocol: only
models listed here (or newly announced ones added as you learn of
them) get warning/halt timers via `CronCreate`.  Update it -- and
re-arm the timers -- the moment a cutoff date is announced or
changes; remove a row once its cutoff has passed and any pending
handoff is resolved.

| Model            | Cutoff (source tz)         | Cutoff (UTC)         | Warning shot | Hard halt   |
| ----------------- | -------------------------- | --------------------- | ------------- | ----------- |
| **NONE PLANNED** | - | - | - | - |

Timers here are session-only (see below) -- this table records the
*dates*, which are durable; the actual `CronCreate` entries must
still be re-armed at the start of every session while a row remains
pending.

- **Set timers relative to the cutoff:** a warning shot (stop
  launching new long-running work, pre-stage the handoff) and a hard
  halt (stop monitors first, then workflows with resumable state;
  leave detached background jobs running with log/status pointers;
  commit or annotate the working tree; write the handoff; stop).
  Size the gap between warning and halt to the task -- minutes for a
  quick session, longer for active multi-hour agent work.
- **Timers are session-only.**  A scheduled wakeup or cron entry set
  for these timers does NOT survive a session restart or crash.
  Re-arm it explicitly at the start of every new session for as long
  as the cutoff is still pending -- this is a real, easy-to-miss
  gotcha, not a one-time setup step.
- **Handoff-first, always.**  On ANY nearing-cutoff or nearing-limit
  warning, write the full handoff BEFORE sleeping or halting --
  handoff-writing outranks the sleep-until-reset protocol and all
  other work.  Budget real time for it (10-15 min is reasonable);
  near a hard cutoff, expect congestion to slow everything down.
- **The handoff must be self-contained.**  A zero-context session
  (a different model, a fresh window) must be able to continue from
  the handoff file alone: current state, what's done, what's next,
  standing constraints, where other artifacts live.
- **Handoff location:** default to `<repo>/.local/state/HANDOFF.md`
  unless the project already has its own convention (check
  CLAUDE.md/AGENTS.md and docs/ first) -- prefer `.local/state/` over
  `.cache/` for this, since cache directories get swept by cleanup
  tools and this file needs to survive.
