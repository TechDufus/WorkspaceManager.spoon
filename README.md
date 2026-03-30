# WorkspaceManager.spoon

Screen-aware workspace orchestration for Hammerspoon on top of
[`GridLayout.spoon`](https://github.com/jesseleite/GridLayout.spoon).

`WorkspaceManager.spoon` is the stateful layer above your layout engine. It decides which layout
is active on which screen, remembers per-screen and per-window overrides, handles summon behavior,
and moves focused windows between displays without doing a full workspace reflow.

## Scope

This spoon owns:

- per-screen workspace state
- persisted layout selection and variant state
- per-window and per-app cell overrides
- screen-aware summon behavior
- focused-window movement between screens
- orchestration of active layouts through
  [`GridLayout.spoon`](https://github.com/jesseleite/GridLayout.spoon)

This spoon does not own:

- your app bundle IDs
- your layout definitions
- your screen default mappings
- your hotkeys or modal structure

That split is intentional. `WorkspaceManager.spoon` is the runtime. Your `init.lua` remains the
composition root.

## Dependency

`WorkspaceManager.spoon` depends on
[`GridLayout.spoon`](https://github.com/jesseleite/GridLayout.spoon).

That dependency is explicit. `WorkspaceManager.spoon` expects a configured GridLayout spoon
instance to be injected into `:start(config)`. It does not vendor GridLayout, and it does not
silently load a private copy behind the user's back.

[`GridLayout.spoon`](https://github.com/jesseleite/GridLayout.spoon) is excellent work by
[Jesse Leite](https://github.com/jesseleite). `WorkspaceManager.spoon` intentionally builds on
that foundation instead of trying to reimplement the layout engine itself.

### Screen-Aware Cell Compatibility

- Plain string cells and per-screen layout selection work with a stock
  [`GridLayout.spoon`](https://github.com/jesseleite/GridLayout.spoon) release.
- Explicit `cell.screen` routing is now supported upstream in
  [`jesseleite/GridLayout.spoon`](https://github.com/jesseleite/GridLayout.spoon) via
  [PR #7](https://github.com/jesseleite/GridLayout.spoon/pull/7), which merged on March 28, 2026.
- As of March 29, 2026, the latest upstream release still predates that merge. If you depend on
  `cell.screen`, pin upstream `master` at `4d32c93` or later until a tagged release includes
  PR #7.

## Installation

For end users, install both spoons from their GitHub Releases:

1. Download `GridLayout.spoon.zip` from
   [`jesseleite/GridLayout.spoon` releases](https://github.com/jesseleite/GridLayout.spoon/releases)
2. Download `WorkspaceManager.spoon.zip` from
   [`TechDufus/WorkspaceManager.spoon` releases](https://github.com/TechDufus/WorkspaceManager.spoon/releases)
3. Double click each `.spoon.zip` file, or unzip them into `~/.hammerspoon/Spoons/`

Version guidance:

- If you only use plain string cells, a released `GridLayout.spoon` build is fine.
- If you use `cell.screen`, install upstream `GridLayout.spoon` `master` at `4d32c93` or later
  until Jesse ships a tagged release that includes [PR #7](https://github.com/jesseleite/GridLayout.spoon/pull/7).

For local development, symlink both spoon directories into `~/.hammerspoon/Spoons/` instead of
installing the release zips.

Then load and compose them from your Hammerspoon config.

## Quick Start

```lua
local apps = {
  Terminal = { id = 'com.apple.Terminal' },
  Browser = { id = 'com.apple.Safari' },
}

local layouts = {
  {
    key = 'focus',
    name = 'Focus',
    cells = {
      { '0,0 80x40' },
    },
    apps = {
      Terminal = { cell = 1, open = true },
      Browser = { cell = 1 },
    },
  },
}

local gridlayout = hs.loadSpoon('GridLayout')
  :start()
  :setApps(apps)
  :setGrid('80x40')
  :setMargins('5x5')

local workspaceManager = hs.loadSpoon('WorkspaceManager')
  :start({
    layoutEngine = gridlayout,
    apps = apps,
    layouts = layouts,
  })

workspaceManager:apply()
```

For complete examples, see:

- [examples/single_monitor.lua](examples/single_monitor.lua)
- [examples/multi_monitor.lua](examples/multi_monitor.lua)

## Public API

- `:start(config)`
  Starts the runtime, validates config, loads persisted state, and starts the screen watcher.
- `:stop()`
  Stops timers and watchers owned by the spoon.
- `:apply()`
  Rebuilds the synthetic active layout and applies it through GridLayout.
- `:showLayoutPicker([screen])`
  Opens a chooser for the focused screen or a supplied target screen.
- `:selectLayout(layoutRef[, screen])`
  Sets the active layout for a screen and reapplies.
- `:selectNextVariant([screen])`
  Cycles the current layout variant for a screen.
- `:resetLayout([screen])`
  Clears overrides for the active layout on a screen and resets variant state.
- `:bindFocusedWindowToCell()`
  Persists a per-window cell override for the focused window.
- `:bindFocusedAppToCell()`
  Opens a chooser that persists a per-app cell override for the focused app on the active screen.
- `:setAppCell(appName, cellIndex[, screen])`
  Persists a per-app cell override for a screen's active layout and reapplies.
- `:clearAppCell(appName[, screen])`
  Removes a per-app override and reverts the app to the layout default cell.
- `:summon(appName)`
  Opens or focuses an app and places it on the active screen/workspace.
- `:moveFocusedWindowToNextScreen()`
  Moves only the focused window to the next screen and snaps it there.
- `:moveFocusedWindowToPreviousScreen()`
  Moves only the focused window to the previous screen and snaps it there.

## Config Reference

### Required keys

- `layoutEngine`
  A configured [`GridLayout.spoon`](https://github.com/jesseleite/GridLayout.spoon)
  instance.
- `apps`
  App definition table keyed by logical app name.
- `layouts`
  Ordered list of GridLayout-compatible layouts.

### Optional keys

- `screenLayouts`
  Per-screen default layout mapping table.
- `settingsKey`
  `hs.settings` key used for persisted state.
- `openAppReapplyDelaySeconds`
  Delay before reapplying after auto-opening apps.
- `screenChangeDelaySeconds`
  Delay before reapplying after screen changes.
- `summon`
  Summon-specific configuration table.

### Default values

Built-in defaults:

- `settingsKey = 'WorkspaceManager.spoon.screen_state.v1'`
- `openAppReapplyDelaySeconds = 0.5`
- `screenChangeDelaySeconds = 1`
- `summon.placementDelaySeconds = 0.2`
- `summon.placementAttempts = 10`

If you do not provide `screenLayouts`, the first layout in `layouts` is used for every screen.

### `screenLayouts`

`screenLayouts` is optional. If omitted, the first layout in `layouts` is used.

Supported keys:

- screen UUID
- screen name
- `primary`
- `screen:<index>`
- `profile:<name>`
- `all`

Example:

```lua
local screenLayouts = {
  layouts = {
    primary = 'wide',
    ['screen:2'] = 'focus',
    ['profile:builtin'] = 'focus',
    ['profile:fourk'] = 'wide',
    all = 'focus',
  },
}
```

Resolution order:

1. exact screen identifiers
2. `profile:<name>`
3. bare profile key
4. `all`
5. first layout in `layouts`

### `summon`

Summon-specific config is nested under `summon`.

Summoned apps target the screen under the mouse pointer when available, then fall back to the
focused window's screen, then `hs.screen.mainScreen()`. If the app already has a standard window,
WorkspaceManager prefers the most recently used standard window for that app when re-summoning.
It first uses tracked app-level focused-window changes when available, then the app's own focused
window, then visible window z-order, and only then falls back to windows on the invocation screen.
Existing apps stay on the selected window's current screen and are focused directly instead of
being re-placed across monitors. If macOS drops the first focus request, WorkspaceManager raises
the selected window and retries focus before falling back to placement.

Example:

```lua
local workspaceManager = hs.loadSpoon('WorkspaceManager')
  :start({
    layoutEngine = gridlayout,
    apps = apps,
    layouts = layouts,
    screenLayouts = screenLayouts,
    summon = {
      placementDelaySeconds = 0.2,
      placementAttempts = 10,
    },
  })
```

### App config shape

Minimum app table:

```lua
local apps = {
  Terminal = { id = 'com.apple.Terminal' },
  Browser = { id = 'com.apple.Safari' },
}
```

Additional keys are allowed. `WorkspaceManager.spoon` only depends on the logical app name and
the app identifier. Your own modal bindings or extra metadata can live in the same table.

### Layout config shape

`layouts` is an ordered list of GridLayout-compatible layouts.

Minimum layout:

```lua
local layouts = {
  {
    key = 'focus',
    name = 'Focus',
    cells = {
      { '0,0 80x40' },
    },
    apps = {
      Terminal = { cell = 1, open = true },
      Browser = { cell = 1, open = true },
    },
  },
}
```

Screen-aware cells are supported through the injected GridLayout dependency, for example:

```lua
cells = {
  {
    { cell = '0,0 52x40', screen = 'screen:2' },
    '0,0 80x40',
  },
}
```

## Validation

`:start(config)` fails fast on invalid standalone configs. That includes:

- missing required top-level config
- malformed app definitions
- layouts missing keys, names, or cells
- layouts that reference unknown apps or missing cell indexes
- invalid `screenLayouts` mappings
- invalid summon timing config

## Persistence Model

Persisted state includes:

- per-screen active layout
- per-screen active variant
- per-layout app overrides
- per-layout per-window overrides

Preferred window tracking is intentionally runtime-only and is not persisted.

## Behavior Notes

- single-window moves should not trigger a full workspace flicker
- `moveFocusedWindowToNextScreen()` is focused-window-only
- per-app overrides set the default slot for a managed app on the active screen/layout
- per-window `bindFocusedWindowToCell()` overrides can coexist with default app slots
- per-window overrides win over per-app overrides for the same window
- if only one screen is present, next/previous screen movement is a no-op
- cross-screen terminal moves intentionally do a fast two-step move-then-snap to avoid wrong-size frames on terminal-like apps

## Development

### Syntax check

```sh
luac -p init.lua workspace_manager.lua screens.lua summon.lua
```

### Run tests

```sh
lua tests/runtime_spec.lua
lua tests/summon_spec.lua
lua tests/init_spec.lua
```

GitHub Actions runs the same parser and spec checks on pushes and pull requests.

### Release automation

This repo ships releases through GitHub Actions:

- `Release` is the primary manual workflow. It validates the repo, builds the Spoon zip and docs,
  creates or bumps the semver tag, and publishes the GitHub release assets directly.
- `Publish Release` is the recovery path for existing tags. It can run on external `v*` tag pushes
  or be dispatched manually for a specific tag, then rebuild and upload the release assets.

Release strategy options:

- `current`
  Tags and publishes the version already checked into `init.lua`.
- `patch`, `minor`, `major`
  Bump `init.lua`, commit `chore(release): vX.Y.Z`, create tag `vX.Y.Z`, and publish the release.

Local release helpers:

```sh
./scripts/version.sh current
./scripts/version.sh next patch
./scripts/package_spoon.sh 0.1.0 dist
```

### What the current test harness covers

- config validation for missing required keys
- config validation for malformed layouts and unknown layout references
- screen default resolution order
- custom screen-change reapply delay
- focused-window move behavior that pre-moves onto the destination screen before snapping
- persisted per-app override reload behavior
- persisted per-window override reload behavior
- summon remembered-window recall and same-screen fallback order
- summon focus retry timing and stale retry cancellation
- `init.lua` watcher lifecycle and wrapper forwarding

### Real Hammerspoon testing

The highest-signal test setup is:

1. keep your local Hammerspoon config in `~/.hammerspoon/init.lua`
2. symlink `~/.hammerspoon/Spoons/WorkspaceManager.spoon` to this repo
3. symlink `~/.hammerspoon/Spoons/GridLayout.spoon` to a local
   [`GridLayout.spoon`](https://github.com/jesseleite/GridLayout.spoon) checkout
   using `master` at `4d32c93` or later if you are testing `cell.screen`
4. reload Hammerspoon after changes

That lets you test:

- local config
- external `WorkspaceManager.spoon`
- external [`GridLayout.spoon`](https://github.com/jesseleite/GridLayout.spoon)
- real monitor hardware

## Repository Layout

- [init.lua](init.lua)
  Public spoon entrypoint.
- [workspace_manager.lua](workspace_manager.lua)
  Core runtime and state management.
- [screens.lua](screens.lua)
  Screen identity, ordering, and profile helpers.
- [summon.lua](summon.lua)
  Summon/open/focus controller.
- [tests/runtime_spec.lua](tests/runtime_spec.lua)
  Plain-Lua regression harness.
- [tests/summon_spec.lua](tests/summon_spec.lua)
  Summon/open/focus regression harness.
- [tests/init_spec.lua](tests/init_spec.lua)
  Spoon entrypoint and watcher lifecycle smoke test.
- [examples/single_monitor.lua](examples/single_monitor.lua)
  Minimal single-screen composition example.
- [examples/multi_monitor.lua](examples/multi_monitor.lua)
  Multi-screen composition example.

## License

MIT
