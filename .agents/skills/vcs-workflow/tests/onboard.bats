#!/usr/bin/env bats
# Behaviour of scripts/onboard.sh: the recorded decision, the level
# application, and one case per precheck.  onboard.sh is new, so it is
# invoked as `sh "$SCRIPTS/onboard.sh"` until the executable bit lands.

load test_helper

ONBOARD() {
	env -C "$1" sh "$SCRIPTS/onboard.sh" "${@:2}"
}

# set_identity NAME EMAIL -- rewrite the private jj user config.
set_identity() {
	printf '[user]\nname = "%s"\nemail = "%s"\n\n[ui]\npaginate = "never"\n' \
		"$1" "$2" > "$JJ_CONFIG"
}

# stub_preflight -- a copy of scripts/ whose preflight.sh always fails,
# so the post-init failure path can be exercised without a jj state
# that only fails by accident.
stub_preflight() {
	local s="$BATS_TEST_TMPDIR/stubbed"
	cp -r "$SCRIPTS" "$s"
	printf '#!/bin/sh\nprintf "PREFLIGHT-FAIL stub\\n"\nexit 1\n' > "$s/preflight.sh"
	chmod +x "$s/preflight.sh"
	printf '%s' "$s"
}

# stub_jj_race -- a PATH whose `jj` creates the store on `jj git init`
# and then reports failure, exactly as a concurrent apply leaves it.
stub_jj_race() {
	local bin="$BATS_TEST_TMPDIR/racebin" real
	real="$(command -v jj)"
	mkdir -p "$bin"
	cat > "$bin/jj" <<-EOF
		#!/bin/sh
		if [ "\$1" = git ] && [ "\$2" = init ]; then
			shift 2
			"$real" git init "\$@" > /dev/null 2>&1
			exit 1
		fi
		exec "$real" "\$@"
	EOF
	chmod +x "$bin/jj"
	printf '%s' "$bin"
}

# --- status -----------------------------------------------------------

@test "onboard status: a git-only repo with no keys is undecided" {
	local d
	d="$(fx_git_only r)"
	run ONBOARD "$d" status
	[ "$status" -eq 0 ]
	[ "$output" = "ONBOARD-STATUS shape=git-only onboarding=undecided level=-" ]
}

@test "onboard status: a colocated repo reports its recorded keys" {
	local d
	d="$(fx_colocated r)"
	env -C "$d" git config --local vcs-workflow.onboarding converted
	env -C "$d" git config --local vcs-workflow.level standard
	run ONBOARD "$d" status
	[ "$status" -eq 0 ]
	[ "$output" = "ONBOARD-STATUS shape=colocated onboarding=converted level=standard" ]
}

@test "onboard status: a recorded decline is reported" {
	local d
	d="$(fx_git_only r)"
	env -C "$d" git config --local vcs-workflow.onboarding declined
	run ONBOARD "$d" status
	[ "$status" -eq 0 ]
	[ "$output" = "ONBOARD-STATUS shape=git-only onboarding=declined level=-" ]
}

@test "onboard status: a jj-only shape has no git config and reads converted/full" {
	local d
	d="$(fx_jj_only r)"
	run ONBOARD "$d" status
	[ "$status" -eq 0 ]
	[ "$output" = "ONBOARD-STATUS shape=jj-only onboarding=converted level=full" ]
}

@test "onboard status: a jj workspace reads converted/full" {
	local w
	w="$(fx_jj_workspace r)"
	run ONBOARD "$w" status
	[ "$status" -eq 0 ]
	[ "$output" = "ONBOARD-STATUS shape=jj-workspace onboarding=converted level=full" ]
}

@test "onboard status: a workspace reports the primary's recorded decision" {
	local w p
	w="$(fx_jj_workspace r)"
	p="$BATS_TEST_TMPDIR/r"
	env -C "$p" git config --local vcs-workflow.onboarding converted
	env -C "$p" git config --local vcs-workflow.level oplog
	run ONBOARD "$w" status
	[ "$status" -eq 0 ]
	[ "$output" = "ONBOARD-STATUS shape=jj-workspace onboarding=converted level=oplog" ]
}

