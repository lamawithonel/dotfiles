# test_helper.bash -- shared setup and fixtures for the vcs-workflow
# bats suite.  Sourced by every tests/*.bats file.
#
# Every test runs under a private HOME and XDG tree inside
# $BATS_TEST_TMPDIR, with JJ_CONFIG pointing at a test identity, so no
# test can read the user's real jj or git configuration or write into
# ~/.config/jj/repos.  The first assertion in setup() proves the
# isolation before any fixture is built.

bats_require_minimum_version 1.5.0

SKILL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPTS="$SKILL_DIR/scripts"
export SKILL_DIR SCRIPTS

setup() {
	export HOME="$BATS_TEST_TMPDIR/home"
	export XDG_CONFIG_HOME="$HOME/.config"
	export XDG_DATA_HOME="$HOME/.local/share"
	export XDG_STATE_HOME="$HOME/.local/state"
	export XDG_CACHE_HOME="$HOME/.cache"
	mkdir -p "$XDG_CONFIG_HOME/jj" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"

	export JJ_CONFIG="$XDG_CONFIG_HOME/jj/config.toml"
	printf '[user]\nname = "Bats Tester"\nemail = "bats@vcs-workflow.test"\n\n[ui]\npaginate = "never"\n' > "$JJ_CONFIG"

	export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
	export GIT_CONFIG_NOSYSTEM=1
	export GIT_TERMINAL_PROMPT=0
	git config --file "$GIT_CONFIG_GLOBAL" user.name "Bats Tester"
	git config --file "$GIT_CONFIG_GLOBAL" user.email "bats@vcs-workflow.test"
	git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
	unset JJ_EDITOR VISUAL EDITOR GIT_DIR GIT_WORK_TREE

	# Guard on the guard: jj must resolve its user config inside the
	# test tree, or every fixture below would touch the real one.
	local user_cfg
	user_cfg="$(jj config path --user 2> /dev/null)"
	case "$user_cfg" in
		"$BATS_TEST_TMPDIR"/*) ;;
		*)
			echo "isolation failure: jj user config is '$user_cfg'" >&2
			return 1
			;;
	esac
}

# assert_repo_config_isolated DIR -- fail unless jj's --repo config for
# the store at DIR lives under $BATS_TEST_TMPDIR.
assert_repo_config_isolated() {
	local repo_cfg
	repo_cfg="$(env -C "$1" jj config path --repo 2> /dev/null)"
	case "$repo_cfg" in
		"$BATS_TEST_TMPDIR"/*) ;;
		*)
			echo "isolation failure: jj repo config is '$repo_cfg'" >&2
			return 1
			;;
	esac
}

# Fixtures.  Each prints the directory it built and nothing else.

# fx_git_only NAME -- a plain git repo on branch main with one commit.
fx_git_only() {
	local d="$BATS_TEST_TMPDIR/$1"
	git init -q -b main "$d"
	env -C "$d" git commit -q --allow-empty -m init
	printf '%s' "$d"
}

# fx_git_only_file NAME -- like fx_git_only but with one tracked file.
fx_git_only_file() {
	local d="$BATS_TEST_TMPDIR/$1"
	git init -q -b main "$d"
	printf 'one\n' > "$d/a.txt"
	env -C "$d" git add a.txt
	env -C "$d" git commit -q -m init
	printf '%s' "$d"
}

# fx_colocated NAME -- git repo with a colocated jj store.
fx_colocated() {
	local d
	d="$(fx_git_only_file "$1")"
	env -C "$d" jj git init --colocate > /dev/null 2>&1
	printf '%s' "$d"
}

# fx_jj_only NAME -- a jj repo with no .git directory.
fx_jj_only() {
	local d="$BATS_TEST_TMPDIR/$1"
	mkdir -p "$d"
	env -C "$d" jj git init --no-colocate > /dev/null 2>&1
	printf '%s' "$d"
}

# fx_noncolocated_jj NAME -- a NON-colocated jj store (its own git
# store under .jj) with a plain git repo created in the same directory
# afterwards.  jj refuses --no-colocate inside an existing git repo, so
# the store is created first and git second.  detect_shape.sh reports
# this as colocated; `jj git colocation status` is what tells them
# apart.
fx_noncolocated_jj() {
	local d="$BATS_TEST_TMPDIR/$1"
	mkdir -p "$d"
	env -C "$d" jj git init --no-colocate > /dev/null 2>&1
	printf 'one\n' > "$d/a.txt"
	git init -q -b main "$d"
	env -C "$d" git add a.txt
	env -C "$d" git commit -q -m init
	printf '%s' "$d"
}

# fx_linked_worktree NAME -- a sibling linked git worktree of a
# colocated repo (prints the worktree path).
fx_linked_worktree() {
	local d
	d="$(fx_colocated "$1")"
	env -C "$d" git worktree add -q --detach "$BATS_TEST_TMPDIR/$1-wt"
	printf '%s' "$BATS_TEST_TMPDIR/$1-wt"
}

# fx_shadowed NAME -- a NESTED linked git worktree under a colocated
# repo, the worktree-shadowed shape (prints the worktree path).
fx_shadowed() {
	local d
	d="$(fx_colocated "$1")"
	env -C "$d" git worktree add -q --detach "$d/.claude/worktrees/x"
	printf '%s' "$d/.claude/worktrees/x"
}

# fx_jj_workspace NAME -- a secondary jj workspace of a colocated repo
# (prints the workspace path; the primary is $BATS_TEST_TMPDIR/NAME).
fx_jj_workspace() {
	local d
	d="$(fx_colocated "$1")"
	env -C "$d" jj workspace add "$BATS_TEST_TMPDIR/$1-ws" > /dev/null 2>&1
	printf '%s' "$BATS_TEST_TMPDIR/$1-ws"
}

# fx_bare_remote NAME -- a bare git repo usable as origin.
fx_bare_remote() {
	git init -q --bare "$BATS_TEST_TMPDIR/$1.git"
	printf '%s' "$BATS_TEST_TMPDIR/$1.git"
}

# fx_symlinked_root NAME -- a symlink to a colocated repo (prints the
# symlink path).
fx_symlinked_root() {
	local d
	d="$(fx_colocated "$1")"
	ln -s "$d" "$BATS_TEST_TMPDIR/$1-link"
	printf '%s' "$BATS_TEST_TMPDIR/$1-link"
}

# path_without TOOL -- print a PATH that carries every tool the scripts
# use except TOOL.
path_without() {
	local nobin="$BATS_TEST_TMPDIR/nobin" t p
	mkdir -p "$nobin"
	for t in git jq awk sed grep head tail tr wc nproc mktemp cat date find sort uniq \
		cut mkdir rm cp mv ls dirname basename readlink realpath sh bash env true false \
		printf echo test expr xargs touch chmod stat cmp diff ln jj; do
		[ "$t" = "$1" ] && continue
		p="$(command -v "$t" 2> /dev/null)" || continue
		ln -sf "$p" "$nobin/$t"
	done
	printf '%s' "$nobin"
}
