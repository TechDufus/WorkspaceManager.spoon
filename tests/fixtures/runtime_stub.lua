local state = assert(rawget(_G, '__workspaceManagerInitTest'), 'missing init test state')

local function record(name, ...)
  state.calls[name] = (state.calls[name] or 0) + 1
  state.lastArgs[name] = { ... }
end

local M = {}
state.runtimeModule = M

function M.start(config)
  record('runtime.start', config)
  return M
end

function M.stop()
  record('runtime.stop')
  return M
end

function M.apply()
  record('runtime.apply')
end

function M.showLayoutPicker(targetScreen)
  record('runtime.showLayoutPicker', targetScreen)
end

function M.selectLayout(layoutRef, targetScreen)
  record('runtime.selectLayout', layoutRef, targetScreen)
end

function M.selectNextVariant(targetScreen)
  record('runtime.selectNextVariant', targetScreen)
end

function M.resetLayout(targetScreen)
  record('runtime.resetLayout', targetScreen)
end

function M.bindFocusedWindowToCell()
  record('runtime.bindFocusedWindowToCell')
end

function M.bindFocusedAppToCell()
  record('runtime.bindFocusedAppToCell')
end

function M.setAppCell(appName, cellIndex, targetScreen)
  record('runtime.setAppCell', appName, cellIndex, targetScreen)
end

function M.clearAppCell(appName, targetScreen)
  record('runtime.clearAppCell', appName, targetScreen)
end

function M.moveFocusedWindowToNextScreen()
  record('runtime.moveFocusedWindowToNextScreen')
end

function M.moveFocusedWindowToPreviousScreen()
  record('runtime.moveFocusedWindowToPreviousScreen')
end

function M.handleScreenChange()
  record('runtime.handleScreenChange')
end

return M