@test "onboard status: a keyless colocated repo reads the level preflight uses" {
	local d
	d="$(fx_colocated r)"
	run ONBOARD "$d" status
	[ "$status" -eq 0 ]
	[ "$output" = "ONBOARD-STATUS shape=colocated onboarding=undecided level=full" ]
	run env -C "$d" sh "$SCRIPTS/preflight.sh"
	[ "$status" -eq 0 ]
	[[ "$output" == *"level=full"* ]]
}

@test "onboard status: a level key set outside --local is still read" {
	local d
	d="$(fx_colocated r)"
	env -C "$d" git config --local vcs-workflow.onboarding converted
	git config --file "$GIT_CONFIG_GLOBAL" vcs-workflow.level oplog
	run ONBOARD "$d" status
	[ "$output" = "ONBOARD-STATUS shape=colocated onboarding=converted level=oplog" ]
}

@test "onboard status: no repository at all is undecided, exit 0" {
	mkdir -p "$BATS_TEST_TMPDIR/bare"
	run ONBOARD "$BATS_TEST_TMPDIR/bare" status
	[ "$status" -eq 0 ]
	[ "$output" = "ONBOARD-STATUS shape=none onboarding=undecided level=-" ]
}

@test "onboard status: worktree-shadowed reports the shape and exits 0" {
	local w
	w="$(fx_shadowed r)"
	run ONBOARD "$w" status
	[ "$status" -eq 0 ]
	[[ "$output" == "ONBOARD-STATUS shape=worktree-shadowed "* ]]
}

# --- record and reset -------------------------------------------------

@test "onboard record: --decline writes onboarding and decided, no level" {
	local d
	d="$(fx_git_only r)"
	run ONBOARD "$d" record --decline
	[ "$status" -eq 0 ]
	[ "$output" = "ONBOARD-OK onboarding=declined level=-" ]
	[ "$(env -C "$d" git config --local --get vcs-workflow.onboarding)" = declined ]
	[ "$(env -C "$d" git config --local --get vcs-workflow.decided)" = "$(date -u +%Y-%m-%d)" ]
	run env -C "$d" git config --local --get vcs-workflow.level
	[ "$status" -ne 0 ]
}

@test "onboard record: --level writes converted and the level" {
	local d
	d="$(fx_git_only r)"
	run ONBOARD "$d" record --level oplog
	[ "$status" -eq 0 ]
	[ "$output" = "ONBOARD-OK onboarding=converted level=oplog" ]
	[ "$(env -C "$d" git config --local --get vcs-workflow.onboarding)" = converted ]
	[ "$(env -C "$d" git config --local --get vcs-workflow.level)" = oplog ]
}

@test "onboard record: jj-only refuses a level it cannot store" {
	local d
	d="$(fx_jj_only r)"
	run --separate-stderr ONBOARD "$d" record --level standard
	[ "$status" -eq 1 ]
	[ "$output" = "ONBOARD-REFUSE reason=no-git-config level=standard" ]
	run --separate-stderr ONBOARD "$d" record --level full
	[ "$status" -eq 0 ]
	[ "$output" = "ONBOARD-OK onboarding=converted level=full" ]
}

@test "onboard record: jj-only refuses a decline it cannot store" {
	local d
	d="$(fx_jj_only r)"
	run --separate-stderr ONBOARD "$d" record --decline
	[ "$status" -eq 1 ]
	[ "$output" = "ONBOARD-REFUSE reason=no-git-config level=-" ]
}

@test "onboard record: no repository at all refuses, exit 2" {
	mkdir -p "$BATS_TEST_TMPDIR/bare"
	run --separate-stderr ONBOARD "$BATS_TEST_TMPDIR/bare" record --level full
	[ "$status" -eq 2 ]
	[[ "$output" == ONBOARD-REFUSE*shape=none* ]]
}

