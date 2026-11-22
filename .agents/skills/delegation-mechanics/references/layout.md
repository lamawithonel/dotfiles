# Layout and Names

Use this file to place and name each session.  `agent-launch` follows
these rules for executives, coordinators, and consultants.  You follow
them by hand for worker panes.

## Herdr (level 1)

The `roles` skill (`~/.agents/skills/roles/`, section "Names and
layout") holds the table of placement, tab names, and session names for
each class.  This file holds the commands.

- Executive: in the tab the user started it in.
- Coordinator and consultant: each in its own new tab in the workspace
  of its executive or creator.
- Worker on another harness: a pane in a worker tab in the
  dispatcher's workspace.
- Only the user creates Herdr workspaces.

- Keep each agent name to 32 characters or fewer, from `[a-z0-9_-]`,
  starting with a letter.  Shorten a long `<sub-domain>` to fit.
- When the user declares an executive, it renames its own tab and
  workspace.  It moves neither.

  ```sh
  herdr tab rename "$HERDR_TAB_ID" executive
  herdr workspace rename "$HERDR_WORKSPACE_ID" <domain>
  ```

- Put each coordinator and consultant in a new tab.

  ```sh
  herdr tab create --workspace "$HERDR_WORKSPACE_ID" --label <tab-name> \
    --cwd "$PWD" --no-focus
  ```

  Read the new tab and pane IDs from the JSON response.  Never infer an
  ID.
- Add a worker as a new pane in a matching worker tab with fewer than 8
  panes.  Open a new tab when the tab is full, and for each set of
  related workers.

  ```sh
  herdr pane layout --pane <pane-id>
  herdr pane split <pane-id> --direction right --cwd "$PWD" --no-focus
  ```

  Split a wide pane right.  Split a narrow or tall pane down.  Stop
  before panes become slivers.
- `--no-focus` leaves the user's focus where it was.  `--cwd` sets the
  directory of the new terminal.
- Name an agent when you start it: `herdr agent start <name> ...`.  An
  asker then addresses it by that name.  Rename with
  `herdr agent rename <target> <name>`.
- Read live state with `herdr workspace list`,
  `herdr tab list --workspace "$HERDR_WORKSPACE_ID"`,
  `herdr pane list --workspace "$HERDR_WORKSPACE_ID"`, and
  `herdr agent list`.
- Target your own pane with `--current` or the ID.  A command with no
  target acts on the pane the user has focused.
- For syntax, run `herdr <group>` and read the group list.  Bare
  `herdr` opens the TUI.  An incomplete mutating command can run with
  defaults.
- To address a session that shares a name with another, follow the
  `roles` skill (`~/.agents/skills/roles/`).

### Close

- Close a worker's pane after you read its final report.  Close a
  worker tab when it is empty.
- Leave a failed worker's pane open for the user.
- Close what you created.  Leave the rest as you found it.

## tmux (level 2)

- One tmux window per session.  Name the window as the Herdr tab is
  named.  Use the same session names.
- Use the tmux session you run in.  Read its name with
  `tmux display-message -p '#S'`.
- Worker panes at level 2: one window per worker group, named as the
  worker tab, split with `tmux split-window`.  At most 8 panes.
- Never use zellij.

```sh
tmux new-window -d -t "$(tmux display-message -p '#S')" -n <window-name> \
  -c "$PWD"
tmux list-windows -F '#{window_name}'
tmux kill-window -t <session>:<window-name>
```

- `-d` leaves the current window selected.
