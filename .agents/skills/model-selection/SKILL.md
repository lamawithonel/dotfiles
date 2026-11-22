---
name: model-selection
description: >-
  Rank models by band, tag, and language from the host benchmark
  registry, set effort, re-route refusals, report the band mix, and
  check channels.  Use before you name a model and effort for any
  dispatch.
---

# Model Selection

This skill covers `score.py` and its JavaScript Object Notation (JSON)
output.  It does not say when to delegate.  For channels, briefs, and
final reports, load `delegation-mechanics`.  For class duties, load
`roles`.

## 1. Rules

- Never choose a model from memory.  Run `score.py --pick`.
- Use `--model ID` when the user names a model.  A user directive
  overrides scoring.
- Name the model and the effort on every dispatch.

## 2. Bands

Choose the lowest band that gets it right the first time.

| Band | Use for |
| --- | --- |
| `bulk` | Many mechanical items that a script or reviewer checks |
| `haiku` | Lookups, file:line location, test runs with a summary, final report digests, mechanical one-file edits |
| `sonnet` | Default for real work: multi-file, synthesis, repro'd bugs, docs |
| `opus` | No repro, cross-subsystem design, adversarial review, or sonnet failed |
| `mythos` | Only when the user names it, or when a user ruling recorded in the project authorizes it for that work.  Cite the ruling file in the dispatch.  Never auto-picked |

- Send a package to `haiku` when it is read-only, touches three files
  or fewer, and has an answer the dispatcher can check.
- Add at most one specialty tag with `--tag`: `design`, `3d`, `math`,
  `writing`, `eq`, `long-horizon`, `cyber`, `medical`, or `business`.
- Add at most one language group with `--lang`: `multilingual`,
  `chinese`, `european`, or `japanese`.

## 3. Pick

```sh
python3 ~/.agents/skills/model-selection/scripts/score.py --pick \
  --band sonnet [--tag design] [--lang japanese]
```

Flags:

- `--band bulk|haiku|sonnet|opus`: the band to pick from.
- `--role executive|coordinator`: sets the band from the class
  default.  Do not combine it with `--band`.  The old
  `--role orchestrator` still works during the switch.
- `--tag TAG` and `--lang GROUP`: see section 2.
- `--effort LEVEL`: `off` through `max`.  Any other value exits 2.
- `--model ID`: pick this exact model.
- `--payload /abs/path/brief.md`: the brief file that a `herdr` or
  `shell` command reads.  Use an absolute path.
- `--band mythos --user-named`: picks the best mythos variant, at
  `xhigh` by default.  Use it only when the user names it (for example
  through `/consultant`), or when a user ruling recorded in the project
  authorizes it for that work.  Cite the ruling file in the dispatch.
  Without `--user-named`, `--band mythos` lists the models and exits 3.
- `--consultant-for BAND:EFFORT`: give the creator's band and effort.
  It picks one band up (stops at `opus`) and one effort up (stops at
  `max`).  Do not combine it with `--band`, `--role`, `--effort`, or
  `--model`.
- `--mix`: report the measured band mix (section 7).

Old flags (`--system`, `--tier`) exit 2.  Do not use them.

## 4. Read the JSON

- `pick`: dispatch this.  It is the best value among the models whose
  (model, effort) variant meets the band floor.
- `pick.channel`: `agent`, `pi`, `herdr`, or `shell`.
  - `agent`: pass `model_param` to the Claude Code `Agent` tool.
  - `pi`: pass `model_ref` to Pi in-process.
  - `herdr` or `shell`: run `command` as given.  Build it with
    `--payload`.
- `pick.effort`: dispatch at this level.  For Pi it is exactly the
  `--thinking` level that the command sends.
- `banded_effort`: the effort at which the registry measured the
  variant.
- `degrade`: set when `pick` is null.  State the band shortfall, then
  dispatch it.
- `fallback`: a variant in the profile's primary harness.  It is null
  when the pick is already there.  Pi makes no repository edits yet.
  Report repository-edit work for a Pi pick to the supervisor.  Do not
  dispatch it.