@test "onboard record then reset: the section round trips away" {
	local d
	d="$(fx_git_only r)"
	ONBOARD "$d" record --decline > /dev/null
	run ONBOARD "$d" reset
	[ "$status" -eq 0 ]
	[ "$output" = "ONBOARD-OK reset" ]
	run ONBOARD "$d" status
	[ "$output" = "ONBOARD-STATUS shape=git-only onboarding=undecided level=-" ]
}

@test "onboard reset: a repo with no section still exits 0" {
	local d
	d="$(fx_git_only r)"
	run ONBOARD "$d" reset
	[ "$status" -eq 0 ]
}

@test "onboard: no subcommand is a usage error, exit 2" {
	local d
	d="$(fx_git_only r)"
	run --separate-stderr ONBOARD "$d"
	[ "$status" -eq 2 ]
}

@test "onboard: an unknown subcommand is a usage error, exit 2" {
	local d
	d="$(fx_git_only r)"
	run --separate-stderr ONBOARD "$d" convert
	[ "$status" -eq 2 ]
}

@test "onboard record: neither --decline nor --level is a usage error" {
	local d
	d="$(fx_git_only r)"
	run --separate-stderr ONBOARD "$d" record
	[ "$status" -eq 2 ]
}

@test "onboard apply: a missing --level is a usage error" {
	local d
	d="$(fx_git_only r)"
	run --separate-stderr ONBOARD "$d" apply
	[ "$status" -eq 2 ]
}

@test "onboard apply: an unknown level is a usage error" {
	local d
	d="$(fx_git_only r)"
	run --separate-stderr ONBOARD "$d" apply --level paranoid
	[ "$status" -eq 2 ]
}

# --- apply ------------------------------------------------------------

@test "onboard apply: level full creates the store, three keys, converted" {
	local d
	d="$(fx_git_only_file r)"
	run --separate-stderr ONBOARD "$d" apply --level full
	[ "$status" -eq 0 ]
	[ -d "$d/.jj" ]
	[[ "${lines[0]}" == "PREFLIGHT-OK shape=colocated level=full store="* ]]
	# The store id is the one preflight reported, quoted back verbatim.
	[[ "${lines[1]}" == "ONBOARD-OK level=full shape=colocated store="*" protected=[main] warns=[exclude-added]" ]]
	local from_preflight="${lines[0]#*store=}" from_onboard="${lines[1]#*store=}"
	[ "${from_preflight%% *}" = "${from_onboard%% *}" ]
	[ -n "${from_onboard%% *}" ]
	[ "$(env -C "$d" git config --local --get vcs-workflow.onboarding)" = converted ]
	[ "$(env -C "$d" git config --local --get vcs-workflow.level)" = full ]
	[ "$(env -C "$d" git config --local --get vcs-workflow.decided)" = "$(date -u +%Y-%m-%d)" ]
	run env -C "$d" jj config list --repo
	[ "${#lines[@]}" -eq 3 ]
}

@test "onboard apply: level oplog writes exactly the three safety keys" {
	local d
	d="$(fx_git_only_file r)"
	run --separate-stderr ONBOARD "$d" apply --level oplog
	[ "$status" -eq 0 ]
	[ "$(env -C "$d" git config --local --get vcs-workflow.level)" = oplog ]
	run env -C "$d" jj config list --repo
	[ "${#lines[@]}" -eq 3 ]
	[[ "$output" != *snapshot.auto-track* ]]
}

@test "onboard apply: level standard adds snapshot.auto-track" {
	local d
	d="$(fx_git_only_file r)"
	run --separate-stderr ONBOARD "$d" apply --level standard
	[ "$status" -eq 0 ]
	run env -C "$d" jj config list --repo
	[ "${#lines[@]}" -eq 4 ]
	[[ "$output" == *'snapshot.auto-track = "none"'* ]]
}

@test "onboard apply: git status stays clean and the store is self-ignored" {
	local d
	d="$(fx_git_only_file r)"
	ONBOARD "$d" apply --level full > /dev/null 2>&1
	run env -C "$d" git status --porcelain
	[ -z "$output" ]
}

