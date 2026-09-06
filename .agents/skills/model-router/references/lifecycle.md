# Lifecycle of running delegations

Two verbs, and they are not interchangeable.

**Pause** -- work is expected to continue later in this session or a
successor.  Stop consuming the exhausted resource, flush state, and
leave the resumable things resumable.

**Halt** -- this coordinator is ending.  Stop cleanly in an order that
loses nothing, and hand off to whatever picks up.

Both begin the same way: the moment a warning arrives, stop launching
new delegated work.  Neither is a reason to keep working until the
cutoff.

## What survives

| Channel | Survives | How it comes back |
| --- | --- | --- |
| foreground subagent | no | re-dispatch from the brief |
| background subagent | until the session ends | completion notification; `SendMessage` by name or id resumes it from its transcript |
| workflow | yes | relaunch with `resumeFromRunId`; the unchanged prefix of `agent()` calls returns from the run cache and only the changed call onward re-runs |
| teammate | **no** | nothing.  `/resume` and `/rewind` do not restore in-process teammates, and the lead will message ghosts.  Journal a teammate's work or lose it |
| external shell-out | only if detached | re-run the command; the payload file is the durable input |
| detached host process | yes | adopt it from the journal -- task ids, container names, log paths -- instead of restarting it |
| shared task list | yes | local, never uploaded, survives a resumed session |

The brief is the durable form of a foreground worker.  Keep it, and
re-dispatching is free.

## Pausing

1. Stop the API-consuming workers: `TaskStop` for tracked tasks, a
   shutdown request for a teammate, an explicit stop for a running
   workflow.  An interrupted workflow resumes from its run cache
   later; that is the whole reason to stop it deliberately rather than
   let it die mid-flight.
2. Flush durable state with an explicit NEXT action written down.
3. Launch any pending long host-side operation -- builds, renders,
   container jobs -- so the wait costs no wall-clock time.  Host
   processes outlive the session and keep accumulating output.
4. Make no further API-consuming moves.

In-band recovery consumes the same quota that ran out, so a paused
coordinator cannot poll, heartbeat, or schedule its way back.  Size a
single sleep to return after the reset, and let it re-invoke the
session.

## Halting

Order matters:

1. Monitors first.
2. Then workflows that hold resumable state, so the run cache is
   written.
3. Leave detached background jobs running, and record log and status
   pointers for them.
4. Commit or annotate the working tree.
5. Write the handoff.
6. Stop.

Handoff-first outranks everything else, including the sleep.  A
handoff must be self-contained: a zero-context successor -- a
different model, a fresh window -- continues from that file alone.
Current state, what is done, what is next, standing constraints, and
where the other artifacts live.  Budget real time for writing it.

## Crash-only

A pause and a crash differ only in warning.  Design so they are the
same event:

- Progress truth lives on disk -- commits, task-list state, a journal
  file -- never only in conversation memory.
- No work unit holds unjournaled critical state longer than one turn.
- Journal each turn that edits or deletes a project file, and journal
  version-control work by pointer (op-id, change-id) rather than by
  copying the diff.

A delegation that has been briefed, journaled, and given a durable
receipt target is already crash-safe.  One that lives only in the
coordinator's context is not.

## Triggers

The conditions that start a pause or a halt -- rate-limit windows,
model cutoff dates, warning and hard-halt timers -- are host-local and
schedule-specific.  They live in the host's own instructions, not
here.  This file owns only what happens to delegated work once one of
them fires.
