---
name: consultant
description: >-
  Start a consultant for the user through `agent-launch`.  The user
  types `/consultant [args]` in any session.  The default is the mythos
  band at `xhigh` effort.
license: Apache-2.0
compatibility: >-
  Claude Code and Pi.  Needs `agent-launch` in `~/.local/bin/` and
  the `model-selection` skill.
metadata:
  version: "1.0"
  domain: delegation
allowed-tools: Read Bash(agent-launch:*) Bash(python3:*)
disable-model-invocation: true
---

# Consultant

The user typed `/consultant [args]`.  Start one consultant.  A consultant
answers questions, is read-only, and makes no work product.  The user is
its creator.

## Route

- Start the consultant with `agent-launch consultant` and no other
  route.  Never run `claude`, `pi`, `herdr`, or `tmux` to start it.
  Reason: `agent-launch` sets the read-only tools, the class file, and
  the names.

## Steps

1. Pick the domain: this session's domain if it has one, else the
   name of the project directory.  Done when you hold one name.
2. Turn the args into a band and an effort.  Start from mythos and
   `xhigh`.
   - Band words: `mythos`, `opus`, `sonnet`, `haiku`.  A band word
     lowers the band.
   - Effort words: `low`, `medium`, `high`, `xhigh`, `max`.  An effort
     word sets the effort.  `max` is the ceiling.
   - Ask the user once when a word fits neither list.
   - Keep mythos as the top band.  The user is the creator, so the
     one-band-above rule stops here.
3. Get the model from the `model-selection` skill.  Done when you hold
   a `model_param`.
   - No band word: `python3 ~/.agents/skills/model-selection/scripts/score.py --pick --band mythos --user-named --effort <E>`.  `<E>` is `xhigh` unless step 2 set another effort.
   - Band word given: `python3 ~/.agents/skills/model-selection/scripts/score.py --pick --band <band> --user-named --effort <E>`.
   The user is the creator, so do not pass `--consultant-for`.
   Use the returned `model_param` as `<M>`.
4. Run the launch.  Done when `agent-launch` exits 0.
   ```text
   agent-launch consultant <domain> --model <M> --effort <E> \
     --creator user:mythos:xhigh
   ```
   Pass the user's question as `--first-prompt FILE` when the args
   carry one.  Write the question to a file in `$TMPDIR` first.
5. Tell the user the tab and session name that `agent-launch` printed.
   The consultant is read-only.  The user ends it.

## Failure

- When `agent-launch` is missing or exits non-zero, show the user the
  error and stop.  Start no session by another route.
