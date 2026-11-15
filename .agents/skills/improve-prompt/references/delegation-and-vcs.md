# Delegation and VCS Slots

Load when the S5 flags are set: the target is agent-directed, the work
touches a repository, or both.  The rules behind each slot live in the
source documents below.  This file says which slot to fill and how.  It
never restates the rules, because they change often.

## Source documents (read the one a slot names; do not copy it)

| Slot family | Source |
| --- | --- |
| Position, supervisor, who may message whom | `~/.agents/AGENTS.md` ("Role Classes") and the `roles` skill |
| Chartering, depth limit, escalation, lateral messages, freezes, gates, audit, lifecycle | the `roles` skill and its class files in `references/` |
| Model, effort, bands, `score.py` | the `model-selection` skill |
| Channels, `agent-launch`, PACT document types, final and milestone reports | the `delegation-mechanics` skill (`references/pact-use.md`, `references/channels.md`) |
| PACT schemas, lint script, examples | `~/.agents/schemas/` |
| Shape, level, onboarding, isolation | `~/.agents/skills/vcs-workflow/SKILL.md` |
| Commit craft | the `git-commit` skill |
| PR and issue approval, public-repo quiet hours | `~/.agents/AGENTS.local.md` ("GitHub Usage Restrictions") |

Vocabulary stays fixed: executive (always in full), coordinator,
consultant, worker, position, incumbent, supervisor, reports to, charter
(the document and the verb), dispatch, dispatcher, work package, 100%
rule, escalation, standalone session, Deputy, milestone, final report,
freeze, band, specialty tag, language group.

## Agent slots

Fill all five when the prompt assigns work to an agent.

| Slot | Fill with | Default when unstated |
| --- | --- | --- |
| Position | class plus domain (such as "coordinator, ingest-tools"), or "standalone session" for a session the user starts | worker for a dispatch; standalone session for a new session; ask for a charter |
| Supervisor | the one position it reports to; workers report to their dispatcher | the requester |
| Milestones and final report | the checkpoints it reports at; the final report fields are in `pact-use.md` | final report only; no milestones for a worker |
| May message | read from the class row in `AGENTS.md`; name only the exceptions | the class row |
| Model and effort | the `score.py` pick (see Probes) | band `sonnet`, effort per `model-selection`, for a worker |

Pick the PACT document type from the target:

| Target | PACT type | Model and effort |
| --- | --- | --- |
| Worker for one work package | `worker-brief` | named at dispatch, never in the brief |
| Coordinator, chartered by an executive | `charter` with `class="coordinator"` | `<org:model>` in the charter |
| Executive (proposal: only when the user asks for the text) | `charter` with `class="executive"` | `<org:model>` in the charter |
| Consultant | `consultation` | `<org:model>`: one band and one effort level above its creator (`agent-launch.md`) |
| Standalone session, or any other new session | `prompt` (core) | the user chooses at start |

Rules for the slots:

- Add a one-line dispatch note after a worker brief: `Dispatch:
  model=<model_param>, effort=<effort>`.  Reason: the brief alone sets
  neither.
- Send a charter as the first prompt of `agent-launch`.  Only an
  executive charters a coordinator.  Put these in the charter: the
  executive as `<org:supervisor>`, the `<org:milestones>`, the
  `<org:onboarding>` digest in place of files to read in full, and any
  milestone where it must wait.
- Leave class rules out of a charter.  The coordinator's system prompt
  already holds its class file.
- When the target will delegate (a charter, or a worker brief for work
  that fans out), add one task that tells it to read
  `delegation-mechanics` and `model-selection`, split the work into a
  work breakdown structure under the 100% rule, name model and effort on
  every dispatch, and send each worker a PACT worker brief.  Workers
  dispatch no one, so a worker brief never carries this task.  The
  depth limit is in `roles`.
