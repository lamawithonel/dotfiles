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

- Split long pipelines and logical chains one segment per line, with
  the binary operator (`|`, `&&`, `||`) leading the continuation line.
  A leading operator distinguishes a continuation from a new command.
- Indent `case` alternatives one level from `case` and `esac`, and
  their actions one level further.  The indentation keeps the
  statement's boundaries visible at a glance.
- Put one space after redirection operators: `> "$file"`, not
  `>"$file"`.
- Preserve column alignment across neighboring lines of similar
  structure (aligned trailing comments, parallel assignments); do not
  collapse deliberate padding.
- Always use `set -o <option>` for shell options, one per line.
  - `errexit` must be the first option if used.
  - POSIX-compatible options come second (e.g. `nounset`, `noexec`).
  - Common non-POSIX options come third (e.g. `pipefail`).
  - Uncommon and shell-specific options come last (e.g., `extended_glob`
    `globstar`)

## Static Checks

Shell is loosely typed and loosely parsed, so every check below is
mandatory wherever its tool is available.  Run the full battery after
creating or editing any shell script, before calling the work
complete.  Do not rely on editor tooling or hooks to run the checks
for you-- some environments restrict hooks.  One-time-use throwaway
scripts are exempt.

### The battery

    sh -n FILE                     # bash -n for Bash-dialect scripts
    shellcheck FILE
    shfmt -d -bn -ci -sr -kp FILE  # diff must be empty
    checkbashisms FILE             # #!/bin/sh scripts only
    shellmetrics FILE              # CCN <= 10 / function, <= 8 file average

### Why each check earns its place

- **`sh -n` / `bash -n`**-- the zero-cost syntax gate.  Run it first:
  it fails in milliseconds on errors every later tool would report
  more confusingly.
- **`shellcheck`**-- the primary linter.
- **`shfmt -d -bn -ci -sr -kp`**-- mechanical format enforcement.  It
  reads the dialect from the shebang and defaults to tab indentation,
  and the preference flags enforce the continuation-operator, case-
  indentation, redirect-spacing, and alignment-padding rules from the
  style guide above.  An empty diff is the pass condition.
- **`checkbashisms`**-- POSIX conformance for `#!/bin/sh` scripts.
  It catches non-POSIX constructs that shellcheck's sh mode misses,
  so it is not redundant with shellcheck.
- **`shellmetrics`**-- cyclomatic complexity, against the thresholds
  below.

### Complexity thresholds

- CCN <= 10 per function; file average <= 8.
- Exception: a function whose CCN comes from one large `case`
  statement may reach CCN 16 when every branch is under 5 lines and
  regular in shape with respect to the others.
- Refactor anything over threshold, but only functions under active
  development.  Leave legacy functions alone unless refactor is
  explicitly in scope.
