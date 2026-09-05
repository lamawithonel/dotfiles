---
paths:
  - "**/*.rs"
  - "**/*.py"
  - "**/*.mojo"
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.go"
  - "**/*.c"
  - "**/*.h"
  - "**/*.cpp"
  - "**/*.hpp"
  - "**/*.sh"
  - "**/*.bash"
  - "**/*.awk"
  - "**/*.yaml"
  - "**/*.yml"
---

# Comment Style

When writing a verbose comment-- anything longer than one sentence--
apply the `english-writing-style-guide` (writing) skill: wrapping,
punctuation, spacing, and acronym rules all carry into comment prose.
Single-sentence comments need only match the surrounding code's comment
density and idiom.

## Comment Content Rules

- State first-principles facts and constraints: describe what the code
  achieves and the technical constraint, invariant, or non-obvious reason
  forcing that design.  Do not restate self-evident syntax.
- Never reference transient process metadata-- such as tickets, pull
  requests (PRs), issue numbers, roadmap phases, review threads, or
  author names-- in comments.  Place ephemeral context in version
  control commit history, pull request descriptions, or issue trackers.
- Keep inline comments concise and direct.  Reserve expansive narrative
  prose and system architecture for dedicated documentation files.

