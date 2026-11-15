# Delegation and VCS Slots

Load when the S5 flags are set: the target is agent-directed, the work
touches a repository, or both.  The rules behind each slot live in the
source documents below.  This file says which slot to fill and how.  It
never restates the rules, because they change often.

## Source documents (read the one a slot names; do not copy it)

| Slot family | Source |
| --- | --- |
| Position, supervisor, who may message whom | `~/.agents/AGENTS.md` ("Role Classes") and `~/.agents/ROLES.md` |
| Commissioning, depth limit, escalation, lateral messages, holds, gates, audit, lifecycle | `~/.agents/ROLES.md` |
| Model, effort, work breakdown structure, worker guards | `~/.agents/skills/model-router/SKILL.md` and its `references/effort.md` |
| Brief tags and envelopes | `~/.agents/skills/model-router/references/brief.md` |
| Shape, level, onboarding, isolation | `~/.agents/skills/vcs-workflow/SKILL.md` |
| Commit craft | the `git-commit` skill |
| PR and issue approval, public-repo quiet hours | `~/.agents/AGENTS.local.md` ("GitHub Usage Restrictions") |

Vocabulary stays fixed: position, incumbent, supervisor, reports to,
commission (orchestrators and coordinators), dispatch (workers),
dispatcher, work package, 100% rule, escalation, independent session,
Deputy, milestones, receipt, band, specialty tag, language group.

## Agent slots

Fill all five when the prompt assigns work to an agent.

| Slot | Fill with | Default when unstated |
| --- | --- | --- |
| Position | class plus domain (such as "coordinator, billing-tools"), or "independent session" for a session the user starts | worker for a dispatch; independent for a new session; ask for a commission |
| Supervisor | the one position it reports to; workers report to their dispatcher | the requester |
| Milestones and receipt | the checkpoints it reports at, and the receipt format it returns | `brief.md` receipt; no milestones for a worker |
| May message | read from the class row in `AGENTS.md`; name only the exceptions | the class row |
| Model and effort | the `score.py` pick (see Probes) | band `sonnet`, effort per `model-router`, for a worker |

Two placement rules:

- A **worker brief** never carries model or effort inside the brief.
  `model-router` names them at dispatch, so the rewrite adds a one-line
  dispatch note after the brief: `Dispatch: model=<model_param>,
  effort=<effort>`.
- A **commission** (orchestrator or coordinator, a new session) names
  the model and effort inside `<role>`, because the commission is what
  launches the session.

When the target will delegate (any commission, or a worker brief for
work that fans out), add one task that tells it to load `model-router`,
split the work into a work breakdown structure under the 100% rule, name
model and effort on every dispatch, and put the worker guards in every
worker brief.  Workers dispatch no one, so a worker brief never carries
this task.  Point to `ROLES.md` for the depth limit.  Coordinators
prefer `Workflow` for short-lived Claude workers and `Agent` for
long-lived ones.

Only an orchestrator commissions a coordinator.  A coordinator
commission also states: its orchestrator as supervisor, its own Herdr
tab in the orchestrator's workspace, that it asks the orchestrator for
any new peer coordinator instead of creating one, escalation of
out-of-domain requests to the orchestrator, brokered introduction for
first contact with any other orchestrator, an onboarding digest in
place of files to read in full, and any milestone where it must wait
instead of going on (`ROLES.md`, "Commissioning").  A prompt for a
session the user will start describes an independent session, never a
coordinator; only the user declares an orchestrator.

## Repository slots

Fill all four when the work reads or changes a repository.

| Slot | Fill with | Default when unstated |
| --- | --- | --- |
| Isolation | a jj workspace at level `standard` or `full`; never a git worktree; work in place at `oplog` or when the repo is not onboarded | in place, no worktree |
| Commit policy | atomic commits through `git-commit` after the verification gates pass, or leave changes uncommitted for the dispatcher | leave uncommitted |
| Push and PR ceiling | pushes, PRs, and issues need user approval; never merge; no activity on public repos during quiet hours | no push, no PR; report to the supervisor |
| Level and onboarding | the shape and level, and what to do when a git-only repo is undecided | follow `vcs-workflow` (ask once when interactive; headless reports `ONBOARD-PENDING` and uses plain git) |

