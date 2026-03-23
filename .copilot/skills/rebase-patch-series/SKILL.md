---
name: rebase-patch-series
description: 'Rebase git commits into a clean PR patch series where each commit is one logical change and no commit overwrites a previous commit. Use when asked to "clean up commits", "rebase into a patch set", "squash fixups", "split a commit", "reorder commits", or prepare a branch for PR review. Supports: (1) Analyzing commits to plan a logical series, (2) Interactive rebase with edit/squash/fixup/drop, (3) Splitting multi-concern commits, (4) Folding late fixes into earlier commits, (5) Rewriting commit messages to reflect final state.'
allowed-tools: Bash
---

# Rebase into Clean Patch Series

Reorganize a feature branch into a logical, reviewable sequence of
commits suitable for a pull request.  Each commit in the final series
should represent one self-contained logical change, and no later commit
should undo or overwrite work from an earlier one.

## Core Principles

1. **One logical change per commit.**  A commit that touches unrelated
   concerns must be split.
2. **No commit overwrites a prior commit in the series.**  If a later
   commit fixes or amends something introduced earlier, fold it into
   the original commit.
3. **Commit messages describe the final state**, not the history of how
   you got there.  After folding a fix into an earlier commit, reword
   the message as if the fix was always part of that commit.
4. **The series tells a story.**  Order commits so each builds on the
   last: foundational changes first, then consumers, then docs.

## Workflow

### Phase 1: Analyze

Before touching anything, understand the current state.

```bash
# View the commit series
git log --oneline --reverse <base>..HEAD

# View the full diffstat
git diff --stat <base>..HEAD

# Inspect individual commits
git show --stat <sha>
```

Build a mental model of what each commit does.  Identify:

- Commits that touch multiple unrelated concerns (split candidates)
- Later commits that fix or amend earlier ones (fold candidates)
- Commits that should be reordered for logical flow
- Commits that can be dropped entirely

### Phase 2: Plan

Present the plan to the user before executing.  Use this format:

```
Current series:
  1. abc1234 feat: add user model
  2. def5678 feat: add API routes
  3. 789abcd fix: typo in user model   ← fold into commit 1
  4. 012cdef docs: add API docs

Proposed series:
  1. feat: add user model              (amend with fix from commit 3)
  2. feat: add API routes
  3. docs: add API docs
```

Get explicit confirmation before proceeding.

### Phase 3: Execute the Rebase

#### Starting the Rebase

```bash
# Always rebase onto the merge base
git rebase -i <base>
```

Use `GIT_SEQUENCE_EDITOR` to script the todo list non-interactively:

```bash
cat <<'EOF' > /tmp/rebase-seq.txt
edit abc1234 feat: add user model
pick def5678 feat: add API routes
drop 789abcd fix: typo in user model
pick 012cdef docs: add API docs
EOF
GIT_SEQUENCE_EDITOR="cp /tmp/rebase-seq.txt" git rebase -i <base>
```

#### Folding a Later Commit into an Earlier One

When a later commit should have been part of an earlier one:

1. Mark the earlier commit as `edit` and `drop` the later one.
2. Before starting the rebase, stage the later commit's changes:

```bash
# Save the patch from the commit to be folded
git show <sha-to-fold> --format= > /tmp/fold.patch
```

3. When the rebase stops at the edit point:

```bash
# Apply the saved changes
git apply /tmp/fold.patch
git add -A
git commit --amend    # Reword to reflect the combined change
git rebase --continue
```

Alternative: if the fold commit is simple, use `stash`:

```bash
# Stash the changes before rebase
git stash

# After rebase stops at edit point
git stash pop
git add -A
git commit --amend
git rebase --continue
```

#### Splitting a Commit

When one commit contains multiple logical changes:

1. Mark the commit as `edit` in the rebase todo.
2. When the rebase stops:

```bash
# Undo the commit but keep changes staged
git reset --soft HEAD~1

# Unstage everything
git reset HEAD .

# Stage and commit each logical group separately
git add <files-for-first-change>
git commit -m "<type>: <first change>"

git add <files-for-second-change>
git commit -m "<type>: <second change>"

git rebase --continue
```

For fine-grained splitting within a single file, use `git add -p`
to stage individual hunks.

#### Reordering Commits

Simply change the order of `pick` lines in the rebase todo.  Watch
for conflicts — if commit B depends on commit A, A must come first.

### Phase 4: Verify

After the rebase completes, verify the result:

```bash
# Confirm the series looks correct
git log --oneline --reverse <base>..HEAD

# Confirm total diff is unchanged (CRITICAL)
# Compare the diffstat before and after
git diff --stat <base>..HEAD

# If you saved the pre-rebase diff:
git diff <base>..HEAD > /tmp/after.diff
diff /tmp/before.diff /tmp/after.diff
```

The total diff from base to HEAD **must be identical** before and
after the rebase.  If it differs, something was lost or duplicated.

### Phase 5: Resolve Conflicts

If conflicts arise during rebase:

```bash
# See what conflicted
git status

# After resolving conflicts in the files
git add <resolved-files>
git rebase --continue
```

If the rebase becomes too tangled:

```bash
git rebase --abort
```

Then try a different strategy (different ordering, smaller steps).

## Commit Message Conventions

Follow the project's commit style when rewriting messages:

- **Headline:** Present tense, imperative mood, under 50 characters
  (hard limit 72)
- **Body:** Focus on "why" and "how", not "what".  Wrap at 72
  characters.  Use Markdown formatting if helpful.
- **Trailers:** Use Git trailers for metadata (`Co-authored-by:`,
  `Closes:`, `Refs:`, `See-also:`).

When amending a commit after folding in a fix, **reword the message
as if the fix was always part of the original commit**.  Do not
mention that it was folded in or reference the old fixup commit.

## Safety Rules

- **NEVER** force-push to `main` or `master`.
- **ALWAYS** confirm the plan with the user before executing.
- **ALWAYS** verify the total diff is unchanged after rebase.
- **PREFER** `GIT_SEQUENCE_EDITOR` for scripted rebases to avoid
  interactive editor issues in automation.
- If the rebase goes wrong, `git rebase --abort` and reassess.
- When in doubt about conflict resolution, ask the user.

## Common Scenarios

### Scenario: Last Commit Should Be Part of Earlier Ones

The most common case.  A late commit fixes or extends work from
multiple earlier commits.

1. Identify which hunks in the late commit belong to which earlier
   commit.
2. Use `git show <late-sha> -- <file>` to extract per-file patches.
3. Split the late commit's changes and fold each piece into the
   appropriate earlier commit.
4. This may require multiple rebase passes, or a single pass with
   careful patch application at each `edit` stop.

### Scenario: Jumbled History from Iterative Development

Multiple commits that zigzag between concerns.

1. List all commits and categorize by concern.
2. Plan a series grouped by concern, ordered by dependency.
3. Execute rebase with aggressive reordering, squashing related
   commits within each group.
4. Reword messages to describe the final combined change.

### Scenario: Incorporating PR Review Feedback

Review feedback arrives as new fixup commits on top of the series.

1. Map each fixup to the original commit it addresses.
2. Use `fixup` or `edit` + amend to fold each fix into its target.
3. Reword original messages if the fix changes the commit's scope.
4. Verify the series, push with `--force-with-lease`.
