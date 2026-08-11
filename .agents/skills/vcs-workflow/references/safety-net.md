# Safety Net

`scripts/preflight.sh` is the only script in this skill permitted to
mutate jj config, and only at `--repo` scope.  It writes four keys,
asserts they closed, and fails closed -- never open -- when a
protected bookmark cannot be resolved.  This file documents exactly
what it writes, the two traps it exists to route around (`trunk()`
and jj's real editor precedence), and the two facts about *where*
that config lives (non-durable across `jj git clone`, durable across
`jj workspace add`) that decide when to re-run it.

Verified live against jj 0.44.0-af45d57 for this revision; every
receipt below is a real command run against a scratch repo, not a
transcription from the design doc.

## What preflight.sh writes

Exactly four `--repo`-scoped keys.  Nothing else -- this is the
R3-sanctioned exception to the skill's no-config-mutation rule, and it
is the only one.

| Key | Value | Why (one line) | Undo |
| :-- | :-- | :-- | :-- |
| `revset-aliases."immutable_heads()"` | `builtin_immutable_heads() \| bookmarks(exact:"<name>") \| ...` (one clause per protected bookmark) | Protects named bookmarks directly; never unions in `trunk()` -- see the trap below. | `jj config unset --repo 'revset-aliases."immutable_heads()"'` |
| `ui.editor` | `:true` | Editor-guard write, part 1 of 3 -- see the guard section below for why this alone is not enough. | `jj config unset --repo ui.editor` |
| `ui.diff-editor` | `:true` | Same guard, for `jj diff --tool`/`jj split`'s diff-editor path, which reads a separate key. | `jj config unset --repo ui.diff-editor` |
| `merge-tools.difftastic.program` | `difft` | jj's builtin `difftastic` preset invokes a binary literally named `difftastic`; every mainstream install (mise, cargo, brew, distro) names it `difft`, so the preset fails "No such file or directory" until this is set. | `jj config unset --repo 'merge-tools.difftastic.program'` |

Receipt -- the exact TOML preflight wrote on a fresh colocated repo
with one local bookmark `main`, read back with `jj config path --repo`
(the config-id is opaque and repo-specific; only the shape matters):

```toml
#:schema https://docs.jj-vcs.dev/latest/config-schema.json

[revset-aliases]
"immutable_heads()" = 'builtin_immutable_heads() | bookmarks(exact:"main")'

[ui]
editor = ":true"
diff-editor = ":true"

[merge-tools.difftastic]
program = "difft"
```

`preflight.sh` is idempotent: re-running it overwrites these four
keys in place and re-runs the closing assertion; it never errors on
a second run against the same store.

## The trunk() trap

`trunk()` is a **builtin revset alias**, not a bookmark lookup.  It
resolves through `remote_bookmarks(exact:"main"/"master"/"trunk",
remote:"origin"/"upstream") | root()` -- it never consults a
local-only bookmark of the same name.  A repo with a purely local
`main` (no remote configured, or the remote not yet fetched) has a
`trunk()` that resolves to nothing but `root()`, no matter how
`immutable_heads()` is configured.

The trap: `jj log -r 'trunk() & immutable()'` looks like the obvious
"is my trunk protected" check, and it lies.  It returns `root()` --
looking non-empty, looking like success -- even when the named
bookmark itself is wide open.  Live receipt, `main` at `@` on a fresh
repo, `immutable_heads()` already configured to include
`bookmarks(exact:"main")`:

```
$ jj log -r 'trunk() & immutable()' --no-graph -T 'commit_id ++ "\n"'
0000000000000000000000000000000000000000
```

That is `root()`'s all-zero commit id -- not `main`'s.  The assertion
that actually answers "is this bookmark protected" checks the
bookmark directly:

```
$ jj log -r 'bookmarks(exact:"main") & ~immutable()' --no-graph -T 'commit_id ++ "\n"'
$                                                          # empty = protected
```

This is `preflight.sh`'s closing assertion (its own header comment
labels it "invariant 3"), run once per configured protected bookmark
that exists.  A non-empty result there is `bookmark '<name>' is NOT
protected`, and the script exits 1.  Never write or trust `trunk() &
immutable()` in any script or ad hoc check in this repo -- it is a
false-positive generator, not a stricter form of the real check.

## The editor guard is three-part

jj 0.44.0's real editor precedence, highest to lowest (confirmed live
and independently stated verbatim, offline, by `jj help -k config`
under `## Editor`: `$JJ_EDITOR > ui.editor > $VISUAL > $EDITOR`):

| Precedence | Source | Beats |
| :-- | :-- | :-- |
| 1 (highest) | a command-line `--config 'ui.editor=...'` flag | everything below |
| 2 | `$JJ_EDITOR` | persisted `ui.editor`, `$VISUAL`, `$EDITOR` |
| 3 | persisted `ui.editor` from any file scope, `--repo` included | `$VISUAL`, `$EDITOR` |
| 4 (lowest) | `$VISUAL` / `$EDITOR` or jj's built-in default | nothing |

**`$JJ_EDITOR` outranks a persisted `--repo` write.**  This is the A7
correction: an earlier draft assumed the reverse and shipped only the
`--repo` write as the guard.  Falsified live -- with `ui.editor =
"cat"` persisted at `--repo` scope and `JJ_EDITOR=true` in the
environment, a bare `jj describe` completed in 0.019s with `Nothing
changed.`  `JJ_EDITOR` won.  A `--repo` write alone is not a guard
against an ambient `JJ_EDITOR`; it only wins when nothing higher in
the table is set.

