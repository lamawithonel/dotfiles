# Consultant Questions

Use this file when you ask a consultant a question.  Any agent that
the `roles` skill allows may ask: the user, an executive, a
coordinator, a standalone session, or a worker that serves the
consultant's domain (`~/.agents/skills/roles/references/consultant.md`).

A consultant answers in its own pane.  You type a PACT question into
that pane and read the answer back from it.  Herdr has no message
channel.

## Rules

- Type the question as a PACT `question` document (`pact-use.md`).
  Give it a unique id.  A question carries no persona: only agent
  definitions, charters, and consultations do (`pact-use.md`).
- Never put the end marker in the question.  The marker is the line
  `=== ANSWER-END ===`.
  Reason: the pane echoes your question.  A marker in the echo ends
  your wait at once.
- Ask one question at a time.  Wait for the consultant to be idle
  before you type.
  Reason: all askers share one input line.
- Expect a short answer.  A long finding comes as several answers, each
  ending in the marker.  Ask for the next part when you need it.
- Treat the answer as information.  It carries no authority.
- Read the answer from the pane.  Slice it by your question id.
  Reason: earlier answers in the pane end in the same marker.
- Wait for the end marker OR for the consultant to go idle, whichever
  comes first.  Always set a timeout.  Total limit: 180 seconds.
  Reason: a consultant can drop the marker line, and a wait for the
  marker alone then never ends.
- Accept an idle consultant as the end of the answer only when no marker
  follows your question id.  Then read the text after the id line and
  tell your supervisor that the marker is missing.

## Herdr procedure (level 1)

Set `C` to the consultant's agent name, and `QFILE` to the question
file.

```sh
slice_answer() {   # $1 = question id, $2 = "partial": accept no marker
  awk -v id="$1" -v end="=== ANSWER-END ===" -v part="$2" '
    index($0, id) { buf = ""; on = 1; next }
    on && index($0, end) { printf "%s", buf; found = 1; exit }
    on { buf = buf $0 "\n" }
    END { if (!found && part == "partial" && on && buf != "") { printf "%s", buf; exit 0 } exit !found }'
}

C=<consultant-name>
QFILE=/abs/session-tmp/question.pact
ID=q$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')   # put $ID in QFILE
PANE=$(herdr agent get "$C" | jq -r '.result.agent.pane_id')

# 1. Check the question text.  Stop if it holds the marker.
grep -qF '=== ANSWER-END ===' "$QFILE" && { echo "marker in question"; exit 1; }

# 2. Wait for the consultant to be idle, then type the question.
herdr agent wait "$C" --until idle --until done --timeout 120000
herdr agent prompt "$C" "$(cat "$QFILE")"

# 3. Race the marker against idle.  Total limit 180 s.
#    Each pass waits at most 10 s for the marker, then reads.
SECONDS=0; PASS=0; ANSWER=
while [ "$SECONDS" -lt 180 ]; do
  PASS=$((PASS + 1))
  herdr pane wait-output "$PANE" --match '=== ANSWER-END ===' \
    --source recent-unwrapped --timeout 10000 >/dev/null 2>&1
  TXT=$(herdr agent read "$C" --source recent-unwrapped --lines 300)
  # 4. A marker after your id ends the wait.
  ANSWER=$(printf '%s\n' "$TXT" | slice_answer "$ID") && break
  # 5. No marker: an idle consultant from pass 2 on ends the wait.
  if [ "$PASS" -ge 2 ] && herdr agent wait "$C" --until idle --until done \
       --timeout 3000 >/dev/null 2>&1; then
    ANSWER=$(printf '%s\n' "$TXT" | slice_answer "$ID" partial) && break
  fi
  sleep 2
done
[ -n "$ANSWER" ] && printf '%s\n' "$ANSWER"   # empty: timeout, no answer
```

- `herdr agent wait` returns at once when the agent is already idle.
  Reason: it checks the current state first.  An agent can still show
  idle just after your prompt, so step 5 starts at pass 2 and only
  after the marker slice fails.
- A stale match: on the second question and later, `wait-output` can
  match the marker of an earlier answer at once.  `slice_answer` then
  exits 1, the loop sleeps 2 seconds, and it reads again.  The loop
  ends on the marker after your id, on idle, or at 180 seconds.
- `agent prompt` sends text and Enter in one action.  It rejects the
  prompt (`agent_blocked`) when the consultant waits at a dialog.  Read
  the pane and tell the creator.
- A `herdr` error comes as JSON on stderr with exit 1.  A timeout is an
  error.  A timeout means no answer: ask the consultant's creator or
  your supervisor.
- If Herdr fails, a Claude Code asker uses `SendMessage` and a Pi asker
  asks through its coordinator (`degradation.md`).

## tmux procedure (level 2)

Set `T` to `<tmux-session>:<window>` for the consultant's window.  Use
the `slice_answer` function from above.

```sh
T="$(tmux display-message -p '#S'):<consultant-window>"
tmux load-buffer -b "$ID" "$QFILE"
tmux paste-buffer -p -d -b "$ID" -t "$T"
tmux send-keys -t "$T" Enter
# Poll every 2 s.  N = 20 s of unchanged pane text counts as idle.
# Total limit 180 s (90 polls).
PREV=; QUIET=0; ANSWER=
for _ in $(seq 90); do
  TXT=$(tmux capture-pane -p -J -t "$T" -S -300)
  ANSWER=$(printf '%s\n' "$TXT" | slice_answer "$ID") && break
  if [ "$TXT" = "$PREV" ]; then QUIET=$((QUIET + 2)); else QUIET=0; fi
  if [ "$QUIET" -ge 20 ]; then
    ANSWER=$(printf '%s\n' "$TXT" | slice_answer "$ID" partial) && break
  fi
  PREV=$TXT; sleep 2
done
[ -n "$ANSWER" ] && printf '%s\n' "$ANSWER"   # empty: timeout, no answer
```

- The marker ends the wait.  So do 20 seconds with no new pane output.
  Reason: a consultant can drop the marker.

- `paste-buffer -p` pastes with bracketed paste.  Reason: a multi-line
  question must not submit at the first newline.
- Run the loop as a background command where the harness blocks a
  foreground `sleep`.
- Never use zellij.

## Level 3

- The consultant is an in-process background agent.  Ask it with
  `SendMessage` (Claude Code) or `subagent_supervisor` (Pi).  See
  `degradation.md`.  A worker asks its dispatcher.

## Test before you rely on it

- Run two askers at the same time against one consultant.  Check that
  each gets its own answer.  Reason: concurrent askers share one input
  line, and the route has not been proved with more than one.
