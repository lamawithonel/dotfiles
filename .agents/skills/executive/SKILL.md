---
name: executive
description: >-
  Declare this running session an executive for one domain.  The user
  types `/executive <domain>` in Claude Code or `/skill:executive
  <domain>` in Pi.
license: Apache-2.0
compatibility: >-
  Claude Code and Pi.  The tab and workspace labels need Herdr.  The
  rest works without it.
metadata:
  version: "1.0"
  domain: delegation
allowed-tools: Read Bash(herdr tab get:*) Bash(herdr tab rename:*) Bash(herdr workspace rename:*)
disable-model-invocation: true
---

# Executive

The user typed `/executive <domain>`.  The argument is the domain.  This
session is now the executive for that domain.

## Steps

1. Take the domain from the argument.  Done when you hold one word or
   hyphenated name.  Ask the user for the domain when the argument is
   empty, then stop until the user answers.
2. Check for Herdr.  Run `test "${HERDR_ENV:-}" = 1`.  Done when you
   know yes or no.  On no, skip step 3.
3. Relabel with Herdr.  Done when both labels read as set.
   - Run `herdr tab get "$HERDR_TAB_ID"` and
     `herdr workspace get "$HERDR_WORKSPACE_ID"` first.  They only
     read.
   - Run `herdr tab rename "$HERDR_TAB_ID" executive`.
   - Run `herdr workspace rename "$HERDR_WORKSPACE_ID" <domain>`.
   - Leave the tab and the workspace where they are.  Rename only.
4. Take the session name `<domain>-executive`.  Use it as your name in
   every message and report.  In Claude Code, run `/rename
   <domain>-executive` if you can.  Otherwise state the name.
5. Read `~/.agents/skills/roles/references/executive.md` and follow it
   from now on.  Done when you can state your duties and the INLINE
   BUDGET.
6. Tell the user, in these words or close to them:
   - "I am now the executive for `<domain>`.  These rules last only
     until the next compaction."
   - "For permanent rules, relaunch me through
     `agent-launch executive <domain>`."
7. Wait for the user's first request.

## Names

- Workspace: `<domain>`.
- Tab: `executive`.
- Session: `<domain>-executive`.
