#!/usr/bin/env python3
"""PreToolUse hook (Bash): enforce the user's no-exception rules.

Reads the hook JSON on stdin.  Splits the Bash command into simple commands
(through quotes, separators, subshells, command substitutions, heredocs,
`bash -c`, `eval`, and common wrappers such as `env` and `timeout`) and
returns one decision on stdout:

  ask   gh pr create | merge | close; gh issue create; a branch or PR
        delete (git branch -d, git push --delete, a `:branch` refspec,
        git update-ref -d, gh api DELETE); a push to a default branch;
        gh api calls that create a PR or issue, merge, or run a mutation.
  deny  a push to a public GitHub repository during the quiet hours
        (09:00 to 18:00 US/Eastern, Monday to Friday); cd, pushd, popd.

A deny outranks an ask.  Anything else produces no output (allow).  The
reasons cite ~/.agents/AGENTS.local.md and ~/.claude/CLAUDE.local.md.

This is a lexical gate, not an enforcement boundary.  It cannot see shell
variables, aliases, scripts, or commands that another program runs.  The
sandbox network and credential rules stay underneath it.

Test hooks, read from the hook's own environment only:
  GATE_NOW         ISO 8601 timestamp that replaces the clock.
  GATE_VISIBILITY  public, private, or unknown; replaces the gh lookup.

Exit code: 0 always.  A malformed input is allowed with a warning on stderr.
"""

import json
import os
import re
import subprocess
import sys
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass, replace
from datetime import datetime
from typing import Final
from zoneinfo import ZoneInfo

EASTERN: Final = ZoneInfo("America/New_York")
QUIET_START: Final = 9
QUIET_END: Final = 18
GIT_TIMEOUT_S: Final = 3
GH_TIMEOUT_S: Final = 6

NO_CD_REASON: Final = (
    "CLAUDE.local.md forbids cd, pushd, and popd in a Bash call, even inside a "
    "subshell.  Name each path as an absolute path, or run the tool in place: "
    "git -C DIR, make -C DIR, jj -R DIR, or env -C DIR cmd ... ."
)
ISSUE_REASON: Final = (
    "AGENTS.local.md: do not open a bug report or issue without the user's approval."
)
GH_ASK_REASON: Final = {
    ("pr", "create"): "AGENTS.local.md: do not open a PR without the user's approval.",
    ("pr", "new"): "AGENTS.local.md: do not open a PR without the user's approval.",
    ("issue", "create"): ISSUE_REASON,
    ("issue", "new"): ISSUE_REASON,
    ("pr", "merge"): (
        "AGENTS.md: merging to the default branch is a standing human gate.  "
        "Ask the user."
    ),
    ("pr", "close"): (
        "AGENTS.local.md: do not delete or close a PR or its branch without the "
        "user's approval."
    ),
}
DELETE_REASON: Final = (
    "AGENTS.local.md: do not delete a branch or PR without the user's approval."
)
DEFAULT_PUSH_REASON: Final = (
    "AGENTS.md: the autonomy ceiling is the PR.  A push to a default branch needs "
    "the user's approval."
)
ALL_REFS_REASON: Final = (
    "This push sends every branch, the default branch included.  "
    "AGENTS.md: the autonomy ceiling is the PR.  Ask the user."
)
API_REASON: Final = (
    "AGENTS.local.md: this gh api call creates a PR or issue, merges, deletes, "
    "or runs a GraphQL mutation.  Ask the user first."
)
QUIET_REASON: Final = (
    "AGENTS.local.md, Public-Resource Quiet Hours: no GitHub activity on a public "
    "repository between 09:00 and 18:00 US/Eastern, Monday to Friday.  "
    "Wait until the window closes, or push to a private repository."
)
QUIET_UNKNOWN_REASON: Final = (
    "AGENTS.local.md, Public-Resource Quiet Hours: this push is inside the "
    "window and the repository's visibility could not be read.  Ask the user."
)

