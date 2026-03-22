--------------------------------------------------------------------------------
-- WorkspaceManager.spoon
--------------------------------------------------------------------------------

local M = {
  name = 'WorkspaceManager',
  version = '0.1.0',
  author = 'TechDufus',
  license = 'MIT <https://opensource.org/licenses/MIT>',
  homepage = 'https://github.com/TechDufus/WorkspaceManager.spoon',
}

local runtime = nil
local summon = nil
local screenWatcher = nil

local function ensureModules()
  runtime = runtime or dofile(hs.spoons.resourcePath('workspace_manager.lua'))
  summon = summon or dofile(hs.spoons.resourcePath('summon.lua'))(runtime)
end

function M:start(config)
  ensureModules()

  runtime.start(config or {})
  summon.start(config or {})

  if screenWatcher then
    screenWatcher:stop()
  end

  screenWatcher = hs.screen.watcher.new(function()
    runtime.handleScreenChange()
  end)
  screenWatcher:start()

  return self
end

function M:stop()
  if screenWatcher then
    screenWatcher:stop()
    screenWatcher = nil
  end

  if summon and summon.stop then
    summon.stop()
  end

  if runtime and runtime.stop then
    runtime.stop()
  end

  return self
end

function M:apply()
  runtime.apply()
  return self
end

function M:showLayoutPicker(targetScreen)
  runtime.showLayoutPicker(targetScreen)
  return self
end

function M:selectLayout(layoutRef, targetScreen)
  runtime.selectLayout(layoutRef, targetScreen)
  return self
end

function M:selectNextVariant(targetScreen)
  runtime.selectNextVariant(targetScreen)
  return self
end

function M:resetLayout(targetScreen)
  runtime.resetLayout(targetScreen)
  return self
end

function M:bindFocusedWindowToCell()
  runtime.bindFocusedWindowToCell()
  return self
end

function M:summon(appName)
  summon.summon(appName)
  return self
end

function M:moveFocusedWindowToNextScreen()
  runtime.moveFocusedWindowToNextScreen()
  return self
end

function M:moveFocusedWindowToPreviousScreen()
  runtime.moveFocusedWindowToPreviousScreen()
  return self
end

return M
