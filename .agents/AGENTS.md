# Global Instructions

## Local Instructions

Read @~/.agents/AGENTS.local.md for local instructions.  Local instructions
take precedence over global instructions.

## Session Start Instructions

Perform these actions if they have not yet been performed unless the user
requests otherwise:

- Use the `/caveman` skill
- Use the `/ponytail` skill
- Create a session temporary directory at session start or if the session
  was resumed-- either `$TMPDIR/<session-id>` or `/tmp/<session-id>` if
  `$TMPDIR` is unset.  Remember the expanded path and hard-code it when used.

---

## Hierarchical Agent Limits

- **Forked Sub-Contexts:** Force worker sub-agents to operate within isolated
  execution windows.  They must swallow verbose compilation streams internally
  and return only high-signal results to the parent thread.
- **State-Stagnation Circuit Breaker:** Sub-agents are allowed up to 12
  sequential turns to execute complex, multi-step implementations.  However,
  they MUST immediately self-terminate and yield control if **3 consecutive
  turns** result in zero state progress (e.g., executing the identical terminal
  command, repeating a failing edit, or hitting the exact same error boundary).
- **Early Boundary Escape:** If a sub-agent discovers during its initial
  context-gathering turn that the assignment requires modifying more than
  3 decoupled subsystems, it must halt immediately, output an execution map,
  and return control to the coordinator for finer task partitioning.

## Project-level Host-Local Directories

If a project directory has no declared host-local directory scheme...

- Use `.local/share/` for host-local data (
- Use `.local/state/` for host-local state
- Use `.cache/` for host-local temporary files
- Add them to `.gitignore` to make them host-local, falling back to more
  specific sub-directories or file patterns if the project uses the directories.
- Use the XDG base dir specification guidelines when selecting the correct
  directory.  The directories intentionally mimic the XDG base dir spec to
  make this classification easy.

## Long-Context Recovery

To recover from crashes or paused sessions...

- Keep a YAML-formatted project journal at `.local/state/agents/journal/<YYYY-MM-DD>.md`
- Log a journal entry on each turn that edits or deletes a project file.
- Use `.cache/agents/` as a project-level scratchpad.
- **DO NOT** use session IDs in path or file names.
- **DO** use session IDs in file entry headers, metadata, comments, etc.
- **DO NOT** eagerly read every journal file.
- **DO** look for and read the latest file at session start.
- **DO** inform the user if there are files older than 2 weeks old.
- **DO NOT** trim or purge the directories without asking the user.

## English Writing Style Guide

- Use two spaces after sentences for readability.  Most text is rendered
  with monospace fonts and no kerning, and variable-width rendering systems
  can collapse the two spaces at render-time.
- Use an oxford comma in lists of three or more items for clarity, e.g.,
  "A, B, and C".
- Do not use the unicode em-dash (—).  Instead, use two ASCII hyphens (--).
- Use zero space before an em-dash and one space after when using it in a
  sentence.  For example, "A-- B" instead of "A -- B" or "A--B".
- Use the em-dash sparingly and only when it improves clarity.  Avoid using
  it in place of parentheses or commas.
- Semicolons are OK when used correctly; they fall flat when overused.

## Agent Prompt Style

- **ALWAYS** use XML-style prompts when crafting instructions for agents.
- Always start with a `<persona>` section to illicit the desired behavior
  unless starting from a pre-defined agent persona.
- **ALWAYS** use a `<prompt>` section for the primary instructions.
- Use a `<context>` section to orient agents.
- Use `<return>` with an optional `<template>` to specify return expectations.
- Use other tags as needed.  Tags are informal with no set schema.
- Tags may be nested and may include arbitrary parameters.

Example:

```
<persona name="Mr. Robot">
You are a...
</persona>

<context>
...
</context>

<prompt>
...
</prompt>

<return>
Return instructions...
  <template>
  ...
  </template>
</return template>
```

## Code Repository Comprehension

When the user points you at a different repository (by path or URL):

- Read `AGENTS.md` at the repo root first.
- If `AGENTS.md` does NOT exist, fall back to `README.md` for orientation.
- **NEVER crawl an entire repo to understand it!**

## No Inline Shell Scripts

- **NEVER** use `bash -c`, `sh -c`, or other POSIX-like shells with `-c`.
- Prefer `python -c` or temporary shell script files.
- Do not use shell expansion features with `Bash()`, not even variables.

Bad:

```sh
sh -c "cd /path/to/thing && VAL=var do-the-thing with arguments | grep 'what I want'"
```

Good:
<!-- markdownlint-disable MD013 -->
```python
python -c "import os, subprocess; r = subprocess.run(['do-the-thing', 'with', 'arguments'], cwd='/path/to/thing', env={**os.environ, 'VAR': 'val'}, capture_output=True, text=True); print('\n'.join(l for l in r.stdout.splitlines() if 'what I want' in l))"
```
<!-- markdownlint-enable -->

## Software Development Lifecycle

- **ALWAYS** use RED -> GREEN testing
- **ALWAYS** use Behavior-Driven Development (BDD)
- Obey the Test Pyramid: Data Types > Units > Services > End-to-End Acceptance

## Git Commit Style Guide

- One logical change per commit
- Use Markdown style and formatting for the message body
- Present tense: "add" not "added"
- Imperative mood: "fix bug" not "fixes bug"
- Reference issues: `Closes: #KEY-123`, `Refs: #KEY-456`
- Keep headline concise, under 50 characters if possible, no more than
  72 characters at maximum
- The message body should focus on the intent, motivation, and decisions.
- Use Git trailers for metadata and references: `Co-authored-by:`,
  `See-also:`, etc.

## Host-Local Project Directories

If a project has not yet declared a specification, use use this directory
scheme for host-local files:

- `.local/share/` for host-local data 
- `.local/state/` for host-local state
- `.cache/` for host-local temporary files

If they are not already used by the project, add these directory patterns
to the project `.gitignore` on first use or creation of a nested file:

- `.local/`
- `.cache/`

If the project already uses them and they cannot be safely git-ignored, add
the next deepest level that can be safely added, for example, `.local/state/`
if it is unused or `.local/state/<slug>/` if `.local/state/` is used.

## Tool Preferences

- Use mise as the primary task runner and devtool dependency manager
- Use language-specific package managers for project dependency management
- Use `cargo build`, `cargo embed`, and `probe-rs` for Rust build and flash
  operations — not mise.
- Use `gh` to interact with GitHub, do not use `curl` even for single files.

### Open Source Software Selection

Follow these rules when selecting open source software for use in a project.

- Prefer software licensed using a permissive license with patent protections,
  like Apache-2.0, or simple permissive licenses, like MIT or BSD.
- Notify the user when a core component uses any copyleft license, e.g.,
  GPL-2.0, LGPL-2.1, MPL-2.0, AGPL-3.0, CDDL-1.1, etc.
- Ask before adding tools or components that use strong copyleft licenses,
  e.g., AGPL-3.0, GPL-3.0, SSPL-1.0, etc.
- Ask before adding tools or components that use mixed-license "freemium"
  or "shareware" software, e.g., open core with proprietary add-ons, BUSL-1.1,
  "Commons Clause", RSALv2, etc.
