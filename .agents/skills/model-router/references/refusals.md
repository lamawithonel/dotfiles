# Refusals

A refusal is not a capability failure.  A worker that tried and got it
wrong takes the normal escalation path (raise effort, then band), not a
re-route.

## 1. Recognition order

1. **Receipt status.**  `Status: REFUSED (<category>)` or
   `Status: PARTIAL`, with the declined items listed.  Self-report is
   the only marker that works in every harness.
2. **API marker.**  The Claude API returns `stop_reason: "refusal"`
   with a category (`cyber`, `bio`, `frontier_llm`,
   `reasoning_extraction`, `general_harms`, or null), possibly after
   partial output.  Gateways return `[CONTENT_FILTERED]`.  Whether the
   `Agent` result exposes the stop reason is unknown.
3. **Text cues.**  A direct decline; a deflection to a narrower or
   different task; or a hedge that omits the substance.  Empty or
   truncated output with no gateway marker is a failure, not a refusal.

## 2. Re-route steps

1. **Scope.**  Re-route only category `cyber` or `bio`, or text-detected
   refusals on tasks tagged `cyber` or `medical`.  Never re-route
   `general_harms`, `frontier_llm`, or `reasoning_extraction`.
2. **Quote the authorization.**  Quote verbatim the authorization from
   the user or the commissioning brief that covers the task.  A
   self-written purpose line does not count.  With none to quote, stop
   and ask.
3. **Bio needs the user.**  A `bio` re-route proceeds only with the
   user's approval for that event, every time.  `cyber` and `medical`
   proceed on the quoted authorization.
4. **Re-dispatch once** to `on_refusal` from `score.py`: the best model
   on the tag's board in the same band from a different vendor.  Never
   another Claude model; the classifiers are shared.  `on_refusal` is
   set only when the call carried a tag with a refusal re-route
   (`cyber` or `medical`).  There is no `bio` tag: bio folds into
   `medical`, so re-run `score.py --pick --band B --tag medical` (or
   `--tag cyber`) and read `on_refusal`.  It is also null when no
   different-vendor, non-Anthropic variant in the band has a score on
   the tag's board.  If it is still null, stop and report to the
   supervisor; never pick a vendor by hand.  `on_refusal.channel` is
   `herdr` when `HERDR_ENV=1`, else `shell`; from Claude Code that is
   a Pi worker run through that channel.  Send the same brief plus the
   quoted authorization.  Name its model and effort.
5. **Review, stop, log.**  Review the output with extra care; low-refusal
   models are weakly calibrated, so safety review stays with the
   coordinator.  On a second refusal, report to the supervisor with no
   third hop.  Log one line per event (date, model, tag, category,
   outcome) under `~/.local/state/agents/`.

## 3. Tag interaction

For `cyber` and `medical`, `score.py` returns both `pick` (or `degrade`)
and `on_refusal`.  The Cyber Index scores refusals as failures, so a
non-Claude pick may already appear for offensive work.
