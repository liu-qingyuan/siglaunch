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
the Agent process directly. When no Agent matches, Siglaunch selects Herdr's
versioned cold-start contract. Herdr 0.7.4 receives the Workspace and exact argv
through `agent start --cwd`; Herdr 0.7.5 and newer creates the Workspace and
starts canonical `pi` in its root pane with the configured arguments. Both paths
require Herdr to confirm the same complete argv. Siglaunch never joins that argv
into a shell command or starts Pi itself. On Herdr 0.7.5 and newer,
`pi.command[0]` must be `pi` because Herdr owns canonical executable selection.

```bash
swift run Siglaunch
```

Run the test suite with:

```bash
swift test
```

## Local App installation

Siglaunch requires exactly one valid `Developer ID Application` signing identity
for Team ID `S3YCJDN4GX`. Confirm the identity is available before installing:

```bash
security find-identity -v -p codesigning
```

Quit any running copy with **Quit Siglaunch**, then build, sign, verify, and install
the release App Bundle with:

```bash
./scripts/install-siglaunch
```

The default destination is `/Applications/Siglaunch.app`. The command stages and
verifies the new bundle next to that destination before replacing an existing
installation. Re-run the same command to update Siglaunch. A failed update restores
the previous App; the command never falls back to ad-hoc signing, launches the App,
or reads or changes files under `~/Library/Application Support/Siglaunch`.
Automated tests use the same command with `--destination /temporary/Siglaunch.app`.

Open the installed menu bar App from Applications, Launchpad, Spotlight, or:

```bash
open -a Siglaunch
```

Siglaunch remains outside the Dock and App Switcher. Choose **Quit Siglaunch** from
its menu to release the camera and end the process. Open it from the same entry
again to restart it; opening an already running App does not create another
resident process.

This local installation is not notarized and is not an external distribution
workflow. Login Items, automatic launch at sign-in, installers, automatic updates,
and a branded App icon are not supported.

The real Developer ID, `/Applications`, launch, quit, and relaunch smoke is disabled
by default. It replaces the live installation and can start camera access. Run it
only after explicitly authorizing those effects with both variables:

```bash
SIGLAUNCH_RUN_INSTALL_SMOKE=1 \
SIGLAUNCH_CONFIRM_APPLICATIONS_INSTALL='replace /Applications/Siglaunch.app' \
swift test \
  --filter InstallSiglaunchTests/testLiveApplicationsInstallLaunchQuitAndRelaunchWhenExplicitlyAuthorized
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

The live Herdr cold-start smoke is disabled by default. It creates a real Pi
Agent through the installed supported Herdr contract and intentionally leaves
the resulting Herdr state in place. Run it only with a connected GUI client and
an explicitly prepared Workspace and argv:

```bash
SIGLAUNCH_RUN_HERDR_START_SMOKE=1 \
SIGLAUNCH_HERDR_START_WORKSPACE="$PWD" \
SIGLAUNCH_HERDR_START_COMMAND_JSON='["pi"]' \
swift test \
  --filter HerdrAgentAdapterTests/testLiveHerdrStartsConfiguredPiAgentWhenOptedIn
```

Recognizer Training consumes only the normalized local samples produced by Pose
Dataset preparation. Create ML performs a deterministic 80/20 stratified split,
and the compiled candidate is loaded successfully before it atomically replaces
`~/Library/Application Support/Siglaunch/PersonalRecognizer.mlmodelc`. Images,
models, progress, and metrics are never uploaded.

The real Create ML smoke is disabled by default. It generates a temporary local
Pose Dataset, trains a classifier, compiles and installs the candidate, then
reloads the active Core ML model:

```bash
SIGLAUNCH_RUN_CREATE_ML_SMOKE=1 swift test \
  --filter RecognizerTrainingAdapterTests/testLiveCreateMLArtifactCompilesAndReloadsWhenOptedIn
```

The live Personal Recognizer fixture integration is also disabled by default
because the model and representative hand images are user-specific. Point the
model root at a directory containing `PersonalRecognizer.mlmodelc`, and provide
a fixture root containing `positive.png`, `near-miss.png`, and `nonmatch.png`.
All three images run through the production Vision crop and compiled Core ML
classifier:

```bash
SIGLAUNCH_RUN_PERSONAL_RECOGNIZER_FIXTURE=1 \
SIGLAUNCH_PERSONAL_RECOGNIZER_MODEL_ROOT="$HOME/Library/Application Support/Siglaunch" \
SIGLAUNCH_PERSONAL_RECOGNIZER_FIXTURE_ROOT="/path/to/private/pose-fixtures" \
swift test \
  --filter VisionDiagnosticAdapterTests/testLiveCompiledPersonalRecognizerClassifiesRepresentativeFixturesWhenOptedIn
```

Gesture Monitoring defaults to `15 FPS`; the menu also offers `10 FPS` and
`30 FPS`. The camera selects the closest supported rate that does not exceed the
target. Recognition keeps one in-flight frame and one replaceable latest frame,
while menu diagnostics report target, selected capture, and completed recognition
FPS.

The live camera FPS smoke is disabled by default. Run it only from a macOS GUI
session where camera prompts can be answered; it verifies the selected rate does
not exceed `15 FPS`, receives a lifecycle-tagged frame, and releases the camera:

```bash
SIGLAUNCH_RUN_CAMERA_SMOKE=1 swift test \
  --filter CameraAdapterTests/testLiveBuiltInCameraFrameRateCaptureAndReleaseWhenOptedIn
```