- `on_refusal`: the re-route target.  It is null unless the call
  carried a `cyber` or `medical` tag.
- `mix_band`: the band that the pick (or degrade) counts toward in the
  mix.
- `warnings`: read every one.  One says when the role effort was capped
  to keep the pick in its band.
- Exit codes: 0 means a pick or degrade.  2 means a usage or registry
  error.  3 means no pick and no degrade: stop and report.

Details: `references/scoring.md`.

## 5. Class defaults and effort

- Executive: `opus` at `xhigh`.  The executive `xhigh` default is a
  candidate to test on local evals.
- Coordinator: `sonnet` at `high`.  An executive may charter an `opus`
  coordinator with a one-line reason.
- Worker: `medium` effort at the band the package needs.
- Consultant: one band and one effort above its creator.  The band
  stops at `opus`.  The effort may reach `max`.  Use
  `--consultant-for`.  A user-made consultant defaults to `mythos` at
  `xhigh`.
- Never use `max` as a role default.
- Raise effort to `high` before you change band.  Above `high`, change
  band.
- Re-sweep effort on local evals at each model upgrade.  The vendor
  start-effort table is in `references/effort.md`, section 2.
- At `xhigh` or `max`, a worker stops once its checks pass and starts
  no reviewer subagents.  At `low` effort, a worker runs a check that
  exercises each change before it reports done.  State both lines in
  the brief when the effort matches.
- Bulk work from Claude Code stays on the subscription (zero marginal
  cost).

Rules for each harness: `references/effort.md`.

## 6. Pass the model and effort to the harness

- `Agent`: set `model` and `effort`.
- `Workflow`: set `model` and `effort` on every agent call.
- Pi: pass `--model` and `--thinking`.
- Herdr pane: pass the flags of the CLI inside the pane after `--`,
  for example `pi --model ... --thinking ...`.  Herdr has no model or
  effort flag.
- Dispatch Fable by the alias `fable`, so it runs the latest version.
  Never dispatch it by a version ID.
- `CLAUDE_CODE_SUBAGENT_MODEL=sonnet` backs up a missed `model`.  Set
  `model` anyway.

## 7. Band mix

- Aim for about 16% `haiku` or below, 64% `sonnet`, and 20% `opus` or
  above.
- Give a one-line reason for every `opus`-or-above dispatch.
- Run `score.py --mix [--session ID] [--days N]` to see the measured
  mix.  It needs the log-dispatch hook.  The log holds the alias that
  you requested.  A fallback model can answer instead: the hook also
  logs the model that answered (`served_model`), and `--mix` counts
  that model and reports how many lines it did this for (`served`).
- Run `~/.agents/skills/model-selection/scripts/token-share.py
  [--session ID] [--days N]` to see tokens by model, including inline
  work that the dispatch log cannot see.

## 8. Refusals

- A worker that declines returns `REFUSED (<category>)` or `PARTIAL`.
- Re-route `cyber`, `bio`, and `medical` once, to a different vendor.
  Quote the authorization.
- Get the target from `score.py --pick` with `--tag cyber` (or
  `--tag medical` for `bio`).  When `on_refusal` is null, stop and
  report.
- Get the user's approval for every `bio` re-route.

Steps: `references/refusals.md`.

## 9. Channel checks

- Run `~/.agents/skills/model-selection/scripts/test-external.sh [pi]`
  to test the external channels.  The output is Test Anything Protocol
  (TAP); exit 77 means skipped.
- Run `20-pi-credentials.sh` to find hidden Pi credentials.

## 10. Registry refresh

- Refresh the benchmark registry with the feed scripts in
  `~/.agents/skills/model-selection/scripts/`.  Steps and feeds:
  `references/pipeline.md`.

## 11. References

| Need | File |
| --- | --- |
| Bands, value, tags, profiles | `references/scoring.md` |
| Effort rules per harness | `references/effort.md` |
| Refusal recognition and re-route | `references/refusals.md` |
| Feeds and registry upkeep | `references/pipeline.md` |