@test "onboard apply: re-applying the same level is a no-op" {
	local d first second
	d="$(fx_git_only_file r)"
	# The first apply converges the local ignore file and says so, so
	# the steady state is the second receipt onwards.
	ONBOARD "$d" apply --level full > /dev/null 2>&1
	first="$(ONBOARD "$d" apply --level full 2> /dev/null)"
	second="$(ONBOARD "$d" apply --level full 2> /dev/null)"
	[ "$first" = "$second" ]
	run env -C "$d" jj config list --repo
	[ "${#lines[@]}" -eq 3 ]
}

@test "onboard apply: a level change rewrites the --repo keys only" {
	local d before after
	d="$(fx_git_only_file r)"
	ONBOARD "$d" apply --level full > /dev/null 2>&1
	before="$(env -C "$d" jj log --no-graph -r @ -T 'change_id.short()')"
	run --separate-stderr ONBOARD "$d" apply --level standard
	[ "$status" -eq 0 ]
	[ "$(env -C "$d" git config --local --get vcs-workflow.level)" = standard ]
	after="$(env -C "$d" jj log --no-graph -r @ -T 'change_id.short()')"
	[ "$before" = "$after" ]
	run env -C "$d" jj config list --repo
	[ "${#lines[@]}" -eq 4 ]
}

@test "onboard apply: an already-colocated repo skips init and still records" {
	local d
	d="$(fx_colocated r)"
	run --separate-stderr ONBOARD "$d" apply --level full
	[ "$status" -eq 0 ]
	[[ "${lines[1]}" == "ONBOARD-OK level=full shape=colocated "* ]]
	[ "$(env -C "$d" git config --local --get vcs-workflow.onboarding)" = converted ]
}

@test "onboard apply: --dry-run reports and creates nothing" {
	local d
	d="$(fx_git_only_file r)"
	run --separate-stderr ONBOARD "$d" apply --level full --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == "ONBOARD-DRY-RUN level=full shape=git-only init=yes warns=[]" ]]
	[ ! -d "$d/.jj" ]
	run env -C "$d" git config --local --get vcs-workflow.onboarding
	[ "$status" -ne 0 ]
}

@test "onboard apply: a subdirectory of an ordinary repo converts the root" {
	local d
	d="$(fx_git_only_file r)"
	mkdir -p "$d/sub"
	run --separate-stderr ONBOARD "$d/sub" apply --level full
	[ "$status" -eq 0 ]
	[[ "${lines[1]}" == "ONBOARD-OK level=full shape=colocated "* ]]
	[ -d "$d/.jj" ]
	[ ! -d "$d/sub/.jj" ]
}

@test "onboard apply: a symlinked root still sees a nested worktree" {
	local w link
	w="$(fx_shadowed r)"
	link="$BATS_TEST_TMPDIR/r-link"
	ln -s "$BATS_TEST_TMPDIR/r" "$link"
	run --separate-stderr ONBOARD "$link" apply --level full
	[ "$status" -eq 1 ]
	[ "$output" = "ONBOARD-REFUSE reason=nested-worktrees" ]
	[[ "$stderr" == *"$w"* ]]
}

@test "onboard apply: jj-only refuses any level but full" {
	local d
	d="$(fx_jj_only r)"
	run --separate-stderr ONBOARD "$d" apply --level standard
	[ "$status" -eq 1 ]
	[ "$output" = "ONBOARD-REFUSE reason=no-git-config level=standard" ]
}

@test "onboard apply: jj-only accepts level full" {
	local d
	d="$(fx_jj_only r)"
	run --separate-stderr env -C "$d" PREFLIGHT_PROTECTED_BOOKMARKS=main \
		sh "$SCRIPTS/onboard.sh" apply --level full
	[ "$status" -eq 0 ]
	[[ "${lines[1]}" == "ONBOARD-OK level=full shape=jj-only "* ]]
}

