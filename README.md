# WorkspaceManager.spoon

Screen-aware workspace orchestration for Hammerspoon on top of `GridLayout.spoon`.

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
- orchestration of active layouts through `GridLayout.spoon`

This spoon does not own:

- your app bundle IDs
- your layout definitions
- your screen default mappings
- your hotkeys or modal structure

That split is intentional. `WorkspaceManager.spoon` is the runtime. Your `init.lua` remains the
composition root.

## Dependency

`WorkspaceManager.spoon` depends on `GridLayout.spoon`.

That dependency is explicit. `WorkspaceManager.spoon` expects a configured GridLayout spoon
instance to be injected into `:start(config)`. It does not vendor GridLayout, and it does not
silently load a private copy behind the user's back.

### Current GridLayout Note

Multi-monitor screen-aware cells currently depend on the GridLayout change introduced in:

- `jesseleite/GridLayout.spoon#7`

Until that lands in an upstream release, you need either:

- a local checkout of the PR branch, or
- a local overlay of the patched `helpers.lua`

If you only use single-screen or legacy non-screen-aware cells, a stock GridLayout release is fine.

## Installation

Install both spoons into `~/.hammerspoon/Spoons/`:

1. `GridLayout.spoon`
2. `WorkspaceManager.spoon`

Then load and compose them from your Hammerspoon config.

## Quick Start

```lua
local apps = require('apps')
local layouts = require('layouts')
local positions = require('positions')
local screenLayouts = require('screen_layouts')

local gridlayout = hs.loadSpoon('GridLayout')
  :start()
  :setApps(apps)
  :setGrid(positions.full_grid)
  :setMargins('5x5')

local workspaceManager = hs.loadSpoon('WorkspaceManager')
  :start({
    layoutEngine = gridlayout,
    apps = apps,
    layouts = layouts,
    screenLayouts = screenLayouts,
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
- `:summon(appName)`
  Opens or focuses an app and places it on the active screen/workspace.
- `:moveFocusedWindowToNextScreen()`
  Moves only the focused window to the next screen and snaps it there.
- `:moveFocusedWindowToPreviousScreen()`
  Moves only the focused window to the previous screen and snaps it there.

## Config Reference

### Required keys

- `layoutEngine`
  A configured `GridLayout.spoon` instance.
- `apps`
  App definition table keyed by logical app name.
- `layouts`
  Ordered list of GridLayout-compatible layouts.

### Optional keys

- `screenLayouts`
  Per-screen default layout mapping table.
- `settingsKey`
  `hs.settings` key used for persisted state.
- `defaultLayoutKeys`
  Fallback profile-to-layout mapping overrides.
- `openAppReapplyDelaySeconds`
  Delay before reapplying after auto-opening apps.
- `screenChangeDelaySeconds`
  Delay before reapplying after screen changes.
- `summon`
  Summon-specific configuration table.

### Default values

Built-in defaults:

- `settingsKey = 'workspaces.screen_state.v1'`
- `openAppReapplyDelaySeconds = 0.5`
- `screenChangeDelaySeconds = 1`
- `summon.placementDelaySeconds = 0.2`
- `summon.placementAttempts = 10`

Built-in profile fallback mapping:

- `builtin -> fullscreen`
- `fourk -> fourk`
- `standard -> hd`
- `ultrawide -> standard`

You can override the profile fallback mapping with `defaultLayoutKeys`:

```lua
local workspaceManager = hs.loadSpoon('WorkspaceManager')
  :start({
    layoutEngine = gridlayout,
    apps = apps,
    layouts = layouts,
    defaultLayoutKeys = {
      builtin = 'fullscreen',
      fourk = 'fullscreen',
      standard = 'hd',
      ultrawide = 'fourk',
    },
  })
```

### `screenLayouts`

`screenLayouts` is optional. If omitted, the profile defaults above are used.

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
    primary = 'fourk',
    ['screen:2'] = 'fullscreen',
    ['profile:builtin'] = 'fullscreen',
    ['profile:fourk'] = 'fourk',
    all = 'hd',
  },
}
```

Resolution order:

1. exact screen identifiers
2. `profile:<name>`
3. bare profile key
4. `all`
5. built-in profile default

### `summon`

Summon-specific config is nested under `summon`.

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
  Terminal = { id = 'com.mitchellh.ghostty' },
  Browser = { id = 'com.brave.Browser' },
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
    key = 'fullscreen',
    name = 'Fullscreen',
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
- per-window `bindFocusedWindowToCell()` overrides can coexist with default app slots
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
```

### What the current test harness covers

- config validation for missing required keys
- screen default resolution order
- custom screen-change reapply delay
- focused-window move behavior that pre-moves onto the destination screen before snapping
- persisted per-window override reload behavior
- summon retry timing and placement retry cut-off

### Real Hammerspoon testing

The highest-signal test setup is:

1. keep your local Hammerspoon config in `~/.hammerspoon/init.lua`
2. symlink `~/.hammerspoon/Spoons/WorkspaceManager.spoon` to this repo
3. symlink `~/.hammerspoon/Spoons/GridLayout.spoon` to a local GridLayout checkout
4. reload Hammerspoon after changes

That lets you test:

- local config
- external `WorkspaceManager.spoon`
- external `GridLayout.spoon`
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
- [examples/single_monitor.lua](examples/single_monitor.lua)
  Minimal single-screen composition example.
- [examples/multi_monitor.lua](examples/multi_monitor.lua)
  Multi-screen composition example.

## License

MIT
