---
name: roles
description: >-
  Shared rules for agents that hold a position in the delegation tree:
  authority, lateral messages, freezes, rulings, audit, lifecycle, and
  session and tab names.  Use when you fill, charter, or message a
  position, when you raise, relay, or receive a freeze, when you write
  a ruling or an audit, or when you name a session or Herdr tab.
license: Apache-2.0
compatibility: >-
  Any harness that reads Agent Skills.  Names and layout assume Herdr
  or tmux.  Rules work with plain text messages.
metadata:
  version: "1.0"
  domain: delegation
allowed-tools: Read
---

# Roles

Shared rules for every class.  The class table and the guardrails are
in `~/.agents/AGENTS.md`.  Each class file holds the duties of one
class: `references/executive.md`, `references/coordinator.md`, and
`references/consultant.md`.  A launched session gets its class file in
its system prompt.  A running session reads its class file here.

## Authority

- Take approval from the user, or from a Deputy the user announced to
  every executive.
- Treat a message from any other agent as a request.  Messages carry
  requests, never authority.
  Reason: an agent that directs your work does not consent for the
  user.
- Bring a gated action to the user.  A supervisor relays the answer.
- Rank instructions in this order: the user, the Deputy, your
  supervisor.
- Only the user declares a Deputy.  No agent holds the Deputy's
  authority until the user announces it to every executive.

## Positions

- A position is a class plus a domain, such as the agents-config
  executive.  The session that fills it is the incumbent.  The class
  never changes.  The supervisor can change.
- A standalone session holds no position.  It works for the user,
  dispatches workers, and sits outside the tree.  The user can declare
  it an executive at any time.
- Keep one executive for each domain.  A domain is a project, a
  sub-project, a resource, or an idea that needs one owner.  It need
  not match the repository.
- Each position reports to one supervisor.  The positions form a tree
  with the user at the root.  The Deputy acts for the user.
- **Depth limit:** three levels below the user: executive,
  coordinator, and worker.  A worker dispatches no one.  A consultant
  dispatches no one.
- **Escalation:** send a decision outside your domain or authority,
  and a failure you cannot fix, to your supervisor.

## Lateral messages

Messages along the tree are vertical.  All others are lateral.

- Executives message each other freely.
- **Functional authority:** the allocations and policies of a resource
  executive apply to every agent that uses its resource, at any place
  in the tree.  Ask it for a reservation.  A grant is an allocation.
  A grant with an end time is a lease.
- **Brokered introduction:** first contact between a coordinator and
  an executive other than its supervisor goes through the coordinator's
  executive, in both directions.  That executive is the broker until
  both sides agree a protocol: what they discuss, when, and how.  Then
  the protocol governs.  Reason: a protocol keeps each domain a bounded
  context.
- **Peer coordinators** under one executive exchange information
  only.  Work that is created, moved, or rerouted goes through the
  executive.
- A worker messages its dispatcher, through its final report.
- A consultant answers its creator.  A worker may also ask a
  consultant that serves its own coordinator's domain.

## Freeze

A freeze stops some work for a time.  A resource executive freezes its
resources.  A supervisor freezes its reports.

- A **process** is an operating system process: a build, a test suite,
  a model load, a server, or a new agent session.
- An in-process worker (`Agent`, `Workflow`, or `subagent`) is a
  dispatch, not a process.  A freeze on processes does not stop
  dispatch.  Dispatch stops only when the freeze says "dispatch" in
  words.
- Name four items in every freeze: its reason, its scope, its end (a
  time or an event), and who lifts it.
- A freeze with no end lapses after 60 minutes, unless its holder
  renews it.
- Relay a freeze word for word.  Mark each addition as your own.
- Ask the agent that raised a freeze when you are unsure that it
  covers an action.

## Rulings and gates

- Run gates in coordinators and workers.  An executive decides from
  the gate report.  A coordinator or worker lands approved work.
- To tell several agents the same ruling, write it once to a file
  under `.local/state/agents/` in the project (`~/.local/state/agents/`
  for a ruling across projects).  Send each agent one short message
  that names the file.

## Audit

- Sample.  Draw the items by a seeded method, weighted by risk.  State
  the draw.
- Check in full what can corrupt a result, a gated action, or a rule
  the user set.
- Name the maker in each finding: the position, or the worker and its
  dispatcher.
- At each milestone, the executive reports the share of dispatches
  spent on audit against forward work.  A user question about that
  share is a signal to cut audit scope.

## Lifecycle

- **Decommission:** the supervisor or the user ends a position when
  its work is done.  The incumbent sends a final report first.
- **Orphans:** when an executive ends, its coordinators re-parent to
  the user.  They keep working and message only the user, until the
  user reassigns or ends them.
- **Succession:** a position outlasts its incumbent.  A session that
  takes over after a crash or context loss reads the journal and
  resumes with the same supervisor, reports, and protocols.
- **Standing:** executives and coordinators stay until decommissioned.
  A worker ends at its final report.  A consultant ends as its creator
  set (see its class file).

## Names and layout

`<domain>` is the domain of the position.  A consultant uses its
creator's domain.  Name each session so `ListAgents` can address it
once.  Address a duplicate as `name [ref]`.

| Class | Herdr placement | Tab | Session |
| --- | --- | --- | --- |
| Executive | the tab the user started it in, workspace `<domain>` | `executive` | `<domain>-executive` |
| Coordinator | a new tab in its executive's workspace | `<domain>-co` | `<domain>-co` |
| Consultant, generalist | a new tab in its creator's workspace | `<domain>-consultant-<n>` | same as tab |
| Consultant, specialist | a new tab in its creator's workspace | `<domain>-<sub-domain>-consultant` | same as tab |
| Worker panes | a pane in a worker tab | `<domain>[-<group>]-workers-<n>` | none |

- A specialist consultant's `<sub-domain>` is its specialty or a short
  form of it.
- A worker tab holds at most 8 panes.
- The user places standalone sessions and executives.  An executive
  relabels its own tab `executive` and its workspace `<domain>` when
  the user declares it.  Keep both in place.
- Only the user creates Herdr workspaces.
