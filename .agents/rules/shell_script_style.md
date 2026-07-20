---
paths:
  - "**/*.sh"
  - "**/*.bash"
---

# Shell Script Style Guide

- Prefer safety over speed or compactness.
- Prefer POSIX syntax over Bash- or Zsh-specific syntax, except in the following
  cases:
  - Where shell-specific features are faster to execute, e.g.,
    `[[ "abc123" =~ c1 ]` instead of `echo abc123 | grep -q c1` (new process
    overhead).
  - Where shell-specific features are significantly more readable, e.g.,
    `<<-` heredocs with indented content and `source` instead of `.`.
  - Where shell-specific features add safety, e.g.,
    `set -o pipefail`, `local`, `readonly`, `typeset`, etc.
- Quote all string-literals with 'hard quotes'.
- Only use "soft quotes" when shell expansion is required.
- Enclose all variables in curly braces when they are used for interpolation,
  e.g., `"this ${string}"` or `"${HOME}/path/to/a/thing`, but not when they are
  standalone, e.g., `"$solitary_variable"` or `curl -o "$output_file" "$url"`.
- Use `UPPER_SNAKE_CASE` (with no leading underscore) for constants, exported
  variables, and other "public" variables intended for use across by other
  tools, programs, and applications.
- Use `_underscore_lead_lower_snake_case` for "local" and "private' variable
  and function names, regardless of whether they are declared with `local`
  or not.
- Use `lower_snake_case` (with no leading underscore) for "public" function
  names (exported or used across multiple files), e.g., utility functions
  like `join_string_by()` or `mean_of()`, and user-interactive functions.
- Use `_underscore_lead_lower_snake_case` for exported but "private" functions,
  e.g., helper functions used by user-interactive functions.
- Unset functions and variables if they are not needed after use, e.g.,
  temporary variables and one-time use helper functions.
- Batch `export` and `unset` calls as a micro-optimization-- speed matters!
- ALWAYS use the XDG Base Directory Specification!  Tell the user when they
  could use an XDG directory instead of their proposed location.
  See: @../references/basedir.html.
- Indent with tabs, not spaces.  Spaces MAY be used after tabs for `<<-`
  heredoc content, e.g. to indent the output file with its native indentation,
  but the initial indentation must be tabs.  Example:

  <!-- markdownlint-disable MD010 -->
  ```shell
  cat <<-EOF
  	1. Foo
  	2. Bar
  	   - Baz
  EOF
  ```
  <!-- markdownlint-enable -->

- Always use `set -o <option>` for shell options, one per line.
  - `errexit` must be the first option if used.
  - POSIX-compatible options come second (e.g. `nounset`, `noexec`).
  - Common non-POSIX options come third (e.g. `pipefail`).
  - Uncommon and shell-specific options come last (e.g., `extended_glob`
    `globstar`)
- Lint shell script files with `shellcheck` if it is available, except for
  one-time-use temporary scripts.