@test "onboard apply: a failing preflight names whether the store was created" {
	local d s
	d="$(fx_git_only_file r)"
	s="$(stub_preflight)"
	run --separate-stderr env -C "$d" sh "$s/onboard.sh" apply --level full
	[ "$status" -eq 1 ]
	[ "${lines[0]}" = "PREFLIGHT-FAIL stub" ]
	[ "${lines[1]}" = "ONBOARD-REFUSE reason=preflight store-created=yes" ]
	run env -C "$d" git config --local --get vcs-workflow.onboarding
	[ "$status" -ne 0 ]
}

@test "onboard apply: a failing preflight on an existing store says store-created=no" {
	local d s
	d="$(fx_colocated r)"
	s="$(stub_preflight)"
	run --separate-stderr env -C "$d" sh "$s/onboard.sh" apply --level full
	[ "$status" -eq 1 ]
	[ "${lines[1]}" = "ONBOARD-REFUSE reason=preflight store-created=no" ]
}

@test "onboard apply: a store created by a concurrent apply is adopted" {
	local d bin
	d="$(fx_git_only_file r)"
	bin="$(stub_jj_race)"
	run --separate-stderr env -C "$d" PATH="$bin:$PATH" \
		sh "$SCRIPTS/onboard.sh" apply --level full
	[ "$status" -eq 0 ]
	[[ "${lines[1]}" == "ONBOARD-OK level=full shape=colocated "* ]]
	[ -d "$d/.jj" ]
}

# --- the local ignore file --------------------------------------------

@test "onboard apply: level full excludes .local and .cache locally" {
	local d
	d="$(fx_git_only_file r)"
	run --separate-stderr ONBOARD "$d" apply --level full
	[ "$status" -eq 0 ]
	[[ "${lines[1]}" == *"warns=[exclude-added]" ]]
	[ "$(grep -c -x -e '.local/' -e '.cache/' "$d/.git/info/exclude")" -eq 2 ]
	[ ! -e "$d/.gitignore" ]
	run env -C "$d" git status --porcelain
	[ -z "$output" ]
}

@test "onboard apply: a repo that already ignores them is left alone" {
	local d
	d="$(fx_git_only_file r)"
	printf '.local/\n.cache/\n' > "$d/.gitignore"
	env -C "$d" git add .gitignore
	env -C "$d" git commit -q -m ignore
	run --separate-stderr ONBOARD "$d" apply --level full
	[ "$status" -eq 0 ]
	[[ "${lines[1]}" == *"warns=[]" ]]
	run grep -q -x -e '.local/' -e '.cache/' "$d/.git/info/exclude"
	[ "$status" -ne 0 ]
}

@test "onboard apply: an unwritable ignore file names the store it created" {
	local d
	d="$(fx_git_only_file r)"
	chmod a-w "$d/.git/info/exclude" "$d/.git/info"
	run --separate-stderr ONBOARD "$d" apply --level full
	chmod u+w "$d/.git/info" "$d/.git/info/exclude"
	[ "$status" -eq 1 ]
	[ "$output" = "ONBOARD-REFUSE reason=exclude-write store-created=yes" ]
}

@test "onboard apply: level oplog writes nothing into the ignore file" {
	local d
	d="$(fx_git_only_file r)"
	run --separate-stderr ONBOARD "$d" apply --level oplog
	[ "$status" -eq 0 ]
	[[ "${lines[1]}" == *"warns=[]" ]]
	run grep -q -x -e '.local/' -e '.cache/' "$d/.git/info/exclude"
	[ "$status" -ne 0 ]
}

# --- prechecks 1-11 ---------------------------------------------------

@test "onboard precheck 1: jj absent skips, exit 0" {
	local d nobin
	d="$(fx_git_only_file r)"
	nobin="$(path_without jj)"
	run --separate-stderr env -C "$d" PATH="$nobin" sh "$SCRIPTS/onboard.sh" apply --level full
	[ "$status" -eq 0 ]
	[ "$output" = "ONBOARD-SKIP reason=jj-absent" ]
	[ ! -d "$d/.jj" ]
}

