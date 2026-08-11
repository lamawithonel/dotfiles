# Discover Claude Models: Tiered Roster Detection

Determines which Claude models THIS host's Claude Code deployment can
dispatch, without any model-listing API.  Needed because private
deployments (Enterprise, Bedrock) are OAuth2-locked, use their own
model ids, run older CLI versions, and Claude Code has no
`--list-models`.

Three layers; lower layers only propose, the probe decides:

## Layer 1: Seed (declared)

Start from ids already in `~/.agents/models.json` (native claude-code
entries) plus anything the user names.  Ground truth as of the last
update; zero fragility.

## Layer 2: Cache Read (best-effort, undocumented)

`~/.claude.json` caches the `/model` picker and access data.
Observed keys (CLI 2.1.x; treat every key as optional -- older
versions differ, absent keys just yield nothing):

```sh
jq -r '
    (.additionalModelOptionsCache[]?.value // empty),
    (.modelAccessCache[]? // empty),
    (.orgModelDefaultCache // empty)
' ~/.claude.json 2>/dev/null | grep -v '^null$'
```

`additionalModelOptionsCache[].value` holds picker ids verbatim,
including deployment-specific forms like `claude-fable-5[1m]` or
Bedrock's `claude-5-sonnet[1m]`.  Never treat cache output as
entitlement -- it proposes candidates only.  The CLI binary's
`strings` output is NOT a source (145 historical alias strings,
mostly retired models).

## Layer 3: Probe (truth)

`scripts/probe-claude-models.sh` dispatches a one-word prompt per
candidate through the CLI's own OAuth session and classifies
accept/error.  Version- and deployment-independent: it tests exactly
the entitlement that matters.

**Sandbox constraint (verified on the restricted work host): the
probe fails inside sandboxed tool calls -- the sandbox blocks the
CLI's network.**  It works in a plain terminal.  Two ways to run it:

1. Ask the user to run it via the `!` prefix or a terminal:

       ! ~/.agents/skills/model-router/scripts/probe-claude-models.sh

   Results land in `~/.agents/.local/state/model-router/probe.json`;
   read that file afterward.
2. In-session fallback: probe via native `Agent` tool calls (the
   harness's own API path is never sandboxed) -- one tiny task per
   candidate `model` value, classify success/error.  Only covers ids
   the `Agent` tool accepts as `model` values.

The script uses `MAX_THINKING_TOKENS=0` and `--effort low` for
speed, retrying without `--effort` on CLIs too old to know the flag
(an unknown-flag error must never read as "not entitled").

## Applying Results

- Probe `ok` -> ensure a `models.json` entry: the probed id goes in
  `execution` and `aliases`; set `public_id` to the model's public
  identity in `~/.agents/benchmarks.json` (Bedrock snapshots map to
  the same-named public release, e.g. `claude-opus-4-8[1m]` ->
  `claude-opus-4.8`; `[1m]` vs base = separate entries, same
  `public_id`, different `context_window`).  If the identity is
  missing from benchmarks.json, add it with null values and a
  `match` block -- the refresh daemon fills it.
- Probe `error` -> mark the entry `"enabled": false` with the error
  as a note; never delete.
- Stamp `models.json` with the probing `claude --version`
  (`probed_with` field); re-run discovery when the version changes.