RESERVED: Final = frozenset(
    ("{", "}", "!", "if", "then", "else", "elif", "fi", "do", "done", "while")
    + ("until", "time", "coproc")
)
SHELLS: Final = frozenset(("sh", "bash", "zsh", "dash", "ksh", "ash"))
NO_CD: Final = frozenset(("cd", "pushd", "popd"))
ASSIGNMENT: Final = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
GITHUB_URL: Final = re.compile(
    r"github\.com[:/]+([^/\s]+)/([^/\s]+?)(?:\.git)?/?$", re.IGNORECASE
)
DEFAULT_BRANCHES: Final = frozenset(("main", "master"))


@dataclass(frozen=True, slots=True)
class Finding:
    """One decision with the reason shown to the model and the user."""

    level: str
    reason: str


@dataclass(frozen=True, slots=True)
class Command:
    """One simple command: its words after quote removal, and heredoc text."""

    words: tuple[str, ...]
    docs: tuple[str, ...] = ()


@dataclass(frozen=True, slots=True)
class Wrapper:
    """A command that runs its trailing command: which options take a value."""

    values: frozenset[str] = frozenset()
    chdir: frozenset[str] = frozenset()
    positionals: int = 0
    inert: frozenset[str] = frozenset()


# ---------------------------------------------------------------- lexer


def _skip_quoted(text: str, start: int) -> int:
    """Return the index after the quoted run that opens at text[start]."""
    quote = text[start]
    i = start + 1
    while i < len(text) and text[i] != quote:
        i += 2 if (quote == '"' and text[i] == "\\") else 1
    return i + 1


def _match_close(text: str, start: int) -> int:
    """Return the index of the ')' that closes the '(' before start."""
    depth = 1
    i = start
    while i < len(text):
        c = text[i]
        if c in "'\"":
            i = _skip_quoted(text, i)
            continue
        if c == "\\":
            i += 1
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return len(text)


def _backtick_end(text: str, start: int) -> int:
    """Return the index of the backtick that closes the one before start."""
    i = start
    while i < len(text) and text[i] != "`":
        i += 2 if text[i] == "\\" else 1
    return min(i, len(text))


def _scan_substitutions(text: str) -> list[Command]:
    """Parse the $(...) and backtick bodies inside text that is not lexed."""
    found: list[Command] = []
    i = 0
    while i < len(text):
        if text.startswith("$(", i):
            end = _match_close(text, i + 2)
            found.extend(parse(text[i + 2 : end]))
            i = end
        elif text[i] == "`":
            end = _backtick_end(text, i + 1)
            found.extend(parse(text[i + 1 : end]))
            i = end
        elif text[i] == "\\":
            i += 1
        i += 1
    return found