`preflight.sh` therefore does two things, and a third belongs to
every other script in this skill that invokes an editor:

1. **Writes the `--repo` floor** (`ui.editor` / `ui.diff-editor` =
   `:true`, table above) -- covers the case where nothing higher is
   set.
2. **Asserts `$JJ_EDITOR` is neutralized** -- fails closed if
   `$JJ_EDITOR` is set to anything other than `:true`:

   ```
   $ JJ_EDITOR=vim scripts/preflight.sh
   PREFLIGHT-FAIL JJ_EDITOR is set ('vim') and outranks --repo ui.editor; unset it or set it to ':true'
   ```

   Clear it with `env -u JJ_EDITOR <cmd>`, or export
   `JJ_EDITOR=:true` for the session -- either satisfies preflight.
3. **Every editor-invoking command line elsewhere carries `--config
   'ui.editor=:true'` as well** (highest precedence, table above) --
   preflight cannot enforce this at other call sites; it is the
   belt-and-braces layer that holds even if a caller forgets to
   check `$JJ_EDITOR` first.

All three parts must hold (invariant 4).  Any one alone has a known
bypass.

## Config non-durability across `jj git clone`

`--repo`-scoped config does not live inside `.jj/`.  It lives at
`~/.config/jj/repos/<opaque-config-id>/config.toml`, and that
config-id is stored in `.jj/repo/config-id` -- keyed to the checkout,
not the project.  `jj git clone` allocates a fresh store and a fresh
config-id, so the safety net does not travel with the clone.  Live
receipt, cloning an already-preflighted repo:

```
$ jj config path --repo          # original
/home/lucas/.config/jj/repos/d146dbeea91a29df2b2b/config.toml
$ jj git clone <original> <clone> --colocate && cd <clone>
$ jj config path --repo          # clone
/home/lucas/.config/jj/repos/3648c92a7b5fbe7053ec/config.toml
$ jj config list --repo
Warning: No config to list.
```

Different config-id, empty config: the four keys are gone.
`preflight.sh` must be re-run against every fresh `.jj` store --
`jj git init`, `jj git init --colocate`, and every `jj git clone` --
never assumed to carry over from having run once for the project.
This is invariant 2's "since **this** `.jj` store was created", not
"since this project was first cloned".

## Workspace inheritance

`jj workspace add` is the one case that needs no extra preflight run.
A secondary workspace's `.jj/repo` is a plain-text **pointer file**
(not a symlink), holding a relative path back to the primary's
`.jj/repo` directory:

```
$ cat ../secondary-ws/.jj/repo
../../primary/.jj/repo
```

`jj config path --repo`, resolved from inside the secondary
workspace, follows that pointer and lands on the **same** config-id
as the primary -- same file, same four keys, already present:

```
$ cd ../secondary-ws && jj config path --repo
/home/lucas/.config/jj/repos/d146dbeea91a29df2b2b/config.toml    # identical to primary
$ jj config list --repo
revset-aliases."immutable_heads()" = 'builtin_immutable_heads() | bookmarks(exact:"main")'
ui.editor = ":true"
ui.diff-editor = ":true"
merge-tools.difftastic.program = "difft"
```

Secondary workspaces therefore need zero extra action: preflight once
against the store is preflight for every workspace that points into
it.

## `jj git init` spawns no git subprocess

`jj git init` and `jj git init --colocate` never `execve` a `git`
binary -- jj talks to the git object database through in-process
bindings, not a subprocess.  Independently confirmed by strace on
both a fresh directory and an already-`git init`-ed one:

```
$ strace -f -e trace=execve jj git init --colocate
218579 execve("/home/.../jj", ["jj", "git", "init", "--colocate"], ...) = 0
```

Exactly one `execve`, of `jj` itself, in both cases.  Consequence for
this skill's permission surface: neither `jj git init` nor `jj git
init --colocate` ever matches `Bash(git init:*)` -- different
top-level command string, by construction of the program name, not
by luck.  No permission grant is needed for it, and none should be
requested speculatively.

## Protected-bookmark resolution order (fail-closed)

`preflight.sh`'s `_resolve_protected()` tries, in order, and commits
to the first hit -- there is no merging across tiers:

1. **`$PREFLIGHT_PROTECTED_BOOKMARKS`**, space-separated, if set.
   Explicit override; skips the rest.
2. **The remote's symbolic HEAD**, colocated shapes only:
   `git symbolic-ref --short refs/remotes/origin/HEAD`, `origin/`
   prefix stripped.
3. **Conventional names**, tried in this fixed order: `main`,
   `master`, `trunk` -- first one that resolves via `jj bookmark list
   <name>` returning non-empty wins.
4. **Fail closed.**  None of the above resolved: exit 1, no config
   written, no silent "protecting nothing".

Live receipt, a fresh repo with no remote and no conventionally named
bookmark:

```
$ scripts/preflight.sh
PREFLIGHT-FAIL cannot resolve a protected bookmark (no remote HEAD, no main/master/trunk); set PREFLIGHT_PROTECTED_BOOKMARKS explicitly
$ PREFLIGHT_PROTECTED_BOOKMARKS=release-1.0 scripts/preflight.sh
PREFLIGHT-OK shape=colocated store=d083ed8dc0dbf65f40c2 protected=[release-1.0] probe=ok
```

A repo using a nonstandard trunk name gets **no** protection until
`PREFLIGHT_PROTECTED_BOOKMARKS` is set -- this is a real residual gap,
not a bug: surface it to the operator rather than guessing a name.
