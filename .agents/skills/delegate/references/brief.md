# The brief

A **brief** is the distilled, self-contained payload a worker
receives.  It is never parent conversation history, and it is never a
raw paste of what the coordinator happens to be holding.  Target under
roughly 2K tokens.

The contract below is one contract.  Only the envelope changes with
the channel.

## The contract

Four things, always, whatever the channel:

1. **Objective.**  One sentence.  The single outcome that defines
   done.
2. **Context.**  Absolute paths, branch names, revision ids, and facts
   the worker cannot cheaply rediscover.  File *paths*, never file
   dumps -- the worker reads disk.
3. **Constraints.**  The ceiling, the breaker, and the boundary escape
   (see `../SKILL.md`), plus whatever limits this task adds.
4. **Return.**  The exact shape of the receipt, plus the one runnable
   acceptance check the worker must pass before returning -- a test
   command, a lint, a render, a build.

Distillation rules:

- Swallow verbose streams in the worker; return conclusions and
  `file:line` receipts only.
- Include a runnable acceptance check whenever the task edits code.
- State the return contract explicitly.  Unstructured worker output is
  a briefing bug, not a worker quirk.

## Envelope: native dispatch

For an `Agent` or `Workflow` call, the brief *is* the prompt string.
Structure it with the tags below.

```xml
<persona name="Mr. Robot">
You think...          # (Interior-Individual)
You behave...         # (Exterior-Individual)
You relate to/with... # (Interior-Collective)
You participate...    # (Exterior-Collective)
</persona>

<role>
You are a...
</role>

<context>
...
</context>

<the_ask>
Summary...
  <example_group>
    <example>short example...</example>
    <example>single-line example...</example>
    <example>
      longer
      multi-line
      text
    </example>
  </example_group>
</the_ask>

<return>
Return instructions...
  <template>
    ...
  </template>
</return>
```

## Envelope: external dispatch

For a CLI shell-out the brief goes to a payload file, wrapped so the
routing decision travels with it.  The attributes come from
`model-router`.

```xml
<subagent_task harness="pi" model="openrouter/z-ai/glm-5.2" tier="2" profile="coding">
  <objective>One sentence.  The single outcome that defines done.</objective>
  <context>
    Absolute paths, branch names, and facts the worker cannot cheaply
    rediscover.  File PATHS, never file dumps-- the worker reads disk.
  </context>
  <constraints>
    The ceiling, the breaker, and the boundary escape, plus
    task-specific limits.
  </constraints>
  <return>
    Exact shape of the expected answer, plus the acceptance check the
    worker must run (test command, lint, render) before returning.
  </return>
</subagent_task>
```

## Style

Style is the formatting layer of the contract, not a second contract.

- Write XML-style prompts.  Always.
- Write in the imperative.
- Open with `<persona>` to elicit the behaviour you want, except when
  starting from a pre-defined agent persona.  A persona is not a role:
  it exists to tickle the tensors and poke the weights, choosing words
  and phrases that activate the relevant embeddings and experts.
  Define the personality in terms of integral theory's four quadrants.
- `<role>` states the agent's role and responsibilities.
- `<context>` orients the agent.
- `<return>` states return expectations, with an optional
  `<template>`.
- Add other tags as needed.  Tags are informal, with no set schema:
  `<approach>`, `<deliverables>`, `<example_group>`, `<example>`,
  `<hard_gates>`, `<kickoff>`, `<scope>`, `<stages>`, `<the_ask>`,
  `<working_agreement>`, `<success_criteria>`, `<prompt>`.
- Tags may nest and may carry arbitrary parameters.
- Put tags on their own lines, except extremely short ones.
- Leave a blank line between top-level sections.