class Lexer:
    """A small shell lexer that keeps only what command gating needs."""

    def __init__(self, text: str) -> None:
        self.text = text
        self.i = 0
        self.words: list[str] = []
        self.cur: list[str] = []
        self.in_word = False
        self.commands: list[Command] = []
        self.docs: list[str] = []
        self.skip_word = False
        self.herestring = False
        self.pending: list[tuple[str, bool, bool]] = []
        self.line_start = 0

    def run(self) -> list[Command]:
        """Lex the whole text and return its simple commands."""
        handlers: dict[str, Callable[[], None]] = {
            " ": self._blank,
            "\t": self._blank,
            "\n": self._newline,
            "'": self._single,
            '"': self._double,
            "\\": self._backslash,
            "$": self._dollar,
            "`": self._backtick,
            "#": self._comment,
            "<": self._redirect,
            ">": self._redirect,
        }
        for sep in ";&|()":
            handlers[sep] = self._separator
        while self.i < len(self.text):
            handlers.get(self.text[self.i], self._plain)()
        self._end_cmd()
        return self.commands

    def _append(self, chunk: str) -> None:
        self.cur.append(chunk)
        self.in_word = True

    def _end_word(self) -> None:
        if not self.in_word:
            return
        word = "".join(self.cur)
        self.cur.clear()
        self.in_word = False
        if self.skip_word:
            self.skip_word = False
        elif self.herestring:
            self.docs.append(word)
            self.herestring = False
        else:
            self.words.append(word)

    def _end_cmd(self) -> None:
        self._end_word()
        if self.words:
            self.commands.append(Command(tuple(self.words), tuple(self.docs)))
        self.words.clear()
        self.docs.clear()
        self.skip_word = False
        self.herestring = False

    def _plain(self) -> None:
        self._append(self.text[self.i])
        self.i += 1

    def _blank(self) -> None:
        self._end_word()
        self.i += 1

    def _separator(self) -> None:
        self._end_cmd()
        self.i += 1

    def _newline(self) -> None:
        self._end_cmd()
        self.i += 1
        self._read_heredocs()
        self.line_start = len(self.commands)

    def _comment(self) -> None:
        if self.in_word:
            self._plain()
            return
        end = self.text.find("\n", self.i)
        self.i = len(self.text) if end < 0 else end

    def _single(self) -> None:
        end = self.text.find("'", self.i + 1)
        end = len(self.text) if end < 0 else end
        self._append(self.text[self.i + 1 : end])
        self.i = end + 1

    def _backslash(self) -> None:
        nxt = self.text[self.i + 1 : self.i + 2]
        if nxt != "\n":
            self._append(nxt)
        self.i += 2

    def _dollar(self) -> None:
        nxt = self.text[self.i + 1 : self.i + 2]
        if nxt == "(":
            self._paren_substitution()
        elif nxt == "'":
            self.i += 1
        else:
            self._plain()

    def _paren_substitution(self) -> None:
        end = _match_close(self.text, self.i + 2)
        self.commands.extend(parse(self.text[self.i + 2 : end]))
        self._append("$()")
        self.i = end + 1

    def _backtick(self) -> None:
        end = _backtick_end(self.text, self.i + 1)
        self.commands.extend(parse(self.text[self.i + 1 : end]))
        self._append("`")
        self.i = end + 1

    def _double(self) -> None:
        text = self.text
        self.i += 1
        self._append("")
        while self.i < len(text) and text[self.i] != '"':
            self._double_char()
        self.i += 1

    def _double_char(self) -> None:
        text, i = self.text, self.i
        if text[i] == "\\" and text[i + 1 : i + 2] in ('"', "\\", "$", "`", "\n"):
            self._append(text[i + 1 : i + 2].strip("\n"))
            self.i += 2
        elif text.startswith("$(", i):
            self._paren_substitution()
        elif text[i] == "`":
            self._backtick()
        else:
            self._append(text[i])
            self.i += 1

    def _redirect(self) -> None:
        text, i = self.text, self.i
        if self.in_word and "".join(self.cur).isdigit():
            self.cur.clear()
            self.in_word = False
        else:
            self._end_word()
        if text.startswith("<<<", i):
            self.i += 3
            self.herestring = True
        elif text.startswith("<<", i):
            self._heredoc_declaration()
        elif text[i + 1 : i + 2] == "(":
            self.i += 1
        else:
            self.i += 2 if text[i + 1 : i + 2] in ("&", "|", ">") else 1
            self.skip_word = True

    def _heredoc_declaration(self) -> None:
        text = self.text
        i = self.i + 2
        strip_tabs = text[i : i + 1] == "-"
        i += int(strip_tabs)
        while i < len(text) and text[i] in " \t":
            i += 1
        delim: list[str] = []
        quoted = False
        while i < len(text) and text[i] not in " \t\n;&|()<>":
            if text[i] in "'\"\\":
                quoted = True
            else:
                delim.append(text[i])
            i += 1
        self.pending.append(("".join(delim), strip_tabs, quoted))
        self.i = i

    def _read_heredocs(self) -> None:
        text = self.text
        for delim, strip_tabs, quoted in self.pending:
            body: list[str] = []
            while self.i < len(text):
                end = text.find("\n", self.i)
                end = len(text) if end < 0 else end
                line = text[self.i : end]
                self.i = end + 1
                if (line.lstrip("\t") if strip_tabs else line) == delim:
                    break
                body.append(line)
            self._attach_doc("\n".join(body), quoted)
        self.pending.clear()

    def _attach_doc(self, body: str, quoted: bool) -> None:
        if not quoted:
            self.commands.extend(_scan_substitutions(body))
        for k in range(self.line_start, len(self.commands)):
            cmd = self.commands[k]
            self.commands[k] = replace(cmd, docs=(*cmd.docs, body))


