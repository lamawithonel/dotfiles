---
name: agent-skills-validate
description: 'Validate an Agent Skill against the Agent Skills Specification (https://agentskills.io/specification).  Checks SKILL.md frontmatter shape (name, description), name/folder match, body length, scripts/ executability, and bundled-resource layout.  Spec violations fail; harness-specific frontmatter keys warn, except a near-miss of a real key, which fails because the behaviour the author asked for never happens.  Use whenever the user asks to validate a skill, audit a skill folder, check skill compliance, verify SKILL.md, or wants pre-commit/CI checks for a custom skill.  Accepts a path or a registered skill name — any location works (harness skill dirs, symlinked trees, project source dirs); only skills installed by external package managers (apm_modules) are refused, since those are upstream, not owned by the caller.'
license: Apache-2.0
---

# Agent Skills Validate

Validate one or more Agent Skills against the
[Agent Skills Specification](https://agentskills.io/specification).
Provider-neutral: works with any inference engine that
implements the spec.

## When to Use

- User asks to validate a skill, check skill compliance, audit
  a skill folder, or verify SKILL.md
- Pre-commit or CI checks for a hub-local skill
- After scaffolding a new skill via `make-skill-template`
- After editing an existing skill's frontmatter or layout

## What it Checks

For each skill, 18 spec-derived checks:

| #  | Check                                                                       |
|----|-----------------------------------------------------------------------------|
| 1  | `SKILL.md` (or `skill.md`) exists at the skill root                         |
| 2  | File starts with `---` frontmatter delimiter                                |
| 3  | Frontmatter is closed with a second `---`                                   |
| 4  | Frontmatter parses as valid YAML                                            |
| 5  | Frontmatter is a YAML mapping (not a list or scalar)                        |
| 6  | Frontmatter has `name:` field                                               |
| 7  | `name` length is 1–64 characters                                            |
| 8  | `name` is lowercase                                                         |
| 9  | `name` uses only `[a-z0-9-]` (ASCII; see Known Limitations)                 |
| 10 | `name` has no leading or trailing hyphen                                    |
| 11 | `name` has no consecutive hyphens (`--`)                                    |
| 12 | `name` matches `basename(skill_dir)` (NFKC-normalized when `python3` available) |
| 13 | Frontmatter has `description:` field                                        |
| 14 | `description` length is 1–1024 characters (after trim)                      |
| 15 | `compatibility`, when present, is ≤ 500 characters                          |
| 16 | Frontmatter key spelling and portability (two-tiered — see below)          |
| 17 | Body (post-frontmatter) is under 500 lines                                  |
| 18 | If `scripts/` exists, every file in it is executable                        |

Checks 3, 4, and 5 are early-exit: if frontmatter isn't closed
or doesn't parse as a YAML mapping, downstream key/field checks
are skipped (their failures would be noise).

## Result Tiers

No harness rejects a skill for an unrecognized frontmatter key —
they drop it and carry on.  So an unknown key is only a defect
when the skill *depended* on it.  Check 16 sorts on that:

| Key | Tier | Why |
|-----|------|-----|
| Spec key: `name`, `description`, `license`, `compatibility`, `metadata`, `allowed-tools` | pass | portable everywhere |
| Known harness extension: `argument-hint`, `disable-model-invocation`, `user-invocable`, `model` | **warn** | the owning harness honours it; the rest ignore it silently.  Portability note, not a defect |
| Unrecognized and unlike any real key | **warn** | inert everywhere; costs nothing but bytes |
| Near-miss of a real key, e.g. `user-invokable` for `user-invocable` | **fail** | the author asked for behaviour that never happens |
| Near-miss of a *capability guard* — `allowed-tools`, `disable-model-invocation`, `user-invocable` | **fail** | the restriction silently disappears and the skill is more exposed than it was written to be |

That last row is the one that matters.  A typo in a key that
grants something is a missing feature; a typo in a key that
*withholds* something is a hole, and it fails silently in exactly
the direction you would not notice.

Near-miss detection uses `difflib.get_close_matches` at a 0.8
cutoff and needs `python3`.  Without it, unrecognized keys are
reported as a single warning and left unclassified.

Warnings count as passes and never change the exit status.

## Usage

### Validate one skill (by path or name)

    bash skills/agent-skills-validate/scripts/validate.sh <path-or-name>

Examples:

    bash skills/agent-skills-validate/scripts/validate.sh skills/repos-migrate
    bash skills/agent-skills-validate/scripts/validate.sh repos-migrate
    bash skills/agent-skills-validate/scripts/validate.sh ./skills/conventional-commits

The arg is treated as a path if it contains a `/` or starts
with `.`.  Otherwise it's resolved against `skills/` first,
then any other registered roots.

### Validate every skill in a roots list

    bash skills/agent-skills-validate/scripts/validate-all.sh

By default this loops `skills/` only.  Pass roots as args to
override:

    bash skills/agent-skills-validate/scripts/validate-all.sh skills/ extra-skills/

Exits non-zero if any skill failed.

## What it Refuses to Validate

The validator **refuses** to run on apm-installed paths.  Any
path whose ancestor contains `apm_modules` is rejected with:

    upstream-managed skill, not validated: <path>

This is a contract, not a failure mode.  Apm-installed skills
come from external sources and are not owned by the caller —
fixing them belongs upstream.  Validating locally would either
produce noise (drift from the upstream version) or pressure
contributors to monkey-patch installed copies.

Location alone never disqualifies a skill: hand-authored skills
validate from anywhere — `~/.agents/skills`, harness symlink
trees like `~/.claude/skills`, or a source directory inside a
project during development.  The content of the skill directory
is what is validated, not its location.

## Output Format

TAP-ish, one line per check:

    ok 1 - SKILL.md (or skill.md) exists at skill root
    ok 2 - file starts with frontmatter delimiter
    not ok 3 - frontmatter closed with second --- (got 1 delimiters)
    ...

A warning is an `ok` line carrying a `# WARN` directive, followed
by indented detail:

    ok 16 - frontmatter uses non-spec keys (unknown: argument-hint) # WARN
    #   WARN:  argument-hint: harness extension, not in the spec; ...

Followed by a summary, which names warnings only when there are
some:

    1..18
    18 passed, 0 failed, 1 warning

`validate-all.sh` tallies them per skill:

    # summary: 43 skills, 7 failed, 4 warned, 0 skipped

Exit 0 if no check failed, non-zero otherwise.  Warnings do not
affect the exit status.  Exit 3 is reserved for the apm-refusal
contract (see above).

## CI Integration

The `tests/skills/spec_compliance.bats` file invokes
`validate-all.sh` and asserts exit 0.  Wire it into your green
gate via:

    mise run test:skills

Existing test runners (e.g. `mise run test:migration`) are
unaffected — the spec test runs independently.

## Known Limitations

These are deliberate divergences from the upstream `skills-ref`
Python validator at
https://github.com/agentskills/agentskills/tree/main/skills-ref:

- **Check 9 is ASCII-only.**  The spec allows unicode lowercase
  letters in skill names (e.g. Cyrillic, CJK).  `skills-ref`
  uses `unicodedata` + `str.isalnum()` to enforce this in
  Python; replicating that correctly in bash is non-trivial,
  and every hub-local skill is ASCII today.  Hub authors
  shipping i18n skill names should additionally validate with
  `skills-ref` upstream.
- **Check 12 NFKC-normalizes only when `python3` is on PATH.**
  Without `python3`, the comparison degrades to a raw byte-
  equal string compare.  Decomposed-vs-composed unicode forms
  (e.g. `café` written as `é`) will be rejected as
  mismatching folder names.
- **Check 18 (`scripts/` executability) has no spec mandate.**
  The Agent Skills Specification is silent on file
  permissions; this is a hub-local hygiene rule kept from the
  original implementation.

## Why a Skill, Not Just a Script

Per the Agent Skills Specification's progressive-disclosure
model, validation logic belongs in a self-contained skill so
that:

- Any inference engine can invoke it as a slash command
- The validator's scripts are bundled with its docs
- CI consumers can call into the bundled scripts without
  importing the skill body
- Other skills can invoke `agent-skills-validate` rather than
  reimplementing the spec checks

This mirrors the pattern from `repos-migrate`, which exposes
its `--resolve` API as the canonical path-resolution contract
for the four upstream `repos-*` skills.
