local positions = {
  full_grid = '80x40',
  full = '0,0 80x40',
  wide_left = '0,0 52x40',
  wide_right = '52,0 28x40',
}

local apps = {
  Terminal = { id = 'com.apple.Terminal' },
  Browser = { id = 'com.apple.Safari' },
  Notes = { id = 'com.apple.Notes' },
}

local layouts = {
  {
    key = 'wide',
    name = 'Wide Workspace',
    cells = {
      { positions.wide_left },
      { positions.wide_right },
    },
    apps = {
      Terminal = { cell = 1, open = true },
      Browser = { cell = 2, open = true },
      Notes = { cell = 2 },
    },
  },
  {
    key = 'focus',
    name = 'Focus',
    cells = {
      { positions.full },
    },
    apps = {
      Terminal = { cell = 1, open = true },
      Browser = { cell = 1, open = true },
      Notes = { cell = 1 },
    },
  },
}

local screenLayouts = {
  layouts = {
    ['profile:fourk'] = 'wide',
    ['profile:builtin'] = 'focus',
  },
}

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
    summon = {
      placementDelaySeconds = 0.2,
      placementAttempts = 10,
    },
  })

workspaceManager:apply()

hs.hotkey.bind({ 'cmd' }, 'o', function()
  workspaceManager:moveFocusedWindowToNextScreen()
end)

hs.hotkey.bind({ 'shift', 'cmd' }, 'o', function()
  workspaceManager:moveFocusedWindowToPreviousScreen()
end)

hs.hotkey.bind({ 'shift', 'cmd' }, 'u', function()
  workspaceManager:bindFocusedAppToCell()
end)
