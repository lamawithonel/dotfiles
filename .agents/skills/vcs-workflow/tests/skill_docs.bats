#!/usr/bin/env bats
# Contract for the three routing documents this lane owns: SKILL.md,
# references/git-only.md, and references/repo-shapes.md.  Every claim
# checked here is one an agent routes on, so a stale sentence is a
# routing defect, not a typo.

load test_helper

SKILL="$SKILL_DIR/SKILL.md"
REFS="$SKILL_DIR/references"

FORBIDDEN='difftastic|ast-grep|ast_grep|Serena|Verified-against|bootstrap|gh_recover|git_only_hunks'

# flat FILE -- the file as one line, so an assertion is not hostage to
# where a sentence happens to wrap.
flat() {
	tr '\n' ' ' < "$1" | tr -s ' '
}

@test "sweep: no retired tooling in the three routing documents" {
	local f hits
	for f in "$SKILL" "$REFS/git-only.md" "$REFS/repo-shapes.md"; do
		hits="$(grep -n -i -E "$FORBIDDEN" "$f" || true)"
		[ -z "$hits" ] || {
			echo "$f still carries: $hits" >&2
			return 1
		}
	done
}

@test "SKILL.md: frontmatter keeps the name and drops the version pins" {
	run grep -q '^name: vcs-workflow$' "$SKILL"
	[ "$status" -eq 0 ]
	run grep -q 'vcs-handoff/2' "$SKILL"
	[ "$status" -eq 0 ]
	run grep -ciE 'jj 0\.|git 2\.5|pins live there' "$SKILL"
	[ "$output" = '0' ]
}

@test "SKILL.md: body is under 500 lines" {
	local body
	body="$(awk 'NR > 1 && /^---$/ { seen = 1; next } seen' "$SKILL" | wc -l)"
	[ "$body" -lt 500 ]
}

@test "SKILL.md: the opening states the four load-bearing facts" {
	run grep -q 'private operations log' "$SKILL"
	[ "$status" -eq 0 ]
	run grep -q 'never by staging' "$SKILL"
	[ "$status" -eq 0 ]
	run grep -q 'erases the git index' "$SKILL"
	[ "$status" -eq 0 ]
	run grep -q 'no index' "$SKILL"
	[ "$status" -eq 1 ]
}

@test "SKILL.md: the entry gate table carries every shape and onboarding" {
	local s
	for s in colocated jj-only jj-workspace git-only worktree-shadowed none; do
		run grep -qE "^\| .*\`$s\`" "$SKILL"
		[ "$status" -eq 0 ] || {
			echo "entry gate has no row for $s" >&2
			return 1
		}
	done
	run grep -qE '^\| .*`git-only`.*onboard\.sh status' "$SKILL"
	[ "$status" -eq 0 ]
}

@test "SKILL.md: onboarding names both questions, the keys, and the pending case" {
	run grep -q '## Onboarding' "$SKILL"
	[ "$status" -eq 0 ]
	run grep -q 'ONBOARD-PENDING' "$SKILL"
	[ "$status" -eq 0 ]
	run grep -q 'vcs-workflow.onboarding' "$SKILL"
	[ "$status" -eq 0 ]
	run grep -q 'vcs-workflow.decided' "$SKILL"
	[ "$status" -eq 0 ]
	run grep -q 'onboard.sh reset' "$SKILL"
	[ "$status" -eq 0 ]
	run grep -q 'references/onboarding.md' "$SKILL"
	[ "$status" -eq 0 ]
	# What apply does beyond the three keys: the local ignore patterns,
	# and the one shape that can only be full.
	run grep -q '.git/info/exclude' "$SKILL"
	[ "$status" -eq 0 ]
	flat "$SKILL" | grep -q 'never .\.gitignore.'
	flat "$SKILL" | grep -q 'jj-only repo is always level .full.'
}

@test "SKILL.md: the pipeline table has a level column and the block receipt" {
	run grep -qE '^\| Step \| Command \| Level \| Undo \|' "$SKILL"
	[ "$status" -eq 0 ]
	run grep -q 'LEVEL-BLOCKED' "$SKILL"
	[ "$status" -eq 0 ]
	run grep -q 'exit 6' "$SKILL"
	[ "$status" -eq 0 ]
}

@test "SKILL.md: the pipeline table marks Handoff standard, full" {
	run grep -qE '^\| Handoff \|.*\| standard, full \|' "$SKILL"
	[ "$status" -eq 0 ] || {
		grep -E '^\| Handoff \|' "$SKILL" >&2
		return 1
	}
	# emit_handoff.sh is one of the scripts the oplog paragraph names,
	# because it now refuses there too.
	flat "$SKILL" | grep -q 'and .emit_handoff.sh. refuse with'
	run grep -q 'LEVEL-BLOCKED' "$SCRIPTS/emit_handoff.sh"
	[ "$status" -eq 0 ]
}

@test "SKILL.md: preflight documents the per-level keys and the identity gate" {
	run grep -q 'PREFLIGHT-FAIL identity' "$SKILL"
	[ "$status" -eq 0 ]
	run grep -q 'snapshot.auto-track' "$SKILL"
	[ "$status" -eq 0 ]
	run grep -ciE 'four `--repo` keys|exactly four' "$SKILL"
	[ "$output" = '0' ]
}

@test "SKILL.md: the isolation section is at most 25 lines" {
	local n
	n="$(awk '/^## Isolation$/ { c = 1; next } /^## / { c = 0 } c' "$SKILL" | wc -l)"
	[ "$n" -gt 0 ]
	[ "$n" -le 25 ]
	run grep -q 'references/isolation.md' "$SKILL"
	[ "$status" -eq 0 ]
}

