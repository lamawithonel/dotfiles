## Markdown and Writing Style Guide

- Wrap text after the first word extended beyond 72 characters, and do
  not exceed 80 characters.  Wrap before 72 characters if the last word
  would extend beyond 80 characters.  Exceptions: URLs, long paths, and
  code examples.
- Use two spaces after sentences for readability.  Markdown is
  frequently read in monospace text editors where kerning is not used,
  and the extra spacing helps visually separate sentences.
- Use an oxford comma in lists of three or more items for clarity,
  e.g., "A, B, and C".
- Do not use forced line breaks (two or more spaces at the end of a
  line.)

## Shell Script Style Guide

- Wrap comments at the first word extended beyond 72 characters, and do
  not exceed 80 characters.  Wrap before 72 characters if the last word
  would extend beyond 80 characters.  Exceptions: URLs, long paths, and
  code examples.
- Prefer POSIX syntax over Bash- or Zsh-specific syntax, except in the
  following cases:
    - Where shell-specific features are faster to execute, e.g.,
       `[[ "abc123" =~ c1 ]` instead of `echo abc123 | grep -q c1`.
    - Where shell-specific features are significantly more readable,
       e.g., `<<-` heredocs with indented content and `source` instead
       of `.`.
- Use shell-specific features that add safety, e.g.,
  `set -o pipefail`, `local`, `readonly`, `typeset`, etc.
- Quote strings with 'hard quotes' unless variable expansion is needed.
- Enclose all variables in curly braces when they are part of a larger
  string, e.g., `"this ${string}"`, but not when they are a standalone,
  e.g., `"$solitary_variable"`.
- Use `UPPER_SNAKE_CASE` for variables intended to be used across
  multiple functions, e.g., configuration variables.
- Use `_underscore_lead_lower_snake_case` for file-local variables and
  functions, regardless of whether they are declared with `local` or
  not.
- Use `lower_snake_case` for functions intended to be used across
  multiple files, e.g., utility functions.
- Unset unneeded functions and variables not needed after use, e.g.,
  temporary variables and helper functions.
- Batch `export` and `unset` calls as a micro-optimization-- speed
  matters!
- Use XDG Base Directory Specification wherever possible.
- Use tabs for indentation.  Spaces may be used after tabs for `<<-`
  heredoc content, e.g. to indent the output file with its native
  indentation, but the initial indentation must be tabs.
- Always use `set -o <option>` for shell options, one per line.
  - `errexit` must be the first option if used.
  - POSIX-compatible options come second (e.g. `nounset`, `noexec`).
  - Common non-POSIX options come third (e.g. `pipefail`).
  - Bash-specific options come last.

## Git Commit Style Guide

- One logical change per commit
- Use Markdown formatting for body if needed (e.g., lists, code blocks)
- Present tense: "add" not "added"
- Imperative mood: "fix bug" not "fixes bug"
- Reference issues: `Closes: #123`, `Refs: #456`
- Keep headline concise, under 50 characters if possible, no more
  than 72
- The body should focus on the "why" and "how" more than the "what"
  (which should be in the headline)
- Wrap text at 72 characters except for URLs
- Use Git trailers for metadata and references: `Co-authored-by:`,
  `See-also:`, etc.

## Tool Preferences

- Use Podman over Docker for container operations.  Rootless mode is
  the default.
- Use mise as the primary task runner and non-Cargo devtool dependency
  manager.
- Use `cargo build`, `cargo embed`, and `probe-rs` for Rust build and
  flash operations — not mise.
- Use SELinux-aware bind mounts (`:Z`) when mounting host paths into
  containers.

## Dockerfile Style

- Prefer `Dockerfile` over `Containerfile`.  Use Podman's
  `--format docker` flag (or equivalent) for compatibility.
- Use BuildKit syntax: `# syntax=docker/dockerfile:1` at the top.
- Use `RUN --mount=type=cache` for package manager and build caches.
- Set `SHELL ["/bin/bash", "-o", "pipefail", "-c"]` (or equivalent
  safe shell) early in the Dockerfile.
- Minimize layers: combine related `RUN` instructions.
- Use `--no-install-recommends` (apt) or equivalent for minimal
  installs.
- Prefer multi-stage builds to keep final images small.

## PR and Branch Workflow

- Use feature branches for all changes.
- Organize commits into a clean patch series: each commit is one
  logical change, no commit overwrites a previous commit in the
  series.
- No merge commits on feature branches; rebase onto the target branch.
- **Never force-push** (including `--force-with-lease`) without
  explicit user confirmation.  The only exception is fully autonomous
  mode, where the feature branch is created, modified, and pushed
  entirely within a single unattended task.

## Licensing Preferences

- Prefer permissive licenses with patent protections, e.g.,
  Apache-2.0.
- Second preference: simple permissive licenses, e.g., MIT, BSD.
- Notify the user when a core component uses a copyleft license
  (e.g., GPLv2, LGPLv2.1).
- Ask before using strong copyleft licenses (e.g., AGPLv3, GPLv3).
- Ask before using mixed-license "freemium" software (e.g., open core
  with proprietary add-ons, BSL).
