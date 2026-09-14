# Safety Net

`scripts/preflight.sh` is the only script in this skill permitted to
mutate jj config, and only at `--repo` scope.  It asserts a usable
identity, writes the keys the recorded level calls for, asserts they
closed, and fails closed -- never open -- when a protected bookmark
cannot be resolved.  This file documents exactly what it writes, the
three traps it exists to route around (`trunk()`, jj's real editor
precedence, and jj's identity resolution), and the two facts about
*where* that config lives (non-durable across `jj git clone`, durable
across `jj workspace add`) that decide when to re-run it.

Every receipt below is a real command run against a scratch repo, not
a transcription from the design doc.

## What preflight.sh writes

Three `--repo`-scoped keys at every level, plus `snapshot.auto-track`
at level `standard`.  Nothing else -- this is the R3-sanctioned
exception to the skill's no-config-mutation rule, and it is the only
one.  The level comes from `git config --get vcs-workflow.level`, or
from `--level L`; an absent key, or a jj-only shape with no git config
to read, means `full`.

| Key | Value | Why (one line) | Undo |
| :-- | :-- | :-- | :-- |
| `revset-aliases."immutable_heads()"` | `builtin_immutable_heads() \| bookmarks(exact:"<name>") \| ...` (one clause per protected bookmark) | Protects named bookmarks directly; never unions in `trunk()` -- see the trap below. | `jj config unset --repo 'revset-aliases."immutable_heads()"'` |
| `ui.editor` | `:true` | Editor-guard write, part 1 of 3 -- see the guard section below for why this alone is not enough. | `jj config unset --repo ui.editor` |
| `ui.diff-editor` | `:true` | Same guard, for `jj diff --tool`/`jj split`'s diff-editor path, which reads a separate key. | `jj config unset --repo ui.diff-editor` |
| `snapshot.auto-track` | `none` at level `standard`; unset at `oplog` and `full` | At `standard`, only a file explicitly `jj file track`ed can publish -- the codex's no-bulk-staging rule, mechanically.  At `oplog` and at `full`, preflight *unsets* the key so jj's own default applies. | `jj config unset --repo snapshot.auto-track` |

Per level, exactly:

| Level | `immutable_heads()` | `ui.editor` | `ui.diff-editor` | `snapshot.auto-track` |
| :-- | :-- | :-- | :-- | :-- |
| `oplog` | written | written | written | unset |
| `standard` | written | written | written | `none` |
| `full` | written | written | written | unset |

`oplog` and `full` both **unset** the key rather than skip it, and the
distinction matters on a downgrade.  A store that ran at `standard`
already carries `snapshot.auto-track = "none"`; skipping the key would
leave that write in place, and the repo would go on refusing to snapshot
untracked files at a level that never asked for it.  Unsetting is
idempotent -- `jj config unset` errors when the key is already absent,
and preflight ignores that failure, because an absent key is the
requested end state.

Receipt -- the exact TOML preflight wrote on a fresh colocated repo
with one local bookmark `main` at level `full`, read back with `jj
config path --repo` (the config-id is opaque and repo-specific; only
the shape matters):

```toml
#:schema https://docs.jj-vcs.dev/latest/config-schema.json

[revset-aliases]
"immutable_heads()" = 'builtin_immutable_heads() | bookmarks(exact:"main")'

[ui]
editor = ":true"
diff-editor = ":true"
```

At level `standard` the same file carries one more table, `[snapshot]`
with `auto-track = "none"`; `oplog` and `full` leave it out.  The
receipt names the level it wrote for:

```
PREFLIGHT-OK shape=colocated level=standard store=d083ed8dc0dbf65f40c2 protected=[main] probe=ok
```

`preflight.sh` is idempotent: re-running it overwrites these keys in
place and re-runs the closing assertion; it never errors on a second
run against the same store.  It is also the one place a level change
takes effect -- `onboard.sh apply --level <new>` re-runs it, and
downgrading rewrites the keys without touching the store.

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

jj's real editor precedence, highest to lowest (confirmed live
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

## The identity assertion runs before any write

Same shape as the editor guard, same reason: what jj resolves is not
what git resolves.  jj never falls back to a colocated repo's `git
config` for `user.name` and `user.email`; with its own identity unset
it commits as the literal `JJ_EMPTY_STRING`, backed by a warning
rather than a failure, and every captured commit in the session
carries it.

`preflight.sh` therefore reads `jj config get user.name` and
`user.email` before its first `jj config set`, and dies on an empty
name, an empty email, or a placeholder email.  Email addresses are
case-insensitive, so the address is folded to lower case first and the
folded form is matched against four patterns:

| Pattern | Catches | Example |
| :-- | :-- | :-- |
| `*.invalid` | the reserved never-resolving TLD, in any case | `a@test.INVALID` |
| `*@example` | the dotless placeholder domain | `a@example` |
| `*@example.*` | `example` at the second level, any TLD | `A@EXAMPLE.COM` |
| `*.example.com` | any subdomain of the reserved documentation domain | `a@sub.example.com` |

Fold first, then match: an unfolded check passes `A@EXAMPLE.COM`
straight through, and the placeholder authors every captured commit
exactly as if it had been spelled in lower case.  The receipt names the
address as the user wrote it, not as it was folded:

```
$ scripts/preflight.sh
PREFLIGHT-FAIL identity user.email 'vcs-research@example.invalid' is a placeholder
```

That address is the motivating case, not a hypothetical: the research
spike that produced this skill left `user.name = "VCS Research"` and
that email in `~/.config/jj/config.toml`, so every commit captured on
this host until the identity is replaced would have been authored by
nobody -- and jj only warns.  The assertion is positioned so a failing repo
never reaches a `--repo` write -- exit 1, no key written, nothing to
undo.  Fix the identity in the user config (or set it per repo with
`jj config set --repo user.email`), then re-run.

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

Different config-id, empty config: every key is gone.
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
as the primary -- same file, same keys, already present:

```
$ cd ../secondary-ws && jj config path --repo
/home/lucas/.config/jj/repos/d146dbeea91a29df2b2b/config.toml    # identical to primary
$ jj config list --repo
revset-aliases."immutable_heads()" = 'builtin_immutable_heads() | bookmarks(exact:"main")'
ui.editor = ":true"
ui.diff-editor = ":true"
```

Secondary workspaces therefore need zero extra action: preflight once
against the store is preflight for every workspace that points into
it.

### Resolve the primary root before reading anything about the store

jj follows the pointer on its own; a shell script does not.  Two of
preflight's inputs live at the primary and must be resolved there by
hand:

- **The level key.**  `vcs-workflow.level` is git config, and a
  secondary workspace has no `.git` at all.  Run bare in the workspace,
  `git config --get vcs-workflow.level` finds nothing, preflight falls
  back to `full`, and a repo recorded at `standard` gets its
  `snapshot.auto-track` **unset** by the very run meant to preserve it.
  Read the key as `git -C <primary> config --get vcs-workflow.level`
  instead; `full` is correct only when there is no git config anywhere.
- **The store id.**  It is the contents of `<primary>/.jj/repo/config-id`,
  and it is what callers gate "has preflight run against THIS store" on.
  A workspace and its primary share one store, so they must report one
  id.

The pointer path is **relative to the workspace's own `.jj` directory**,
not to the current working directory, which is the whole trap: `cat
.jj/repo` yields `../../primary/.jj/repo`, and resolving that against
the process's CWD lands somewhere that does not exist.  Resolve it the
same way everywhere -- `preflight.sh`, `emit_handoff.sh`, and
`workspace_hook.sh` all implement this identically:

1. Start at `jj root`.
2. If `<root>/.jj/repo` is a **file**, read it.  An absolute path is
   taken as is; a relative one is resolved against `<root>/.jj`.
3. The primary root is two directories up from the resolved
   `.jj/repo`.
4. Physicalise it with `cd -P && pwd -P`, so a symlinked checkout does
   not compare unequal to itself.

A primary skips step 2 entirely: its `.jj/repo` is a directory, and the
same four steps return its own root.  One code path, both shapes, no
branch at the call sites.

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
PREFLIGHT-OK shape=colocated level=full store=d083ed8dc0dbf65f40c2 protected=[release-1.0] probe=ok
```

A repo using a nonstandard trunk name gets **no** protection until
`PREFLIGHT_PROTECTED_BOOKMARKS` is set -- this is a real residual gap,
not a bug: surface it to the operator rather than guessing a name.

## A resolved name is still validated before it is interpolated

Every resolved name is interpolated into a revset **string literal**,
`bookmarks(exact:"<name>")`, and a jj string literal has no escaping
this script can lean on.  A name carrying a `"` closes the literal, and
whatever follows is persisted verbatim as revset code inside
`immutable_heads()` -- an injection into the one alias the whole safety
net rests on.  The override is the exposed edge, because its value comes
from the environment rather than from jj:

```
$ PREFLIGHT_PROTECTED_BOOKMARKS='main x") | oops(' scripts/preflight.sh
PREFLIGHT-FAIL protected bookmark name 'x")' has an illegal character (allowed: A-Za-z0-9._/+-)
```

The list is space-separated, so that value is three words and the second
one is the one that dies; the point is that nothing after `main` ever
reaches the alias.

So preflight validates each space-separated word against a character
allowlist -- `A-Za-z0-9._/+-`, every character git and jj permit in a
ref name that cannot close a literal or open a call -- and dies on the
first word that fails.  The check runs **before** the first `jj config
set`, so a rejected name leaves no key written and nothing to undo.
Allowlist, not denylist: a new revset metacharacter added upstream
cannot widen what is already accepted.

Two layers, not one.  After the writes land, preflight parses the alias
it just persisted:

```
$ jj log -r 'immutable()' -n 0
```

`-n 0` asks for no commits, so the command does nothing but resolve the
revset, and a resolution error is the whole signal.  It catches what the
character check cannot: an `immutable_heads()` or
`builtin_immutable_heads()` redefined anywhere else in the config stack,
which leaves `immutable()` unparseable no matter how clean preflight's
own names were.

```
PREFLIGHT-FAIL immutable() does not parse: Warning: Redefining `revset-aliases.builtin_immutable_heads()` is not recommended; ... Config error: Invalid `revset-aliases.immutable_heads()` ... Function `nope_function` doesn't exist ...
```

jj's own diagnostic is folded onto the one receipt line, elided above.

Without this check that failure is silent in the worst possible way.
The closing assertion queries `bookmarks(exact:"<name>") & ~immutable()`
per protected bookmark, but it only runs for a bookmark that `jj
bookmark list <name>` reports as existing -- and `jj bookmark list`
fails too when `immutable()` will not parse.  Every bookmark is skipped,
the loop finds no leak because it ran no query, and preflight reports
`PREFLIGHT-OK` over a repo with no protection at all.  Parse first, then
assert.