@test "SKILL.md: git-only is a two-line pointer, not a mode section" {
	local n
	run grep -q '^## git-only mode$' "$SKILL"
	[ "$status" -eq 1 ]
	n="$(awk '/^## Git-only fallback$/ { c = 1; next } /^## / { c = 0 } c' "$SKILL" \
		| grep -c .)"
	[ "$n" -le 6 ]
	run grep -q 'references/git-only.md' "$SKILL"
	[ "$status" -eq 0 ]
}

@test "SKILL.md: toolchain is two lines of feature claims" {
	local n
	n="$(awk '/^## Toolchain$/ { c = 1; next } /^## / { c = 0 } c' "$SKILL" \
		| grep -c .)"
	[ "$n" -ge 1 ]
	[ "$n" -le 5 ]
	run grep -q 'feature claims' "$SKILL"
	[ "$status" -eq 0 ]
}

@test "SKILL.md: forbidden vocabulary loses the mise clause and gains the worktree" {
	run grep -ciE 'mise security toggle|MISE_AQUA' "$SKILL"
	[ "$output" = '0' ]
	run grep -q 'git worktree add' "$SKILL"
	[ "$status" -eq 0 ]
	run grep -q 'mise or cargo' "$SKILL"
	[ "$status" -eq 0 ]
}

@test "SKILL.md: handoff names schema 2 and the consumer split" {
	run grep -q '`git-commit` does not' "$SKILL"
	[ "$status" -eq 0 ]
	run grep -ciE 'vcs-handoff/1|consumed at commit time' "$SKILL"
	[ "$output" = '0' ]
}

@test "SKILL.md: every script path is absolute" {
	local hits
	hits="$(grep -n 'scripts/' "$SKILL" \
		| grep -v '/home/lucas/.agents/skills/vcs-workflow/scripts/' || true)"
	[ -z "$hits" ] || {
		echo "relative script paths: $hits" >&2
		return 1
	}
}

@test "SKILL.md: worktree isolation is replaced by jj workspaces everywhere" {
	run grep -ci 'never pair' "$SKILL"
	[ "$output" = '0' ]
	run grep -q 'isolate with jj workspaces' "$SKILL"
	[ "$status" -eq 0 ]
}

@test "git-only.md: the fallback note is short and names all three causes" {
	local n
	n="$(wc -l < "$REFS/git-only.md")"
	[ "$n" -le 55 ]
	run grep -q 'linked' "$REFS/git-only.md"
	[ "$status" -eq 0 ]
	run grep -qi 'declined' "$REFS/git-only.md"
	[ "$status" -eq 0 ]
	run grep -qi 'jj is absent' "$REFS/git-only.md"
	[ "$status" -eq 0 ]
}

@test "git-only.md: the surviving mechanics are the ones that still exist" {
	run grep -q 'git_diff_safe.sh' "$REFS/git-only.md"
	[ "$status" -eq 0 ]
	run grep -q -- '--force-with-lease' "$REFS/git-only.md"
	[ "$status" -eq 0 ]
	run grep -q 'jj workspace' "$REFS/git-only.md"
	[ "$status" -eq 0 ]
	run grep -q 'no hunk kit' "$REFS/git-only.md"
	[ "$status" -eq 0 ]
	run grep -ciE 'add -p|autosquash|unidiff-zero|hunk-[0-9N]' "$REFS/git-only.md"
	[ "$output" = '0' ]
}

@test "repo-shapes.md: the git-only row routes into onboarding" {
	run grep -qE '^\| `git-only`.*onboarding' "$REFS/repo-shapes.md"
	[ "$status" -eq 0 ]
	run grep -qE '^\| `git-only`.*[Rr]educed mode' "$REFS/repo-shapes.md"
	[ "$status" -eq 1 ]
}

@test "repo-shapes.md: the jj-workspace row states what a workspace lacks" {
	run grep -qE '^\| `jj-workspace`.*no `\.git`' "$REFS/repo-shapes.md"
	[ "$status" -eq 0 ]
	run grep -qE '^\| `jj-workspace`.*gh -R' "$REFS/repo-shapes.md"
	[ "$status" -eq 0 ]
	run grep -qE '^\| `jj-workspace`.*jj git push' "$REFS/repo-shapes.md"
	[ "$status" -eq 0 ]
	# A workspace has no git config of its own, so the level is not
	# readable here -- every reader resolves it at the primary root.
	run grep -qE '^\| `jj-workspace`.*level is read at the primary root' \
		"$REFS/repo-shapes.md"
	[ "$status" -eq 0 ]
}

@test "repo-shapes.md: nested-vs-sibling names the hooks and the on-ramp refusal" {
	run grep -q 'WorktreeCreate' "$REFS/repo-shapes.md"
	[ "$status" -eq 0 ]
	run grep -q 'isolation: "worktree"' "$REFS/repo-shapes.md"
	[ "$status" -eq 0 ]
	run grep -q 'background sessions' "$REFS/repo-shapes.md"
	[ "$status" -eq 0 ]
	run grep -q 'refuses inside' "$REFS/repo-shapes.md"
	[ "$status" -eq 0 ]
	run grep -ci 'never pair' "$REFS/repo-shapes.md"
	[ "$output" = '0' ]
	run grep -c 'isolate with jj workspaces' "$REFS/repo-shapes.md"
	[ "$output" -ge 2 ]
}

@test "repo-shapes.md: the lazy-export section survives intact" {
	run grep -q '## The colocated lazy-export mechanic' "$REFS/repo-shapes.md"
	[ "$status" -eq 0 ]
	run grep -q 'e69de29b' "$REFS/repo-shapes.md"
	[ "$status" -eq 0 ]
}
