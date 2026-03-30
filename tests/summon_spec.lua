package.path = './?.lua;' .. package.path

local function assertEqual(actual, expected, message)
  if actual ~= expected then
    error(string.format('%s (expected %s, got %s)', message, tostring(expected), tostring(actual)), 2)
  end
end

local function assertContains(haystack, needle, message)
  if not tostring(haystack):find(needle, 1, true) then
    error(string.format('%s (missing %s in %s)', message, tostring(needle), tostring(haystack)), 2)
  end
end

local function newScreen(name, uuid)
  return {
    getUUID = function()
      return uuid
    end,
    name = function()
      return name
    end,
  }
end

local timerQueue = {}
local openCalls = {}

local targetScreen = newScreen('Studio Display', 'studio-display')
local aliasedTargetScreen = newScreen('Studio Display', 'studio-display')
local secondaryScreen = newScreen('Built-in Retina Display', 'builtin-display')

local currentWindowScreen = targetScreen
local alternateWindowScreen = targetScreen
local currentFocusedScreen = targetScreen
local currentMouseScreen = nil
local currentOrderedWindows = {}
local focusCallback = nil
local appFocusWatcherCallback = nil
local app

local appWindow = {
  id = function()
    return 101
  end,
  application = function()
    return app
  end,
  isStandard = function()
    return true
  end,
  screen = function()
    return currentWindowScreen
  end,
  focus = function(self)
    self.focused = true
    return self
  end,
}

local alternateWindow = {
  id = function()
    return 202
  end,
  application = function()
    return app
  end,
  isStandard = function()
    return true
  end,
  screen = function()
    return alternateWindowScreen
  end,
  focus = function(self)
    self.focused = true
    return self
  end,
}

local currentAppWindows = { appWindow }
local currentAppFocusedWindow = appWindow

app = {
  bundleID = function()
    return 'com.mitchellh.ghostty'
  end,
  name = function()
    return 'Terminal'
  end,
  allWindows = function()
    return currentAppWindows
  end,
  focusedWindow = function()
    return currentAppFocusedWindow
  end,
  newWatcher = function(_, callback)
    appFocusWatcherCallback = callback
    return {
      start = function(self)
        return self
      end,
      stop = function() end,
    }
  end,
  activate = function(self)
    self.activated = true
  end,
}

local focusedWindow = {
  screen = function()
    return currentFocusedScreen
  end,
}

hs = {
  application = {
    get = function(identifier)
      if identifier == 'com.mitchellh.ghostty' or identifier == 'Terminal' then
        return app
      end

      return nil
    end,
    find = function(identifier)
      if identifier == 'com.mitchellh.ghostty' or identifier == 'Terminal' then
        return app
      end

      return nil
    end,
    open = function(identifier)
      table.insert(openCalls, identifier)
      if identifier == 'com.brave.Browser' or identifier == 'Browser' then
        return true
      end

      return app
    end,
    frontmostApplication = function()
      return {
        bundleID = function()
          return 'com.apple.finder'
        end,
        name = function()
          return 'Finder'
        end,
      }
    end,
  },
  window = {
    focusedWindow = function()
      return focusedWindow
    end,
    orderedWindows = function()
      return currentOrderedWindows
    end,
    filter = {
      windowFocused = 'windowFocused',
      new = function()
        return {
          subscribe = function(self, _, callback)
            focusCallback = callback
            return self
          end,
          unsubscribeAll = function() end,
        }
      end,
    },
  },
  uielement = {
    watcher = {
      focusedWindowChanged = 'AXFocusedWindowChanged',
    },
  },
  mouse = {
    getCurrentScreen = function()
      return currentMouseScreen
    end,
  },
  screen = {
    mainScreen = function()
      return targetScreen
    end,
    primaryScreen = function()
      return targetScreen
    end,
  },
  timer = {
    doAfter = function(delay, fn)
      table.insert(timerQueue, {
        delay = delay,
        callback = fn,
      })

      return {
        stop = function() end,
      }
    end,
  },
}

