local positions = {
  full_grid = '80x40',
  full = '0,0 80x40',
  fourk_left = '0,0 52x40',
  fourk_right = '52,0 28x40',
}

local apps = {
  Terminal = { id = 'com.mitchellh.ghostty' },
  Browser = { id = 'com.brave.Browser' },
  Chat = { id = 'Mattermost.Desktop' },
}

local layouts = {
  {
    key = 'fourk',
    name = '4K Workspace',
    cells = {
      { positions.fourk_left },
      { positions.fourk_right },
    },
    apps = {
      Terminal = { cell = 1, open = true },
      Browser = { cell = 2, open = true },
      Chat = { cell = 2 },
    },
  },
  {
    key = 'fullscreen',
    name = 'Fullscreen',
    cells = {
      { positions.full },
    },
    apps = {
      Terminal = { cell = 1, open = true },
      Browser = { cell = 1, open = true },
      Chat = { cell = 1 },
    },
  },
}

local screenLayouts = {
  layouts = {
    ['profile:fourk'] = 'fourk',
    ['profile:builtin'] = 'fullscreen',
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