Commit policy and the push and PR ceiling are stakes-override slots
(S3).  A `--quick` run takes the conservative default and flags it in
the Assumptions block.  The fixed rules (never merge, approval for PRs
and issues, quiet hours) go in the prompt as a one-line pointer to
`AGENTS.local.md`, not as a copy of its text.

A `worktree-shadowed` shape is a hard stop: the prompt says plain git,
no jj command, reads included.

## Probes (read-only; run only when the target runs on this host)

Run a probe only when the repo path is known.  Offer each result as the
interview default and mark it "(probed)".

```sh
# Model, effort, and family: one call per target.
python3 ~/.agents/skills/model-router/scripts/score.py --pick --band <bulk|haiku|sonnet|opus> [--tag T] [--lang L]
python3 ~/.agents/skills/model-router/scripts/score.py --pick --role <orchestrator|coordinator>

# VCS shape and level: both read the working directory, so use env -C.
env -C <repo> ~/.agents/skills/vcs-workflow/scripts/detect_shape.sh
env -C <repo> ~/.agents/skills/vcs-workflow/scripts/onboard.sh status
```

- From the `score.py` JSON read `pick.model_param` (or `model_ref` for
  Pi), `pick.effort`, `pick.channel`, `warnings`, and `degrade`.  Derive
  the target model family from `pick.id` instead of asking.  A null
  `pick` with a `degrade` means state the shortfall.  A `mythos` model
  runs only when the user names it; the pick never selects one.
- The `score.py` band comes from `model-router`'s caller rubric.  Choose
  the lowest band that gets it right the first time; a band is not a
  probe.  Pick the band, then probe.
- `detect_shape.sh` prints one shape (exit 0, 2, or 3).
  `onboard.sh status` prints `ONBOARD-STATUS shape=... onboarding=...
  level=...`.  They are the entry gate that `vcs-workflow` runs before
  any jj command.
- Never run `onboard.sh apply`, `record`, or `reset`, `preflight.sh`, or
  any `jj` or `git` command that writes.  Converting a repo is the user's
  decision, made through the target's own onboarding questions.
- The probe describes this host at this moment.  A prompt for another
  host or a later session carries the instruction form instead.

## Instruct the target (no probe possible)

Paste the matching block as the first task of the brief, adjusting the
wording to the target.

Model and effort (target will delegate):

```text
Before you dispatch anyone, load the model-router skill.  Split the work
into a work breakdown structure under the 100% rule.  For every dispatch,
run score.py --pick for the band or role, then name the model and the
effort.  Put the worker guards in every worker brief.
```

VCS shape and level (repo path known to the target):

```text
At start, run detect_shape.sh and onboard.sh status from vcs-workflow, by
absolute path, inside the repository.  On worktree-shadowed, use plain
git only.  On an undecided git-only repo, ask the user the onboarding
questions once when you can; otherwise report ONBOARD-PENDING and use
plain git.  Isolate in a jj workspace only at level standard or full,
never a git worktree.
```

## PICCO to brief tags

PICCO still drives the diagnosis.  Only the emitted form changes.

| PICCO slot | Brief tag |
| --- | --- |
| Persona | `<persona>` (four quadrants; `brief.md` defines them) |
| Role (not a PICCO slot; the position and its scope) | `<role>`: position, supervisor, who it may message, milestones |
| Instructions | `<goal>` (one sentence) and `<task_list>` (the work packages) |
| Context | `<context>`: absolute paths, revisions, shape and level, source-document pointers |
| Constraints | `<constraints priority="MUST">`: worker guards (workers only), scope fence, isolation, commit policy, push and PR ceiling |
| Output | `<return>`: receipt format plus one runnable verification command (rubric dimensions 2 and 9) |

Use the `<subagent_task>` envelope when the target runs through a CLI
shell-out (`brief.md`, "External CLI Envelope").  Keep a brief under
2,000 tokens; pass paths, not file dumps.  A commission is longer by
nature, but it points to `ROLES.md` instead of copying it.
