# PACT Use and Reports

Use this file to write or read an agent-to-agent instruction, a final
report, or a milestone report.

PACT is the XML format for agent-to-agent instructions.  Its files are
in `~/.agents/schemas/`: `pact-1.0.xsd` (core), `pact-org` (the profile
with the types below), `pact-lint.sh` (the lint script), and `examples/`.
Copy the example of the type you write, then fill it.  PACT is a draft.
The examples are the authority on element names.

## Document types

| Type | Sender to receiver | Use it to | Persona |
| --- | --- | --- | --- |
| charter | executive to coordinator | found a coordinator position | optional |
| worker brief | dispatcher to worker | give one work package | optional |
| consultation | creator to consultant | state the consultant's domain and purpose | optional |
| question | any asker to a consultant | ask one question | none |
| freeze | supervisor, or a resource executive, to its reports | stop some work for a time | none |
| ruling | executive to several agents | tell all of them one decision | none |
| escalation | any agent to its supervisor | raise a decision or failure above your authority | none |

- Charter: send it as the first prompt (`agent-launch --first-prompt`).
  Name the position, the supervisor, the milestones, the model, and the
  effort.  Point to a short onboarding digest.  Never ask the coordinator
  to read files in full.
- Worker brief: send it as the dispatch prompt of the channel
  (`channels.md`).  It carries the worker's rules, because a worker has
  no class file.  The dispatcher may name the fields it wants back in
  `output`, for that package only.
- Consultation: send it as the consultant's first prompt.
- Question: type it with `herdr agent prompt` (`consultant-questions.md`).
- Freeze: name its reason, scope, end, and who lifts it.  Say "dispatch"
  in the scope only when it covers dispatch.  Relay a freeze word for
  word (`roles` skill).  Name the freeze file in the relay source, and run
  `pact-lint.sh` to check the quote against it.
- Ruling: write the ruling once to a file under `.local/state/agents/`.
  Send each receiver one short message that names the file.
- Escalation: state the decision or failure, what you tried, and what
  you need.

## Write a PACT document

- Start from the example of the type.
- Add a `<persona>` only for creative work where a distinctive voice
  or divergent output matters: art, design, creative marketing, and
  voice-driven writing.  A persona is free-form text, and its child
  elements are free too.  Omit it for analysis, engineering, review,
  research, coordination, and mechanical work, and state the role in
  the `<role>` element instead.  This rule is provisional until the
  persona research reports.
- Write in STE: short imperative sentences.  Declare technical names
  and verbs in the glossary (`glossary` and `term`).
- Write `priority="critical"` with `required="true"` for a rule that
  must hold.  Never write `priority="MUST"`.
- Give paths, not file dumps.  Give one runnable verification command.
- Keep a brief under 2,000 tokens.  Put no raw conversation history in
  it.
- Cover four fields in a worker brief: objective, output format, tool
  and source guidance, and boundaries.
- Give each file one writer.  Keep tightly coupled changes in one
  worker.
- Give a research worker read-only tools, one named output file as its
  only allowed write, and a cap on its summary.  It returns the summary
  with the path.
- Name the model and effort at dispatch.  The brief alone does not set
  them.
- At `xhigh`, `max`, or `low` effort, copy the matching worker line
  (rules 7 and 8 of the `model-selection` `references/effort.md`) into
  the brief.
- Lint before you send: `~/.agents/schemas/pact-lint.sh <file>`.  The lint runs
  `xmllint` and checks the required elements of the type.
  Reason: the writer owns validity.  A receiver never rejects a message
  that fails validation.  It reads what it can.
- Name the file `*.pact`.  The MIME type is `application/pact+xml` or
  `application/prs.pact+xml`.  A PACT body inside a file whose harness
  needs another extension keeps that extension (an agent definition
  `.md`).

## Reports

Reports are plain text with fixed fields.  They are not PACT.  Workflow
agents return JSON that follows their schema.

### Final report

A worker, coordinator, or executive sends it when its work package or
position ends.  Send only this, with `file:line` references.

- Status: `SUCCESS`, `BLOCKED`, `PARTIAL`, or `REFUSED (<category>)`.
  - `PARTIAL`: list the items declined on policy grounds.
  - `REFUSED (<category>)`: list the declined items.  The category is
    `cyber`, `bio`, `medical`, or `other`.
  - On `PARTIAL` or `REFUSED`, the receiver follows the refusal rules of
    the `model-selection` skill.
- Verification command and its exit code, with the counts of tests
  passed and failed.
- Modified or created files, with `file:line` references.
- Summary of decisions.
- A coordinator or executive adds its open items and its protocols.

### Milestone report

A coordinator sends it to its executive.  An executive sends it to the
user.  After it, the sender goes on to its next stage.

- Position: class and domain.
- Milestone: its name from the charter.
- State: `on track`, `blocked`, or `done`.
- Done since the last report, with paths.
- Next stage.
- Decisions needed, or `none`.
- Audit share: the share of dispatches spent on audit against forward
  work.  The executive reports it.
- Level: the level of the ladder, when it dropped (`degradation.md`).