def parse(text: str) -> list[Command]:
    """Split a Bash command string into simple commands."""
    return Lexer(text).run()


# ------------------------------------------------------------- unwrapping

WRAPPERS: Final[Mapping[str, Wrapper]] = {
    "env": Wrapper(
        values=frozenset(("-u", "--unset", "-S", "--split-string")),
        chdir=frozenset(("-C", "--chdir")),
    ),
    "command": Wrapper(inert=frozenset(("-v", "-V"))),
    "builtin": Wrapper(),
    "exec": Wrapper(values=frozenset(("-a",))),
    "nohup": Wrapper(),
    "setsid": Wrapper(),
    "time": Wrapper(),
    "nice": Wrapper(values=frozenset(("-n", "--adjustment"))),
    "ionice": Wrapper(values=frozenset(("-c", "-n", "-p"))),
    "timeout": Wrapper(values=frozenset(("-s", "-k", "--signal")), positionals=1),
    "stdbuf": Wrapper(values=frozenset(("-i", "-o", "-e"))),
    "sudo": Wrapper(values=frozenset(("-u", "-g", "-h", "-p", "-r", "-t", "-C", "-D"))),
    "doas": Wrapper(values=frozenset(("-u", "-C"))),
    "xargs": Wrapper(
        values=frozenset(("-I", "-n", "-P", "-L", "-d", "-a", "-E", "-s", "-l"))
    ),
}


def _join_dir(cwd: str, target: str) -> str:
    return os.path.normpath(os.path.join(cwd, target))


def _skip_wrapper(
    spec: Wrapper, rest: Sequence[str], cwd: str
) -> tuple[tuple[str, ...], str]:
    """Drop a wrapper's own options; return the wrapped words and directory."""
    i = 0
    npos = spec.positionals
    while i < len(rest):
        word = rest[i]
        if word == "--":
            i += 1
            break
        if word.startswith("-") and len(word) > 1:
            if word in spec.inert:
                return (), cwd
            takes_value = word in spec.values or word in spec.chdir
            if word in spec.chdir and i + 1 < len(rest):
                cwd = _join_dir(cwd, rest[i + 1])
            if word.startswith("--chdir="):
                cwd = _join_dir(cwd, word.partition("=")[2])
            i += 2 if takes_value else 1
        elif ASSIGNMENT.match(word):
            i += 1
        elif npos > 0:
            npos -= 1
            i += 1
        else:
            break
    return tuple(rest[i:]), cwd


def _unwrap(words: Sequence[str], cwd: str) -> tuple[tuple[str, ...], str]:
    """Strip keywords, assignments, and wrappers from the front of a command."""
    out = tuple(words)
    while out:
        base = os.path.basename(out[0])
        if out[0] in RESERVED or ASSIGNMENT.match(out[0]):
            out = out[1:]
        elif base == "mise" and out[1:2] in (("exec",), ("x",)) and "--" in out:
            out = out[out.index("--") + 1 :]
        elif base in WRAPPERS:
            out, cwd = _skip_wrapper(WRAPPERS[base], out[1:], cwd)
        else:
            break
    return out, cwd


def _shell_inline(args: Sequence[str]) -> str | None:
    """Return the string after `-c` in a shell's arguments, if there is one."""
    i = 0
    while i < len(args):
        word = args[i]
        if word in ("-o", "+o", "-O", "+O"):
            i += 1
        elif word.startswith("-") and not word.startswith("--") and "c" in word[1:]:
            return args[i + 1] if i + 1 < len(args) else None
        elif not word.startswith("-"):
            return None
        i += 1
    return None


# ------------------------------------------------------------------ git