local placementCalls = {}
local attempts = 0
local workspaceManager = {
  placeApp = function(appName, screen, preferred)
    attempts = attempts + 1
    table.insert(placementCalls, {
      appName = appName,
      screen = screen:name(),
      preferred = preferred,
    })

    return attempts >= 3
  end,
}

local function resetState()
  placementCalls = {}
  timerQueue = {}
  openCalls = {}
  attempts = 0
  app.activated = nil
  appWindow.focused = nil
  alternateWindow.focused = nil
  currentMouseScreen = nil
  currentFocusedScreen = targetScreen
  currentWindowScreen = targetScreen
  alternateWindowScreen = targetScreen
  currentAppWindows = { appWindow }
  currentAppFocusedWindow = appWindow
  currentOrderedWindows = { appWindow }
end

local summon = dofile('./summon.lua')(workspaceManager)
local summonConfig = {
  apps = {
    Terminal = {
      id = 'com.mitchellh.ghostty',
    },
    Browser = {
      id = 'com.brave.Browser',
    },
  },
  summon = {
    placementDelaySeconds = 0.05,
    placementAttempts = 3,
  },
}

local function restartSummon()
  summon.stop()
  summon.start(summonConfig)
end

do
  local invalidSummon = dofile('./summon.lua')(workspaceManager)
  local ok, err = pcall(function()
    invalidSummon.start({
      apps = {
        Terminal = {
          id = 'com.mitchellh.ghostty',
        },
      },
      summon = {
        placementAttempts = -1,
      },
    })
  end)

  assertEqual(ok, false, 'summon.start() should fail on invalid retry counts')
  assertContains(err, 'placementAttempts', 'summon.start() should explain the invalid retry count')
end

resetState()
restartSummon()
summon.summon('Terminal')

