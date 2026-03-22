# WorkspaceManager.spoon

Screen-aware workspace orchestration for Hammerspoon on top of `GridLayout.spoon`.

## Status

This repository is being extracted from a working dotfiles-based Hammerspoon setup.
It currently targets real-world use first, with packaging cleanup following behind.

## Responsibilities

`WorkspaceManager.spoon` owns:
- per-screen workspace state
- persisted layout selection and variant state
- screen-aware summon behavior
- focused-window movement between screens
- per-window cell overrides
- orchestration of active layouts through `GridLayout.spoon`

It does not own:
- your app bundle IDs
- your layout definitions
- your screen default mappings
- your keybindings or modal structure

## Dependency

This spoon depends on `GridLayout.spoon`.

That dependency is explicit. `WorkspaceManager.spoon` expects a configured GridLayout spoon
instance to be provided in `:start(config)`.

## Installation

Install both spoons into `~/.hammerspoon/Spoons/`:

1. `GridLayout.spoon`
2. `WorkspaceManager.spoon`

`WorkspaceManager.spoon` does not vendor or secretly auto-load GridLayout. Your Hammerspoon
config should load GridLayout first, configure it, and then inject that instance into
`WorkspaceManager.spoon`.

## Example

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

## API

- `:start(config)`
- `:stop()`
- `:apply()`
- `:showLayoutPicker([screen])`
- `:selectLayout(layoutRef[, screen])`
- `:selectNextVariant([screen])`
- `:resetLayout([screen])`
- `:bindFocusedWindowToCell()`
- `:summon(appName)`
- `:moveFocusedWindowToNextScreen()`
- `:moveFocusedWindowToPreviousScreen()`

## Config

### Required keys

- `layoutEngine`: configured `GridLayout.spoon` instance
- `apps`: app definition table
- `layouts`: layout definition table

### Optional keys

- `screenLayouts`: per-screen default mapping table
- `settingsKey`: `hs.settings` key used for persisted state
- `defaultLayoutKeys`: profile fallback overrides
- `openAppReapplyDelaySeconds`: delay before re-applying after auto-opening an app
- `screenChangeDelaySeconds`: delay before re-applying after monitor changes
- `summon`: summon-specific configuration table

### Defaults

Current built-in defaults:

- `settingsKey = 'workspaces.screen_state.v1'`
- `openAppReapplyDelaySeconds = 0.5`
- `screenChangeDelaySeconds = 1`
- summon placement retry delay = `0.2`
- summon placement attempts = `10`
- default layout by screen profile:
  - `builtin -> fullscreen`
  - `fourk -> fourk`
  - `standard -> hd`
  - `ultrawide -> standard`

### `screenLayouts`

`screenLayouts` is optional. If omitted, the profile defaults above are used.

Supported keys match the screen identity strategy used by the runtime:

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
    all = 'hd',
  },
}
```

Resolution order is:

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

`apps` is the same app table you already use to identify managed apps.

Minimum shape:

```lua
local apps = {
  Terminal = { id = 'com.mitchellh.ghostty' },
  Browser = { id = 'com.brave.Browser' },
}
```

Additional keys are fine. `WorkspaceManager.spoon` only depends on the app identifier; other
keys can stay for your own config layer, modals, or summon bindings.

### Layout config shape

`layouts` is an ordered list of GridLayout-compatible layouts.

Minimum shape:

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

Screen-aware cells from the multi-monitor GridLayout patch are supported through the injected
`GridLayout.spoon` dependency.

## Persistence

Persisted state includes:

- per-screen active layout
- per-screen active variant
- per-layout app overrides
- per-layout per-window overrides

Preferred window tracking is intentionally runtime-only and is not persisted.

## Behavior Notes

- single-window moves should not trigger full-screen layout flicker
- `cmd+o`-style next-screen movement is focused-window-only
- per-window `bindFocusedWindowToCell()` overrides can coexist with default app slots
- if only one screen is present, next/previous screen movement becomes a no-op

## License

MIT
