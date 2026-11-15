# The Brief

A **brief** is a distilled, self-contained instruction payload delivered
to a delegated worker.  It must not contain raw conversation history or
unfiltered tool dumps from the parent session.  Target an overall length
below 2,000 tokens.

## The Contract

Every brief must provide four essential components regardless of the
underlying channel:

1. **Objective:** Exactly one sentence defining the completion criteria.
2. **Context:** Absolute file paths, Git revision identifiers, branch
   names, and system facts that the worker cannot discover easily.
   Provide file paths rather than inline file dumps; the worker can read
   the filesystem directly.
3. **Constraints:** The worker guards (`<constraints priority="MUST">`
   block: stall watchdog, scope limit, and receipt contract) along
   with task-specific limits.
4. **Return:** The expected receipt structure and one concrete, runnable
   verification command (such as a test suite, linter, or compiler check)
   that the worker must execute before concluding.

## Native In-Process Envelope

For in-process tools (`Agent`, `Workflow`, or `subagent`), format the
brief using structured Extensible Markup Language (XML) tags:

```xml
<persona name="Mr. Robot">
- You think...          # (Interior-Individual)
- You behave...         # (Exterior-Individual)
- You relate to/with... # (Interior-Collective)
- You participate...    # (Exterior-Collective)
</persona>

<role name="Technical Specialist">
You are a {{role description}} assigned to {{brief task description}}.
</role>

<context>
Target file: /home/lucas/project/src/core.py
Repository branch: feature/cleanup
</context>

<goal>
Goal description.
</goal>

<task_list>
  <task name="task-1">
    <summary>Task description goes here.</summary>
    <details>
    Detailed instructions, including any relevant context, constraints, and
    specific steps to follow.
    </details>
    <example_group>
      <example>short example...</example>
      <example>single-line example...</example>
      <example>
        longer
        multi-line
        text

        An example group or standalone example can be used anywhere.
      </example>
    </example_group>
    <acceptance_criteria>
      <criterion>Task-specific criterion 1.</criterion>
      <criterion>Task-specific criterion 2.</criterion>
    </acceptance_criteria>
  </task>
  <task name="task-2">
  ...
  </task>
</task_list>

<constraints priority="MUST">
- STALL WATCHDOG: Stop if 3 consecutive turns yield no state change.
- SCOPE LIMIT: If changes span >3 decoupled subsystems, halt, escalate,
  and return a decomposition (a proposed work breakdown structure).
- RECEIPT CONTRACT: Return only the receipt below, with file:line
  references.
</constraints>

<return>
Return only a structured receipt containing:
- Status: SUCCESS | BLOCKED | PARTIAL | REFUSED (<category>)
  - PARTIAL: some items were declined on policy grounds; list them.
  - REFUSED (<category>): all was declined; category is `cyber`,
    `bio`, `medical`, or other; list the declined items.
- Verification command and exit code
- Modified files with line references (file:line)
- Summary of architectural decisions
  <template format="markdown|json|yaml|plaintext">
    <!-- Place schema, template, or target receipt structure here -->
  </template>
</return>
```

Name the worker's model and effort at dispatch, never in the brief
alone.  On `REFUSED` or `PARTIAL`, follow `refusals.md`.

### Quotes From Sources

A brief for a worker that reads sources adds this line to its
constraints:

```xml
- RAW QUOTES: Quote only from raw text: the file itself, `pdftotext`
  output, a raw download, or `gh api`.  Never quote from WebFetch's
  summarized rendering.  Mark any quote you could not read raw as
  second-hand in the receipt.
```

WebFetch returns a model's summary of the page, not the page, so a
quote taken from it can be a paraphrase.

## External CLI Envelope

For command-line interface (CLI) shell-outs, wrap the native brief in an
outer `<subagent_task>` tag.  Because external harness runs execute
out-of-band without native tool-call context injection, this outer wrapper
signals to the receiving agent that it is operating as a subagent:

```xml
<subagent_task>
  <persona name="...">...</persona>
  <role name="...">...</role>
  <context>...</context>
  <the_ask>...</the_ask>
  <constraints>...</constraints>
  <return>...</return>
</subagent_task>
```

## Style and Persona Guidelines

- Write XML-style prompts in the imperative mood.
- **The Four-Quadrant Persona:** Open with `<persona>` to condition the
  behavior of the model, defining the personality using Integral Theory's
  four quadrants:
  1. **Interior-Individual (Mind/Intentional):** *"You think..."* (cognitive
     posture, analytical philosophy, mental orientation).
  2. **Exterior-Individual (Behavior/Action):** *"You behave..."* (concrete
     execution patterns, verification habits, coding practices).
  3. **Interior-Collective (Culture/Relational):** *"You relate to/with..."*
     (collaboration stance toward the coordinator, expectations of rigor).
  4. **Exterior-Collective (Systems/Participation):** *"You participate..."*
     (interaction with the repository architecture, environment, and tooling).
- A persona is distinct from `<role>`: `<persona>` activates domain priors
  and cognitive framing, while `<role>` defines the functional assignment
  and scope of responsibility.
- Optional tags can be added as required: `<approach>`, `<deliverables>`,
  `<example_group>`, `<example>`, `<kickoff>`, `<scope>`, `<stages>`,
  `<working_agreement>`, and `<template>`.
- Place XML tags on their own lines to preserve clean parser boundaries.
