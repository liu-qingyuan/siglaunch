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
