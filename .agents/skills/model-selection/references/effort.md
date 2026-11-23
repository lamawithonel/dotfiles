# Effort

Effort names do not transfer across vendors.  `high` on one vendor is
not `high` on another; the band table is the only comparison.  Every
dispatch names its effort (see SKILL.md, "Name the model and effort").

## 1. Dispatcher rules

`score.py` returns the best-value variant of the band at whatever
effort it was measured (`banded_effort`: `single`, `low`, up to `max`).
For a Claude Code pick, `effort` is the role effort (executives
`high`, coordinators `high`, workers `medium`; see the `roles`
skill).  It may lower a pick but never lifts it out of its band,
except in the top floor band; a warning says when that cap applies.
For a Pi pick, `effort` is the exact `--thinking` level the command
sends.  Change a default only with a one-line reason.

1. Workers run `medium` for routine work: edits with a clear spec,
   lookups, transcription, summaries.  On hard reasoning, a `medium`
   worker measures about one band lower.
2. Workers run `high` when the work needs reasoning: debugging without
   a repro, design, math, synthesis, or adversarial review.
3. On a quality failure, raise effort to `high` first.  Above `high`,
   change band.  Opus at `high` beats Sonnet at `xhigh` on score and
   cost.  The change counts toward the higher band's share of the mix.
4. Executives run `high`.
5. Never use `max` as a Claude role default.  Use it on a user
   directive or for a final adversarial review.  A Pi pick may come
   back at `max` when that is the variant measured best in the band.
6. Use `low` for mechanical work a script checks, and for wide
   fan-out.
7. At `xhigh` or `max`, a worker stops once its checks pass and starts
   no reviewer subagents.
8. At `low` effort, a worker runs a check that exercises each change
   before it reports done.
9. Re-sweep effort at each model upgrade (see section 2).

## 2. Vendor start efforts

The vendor effort page gives a start effort for each model.[^vendor]
The table is vendor advice, not a local measurement.  The role defaults
in section 1 stay in force until a local eval shows a gain.

| Model | Vendor start effort |
| --- | --- |
| Opus 5 | `high` |
| Opus 5.5 | `medium` |
| Fable 5.x | `high` |
| Sonnet 5.5 | `high`; `medium` for well-specified agentic tasks |
| Haiku 5.5 | `medium` |
| Opus 4.7 and 4.8 | `xhigh` for coding and agentic work |

- The vendor advice to use `xhigh` and `max` only where evals show a
  gain applies to Sonnet 5.5 and Haiku 5.5, and to `xhigh` on Fable
  5.2.  It does not apply to Opus 4.7 and 4.8, which start at `xhigh`.
- Opus 5.5 and Fable 5.2 have vendor advice only.  No local eval
  backs either row.
- Re-sweep rule: at each model upgrade, run an effort sweep on local
  evals before you change a default.  Keep the vendor start effort
  until the sweep shows a better level.  A higher effort can solve
  fewer tasks: one measured run solved 90 tasks at `high` and 85 at
  `xhigh`.[^sweep]
- Test any raise of the executive default above `high` in the same
  sweep.

[^vendor]: https://platform.claude.com/docs/en/build-with-claude/effort
    (undated).
[^sweep]: Sonnet 5 on DeepSWE, single run per level.
    https://arxiv.org/html/2610.34491 (2026-10-25).

## 3. How each harness sets effort

| Harness | Per worker | Notes |
| --- | --- | --- |
| Claude Code | `Agent` `effort` parameter | Overrides agent frontmatter.  `CLAUDE_CODE_EFFORT_LEVEL` overrides everything, including the parameter: never set it |
| Claude Code on Bedrock | Same | No Bedrock-specific behavior is documented |
| Pi | `--thinking <level>` on the command | Levels `off`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`.  See below |
| Herdr pane | The pane program's own flag after `--` | Herdr has no effort flag |

## 4. Pi thinking map and clamp

- Pi clamps `xhigh` and `max` to the `high` budget (16,384 tokens) for
  providers with a thinking-token budget (Anthropic, Bedrock, Google).
- For OpenRouter models Pi sends the level as `reasoning.effort`
  unchanged unless the model's `thinkingLevelMap` remaps it.  A level
  mapped to null is unsupported: the registry's `pi_levels` lists the
  supported ones, and the router skips others.
- GLM honors `max`.  DeepSeek V4.1 Flash 0910 treats `max` as `high`;
  the registry sends `high` for it.
- The `effort` of a Pi pick equals the `--thinking` level in `command`,
  after the `overrides.pi_thinking` remap and the `single` rule.
- A Pi session started without `--thinking` uses the host's
  `defaultThinkingLevel`, which may sit well below the band.  Always
  pass `--thinking`.
