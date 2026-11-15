---
name: model-router
description: >-
  Delegate work to another agent and pick its model, effort, and
  channel.  Use before any Agent, Workflow, subagent, Herdr pane, or
  pi shell-out dispatch.  Chooses inline versus delegate, ranks models
  by band and tag from the host benchmark registry, sets effort, routes
  refusals, and formats briefs and receipts.
argument-hint: "[test]"
---

# Model Router

Pick in this order: inline or delegate, then band, then
`score.py --pick`, then dispatch naming model and effort.  Role
classes live in `~/.agents/AGENTS.md`; commissioning, the supervision
tree, Herdr layout, and class effort defaults live in
`~/.agents/ROLES.md`.  This skill holds the band for each class.

## 1. Inline or delegate

Work inline when the target is known, the context is already loaded,
the edit is local to one examined file, or the brief costs more than
the work.  Delegate when work fans out across subsystems, tool output
would flood the session, or tasks can run in parallel.

Weigh your own band.  In an `opus` or `mythos` session, plan to make
at most about 5 tool calls inline per work package, and dispatch
anything bigger at the band the package needs, usually `sonnet`.  A
design-heavy package may go to `opus` with a one-line reason.
Orchestrators and coordinators keep triage, decomposition,
integration, and receipt review; everything else is a work package.
An orchestrator hands context-heavy work to coordinators.

The INLINE BUDGET in `~/.agents/AGENTS.md` (Role Classes) binds every
orchestrator and coordinator.  An independent session that dispatches
follows it too.

To delegate, split the task into a work breakdown structure and
dispatch one worker per work package.  Apply the 100% rule: the work
packages together cover the whole parent task, with no overlap.
Moving work up a band after a failure, or a decision up to the
supervisor, is escalation.

## 2. Caller rubric

Choose the lowest band that gets it right the first time.

| Band | Use for |
| --- | --- |
| `bulk` | Many mechanical items that a script or reviewer checks |
| `haiku` | Lookups, file:line location, test runs with a summary, receipt digests, mechanical one-file edits |
| `sonnet` | Default for real work: multi-file, synthesis, repro'd bugs, docs |
| `opus` | No repro, cross-subsystem design, adversarial review, or sonnet failed |
| `mythos` | Only when the user names the model.  Never auto-picked |

- Add at most one specialty tag (`design`, `3d`, `math`, `writing`,
  `eq`, `long-horizon`, `cyber`, `medical`, `business`) with `--tag`,
  and at most one language group (`multilingual`, `chinese`,
  `european`, `japanese`) with `--lang`.
- Orchestrators and coordinators: `--role orchestrator|coordinator`
  replaces `--band`.  `--role lead` and the subdomain roles are
  retired and exit 2.
- Target mix: about 16% `haiku` or below, 64% `sonnet`, and 20%
  `opus` or above.  State a one-line reason for every `opus`-or-above
  dispatch.  The pick's `mix_band` says which share it counts toward.
  `score.py --mix [--session ID] [--days N]` reports the measured mix
  where the log-dispatch hook is installed.
  `scripts/token-share.py [--session ID] [--days N]` shows the tokens
  each session spent by model, including inline work, which the
  dispatch log cannot see.
- A package that is read-only, touches three files or fewer, and has
  an answer the dispatcher can check goes to `haiku`.

## 3. Pick

Never choose a model from memory.  An explicit user directive naming a
model overrides scoring (`--model ID`).

```sh
python3 ~/.agents/skills/model-router/scripts/score.py --pick \
  --band sonnet [--tag design] [--lang japanese]
```

Read the JSON:

- `pick`: dispatch this.  It is the best value over the feasible set:
  the profile's models whose (model, effort) variant meets the band
  floor.  `channel` is `agent`, `pi`, `herdr`, or
  `shell`.  Claude Code `Agent`: `model_param`.  Pi in-process:
  `model_ref`.  `herdr` or `shell`: run `command` verbatim, built with
  `--payload /abs/session-tmp/brief.md`.
- `pick.effort`: dispatch at this level; for Pi it is exactly the
  `--thinking` level sent.  `banded_effort` is the measured variant.
  `--effort` takes `off` through `max`; anything else exits 2.