@test "onboard precheck 2: no repository exits 2" {
	mkdir -p "$BATS_TEST_TMPDIR/bare"
	run --separate-stderr ONBOARD "$BATS_TEST_TMPDIR/bare" apply --level full
	[ "$status" -eq 2 ]
	[[ "$output" == ONBOARD-REFUSE*shape=none* ]]
}

@test "onboard precheck 2: worktree-shadowed exits 3" {
	local w
	w="$(fx_shadowed r)"
	run --separate-stderr ONBOARD "$w" apply --level full
	[ "$status" -eq 3 ]
	[[ "$output" == ONBOARD-REFUSE*worktree-shadowed* ]]
}

@test "onboard precheck 3: a linked git worktree skips with the main path" {
	local w main
	w="$(fx_linked_worktree r)"
	main="$BATS_TEST_TMPDIR/r"
	run --separate-stderr ONBOARD "$w" apply --level full
	[ "$status" -eq 0 ]
	[ "$output" = "ONBOARD-SKIP reason=linked-worktree main=$main" ]
}

@test "onboard precheck 4: an existing non-colocated store refuses" {
	local d
	d="$(fx_noncolocated_jj r)"
	run --separate-stderr ONBOARD "$d" apply --level full
	[ "$status" -eq 1 ]
	[ "$output" = "ONBOARD-REFUSE reason=non-colocated-store" ]
	[[ "$stderr" == *'jj git colocation enable'* ]]
	# The script names the command; it never runs it.
	run env -C "$d" jj git colocation status
	[[ "$output" == *"not colocated"* ]]
}

@test "onboard precheck 4: a set JJ_EDITOR refuses before any store" {
	local d
	d="$(fx_git_only_file r)"
	run --separate-stderr env -C "$d" JJ_EDITOR=vim \
		sh "$SCRIPTS/onboard.sh" apply --level full
	[ "$status" -eq 1 ]
	[ "$output" = "ONBOARD-REFUSE reason=jj-editor" ]
	[ ! -d "$d/.jj" ]
}

@test "onboard precheck 4: JJ_EDITOR=:true is the guard's own value and passes" {
	local d
	d="$(fx_git_only_file r)"
	run --separate-stderr env -C "$d" JJ_EDITOR=:true \
		sh "$SCRIPTS/onboard.sh" apply --level full
	[ "$status" -eq 0 ]
}

@test "onboard precheck 5: an in-progress git operation refuses" {
	local d
	d="$(fx_git_only_file r)"
	: > "$d/.git/MERGE_HEAD"
	run --separate-stderr ONBOARD "$d" apply --level full
	[ "$status" -eq 1 ]
	[ "$output" = "ONBOARD-REFUSE reason=git-in-progress" ]
	[ ! -d "$d/.jj" ]
}

@test "onboard precheck 5: a non-empty index refuses" {
	local d
	d="$(fx_git_only_file r)"
	printf 'two\n' > "$d/b.txt"
	env -C "$d" git add b.txt
	run --separate-stderr ONBOARD "$d" apply --level full
	[ "$status" -eq 1 ]
	[ "$output" = "ONBOARD-REFUSE reason=index-not-empty" ]
}

@test "onboard precheck 5: ONBOARD_ALLOW_INDEX=1 warns index-flattened" {
	local d
	d="$(fx_git_only_file r)"
	printf 'two\n' > "$d/b.txt"
	env -C "$d" git add b.txt
	run --separate-stderr env -C "$d" ONBOARD_ALLOW_INDEX=1 \
		sh "$SCRIPTS/onboard.sh" apply --level full
	[ "$status" -eq 0 ]
	[[ "${lines[1]}" == *"warns=[index-flattened exclude-added]" ]]
}

