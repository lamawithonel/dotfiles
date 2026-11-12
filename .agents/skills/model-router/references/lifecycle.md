# Lifecycle of Running Delegations

Managing active delegations requires strict distinction between two
primary operations: **Pause** and **Halt**.

- **Pause:** Halts active resource consumption while maintaining
  intermediate execution state so work can resume later in the current
  session or a future session.
- **Halt:** Concludes the coordinator session permanently, terminating
  or detaching workers and recording a clean handoff artifact.

Whenever quota exhaustion, rate limits, or context cutoff warnings appear,
stop launching new tasks immediately.

---

## State Persistence by Channel

| Channel | Survives Session Restart | Recovery Mechanism |
| --- | --- | --- |
| Foreground child (`Agent`, `subagent`) | No | Re-dispatch from the persisted brief |
| Detached background child | Yes (until process termination) | Notification on completion or reconnect via `SendMessage` / `subagent_supervisor` |
| Multi-step workflow | Yes | Re-launch using `resumeFromRunId`; unchanged stages return cached results |
| Claude teammate | **No** | In-process teammates do not survive `/resume`; intermediate work must be recorded in the project journal |
| Herdr pane worker | Yes (pane stays open) | Read the receipt file the brief names; a failed worker's pane stays open |
| External CLI shell-out | Yes (if executed as background daemon) | Adopt via process ID and journal logs; payload file serves as the input record |
| Shared task list | Yes | Persisted locally across session restarts per `cleanupPeriodDays` |

---

## Procedure: Pausing Delegations

1. **Stop API-consuming workers:**
   - Claude Code: Invoke `TaskStop` on active tasks; signal teammate
     shutdown; pause running workflows.
   - Pi: Signal child tasks through `subagent_supervisor` or stop
     tracked workflow runs.
2. **Preserve run caches:**
   Ensure workflow scripts flush execution milestones to disk so
   subsequent runs reuse the cached prefix.
3. **Flush state to the project journal:**
   Document pending operations and the explicit `NEXT` action in
   `.local/state/agents/journal/<YYYY-MM-DD>.md`.
4. **Trigger detached background tasks:**
   Initiate compilation, rendering, or test runs that execute
   out-of-process so elapsed wall-clock time is utilized productively.
5. **Cease API calls:**
   Do not poll, send keep-alive messages, or run busy loops against
   exhausted endpoints.

---

## Procedure: Halting Delegations

When terminating a coordinator run, execute the following sequence in
order:

1. **Stop observers and monitors:** Terminate background log readers and
   monitoring loops.
2. **Flush stateful workflows:** Allow active workflow checkpoints to
   write to disk.
3. **Record pointers for detached jobs:** Capture process IDs, container
   names, and output log locations for any continuing host tasks.
4. **Commit repository changes:** Commit or snapshot the working tree
   to ensure all modifications are indexed.
5. **Author a self-contained handoff document:**
   Record completed milestones, pending steps, standing constraints, and
   file paths.  A replacement agent with an empty context window must be
   able to resume work using this document alone.
6. **Terminate execution cleanly.**

---

## Crash-Only Architecture

Treat unexpected session interruptions identically to deliberate pauses:

- Maintain authoritative state on disk (version control commits, task
  lists, and journal entries) rather than relying on session memory.
- Log every turn that modifies project files.
- Index version control operations by change pointer or revision
  identifier rather than duplicating large diffs into memory.