- `degrade`: set when `pick` is null; dispatch it only after stating
  the band shortfall.  `mix_band` is the pick's (or degrade's) band.
- `fallback`: a variant in the profile's primary harness; null when
  the pick is already there.  Pi makes no repository edits yet, so
  repository-edit work in `pi-zdr` is reported to the supervisor, not
  dispatched.
- `on_refusal`: the re-route target; null unless the call carried a
  `cyber` or `medical` tag.
- `warnings`: read every one; one says when the role effort was
  capped to keep the pick in its band.
- Exit: 0 pick or degrade; 2 usage or registry error; 3 neither (stop and
  report).

Old flags (`--system`, `--tier`) exit 2.  Details: `references/scoring.md`.

## 4. Name the model and the effort

<constraints priority="MUST">
EVERY dispatch names its model AND its effort.  No exceptions, in every
harness.  Never omit either one, never rely on a default, and never
inherit from the parent.

- `Agent`: set `model` and `effort`.
- `Workflow` scripts: set `model` and `effort` on every agent call.
- Pi: pass `--model` and `--thinking`.
- Herdr panes: pass the CLI's own flags after `--` (`pi --model ...
  --thinking ...` or `claude --model ... --effort ...`).  Herdr has no
  model or effort flag.
- `CLAUDE_CODE_SUBAGENT_MODEL=sonnet` is a backstop for a missed
  `model`, not a license to omit it.  A hook that rejects `Agent`
  calls with no model may or may not exist on this host; behave as if
  neither exists.
</constraints>

## 5. Defaults and effort

Orchestrators run `opus` at `xhigh`.  Coordinators run `sonnet` at
`high`; an orchestrator may commission an `opus` coordinator with a
one-line reason.  Workers run `medium`.
Role defaults never use `max`.  Raise effort to `high` before changing band;
above `high`, change band.  Bulk work from Claude Code stays on the
subscription (zero marginal cost).  Rules and per-harness setting:
`references/effort.md`.

## 6. Channels

Same harness: in-process.  In Claude Code, use `Workflow` for
short-lived workers and `Agent` for long-lived ones you will message
again; the user's standing opt-in for `Workflow` is in
`~/.agents/AGENTS.md`.  In Pi, use `subagent`.  Other harness: a Herdr
pane when `HERDR_ENV=1`, else a disclosed shell-out.  Worker panes
appear only for other-harness picks; in-process workers never get
one.  Pi workers make no repository edits until Pi has an approval
gate and confinement.  Never run the host's own CLI through `Bash`.
Details: `references/channels.md`.

## 7. Refusals

A worker that declines returns `REFUSED (<category>)` or `PARTIAL`.
Re-route `cyber`, `bio`, and `medical` once, to a different vendor,
quoting the authorization.  Every `bio` re-route needs the user's
approval each time.  Get the target by re-running `score.py --pick`
with `--tag cyber`, or `--tag medical` for `bio`.  If `on_refusal` is
still null, stop and report; never pick a vendor by hand.  Steps:
`references/refusals.md`.

## 8. Worker guards

<constraints priority="MUST">
1. STALL WATCHDOG: The worker MUST terminate if 3 consecutive turns yield zero state progress.
2. SCOPE LIMIT: The worker MUST halt, escalate, and return a decomposition (a proposed work breakdown structure) if changes span >3 decoupled subsystems.
3. RECEIPT CONTRACT: The worker MUST suppress verbose streams and return only actionable conclusions with file:line references.
</constraints>

State these in every worker brief.  Brief format: `references/brief.md`.

## 9. References

| Need | File |
| --- | --- |
| Bands, value, tags, profiles | `references/scoring.md` |
| Channels, teammate trap, Pi rules | `references/channels.md` |
| Brief and receipt format | `references/brief.md` |
| Refusal recognition and re-route | `references/refusals.md` |
| Effort rules per harness | `references/effort.md` |
| Pause, halt, recovery | `references/lifecycle.md` |
| Feeds and registry upkeep | `references/pipeline.md` |

Channel health: `scripts/test-external.sh [pi]` (TAP; exit 77 is
skipped).  `20-pi-credentials.sh` diagnoses hidden credentials.