@test "onboard precheck 6: a placeholder identity refuses before any store" {
	local d
	d="$(fx_git_only_file r)"
	set_identity 'VCS Research' 'vcs-research@example.invalid'
	run --separate-stderr ONBOARD "$d" apply --level full
	[ "$status" -eq 1 ]
	[ "$output" = "ONBOARD-REFUSE reason=identity" ]
	[ ! -d "$d/.jj" ]
}

@test "onboard precheck 6: placeholder addresses refuse whatever their case or form" {
	local d addr
	d="$(fx_git_only_file r)"
	for addr in 'A@EXAMPLE.COM' 'a@test.INVALID' 'a@example' 'a@sub.example.com'; do
		set_identity 'Bats Tester' "$addr"
		run --separate-stderr ONBOARD "$d" apply --level full
		if [ "$status" -ne 1 ] || [ "$output" != "ONBOARD-REFUSE reason=identity" ]; then
			echo "accepted placeholder $addr: $output" >&2
			return 1
		fi
	done
	[ ! -d "$d/.jj" ]
}

@test "onboard precheck 6: an empty user.email refuses" {
	local d
	d="$(fx_git_only_file r)"
	set_identity 'Bats Tester' ''
	run --separate-stderr ONBOARD "$d" apply --level full
	[ "$status" -eq 1 ]
	[ "$output" = "ONBOARD-REFUSE reason=identity" ]
}

@test "onboard precheck 7: no resolvable protected bookmark refuses" {
	local d="$BATS_TEST_TMPDIR/r"
	git init -q -b develop "$d"
	env -C "$d" git commit -q --allow-empty -m init
	run --separate-stderr ONBOARD "$d" apply --level full
	[ "$status" -eq 1 ]
	[ "$output" = "ONBOARD-REFUSE reason=no-protected-bookmark" ]
	[ ! -d "$d/.jj" ]
}

@test "onboard precheck 7: PREFLIGHT_PROTECTED_BOOKMARKS satisfies the check" {
	local d="$BATS_TEST_TMPDIR/r"
	git init -q -b develop "$d"
	env -C "$d" git commit -q --allow-empty -m init
	run --separate-stderr env -C "$d" PREFLIGHT_PROTECTED_BOOKMARKS=develop \
		sh "$SCRIPTS/onboard.sh" apply --level full
	[ "$status" -eq 0 ]
	[[ "${lines[1]}" == *"protected=[develop]"* ]]
}

@test "onboard precheck 7: an illegal protected bookmark name refuses first" {
	local d
	d="$(fx_git_only_file r)"
	run --separate-stderr env -C "$d" PREFLIGHT_PROTECTED_BOOKMARKS='main x") | oops(' \
		sh "$SCRIPTS/onboard.sh" apply --level full
	[ "$status" -eq 1 ]
	[ "$output" = "ONBOARD-REFUSE reason=protected-bookmark-name" ]
	[ ! -d "$d/.jj" ]
}

@test "onboard precheck 8: a large untracked file and a fifo refuse" {
	local d
	d="$(fx_git_only_file r)"
	dd if=/dev/zero of="$d/big.bin" bs=4096 count=512 2> /dev/null
	mkfifo "$d/pipe"
	run --separate-stderr ONBOARD "$d" apply --level full
	[ "$status" -eq 1 ]
	[ "$output" = "ONBOARD-REFUSE reason=snapshot-hygiene" ]
	# Both offenders, absolute, one per line.
	[ "$(printf '%s\n' "$stderr" | grep -c -x -e "$d/big.bin" -e "$d/pipe")" -eq 2 ]
	[[ "$stderr" == *.git/info/exclude* ]]
	[[ "$stderr" == *snapshot.max-new-file-size* ]]
	[ ! -d "$d/.jj" ]
}

@test "onboard precheck 8: the scan covers the root, not the caller's directory" {
	local d
	d="$(fx_git_only_file r)"
	dd if=/dev/zero of="$d/big.bin" bs=4096 count=512 2> /dev/null
	mkdir -p "$d/sub"
	run --separate-stderr ONBOARD "$d/sub" apply --level full
	[ "$status" -eq 1 ]
	[ "$output" = "ONBOARD-REFUSE reason=snapshot-hygiene" ]
	[ "$(printf '%s\n' "$stderr" | grep -c -x "$d/big.bin")" -eq 1 ]
}

