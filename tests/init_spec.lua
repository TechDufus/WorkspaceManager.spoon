package.path = './?.lua;' .. package.path

local function assertEqual(actual, expected, message)
  if actual ~= expected then
    error(string.format('%s (expected %s, got %s)', message, tostring(expected), tostring(actual)), 2)
  end
end

local function assertSame(actual, expected, message)
  if actual ~= expected then
    error(message, 2)
  end
end

local state = {
  calls = {},
  lastArgs = {},
  watcherStarts = 0,
  watcherStops = 0,
}

_G.__workspaceManagerInitTest = state

hs = {
  spoons = {
    resourcePath = function(name)
      if name == 'workspace_manager.lua' then
        return './tests/fixtures/runtime_stub.lua'
      end

      if name == 'summon.lua' then
        return './tests/fixtures/summon_stub.lua'
      end

      error('unexpected resource request: ' .. tostring(name))
    end,
  },
  screen = {
    watcher = {
      new = function(callback)
        state.watcherCallback = callback
        return {
          start = function()
            state.watcherStarts = state.watcherStarts + 1
          end,
          stop = function()
            state.watcherStops = state.watcherStops + 1
          end,
        }
      end,
    },
  },
}

local spoon = dofile('./init.lua')
local config = {
  marker = 'config',
}

spoon:start(config)

assertEqual(state.calls['runtime.start'], 1, 'spoon:start() should initialize the runtime')
assertEqual(state.calls['summon.start'], 1, 'spoon:start() should initialize summon support')
assertEqual(state.watcherStarts, 1, 'spoon:start() should start the screen watcher')
assertSame(state.summonRuntime, state.runtimeModule, 'summon should receive the cached runtime module')

state.watcherCallback()
assertEqual(state.calls['runtime.handleScreenChange'], 1, 'screen watcher should forward display changes to the runtime')

spoon:apply()
spoon:showLayoutPicker('screen-a')
spoon:selectLayout('fullscreen', 'screen-b')
spoon:selectNextVariant('screen-c')
spoon:resetLayout('screen-d')
spoon:bindFocusedWindowToCell()
spoon:bindFocusedAppToCell()
spoon:setAppCell('Terminal', 2, 'screen-e')
spoon:clearAppCell('Terminal', 'screen-f')
spoon:summon('Terminal')
spoon:moveFocusedWindowToNextScreen()
spoon:moveFocusedWindowToPreviousScreen()

assertEqual(state.calls['runtime.apply'], 1, 'spoon:apply() should forward to the runtime')
assertEqual(state.calls['runtime.showLayoutPicker'], 1, 'spoon:showLayoutPicker() should forward to the runtime')
assertEqual(state.calls['runtime.selectLayout'], 1, 'spoon:selectLayout() should forward to the runtime')
assertEqual(state.calls['runtime.selectNextVariant'], 1, 'spoon:selectNextVariant() should forward to the runtime')
assertEqual(state.calls['runtime.resetLayout'], 1, 'spoon:resetLayout() should forward to the runtime')
assertEqual(state.calls['runtime.bindFocusedWindowToCell'], 1, 'spoon:bindFocusedWindowToCell() should forward to the runtime')
assertEqual(state.calls['runtime.bindFocusedAppToCell'], 1, 'spoon:bindFocusedAppToCell() should forward to the runtime')
assertEqual(state.calls['runtime.setAppCell'], 1, 'spoon:setAppCell() should forward to the runtime')
assertEqual(state.calls['runtime.clearAppCell'], 1, 'spoon:clearAppCell() should forward to the runtime')
assertEqual(state.calls['summon.summon'], 1, 'spoon:summon() should forward to summon support')
assertEqual(state.calls['runtime.moveFocusedWindowToNextScreen'], 1, 'spoon:moveFocusedWindowToNextScreen() should forward to the runtime')
assertEqual(state.calls['runtime.moveFocusedWindowToPreviousScreen'], 1, 'spoon:moveFocusedWindowToPreviousScreen() should forward to the runtime')

spoon:start(config)
assertEqual(state.watcherStops, 1, 'restarting should stop the previous watcher before replacing it')
assertEqual(state.watcherStarts, 2, 'restarting should start a fresh watcher')

spoon:stop()
assertEqual(state.watcherStops, 2, 'spoon:stop() should stop the active screen watcher')
assertEqual(state.calls['runtime.stop'], 1, 'spoon:stop() should stop the runtime')
assertEqual(state.calls['summon.stop'], 1, 'spoon:stop() should stop summon support')

_G.__workspaceManagerInitTest = nil

print('init_spec ok')