def _git(cwd: str, *args: str) -> str | None:
    """Run a read-only git command; return stripped stdout or None."""
    try:
        done = subprocess.run(
            ["git", "-C", cwd, *args],
            capture_output=True,
            text=True,
            timeout=GIT_TIMEOUT_S,
            check=False,
            env={**os.environ, "GIT_OPTIONAL_LOCKS": "0"},
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    out = done.stdout.strip()
    return out if done.returncode == 0 and out else None


def _default_branches(cwd: str, remote: str) -> frozenset[str]:
    ref = _git(cwd, "symbolic-ref", "--short", "-q", f"refs/remotes/{remote}/HEAD")
    if ref is None:
        return DEFAULT_BRANCHES
    return DEFAULT_BRANCHES | {ref.removeprefix(f"{remote}/")}


def _github_slug(cwd: str, remote: str) -> str | None:
    url = remote
    if not re.search(r"[/:]", remote):
        url = _git(cwd, "remote", "get-url", "--push", remote) or ""
    match = GITHUB_URL.search(url)
    return f"{match.group(1)}/{match.group(2)}" if match else None


def _visibility(slug: str) -> str:
    """Return public, private, or unknown for a GitHub repository."""
    forced = os.environ.get("GATE_VISIBILITY")
    if forced:
        return forced
    try:
        done = subprocess.run(
            ["gh", "repo", "view", slug, "--json", "visibility", "-q", ".visibility"],
            capture_output=True,
            text=True,
            timeout=GH_TIMEOUT_S,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return "unknown"
    answer = done.stdout.strip().upper() if done.returncode == 0 else ""
    if answer == "PUBLIC":
        return "public"
    return "private" if answer in ("PRIVATE", "INTERNAL") else "unknown"


def _in_quiet_hours() -> bool:
    stamp = os.environ.get("GATE_NOW")
    now = datetime.fromisoformat(stamp) if stamp else datetime.now(EASTERN)
    now = now.astimezone(EASTERN)
    return now.weekday() < 5 and QUIET_START <= now.hour < QUIET_END


def _quiet_findings(cwd: str, remote: str) -> list[Finding]:
    if not _in_quiet_hours():
        return []
    slug = _github_slug(cwd, remote)
    if slug is None:
        return []
    state = _visibility(slug)
    if state == "public":
        return [Finding("deny", QUIET_REASON)]
    return [Finding("ask", QUIET_UNKNOWN_REASON)] if state == "unknown" else []


@dataclass(frozen=True, slots=True)
class Push:
    """The parts of a push that the gate reads."""

    remote: str | None
    refspecs: tuple[str, ...]
    delete: bool
    all_refs: bool
    implicit_head: bool


def _short_cluster_has(word: str, letter: str) -> bool:
    return (
        word.startswith("-")
        and not word.startswith("--")
        and word[1:].isalpha()
        and letter in word[1:]
    )


def _parse_git_push(args: Sequence[str]) -> Push:
    delete = all_refs = False
    remote: str | None = None
    positional: list[str] = []
    skip = False
    for i, word in enumerate(args):
        if skip:
            skip = False
        elif word == "--repo" and i + 1 < len(args):
            remote, skip = args[i + 1], True
        elif word.startswith("--repo="):
            remote = word.partition("=")[2]
        elif word in ("-o", "--push-option", "--receive-pack", "--exec"):
            skip = True
        elif word in ("--delete", "-d") or _short_cluster_has(word, "d"):
            delete = True
        elif word in ("--all", "--mirror", "--branches"):
            all_refs = True
        elif not word.startswith("-"):
            positional.append(word)
    if remote is None and positional:
        remote = positional.pop(0)
    return Push(remote, tuple(positional), delete, all_refs, implicit_head=True)


def _destinations(push: Push, cwd: str) -> list[str]:
    """Return the branch names a push would update."""
    branch = _git(cwd, "symbolic-ref", "--short", "-q", "HEAD")
    names: list[str] = []
    for spec in push.refspecs:
        src, _, dst = spec.lstrip("+").partition(":")
        name = (dst or src).removeprefix("refs/heads/")
        names.append(branch or "" if name == "HEAD" else name)
    if not push.refspecs and push.implicit_head and branch:
        names.append(branch)
    return names


def _push_findings(push: Push, cwd: str) -> list[Finding]:
    found: list[Finding] = []
    deleting = push.delete or any(s.lstrip("+").startswith(":") for s in push.refspecs)
    if deleting:
        found.append(Finding("ask", DELETE_REASON))
    if push.all_refs:
        found.append(Finding("ask", ALL_REFS_REASON))
    remote = push.remote or "origin"
    if set(_destinations(push, cwd)) & _default_branches(cwd, remote):
        found.append(Finding("ask", DEFAULT_PUSH_REASON))
    return found + _quiet_findings(cwd, remote)


def _git_subcommand(args: Sequence[str], cwd: str) -> tuple[str, list[str], str]:
    """Skip git's global options; return the subcommand, its args, and the dir."""
    i = 0
    while i < len(args) and args[i].startswith("-"):
        if args[i] == "-C" and i + 1 < len(args):
            cwd = _join_dir(cwd, args[i + 1])
        takes = args[i] in ("-C", "-c", "--git-dir", "--work-tree", "--namespace")
        i += 2 if takes else 1
    return (args[i] if i < len(args) else ""), list(args[i + 1 :]), cwd


def _gate_git(args: Sequence[str], cwd: str) -> list[Finding]:
    sub, rest, cwd = _git_subcommand(args, cwd)
    if sub == "push":
        return _push_findings(_parse_git_push(rest), cwd)
    deletes_branch = sub == "branch" and any(
        w in ("--delete",) or _short_cluster_has(w, "d") or _short_cluster_has(w, "D")
        for w in rest
    )
    if deletes_branch or (sub == "update-ref" and "-d" in rest):
        return [Finding("ask", DELETE_REASON)]
    return []


# ------------------------------------------------------------------- jj

JJ_VALUE_OPTS: Final = frozenset(
    (
        "-R",
        "--repository",
        "--config",
        "--config-file",
        "--at-operation",
        "--at-op",
        "--color",
    )
)
JJ_BOOKMARK_OPTS: Final = frozenset(("-b", "--bookmark"))


def _jj_push_args(args: Sequence[str]) -> Push | None:
    """Return the push that `jj ... git push ARGS` makes, or None."""
    positional = _positionals(args, JJ_VALUE_OPTS, 2)
    if positional != ["git", "push"]:
        return None
    rest = list(args[list(args).index("push") + 1 :])
    names: list[str] = []
    remote: str | None = None
    for i, word in enumerate(rest):
        if word in JJ_BOOKMARK_OPTS and i + 1 < len(rest):
            names.append(rest[i + 1])
        elif word.startswith("--bookmark="):
            names.append(word.partition("=")[2])
        elif word == "--remote" and i + 1 < len(rest):
            remote = rest[i + 1]
        elif word.startswith("--remote="):
            remote = word.partition("=")[2]
    return Push(
        remote,
        tuple(names),
        delete="--deleted" in rest,
        all_refs="--all" in rest,
        implicit_head=False,
    )


def _gate_jj(args: Sequence[str], cwd: str) -> list[Finding]:
    push = _jj_push_args(args)
    return [] if push is None else _push_findings(push, cwd)


# ------------------------------------------------------------------- gh

GH_VALUE_OPTS: Final = frozenset(("-R", "--repo", "--hostname"))
API_FIELD_OPTS: Final = frozenset(("-f", "--raw-field", "-F", "--field", "--input"))
API_VALUE_OPTS: Final = API_FIELD_OPTS | frozenset(
    ("-X", "--method", "-H", "--header", "-q", "--jq", "-t", "--template")
    + ("--cache", "--hostname", "-p", "--preview")
)


def _positionals(
    args: Sequence[str], value_opts: frozenset[str], limit: int
) -> list[str]:
    """Return the first `limit` non-option words, skipping option values."""
    found: list[str] = []
    skip = False
    for word in args:
        if skip:
            skip = False
        elif word in value_opts:
            skip = True
        elif not word.startswith("-"):
            found.append(word)
            if len(found) == limit:
                break
    return found


def _api_method(args: Sequence[str]) -> str:
    method = ""
    has_fields = False
    for i, word in enumerate(args):
        nxt = args[i + 1] if i + 1 < len(args) else ""
        if word in ("-X", "--method"):
            method = nxt
        elif word.startswith("--method="):
            method = word.partition("=")[2]
        elif word.startswith("-X") and len(word) > 2:
            method = word[2:]
        has_fields = has_fields or word in API_FIELD_OPTS
    return (method or ("POST" if has_fields else "GET")).upper()


def _gate_gh_api(args: Sequence[str]) -> list[Finding]:
    endpoint = (_positionals(args, API_VALUE_OPTS, 1) or [""])[0]
    method = _api_method(args)
    mutation = endpoint == "graphql" and any(
        re.search(r"\bmutation\b", word, re.IGNORECASE) for word in args
    )
    risky = (
        method == "DELETE"
        or (method == "POST" and re.search(r"/(pulls|issues)/?$", endpoint))
        or (method == "PUT" and endpoint.endswith("/merge"))
        or mutation
    )
    return [Finding("ask", API_REASON)] if risky else []


def _gate_gh(args: Sequence[str], cwd: str) -> list[Finding]:
    del cwd
    pair = _positionals(args, GH_VALUE_OPTS, 2)
    if pair[:1] == ["api"]:
        return _gate_gh_api(args[list(args).index("api") + 1 :])
    reason = GH_ASK_REASON.get((pair[0], pair[1])) if len(pair) == 2 else None
    return [Finding("ask", reason)] if reason else []


# -------------------------------------------------------------- dispatch

TOOLS: Final[Mapping[str, Callable[[Sequence[str], str], list[Finding]]]] = {
    "gh": _gate_gh,
    "git": _gate_git,
    "jj": _gate_jj,
}


def analyze_text(text: str, cwd: str) -> list[Finding]:
    """Return every finding for every simple command in text."""
    found: list[Finding] = []
    for cmd in parse(text):
        found.extend(analyze_command(cmd, cwd))
    return found


def analyze_command(cmd: Command, cwd: str) -> list[Finding]:
    """Return the findings for one simple command."""
    words, cwd = _unwrap(cmd.words, cwd)
    if not words:
        return []
    name = os.path.basename(words[0])
    if name in NO_CD:
        return [Finding("deny", NO_CD_REASON)]
    if name in TOOLS:
        return TOOLS[name](words[1:], cwd)
    if name == "eval":
        return analyze_text(" ".join(words[1:]), cwd)
    if name in SHELLS:
        inline = _shell_inline(words[1:])
        texts = list(cmd.docs) if inline is None else [inline]
        return [f for text in texts for f in analyze_text(text, cwd)]
    return []


def decide(findings: Sequence[Finding]) -> dict[str, object] | None:
    """Fold findings into one PreToolUse decision; deny outranks ask."""
    if not findings:
        return None
    level = "deny" if any(f.level == "deny" for f in findings) else "ask"
    reasons = dict.fromkeys(f.reason for f in findings if f.level == level)
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": level,
            "permissionDecisionReason": "  ".join(reasons),
        }
    }


def main() -> int:
    """Read the hook input, print a decision if the command is gated."""
    try:
        data = json.load(sys.stdin)
    except ValueError:
        print("gate-bash: warning: malformed hook input; allowing", file=sys.stderr)
        return 0
    if not isinstance(data, dict) or data.get("tool_name") != "Bash":
        return 0
    tool_input = data.get("tool_input")
    command = tool_input.get("command") if isinstance(tool_input, dict) else None
    if not isinstance(command, str) or not command.strip():
        return 0
    cwd = data.get("cwd")
    cwd = cwd if isinstance(cwd, str) and cwd else os.getcwd()
    decision = decide(analyze_text(command, cwd))
    if decision is not None:
        print(json.dumps(decision))
    return 0


if __name__ == "__main__":
    sys.exit(main())
