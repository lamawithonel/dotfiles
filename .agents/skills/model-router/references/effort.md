# Effort

Effort names do not transfer across vendors.  `high` on one vendor is
not `high` on another; the band table is the only comparison.  Every
dispatch names its effort (see SKILL.md section 4).

## 1. Dispatcher rules

`score.py` returns the best-value variant of the band at whatever
effort it was measured (`banded_effort`: `single`, `low`, up to `max`).
For a Claude Code pick, `effort` is the role effort (orchestrators
`xhigh`, coordinators `high`, workers `medium`; see
`~/.agents/ROLES.md`).  It may lower a pick but never lifts it out of its band,
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
4. Orchestrators run `xhigh`.
5. Never use `max` as a Claude role default.  Use it on a user
   directive or for a final adversarial review.  A Pi pick may come
   back at `max` when that is the variant measured best in the band.
6. Use `low` for mechanical work a script checks, and for wide
   fan-out.

## 2. How each harness sets effort

| Harness | Per worker | Notes |
| --- | --- | --- |
| Claude Code | `Agent` `effort` parameter | Overrides agent frontmatter.  `CLAUDE_CODE_EFFORT_LEVEL` overrides everything, including the parameter: never set it |
| Claude Code on Bedrock | Same | No Bedrock-specific behavior is documented |
| Pi | `--thinking <level>` on the command | Levels `off`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`.  See below |
| Herdr pane | The pane program's own flag after `--` | Herdr has no effort flag |

## 3. Pi thinking map and clamp

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
