# Role Classes: Full Rules

`~/.agents/AGENTS.md` holds the class table and reserved authority.
This file holds the rest: commissioning, the supervision tree,
lateral messages, lifecycle, Herdr layout, session names, and effort.

## Commissioning

- Every session the user starts is **independent**: it holds no
  position and works for the user directly.  It may dispatch workers,
  but never commissions coordinators.  The user may declare it an
  orchestrator at any time.
- Only the user declares the Deputy.  No agent holds the Deputy's
  authority until the user announces it to every orchestrator.  The
  Deputy may run in any harness, on any host.
- An orchestrator is the single top-level decision-maker for its
  domain: a project, a sub-project, a resource, an abstract idea, or
  anything that needs one owner to manage finite resources or keep a
  coherent story over time.  There is one per domain.  The domain need
  not match the repository the session started in.
- An orchestrator hands context-heavy work to coordinators.  It may
  dispatch workers for small, bounded jobs, and leaves workflows to
  coordinators.
- Only an orchestrator commissions coordinators, and every coordinator
  reports to the orchestrator that commissioned it.  Coordinators are
  peers; none commissions another.
- **Coordinator requests:** a coordinator that needs a new peer asks
  its orchestrator, which decides.  It may create the coordinator as
  requested; deny the request and tell the coordinator to do the work
  itself; or reshape it: reroute the work to an existing coordinator
  or to another orchestrator, create a coordinator with a different
  domain, split the request across several new coordinators, or
  combine these.
- A commission names the position (class and domain), the supervisor,
  the milestones, and the model and effort (see the `model-router`
  skill).  The class stays fixed.  The user may later reassign a
  coordinator to a different orchestrator.
- Commission agents that hold a position: coordinators.  The user
  declares orchestrators.  Dispatch workers: each gets one work
  package, a unit of the work breakdown structure, and ends at its
  receipt.

## Supervision tree

Every position reports to exactly one supervisor, so the positions
form a tree rooted at the user, the principal.  The Deputy acts for
the user and is not a separate branch.  Independent sessions sit
outside the tree.

- A report puts its supervisor's instructions first, after the user's
  and the Deputy's.
- **Depth limit:** at most three levels below the user: orchestrator,
  coordinator, and worker.  Workers dispatch no one.
- **Span of control:** the number of agents one supervisor runs at
  once.  It has no limit yet.  The 8-pane cap on a Herdr worker tab
  limits the tab, not the supervisor.
- **Escalation:** a decision outside an agent's domain or authority,
  or a failure it can't resolve, goes up the tree to its supervisor.

## Lateral messages

Messages along the tree are vertical; all others are lateral.

- Orchestrators message each other freely.
- **Functional authority:** a resource orchestrator's allocations and
  policies apply to every agent that uses its resources, wherever that
  agent sits in the tree.  `homelab-orchestrator` holds it for GPU,
  CPU, RAM, and disk.  Ask it for a reservation; what it grants is an
  allocation, and a time-limited allocation is a lease.
- **Brokered introduction:** first contact between a coordinator and
  an orchestrator other than its supervisor, in either direction, goes
  through the coordinator's orchestrator.  That orchestrator is the
  broker while the two agree on a protocol: what they may discuss,
  when, and how.  From then on the protocol governs, and the broker
  need not see each message.  Protocols keep each domain a bounded
  context, so scope creep stays out of every party's context.
- **Peer coordinators** under one orchestrator may message each other
  to exchange information and coordinate.  Anything that creates,
  moves, or reroutes work goes through the orchestrator.
- A worker messages only its dispatcher, through its receipt.

## Lifecycle

- **Decommission:** the supervisor or the user ends a position when
  its work is done.  The incumbent sends its supervisor a final
  report first.
- **Orphans:** decommissioning an orchestrator orphans its
  coordinators.  They re-parent to the user, who reassigns them to
  another orchestrator or decommissions them.  Until then they keep
  working and message only the user.
- **Succession:** a position outlasts its incumbent.  A session that
  takes over a position after a crash or context loss reads the
  journal, then resumes with the same supervisor, reports, and
  protocols.

## Herdr layout

Use Herdr when it is available (`HERDR_ENV=1`).  Without it, discrete
workers run as plain shell-outs.

| Agent | Placement | Name |
| --- | --- | --- |
The user places independent sessions and orchestrators; agents never
create Herdr workspaces.  An orchestrator's workspace is wherever the
user started it, and it may hold other top-level sessions too.

| Agent | Placement | Name |
| --- | --- | --- |
| Coordinator | its own new tab in its orchestrator's current workspace | tab `<domain>-co` |
| Discrete worker (`pi`, `claude`, and others) | a pane in a worker tab in its dispatcher's workspace | tab `<domain>[-<group>]-workers-<n>`, after the dispatcher's domain |

- Add a worker as a new pane in a matching worker tab that holds fewer
  than 8 worker panes.  Open a new tab when the tab is full, and for
  each set of related workers.
- `Agent` and `Workflow` workers run in-process, outside Herdr.
- The dispatcher closes a worker's pane after reading its receipt,
  and closes a worker tab once it is empty.  A failed worker's pane
  stays open for the user to inspect.

## Session names

Give each session a name `ListAgents` can address uniquely: an
orchestrator `<domain>-orchestrator`, and a coordinator `<domain>-co`,
matching its tab.  When two sessions share a name, address one as
`name [ref]`.

## Effort defaults

Orchestrators run at `xhigh`, coordinators at `high`, and workers at
`medium`.  The commissioner or dispatcher may change them; the
`model-router` skill holds the rules for when, and the model band for
each class.

## Worker channels

Coordinators prefer `Workflow` for short-lived Claude workers and
`Agent` for long-lived ones they will message again.  The user's
standing opt-in for this is in `~/.agents/AGENTS.md`.  Non-Claude
workers follow the channel rules in the `model-router` skill.
