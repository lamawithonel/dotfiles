---
name: rules-doctor
description: Check and improve agent-harness rules files (.claude/rules/*.md, .pi/rules/*.md, .agents/rules/*.md).  Validates YAML frontmatter against each harness schema (Claude Code path gating; @quandev104/pi-rules routing keys), flags unknown keys, wrong types, and rules that can never fire, and tightens rule content for reliable LLM adherence.  Use whenever a rules file is created or edited, or when asked to check, lint, validate, fix, tighten, or improve a rules file or its frontmatter.  Reports problems by default; edits only when explicitly asked.
license: Apache-2.0
metadata:
  pi-rules-source: "https://github.com/quanpersie2001/pi-rules"
---

# rules-doctor

Rules files are per-topic instruction files a harness injects into
context conditionally.  Two harness contracts matter, and one file
often serves both:

- **Claude Code** reads `.claude/rules/**/*.md` (project and
  `~/.claude/rules/` global).
- **pi-rules** (npm `@quandev104/pi-rules`, repo
  `quanpersie2001/pi-rules`) reads `.pi/rules/**/*.md`.  Unrelated
  projects also use the name "pi-rules"; only that repo's README is
  authoritative.

Other directories (`.agents/rules/`, `.cursor/rules/`) follow one of
these two contracts by convention; match on the keys present, not the
path.

## Workflow

1. Identify the target files: the file named in the request, or the
   rules file just created or edited.
2. If today is more than 3 months past the snapshot date below,
   follow [references/schema-refresh.md](references/schema-refresh.md)
   before validating.  Otherwise the tables below are authoritative.
3. Run the frontmatter checks.
4. When asked to improve, tighten, or review the rule itself, also run
   the content checks.
5. Report.  Edit only when the user explicitly asks for a fix.

## Schemas

**Snapshot date:** 2026-07-19

### Claude Code

Only one frontmatter key is documented:

| Field   | Type       | Behavior                                          |
| ---     | ---        | ---                                               |
| `paths` | glob(s)    | Rule loads when a matching file enters context.   |

No `paths` key means the rule loads at session start, like CLAUDE.md.
Unknown keys are silently ignored.  Rules are guidance the model reads,
not enforced configuration.

### pi-rules

| Field         | Type                     | Description                                                          |
| ---           | ---                      | ---                                                                  |
| `paths`       | `string \| string[]`     | Glob patterns matched against project-relative paths.                |
| `summary`     | `string`                 | One-line routing summary.                                            |
| `triggers`    | `string \| string[]`     | Prompt phrases that should load the rule.                            |
| `alwaysApply` | `boolean` (default false)| Inject on every code-related turn.  Use sparingly.                   |
| `priority`    | `number`                 | Higher priority rules are injected first.                            |
| `kind`        | `"rules" \| "inventory"` | Default `"rules"` (injected); `inventory` files are only listed.     |
| `guard`       | `boolean` (default false)| Require this rule before `write`/`edit` when write guard is enabled. |
| `description` | `string`                 | Human-readable; not used for matching.                               |

The README marks no field required, but routing needs at least one of
`paths`, `triggers`, or `alwaysApply: true` -- without one the file is
never selected.  `summary` is strongly recommended: when parent and
child rules both match, the parent shows only its summary.  `paths`
globs anchor to the session's project directory, not the rules file's
location.

## Frontmatter checks

- **Unknown keys** -- present in the file, absent from the schema.  A
  key valid in one harness but not the other (e.g. `alwaysApply` under
  Claude Code) is a note, not an error: cross-harness files are
  legitimate and unknown keys are ignored.
- **Type mismatches** -- e.g. `alwaysApply: "yes"` (string, expected
  boolean).
- **Never fires** -- none of `paths`, `triggers`, or `alwaysApply: true`
  set.  The harnesses diverge: Claude Code loads such a rule
  unconditionally every session; pi-rules silently ignores it, leaving
  it inert.  Report the divergence once -- do not also flag `paths` as
  missing, same root cause.

## Content checks

Run only when asked to improve, tighten, or review the rule content:

- **Imperative and positive.**  State the target behavior; prohibitions
  name the thing you want avoided and make it more available.  Keep a
  "don't" only as a hard guardrail, paired with what to do instead.
- **Checkable over vague.**  "Wrap at 72 characters" beats "keep lines
  short" -- the model can verify the first.
- **One rule per bullet, one place per rule.**  Duplicating a rule
  across CLAUDE.md and rules files means divergence later; keep a
  single source of truth and cross-reference.
- **Delete no-ops.**  A line the model already obeys by default ("be
  careful", "write good code") spends tokens to change nothing.
- **Explain why only when it changes behavior.**  A surprising
  constraint earns its rationale; an obvious one doesn't.
- **Scope tightly.**  Path-gate anything that can be path-gated;
  `alwaysApply` and pathless Claude Code rules cost context every
  session.  Flag large bodies on always-on rules.
- **Split at ~200 lines.**  Long files dilute adherence; split by topic
  so each loads only when relevant.

## Report

Default to reporting only -- do not touch the file.  One line per
finding:

```
<file>:<key or "frontmatter"> -- <problem>.
```

**Example:** `.pi/rules/api.md` has `alwaysApply: "yes"` and no
`summary`, `paths`, or `triggers`:

```
.pi/rules/api.md:alwaysApply -- wrong type (got string "yes", expected boolean).
.pi/rules/api.md:frontmatter -- never fires under pi-rules (no paths, triggers, or alwaysApply: true); loads unconditionally under Claude Code.
```

## Fix

Only when explicitly asked ("fix it", "correct the frontmatter"):

- Change only what the finding names; leave the rest of the file
  untouched.
- Keep values the user already set.  Derive a missing `summary` from the
  body only when unambiguous (a single clear heading or first sentence);
  otherwise ask, using the harness's interactive question tool
  (`AskUserQuestion` on Claude Code, `ask_user_question` on Pi, or an
  equivalent found via tool discovery), falling back to a plain
  conversational question if none exists.
- **Never-fires fix:** add `alwaysApply: true` rather than a catch-all
  `paths` glob.  Claude Code ignores the unknown key, so its eager
  session-start load is preserved; a `**/*` glob would downgrade it to
  loading only after the first file read.  Note the cost in the report:
  pi-rules will now inject the rule every code-related turn, so weigh a
  large body against that.

## Out of scope

Schemas other than the two above, unless asked to extend this skill.
