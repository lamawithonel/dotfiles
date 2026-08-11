#!/usr/bin/awk -f
# git_only_hunks.awk -- split a `git diff -U0` stream into
# independently-applicable per-hunk patch files, for TTY-free
# sub-file staging in git-only shapes (git's only hunk-grain
# primitive, `git add -p`, is interactive-only).
#
# Usage:
#   scripts/git_diff_safe.sh diff -U0 |
#     awk -v dir="$OUT_DIR" -f scripts/git_only_hunks.awk
# Then apply a chosen hunk:
#   git apply --cached --unidiff-zero "$OUT_DIR/hunk-001.patch"
#
# Prints the hunk count on stdout.  Binary-file diffs carry no @@
# hunks and are skipped; a warning per skipped file goes to stderr.
# Known trap (documented in references/traps.md): `git apply
# --unidiff-zero` relocates by fuzzy match and can mis-place a hunk in
# files with duplicated surrounding lines -- verify with `git diff
# --cached` after each apply.

/^diff --git / {
	hdr = $0 "\n"
	inhdr = 1
	filehunks = 0
	file = $0
	next
}
inhdr && /^Binary files / {
	printf "git_only_hunks: skipped binary diff: %s\n", file | "cat >&2"
	inhdr = 0
	next
}
inhdr && !/^@@/ {
	hdr = hdr $0 "\n"
	next
}
/^@@/ {
	inhdr = 0
	if (out) close(out)
	out = sprintf("%s/hunk-%03d.patch", dir, ++n)
	filehunks++
	printf "%s", hdr > out
	print $0 > out
	next
}
{
	if (out) print $0 > out
}
END {
	if (out) close(out)
	printf "%d\n", n
}
