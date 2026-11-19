#!/bin/sh
#
# SessionStart hook (matcher: compact): re-inject the rule pointers.
#
# Path-scoped rules load into the message history when a matching file is
# read, so a compaction can summarize them away.  After a compaction this
# hook adds a short pointer to the code-rules skill and ~/.agents/rules/,
# and to the no-cd rule, as SessionStart additionalContext.
#
# Reads and ignores stdin.  The settings matcher selects the compact
# source, so the hook does not inspect the payload.
#
# Exit codes: 0 always.  Prints one SessionStart JSON object on stdout.

set -o nounset

cat > /dev/null 2>&1 || true

printf '%s\n' '{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "Context was compacted, so rules read earlier may be gone.  Before you plan, write, or edit code, load the code-rules skill and read the matching language file in ~/.agents/rules/ (for example shell.md, python.md, or rust.md).  Bash calls never use cd, pushd, or popd: use git -C DIR, make -C DIR, or env -C DIR cmd (see ~/.claude/CLAUDE.local.md)."}}'
exit 0
