# Siglaunch

A local-first macOS hub for gesture-triggered developer workflows.

## Development

Siglaunch requires macOS 13 or newer and Swift 6.

The Primary Workflow configuration lives at
`~/Library/Application Support/Siglaunch/workflow.json`. It accepts exactly one
Workspace path and one non-empty Pi Agent argv:

```json
{
  "workspace": {
    "path": "/Users/developer/work/siglaunch"
  },
  "pi": {
    "command": ["pi", "--model", "gpt-5"]
  }
}
```

`pi.command` remains an argv array throughout the Workflow. Siglaunch does not
join it into a shell command. The Herdr executable is resolved as an executable
absolute path from Siglaunch's `PATH`, `~/.local/bin`, `/opt/homebrew/bin`, or
`/usr/local/bin`; Ghostty receives that path separately from its fixed surface
command.

After the default Herdr Session is ready, Siglaunch runs `herdr agent list`,
keeps the original JSON order, and selects the first `pi` Agent whose canonical
`cwd` or `foreground_cwd` matches the configured Workspace. It focuses that
Leading Pi Agent through `herdr agent focus <pane_id>`; Siglaunch never manages
the Agent process directly.

```bash
swift run Siglaunch
```

Run the test suite with:

```bash
swift test
```

The live Ghostty AppleScript smoke is disabled by default because it focuses an
existing Herdr terminal or starts `herdr` in a new Ghostty window. Run it only
against disposable or intentionally prepared live state:

```bash
SIGLAUNCH_RUN_GHOSTTY_SMOKE=1 swift test \
  --filter GhosttyAppleScriptAdapterTests/testLiveGhosttyEnsuresDefaultHerdrSessionWhenOptedIn
```

The live Herdr focus smoke is also disabled by default. It requires a running
Herdr server, a connected GUI client, and an existing Pi Agent in the selected
Workspace. It changes live Herdr focus:

```bash
SIGLAUNCH_RUN_HERDR_FOCUS_SMOKE=1 \
SIGLAUNCH_HERDR_FOCUS_WORKSPACE="$PWD" \
swift test \
  --filter HerdrAgentAdapterTests/testLiveHerdrFocusesWorkspaceLeadingPiAgentWhenOptedIn
```
