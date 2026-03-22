local apps = {
  Terminal = { id = 'com.mitchellh.ghostty' },
  Browser = { id = 'com.brave.Browser' },
}

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

hs.hotkey.bind({ 'cmd' }, 'u', function()
  workspaceManager:bindFocusedWindowToCell()
end)
