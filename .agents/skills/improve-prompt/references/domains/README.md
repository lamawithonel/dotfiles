# Domain Playbooks (maintainer documentation)

This file is for skill maintainers, not loaded during a diagnosis run.

The core skill is domain-agnostic: the S2 genre router adapts technique to
any subject without a per-vertical file.  This directory is an *optional*
extension point.  A domain playbook adds only what the genre router cannot
know -- the subject's own vocabulary and its canonical defaults -- so a
diagnosis can critique in-domain ("the tolerance and fit class are
unstated") instead of generically ("add detail").

**None ship by default.**  Add a playbook only when a subject recurs often
enough that its vocabulary pays for itself.  Absent a file, the skill still
works fully from the genre router alone.

## Load rule

During step 3 (Diagnose), if the diagnosed subject has a file here, the
skill loads `references/domains/<subject>.md` and uses its vocabulary and
defaults.  One hop only: SKILL.md -> `domains/<subject>.md`.  A playbook
never links to another playbook, so improving a prompt in one subject never
pulls an unrelated subject's context into scope.

## Naming and partitioning

- One file per subject, `references/domains/<subject>.md`, kebab-case.
- Keep each file self-contained; no cross-references between playbooks.
- Keep it small -- only subject-specific knowledge, never a copy of the
  genre router or rubric.

## Authoring template

```markdown
# <Subject> Playbook

## Vocabulary
Terms a competent practitioner uses, so critique names real flaws.

## Canonical deliverables
The artifacts this subject usually asks for, and their expected form.

## Common hard constraints
Limits that are almost always relevant here (units, materials, platform,
regulatory, budget) -- surface them in the rubric's Constraints slot.

## Standard success criteria
What "done and good" typically means in this subject (the DoD default).

## Typical ambiguities
The gaps most prompts in this subject leave open, pre-classified by S3 type,
so the ambiguity pass runs faster.

## Verification hooks
The external checks this subject relies on (a test, a standard, a
measurement, a citation source) for the rubric's verification-hook slot.
```
