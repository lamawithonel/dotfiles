# Skill Authoring

Load this only when the prompt being improved is itself a skill or agent
prompt (a SKILL.md, a system prompt, an agent instruction set).  Use it as a
DoD gate: the rewrite must pass every check below.

## Frontmatter contract

- `name`
  - Matches the containing folder name exactly.
  - 1-64 characters.
  - Lowercase letters, digits, and single hyphens only (kebab-case).
  - No leading or trailing hyphen; no consecutive hyphens.
- `description`
  - Third person, stating both *what* it does and *when* to use it.
  - Packed with concrete trigger phrases the user would actually type.
  - <= 1024 characters.
  - No XML/HTML tags.
- No other frontmatter keys unless the target platform defines them.

## Description rule (what + when)

The description is the only always-loaded text, so it must earn the trigger
by itself.  Lead with what the skill produces, then the conditions and exact
phrasings that should fire it.  Prefer real user phrasings ("rewrite this
prompt", "/improve-prompt") over abstract capability statements.  Keep the
trigger conditions specific: a clause broad enough to match almost any
request (e.g. "any under-specified task") causes over-firing on ordinary
work -- require an explicit intent for what the skill does.

## Body rules

- Progressive disclosure: SKILL.md holds the core loop only; push
  catalogs, tables, and long recipes into `references/` loaded on demand.
- Size budget: keep the body under ~500 lines / ~5k tokens.
- "Claude is already smart" token test: drop any instruction the model
  already reliably follows without being told.  Every retained line must
  change behavior.
- Positive phrasing: say what to do; reserve negatives for genuine traps.
- Define an acronym or shorthand before its first use.

## Degrees-of-freedom calibration

Match the instruction's rigidity to the task's fragility.

| Freedom | Use when | Form |
|---|---|---|
| High (prose) | many valid approaches; judgment wanted | guidance, principles |
| Medium (template) | a consistent shape is required | a fill-in template or schema |
| Low (exact command) | fragile, ordered, or irreversible steps | the literal command/sequence |

Over-constraining a high-freedom task wastes tokens and boxes the model in;
under-constraining a fragile one invites unsafe improvisation.

## Reference-layout rules

- One level deep: SKILL.md links each reference directly; a reference never
  links to another reference.
- Partition references so loading one never drags in unrelated material.
- Name and describe each reference at its link so the model loads it only
  when needed.
- Keep maintainer-only docs out of the runtime load list, or mark them
  clearly as not loaded during a run.

## DoD gate checklist

Before emitting a generated or rewritten skill, confirm:

- [ ] `name` matches folder, is valid kebab-case, 1-64 chars, no
      consecutive/edge hyphens.
- [ ] `description` is third person, <=1024 chars, trigger-rich, no XML,
      and its triggers are specific enough not to over-fire.
- [ ] Body is the core loop only, under the size budget, positive-phrased.
- [ ] Every reference is one hop from SKILL.md and partitioned.
- [ ] Degrees of freedom match task fragility for each instruction.
- [ ] No instruction survives that the model would follow anyway.