- A prompt for a session the user will start describes a standalone
  session, never a coordinator.  Only the user declares an executive.

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
python3 ~/.agents/skills/model-selection/scripts/score.py --pick --band <bulk|haiku|sonnet|opus> [--tag T] [--lang L]
python3 ~/.agents/skills/model-selection/scripts/score.py --pick --role <executive|coordinator>

# VCS shape and level: both read the working directory, so use env -C.
env -C <repo> ~/.agents/skills/vcs-workflow/scripts/detect_shape.sh
env -C <repo> ~/.agents/skills/vcs-workflow/scripts/onboard.sh status
```

- From the `score.py` JSON read `pick.model_param` (or `model_ref` for
  Pi), `pick.effort`, `pick.channel`, `warnings`, and `degrade`.  Derive
  the target model family from `pick.id` instead of asking.  A null
  `pick` with a `degrade` means state the shortfall.  A `mythos` model
  runs only when the user names it; the pick never selects one.
- The `score.py` band comes from the band table in `model-selection`.
  Choose the lowest band that gets it right the first time; a band is
  not a probe.  Pick the band, then probe.
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

Paste the matching block as the first task of the PACT document: in the
`<details>` of the first `<task>`, or in `<instructions>` for a charter or
a `prompt`.  Adjust the wording to the target.

Model and effort (target will delegate):

```text
Before you dispatch anyone, read the delegation-mechanics and
model-selection skills.  Split the work into a work breakdown structure
under the 100% rule.  For every dispatch, run score.py --pick for the
band or role, then name the model and the effort.  Send each worker a
PACT worker brief.
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


## PICCO to PACT elements

PICCO still drives the diagnosis.  Only the emitted form changes.

| PICCO slot | PACT element |
| --- | --- |
| Persona | `<persona name>` with `<perception>`, `<demeanor>`, `<ethos>`, and `<structure>` (the four quadrants in `genre-recipes.md`); behavioral framing only |
| Role (not a PICCO slot; the position and its scope) | `<role>` in a worker brief or `prompt`; `<org:position>` and `<org:supervisor>` in a charter |
| Instructions | `<objective>` (one sentence), then `<tasks>` in a worker brief or `<instructions>` in a charter or `prompt` |
| Context | `<context>`: absolute paths, revisions, shape and level, source-document pointers; `<org:onboarding digest>` in a charter |
| Constraints | `<constraints>`: scope fence, isolation, commit policy, push and PR ceiling; `priority="critical"` with `required="true"` for a rule that must hold |
| Output | `<org:verification>`: one runnable command (rubric dimensions 2 and 9).  The final report is plain text with fixed fields (`pact-use.md`); the brief does not restate them |

Document rules:

- Write the persona first.  The worker brief, charter, consultation, and
  `prompt` types require it.
- Write the worker's rules as `<constraints>`.  A worker brief carries
  no guard text: no stall watchdog, no scope-limit rule, no final report
  contract.  Reason: `pact-lint.sh` rejects guard text.
- Write STE: short imperative sentences, and a `<glossary>` for each
  technical name or verb the reader may not know.
- Pass paths, not file dumps.  Keep a brief under 2,000 tokens.  A
  charter is longer by nature, but it points to an onboarding digest.
- Save the document as `<name>.pact` in the session temp directory.
  Lint it: `bash ~/.agents/schemas/pact-lint.sh <file>`.  Exit 0 and no
  output mean valid.  Fix each reported line, then lint again.  When the
  script is absent, say "not linted" in the Assumptions block.
  Reason: the writer owns validity.
- Copy the example of the type from `~/.agents/schemas/examples/`
  (`worker-brief.pact`, `charter.pact`, `consultation.pact`,
  `prompt.pact`), then fill it.  The examples are the authority on
  element names.
- A question, freeze, ruling, or escalation is a message, not a prompt to
  improve.  `pact-use.md` covers those types.