@test "onboard precheck 8: an ignored large file does not refuse" {
	local d
	d="$(fx_git_only_file r)"
	dd if=/dev/zero of="$d/big.bin" bs=4096 count=512 2> /dev/null
	printf 'big.bin\n' > "$d/.git/info/exclude"
	run --separate-stderr ONBOARD "$d" apply --level full
	[ "$status" -eq 0 ]
}

@test "onboard precheck 8: an ignored fifo does not refuse" {
	local d
	d="$(fx_git_only_file r)"
	mkdir -p "$d/.cache/tmp"
	mkfifo "$d/.cache/tmp/pipe"
	printf '.cache/\n' > "$d/.gitignore"
	env -C "$d" git add .gitignore
	env -C "$d" git commit -q -m ignore
	run --separate-stderr ONBOARD "$d" apply --level full
	[ "$status" -eq 0 ]
	[[ "${lines[1]}" == ONBOARD-OK* ]]
}

@test "onboard precheck 9: .gitmodules refuses" {
	local d
	d="$(fx_git_only_file r)"
	: > "$d/.gitmodules"
	run --separate-stderr ONBOARD "$d" apply --level full
	[ "$status" -eq 1 ]
	[ "$output" = "ONBOARD-REFUSE reason=submodules" ]
}

@test "onboard precheck 9: ONBOARD_ALLOW_SUBMODULES=1 warns instead" {
	local d
	d="$(fx_git_only_file r)"
	: > "$d/.gitmodules"
	run --separate-stderr env -C "$d" ONBOARD_ALLOW_SUBMODULES=1 \
		sh "$SCRIPTS/onboard.sh" apply --level full
	[ "$status" -eq 0 ]
	[[ "${lines[1]}" == *"warns=[submodules exclude-added]" ]]
}

@test "onboard precheck 10: a nested git worktree refuses and lists it" {
	local w main
	w="$(fx_shadowed r)"
	main="$BATS_TEST_TMPDIR/r"
	run --separate-stderr ONBOARD "$main" apply --level full
	[ "$status" -eq 1 ]
	[ "$output" = "ONBOARD-REFUSE reason=nested-worktrees" ]
	[[ "$stderr" == *"$w"* ]]
}

@test "onboard precheck 10: a sibling worktree does not refuse" {
	local main
	fx_linked_worktree r > /dev/null
	main="$BATS_TEST_TMPDIR/r"
	run --separate-stderr ONBOARD "$main" apply --level full
	[ "$status" -eq 0 ]
}

@test "onboard precheck 11: a pre-commit hook warns at level full" {
	local d
	d="$(fx_git_only_file r)"
	: > "$d/hk.pkl"
	run --separate-stderr ONBOARD "$d" apply --level full
	[ "$status" -eq 0 ]
	[[ "${lines[1]}" == *"warns=[git-hooks-bypassed exclude-added]" ]]
}

@test "onboard precheck 11: level oplog does not warn about hooks" {
	local d
	d="$(fx_git_only_file r)"
	: > "$d/hk.pkl"
	run --separate-stderr ONBOARD "$d" apply --level oplog
	[ "$status" -eq 0 ]
	[[ "${lines[1]}" == *"warns=[]" ]]
}

@test "onboard precheck 7: a glob in PREFLIGHT_PROTECTED_BOOKMARKS is a literal name, refused before any store" {
	local d
	d="$(fx_git_only_file r)"
	run --separate-stderr env -C "$d" PREFLIGHT_PROTECTED_BOOKMARKS='*' \
		sh "$SCRIPTS/onboard.sh" apply --level full
	[ "$status" -eq 1 ]
	[ "$output" = "ONBOARD-REFUSE reason=protected-bookmark-name" ]
	[ ! -d "$d/.jj" ]
}