assertEqual(app.activated, nil, 'summon should not pre-activate an existing standard window before placement')
assertEqual(appWindow.focused, nil, 'summon should not pre-focus the preferred window before placement retries')
assertEqual(#placementCalls, 1, 'summon should attempt placement immediately')
assertEqual(#timerQueue, 1, 'failed placement should schedule a retry')
assertEqual(timerQueue[1].delay, 0.05, 'retry should use configured placement delay')
assertEqual(placementCalls[1].screen, 'Studio Display', 'summon should keep an existing app on its current screen')

timerQueue[1].callback()

assertEqual(#placementCalls, 2, 'first retry should attempt placement again')
assertEqual(#timerQueue, 2, 'first retry should schedule a second retry when still failing')

timerQueue[2].callback()

assertEqual(#placementCalls, 3, 'second retry should attempt placement again')
assertEqual(#timerQueue, 2, 'successful placement should stop scheduling additional retries')
assertEqual(#openCalls, 0, 'existing apps should not be reopened')

resetState()
restartSummon()
currentMouseScreen = targetScreen
currentFocusedScreen = secondaryScreen
currentWindowScreen = secondaryScreen

summon.summon('Terminal')

assertEqual(app.activated, nil, 'summon should not pre-activate an existing standard window before placement')
assertEqual(appWindow.focused, nil, 'summon should not focus an off-screen window before placement')
assertEqual(#placementCalls, 1, 'mouse-targeted summon should still attempt placement immediately')
assertEqual(placementCalls[1].screen, 'Built-in Retina Display', 'summon should keep an existing app on its current screen even when the mouse is elsewhere')

resetState()
restartSummon()
currentMouseScreen = aliasedTargetScreen
currentFocusedScreen = secondaryScreen
currentWindowScreen = secondaryScreen
alternateWindowScreen = targetScreen
currentAppWindows = { appWindow, alternateWindow }
currentAppFocusedWindow = appWindow
currentOrderedWindows = {}

summon.summon('Terminal')

assertEqual(#placementCalls, 1, 'summon should attempt placement when multiple windows exist')
assertEqual(placementCalls[1].screen, 'Built-in Retina Display', 'summon should prefer the app-focused window before weaker fallbacks')
assertEqual(placementCalls[1].preferred, appWindow, 'summon should use the app-focused window when it is available')

resetState()
restartSummon()
currentMouseScreen = aliasedTargetScreen
currentFocusedScreen = secondaryScreen
currentWindowScreen = secondaryScreen
alternateWindowScreen = targetScreen
currentAppWindows = { appWindow, alternateWindow }
currentAppFocusedWindow = nil
currentOrderedWindows = {}

summon.summon('Terminal')

assertEqual(#placementCalls, 1, 'summon should attempt placement when no preferred or focused window is known')
assertEqual(placementCalls[1].screen, 'Studio Display', 'summon should prefer a window already on the target screen when stronger preferences are unavailable')
assertEqual(placementCalls[1].preferred, alternateWindow, 'summon should pick the matching on-screen window even when screen objects differ')

resetState()
restartSummon()
currentMouseScreen = targetScreen
currentWindowScreen = targetScreen
alternateWindowScreen = secondaryScreen
currentAppWindows = { appWindow, alternateWindow }
currentAppFocusedWindow = appWindow
currentOrderedWindows = { appWindow, alternateWindow }

appFocusWatcherCallback(appWindow, hs.uielement.watcher.focusedWindowChanged)
appFocusWatcherCallback(alternateWindow, hs.uielement.watcher.focusedWindowChanged)

summon.summon('Terminal')

assertEqual(#placementCalls, 1, 'summon should attempt placement after same-app window focus changes')
assertEqual(placementCalls[1].screen, 'Built-in Retina Display', 'summon should restore the most recently focused window even when another window is on the invocation screen')
assertEqual(placementCalls[1].preferred, alternateWindow, 'summon should remember the last focused standard window for an app')

resetState()
restartSummon()
currentMouseScreen = targetScreen
currentWindowScreen = targetScreen
alternateWindowScreen = secondaryScreen
currentAppWindows = { appWindow, alternateWindow }
currentAppFocusedWindow = nil
currentOrderedWindows = { alternateWindow, appWindow }

summon.summon('Terminal')

assertEqual(#placementCalls, 1, 'summon should attempt placement when inferring the preferred window from z-order')
assertEqual(placementCalls[1].screen, 'Built-in Retina Display', 'summon should use the most recent visible window for the app when no watcher update was recorded')
assertEqual(placementCalls[1].preferred, alternateWindow, 'summon should fall back to global window ordering for app window recall')

resetState()
restartSummon()
currentMouseScreen = targetScreen
currentWindowScreen = targetScreen
alternateWindowScreen = secondaryScreen
currentAppWindows = { appWindow, alternateWindow }
currentOrderedWindows = { appWindow }

appFocusWatcherCallback(alternateWindow, hs.uielement.watcher.focusedWindowChanged)
currentAppWindows = { appWindow }
currentAppFocusedWindow = appWindow

summon.summon('Terminal')

assertEqual(#placementCalls, 1, 'summon should still attempt placement when the remembered window is gone')
assertEqual(placementCalls[1].screen, 'Studio Display', 'summon should fall back to an on-screen window when the remembered one no longer exists')
assertEqual(placementCalls[1].preferred, appWindow, 'summon should clear stale remembered windows and fall back cleanly')

resetState()
restartSummon()
currentMouseScreen = targetScreen
currentFocusedScreen = secondaryScreen

summon.summon('Browser')

assertEqual(#openCalls, 1, 'summon should open unopened apps')
assertEqual(openCalls[1], 'com.brave.Browser', 'summon should open the configured app identifier')
assertEqual(#placementCalls, 1, 'summon should place unopened apps immediately after opening them')
assertEqual(placementCalls[1].screen, 'Studio Display', 'summon should place unopened apps on the invocation screen')

print('summon_spec ok')