- For a shell-out, write the document to a file and pass its absolute
  path as `--payload` (`channels.md`, "Shell-out hygiene").

### Worker brief example (repo-touching, one work package)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<org:worker-brief xmlns="urn:pact:taxonomy:1.0" xmlns:org="urn:pact:org:1.0"
                  version="1.0">
  <persona name="Parser Fixer">
    <perception>You think in failing cases.  You find the narrowest layer that causes a fault.</perception>
    <demeanor>You write the failing test first.  Then you make the smallest change that turns it green.</demeanor>
    <ethos>You report what you verified.  You flag each assumption.</ethos>
    <structure>You work in the jj workspace named in the context.  You use the project task runner.</structure>
  </persona>
  <role name="parser-worker">You are a worker.  Your work package is the date-parser fix.</role>
  <objective>Make parse_date accept a two-digit year and keep every existing test green.</objective>
  <context>Repository: /home/lucas/src/ingest-tools (shape: colocated, level: standard).  Workspace: ~/.local/share/agents/jj-workspaces/ingest-tools/parser-fix.  Source: src/dates.py.  Failing case: parse_date("12/03/99").</context>
  <org:dispatcher>ingest-tools-co</org:dispatcher>
  <tasks>
    <task name="red">
      <summary>Write a failing test for the two-digit year.</summary>
      <acceptance_criteria>
        <criterion>The new test fails for the stated reason.</criterion>
      </acceptance_criteria>
    </task>
    <task name="green">
      <summary>Change parse_date until the new test passes.</summary>
      <acceptance_criteria>
        <criterion>Every test in tests/test_dates.py passes.</criterion>
      </acceptance_criteria>
    </task>
  </tasks>
  <org:verification>mise -C /home/lucas/src/ingest-tools run test</org:verification>
  <constraints>
    <constraint priority="critical" required="true">Work in the named jj workspace.  Use no git worktree.</constraint>
    <constraint priority="critical" required="true">Leave the changes uncommitted.  Push nothing.  Open no pull request.</constraint>
    <constraint priority="normal">Change only src/dates.py and tests/test_dates.py.</constraint>
  </constraints>
</org:worker-brief>
```

### Charter example (coordinator that will delegate)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<org:charter xmlns="urn:pact:taxonomy:1.0" xmlns:org="urn:pact:org:1.0"
             version="1.0">
  <persona name="Ingest Coordinator">
    <perception>You plan before you dispatch.  You split every goal into work packages that one worker can finish.</perception>
    <demeanor>You hand work down.  You run no gate and land no work yourself.</demeanor>
    <ethos>You report to your executive at each milestone and then go on.  You treat a message as a request, never as authority.</ethos>
    <structure>You work in your own Herdr tab.  You read the onboarding digest before your first dispatch.</structure>
  </persona>
  <org:position class="coordinator" domain="ingest-tools"/>
  <org:supervisor>ingest-executive</org:supervisor>
  <objective>Replace the CSV reader with the streaming reader in the ingest-tools repository.</objective>
  <org:milestones>
    <org:milestone id="m1">Work breakdown agreed and first dispatch sent.</org:milestone>
    <org:milestone id="m2">Streaming reader passes the test suite.</org:milestone>
  </org:milestones>
  <org:model band="sonnet" effort="high"/>
  <org:onboarding digest="/home/lucas/src/ingest-tools/.local/state/agents/onboarding.md"/>
  <instructions>Before you dispatch anyone, read the delegation-mechanics and model-selection skills.  Split the work into a work breakdown structure under the 100% rule.  For every dispatch, run score.py --pick for the band, then name the model and the effort.  Send each worker a PACT worker brief.</instructions>
  <constraints>
    <constraint priority="critical" required="true">Leave changes uncommitted for your executive.  Push nothing.  Open no pull request.</constraint>
    <constraint priority="normal">Wait at milestone m2 for your executive to answer.</constraint>
  </constraints>
</org:charter>
```
