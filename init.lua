--------------------------------------------------------------------------------
-- WorkspaceManager.spoon
--------------------------------------------------------------------------------

--- === WorkspaceManager ===
---
--- Screen-aware workspace orchestration for Hammerspoon on top of GridLayout.spoon.
---
--- Notes:
--- * Inject a configured GridLayout spoon via `:start(config)`.
--- * This Spoon owns runtime workspace state, layout selection, summon behavior, and overrides.
local M = {}

--- WorkspaceManager.name
--- Variable
--- The name of the Spoon.
M.name = 'WorkspaceManager'

--- WorkspaceManager.version
--- Variable
--- The version of the Spoon.
M.version = '0.1.1'

--- WorkspaceManager.author
--- Variable
--- The author of the Spoon.
M.author = 'TechDufus'

--- WorkspaceManager.license
--- Variable
--- The license of the Spoon.
M.license = 'MIT <https://opensource.org/licenses/MIT>'

--- WorkspaceManager.homepage
--- Variable
--- The homepage of the Spoon.
M.homepage = 'https://github.com/TechDufus/WorkspaceManager.spoon'

local runtime = nil
local summon = nil
local screenWatcher = nil

local function ensureModules()
  runtime = runtime or dofile(hs.spoons.resourcePath('workspace_manager.lua'))
  summon = summon or dofile(hs.spoons.resourcePath('summon.lua'))(runtime)
end

--- WorkspaceManager:start(config)
--- Method
--- Starts the Spoon runtime.
---
--- Parameters:
---  * config - A table containing the WorkspaceManager configuration.
---
--- Returns:
---  * The WorkspaceManager Spoon object.
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

--- WorkspaceManager:stop()
--- Method
--- Stops timers and watchers owned by the Spoon runtime.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The WorkspaceManager Spoon object.
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

--- WorkspaceManager:apply()
--- Method
--- Rebuilds the active synthetic layout and applies it through the injected GridLayout spoon.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The WorkspaceManager Spoon object.
function M:apply()
  runtime.apply()
  return self
end

--- WorkspaceManager:showLayoutPicker([targetScreen])
--- Method
--- Opens the layout chooser for the focused screen or a supplied target screen.
---
--- Parameters:
---  * targetScreen - An optional `hs.screen` object to target instead of the focused screen.
---
--- Returns:
---  * The WorkspaceManager Spoon object.
function M:showLayoutPicker(targetScreen)
  runtime.showLayoutPicker(targetScreen)
  return self
end

--- WorkspaceManager:selectLayout(layoutRef[, targetScreen])
--- Method
--- Selects the active layout for a screen and reapplies the workspace state.
---
--- Parameters:
---  * layoutRef - A layout key or layout table to activate.
---  * targetScreen - An optional `hs.screen` object to target instead of the focused screen.
---
--- Returns:
---  * The WorkspaceManager Spoon object.
function M:selectLayout(layoutRef, targetScreen)
  runtime.selectLayout(layoutRef, targetScreen)
  return self
end

--- WorkspaceManager:selectNextVariant([targetScreen])
--- Method
--- Selects the next variant for the active layout on a screen.
---
--- Parameters:
---  * targetScreen - An optional `hs.screen` object to target instead of the focused screen.
---
--- Returns:
---  * The WorkspaceManager Spoon object.
function M:selectNextVariant(targetScreen)
  runtime.selectNextVariant(targetScreen)
  return self
end

--- WorkspaceManager:resetLayout([targetScreen])
--- Method
--- Clears overrides for the active layout on a screen and reapplies the layout defaults.
---
--- Parameters:
---  * targetScreen - An optional `hs.screen` object to target instead of the focused screen.
---
--- Returns:
---  * The WorkspaceManager Spoon object.
function M:resetLayout(targetScreen)
  runtime.resetLayout(targetScreen)
  return self
end

--- WorkspaceManager:bindFocusedWindowToCell()
--- Method
--- Opens a chooser that binds the focused window to a cell override on the active layout.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The WorkspaceManager Spoon object.
function M:bindFocusedWindowToCell()
  runtime.bindFocusedWindowToCell()
  return self
end

--- WorkspaceManager:bindFocusedAppToCell()
--- Method
--- Opens a chooser that binds the focused app to a cell override on the active layout.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The WorkspaceManager Spoon object.
function M:bindFocusedAppToCell()
  runtime.bindFocusedAppToCell()
  return self
end

--- WorkspaceManager:setAppCell(appName, cellIndex[, targetScreen])
--- Method
--- Persists a per-app cell override for a screen's active layout and reapplies the workspace.
---
--- Parameters:
---  * appName - A string containing the logical app name from `config.apps`.
---  * cellIndex - A number containing the 1-based target cell index.
---  * targetScreen - An optional `hs.screen` object to target instead of the focused screen.
---
--- Returns:
---  * The WorkspaceManager Spoon object.
function M:setAppCell(appName, cellIndex, targetScreen)
  runtime.setAppCell(appName, cellIndex, targetScreen)
  return self
end

--- WorkspaceManager:clearAppCell(appName[, targetScreen])
--- Method
--- Removes a per-app override and reverts the app to its layout default cell.
---
--- Parameters:
---  * appName - A string containing the logical app name from `config.apps`.
---  * targetScreen - An optional `hs.screen` object to target instead of the focused screen.
---
--- Returns:
---  * The WorkspaceManager Spoon object.
function M:clearAppCell(appName, targetScreen)
  runtime.clearAppCell(appName, targetScreen)
  return self
end

--- WorkspaceManager:summon(appName)
--- Method
--- Opens or focuses an app and places it on the active screen and workspace.
---
--- Parameters:
---  * appName - A string containing the logical app name from `config.apps`.
---
--- Returns:
---  * The WorkspaceManager Spoon object.
function M:summon(appName)
  summon.summon(appName)
  return self
end

--- WorkspaceManager:moveFocusedWindowToNextScreen()
--- Method
--- Moves the focused window to the next screen and reapplies its snapped position there.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The WorkspaceManager Spoon object.
function M:moveFocusedWindowToNextScreen()
  runtime.moveFocusedWindowToNextScreen()
  return self
end

--- WorkspaceManager:moveFocusedWindowToPreviousScreen()
--- Method
--- Moves the focused window to the previous screen and reapplies its snapped position there.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The WorkspaceManager Spoon object.
function M:moveFocusedWindowToPreviousScreen()
  runtime.moveFocusedWindowToPreviousScreen()
  return self
end

return M
