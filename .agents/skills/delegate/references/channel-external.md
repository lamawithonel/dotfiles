# External channel

A model with no native channel in the active harness is reached by
shelling out to the other harness's CLI.

## Detect the harness first

| Signal (environment) | Harness |
| --- | --- |
| `CLAUDECODE=1` | Claude Code |
| `PI_CODING_AGENT` or `PI_SESSION_ID` | Pi |
| neither | bare shell: CLI shell-outs only |

| Active harness | External CLI |
| --- | --- |
| Claude Code | `pi` |
| Pi | `claude -p` |

The harness decides the channel, never the candidate set: every
registry model is a candidate in every harness, subject to the probe
below.

## Probe, never assume

Harness availability is per-host.  Before selecting a model whose
channel here is external, confirm the CLI exists:

```sh
command -v pi
command -v claude
```

A model whose only channel's CLI is missing on this host is
ineligible, and the work reroutes to a native model or back inline.
The registry is host-local and normally lists only reachable models;
the probe is the backstop for a stale registry.  On a Claude-Code-only
host the candidate set is just the registry's native Claude entries.

## Run the registry's command

The chosen model's `execution.<harness>` block in
`~/.agents/models.json` is authoritative.  Run its `command`
verbatim.  The shapes below orient; they are not templates to type
from memory.

```sh
# Claude Code -> a non-Claude model, via Pi
pi --model 'openrouter/<vendor>/<model-id>' -p "$(cat payload.md)" --no-session

# Claude Code -> a local llama.cpp model, via Pi
pi --model 'llama-cpp/<name>' -p "$(cat payload.md)" --no-session

# Pi -> a Claude model
claude -p --model <model-id> "$(cat payload.md)"
```

Note the `openrouter/` prefix Pi requires, and that deployment ids
differ per plan -- consumer, Enterprise, and Bedrock ids are not
interchangeable for the same model.  Only the host-local registry
knows which applies.

## Hygiene

- **Payload to a file.**  Write the brief to a temp file and
  substitute it with `"$(cat ...)"`.  Never inline a multi-line prompt
  into the command string.
- **`--no-session`** for fire-and-forget calls, so Pi's session store
  stays clean.
- **Ignore stderr unless stdout is empty.**  These CLIs write progress
  and warnings to stderr on successful runs.
- **Cap the memory.**  A shell-out is a heavy tool call and obeys the
  host's resource-control rules like any other.  Those caps are
  host-local; read them from the host's own instructions.
- **Distill the payload.**  Never paste parent context into `-p`.  See
  `brief.md` for the `<subagent_task>` envelope.

## What the worker inherits

Nothing.  A CLI shell-out is a fresh process with no conversation
history, no team, and no shared task list.  Whatever it needs is in
the payload file or it does not exist.

Standing host rules still bind the worker's actions -- an external
worker may not open pull requests, file issues, or take other gated
actions the coordinator itself is barred from.  Delegation is not a
way around a gate.
