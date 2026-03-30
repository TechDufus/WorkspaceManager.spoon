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
local currentFrontmostApp = nil
local currentHsFocusedWindow = nil
local focusCallback = nil
local appFocusWatcherCallback = nil
local app
local delayedFocusRemaining = 0

local finderApp = {
  bundleID = function()
    return 'com.apple.finder'
  end,
  name = function()
    return 'Finder'
  end,
}

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
    if delayedFocusRemaining > 0 then
      delayedFocusRemaining = delayedFocusRemaining - 1
      return self
    end

    self.focused = true
    currentFrontmostApp = app
    currentHsFocusedWindow = self
    return self
  end,
  raise = function(self)
    self.raised = true
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
    if delayedFocusRemaining > 0 then
      delayedFocusRemaining = delayedFocusRemaining - 1
      return self
    end

    self.focused = true
    currentFrontmostApp = app
    currentHsFocusedWindow = self
    return self
  end,
  raise = function(self)
    self.raised = true
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
    currentFrontmostApp = self
    return true
  end,
}

local focusedWindow = {
  id = function()
    return 999
  end,
  application = function()
    return finderApp
  end,
  isStandard = function()
    return false
  end,
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
      return currentFrontmostApp
    end,
  },
  window = {
    focusedWindow = function()
      return currentHsFocusedWindow
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
  appWindow.raised = nil
  alternateWindow.focused = nil
  alternateWindow.raised = nil
  currentMouseScreen = nil
  currentFocusedScreen = targetScreen
  currentWindowScreen = targetScreen
  alternateWindowScreen = targetScreen
  currentAppWindows = { appWindow }
  currentAppFocusedWindow = appWindow
  currentOrderedWindows = { appWindow }
  currentFrontmostApp = finderApp
  currentHsFocusedWindow = focusedWindow
  delayedFocusRemaining = 0
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

assertEqual(app.activated, true, 'summon should activate an existing app before focusing its window')
assertEqual(appWindow.focused, true, 'summon should focus an existing standard window immediately')
assertEqual(#placementCalls, 0, 'summon should not run placement for existing standard windows')
assertEqual(#timerQueue, 0, 'summon should not schedule retries for existing standard windows')
assertEqual(#openCalls, 0, 'existing apps should not be reopened')

resetState()
restartSummon()
currentMouseScreen = targetScreen
currentFocusedScreen = secondaryScreen
currentWindowScreen = secondaryScreen

summon.summon('Terminal')

assertEqual(app.activated, true, 'summon should activate an existing app before focusing its window')
assertEqual(appWindow.focused, true, 'summon should focus an existing off-screen window without moving it')
assertEqual(#placementCalls, 0, 'mouse-targeted summon should not re-place an existing standard window')

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

assertEqual(appWindow.focused, true, 'summon should focus the app-focused window when it is available')
assertEqual(alternateWindow.focused, nil, 'summon should not focus weaker fallback windows when a stronger preference exists')
assertEqual(#placementCalls, 0, 'summon should not place existing windows when choosing between multiple windows')

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

assertEqual(alternateWindow.focused, true, 'summon should pick the matching on-screen window even when screen objects differ')
assertEqual(appWindow.focused, nil, 'summon should not focus weaker window fallbacks when a same-screen window exists')
assertEqual(#placementCalls, 0, 'summon should not place existing windows when using screen fallback')

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

assertEqual(alternateWindow.focused, true, 'summon should remember the last focused standard window for an app')
assertEqual(appWindow.focused, nil, 'summon should not revert to another window when a remembered window exists')
assertEqual(#placementCalls, 0, 'summon should not place existing windows when restoring remembered windows')

resetState()
restartSummon()
currentMouseScreen = targetScreen
currentWindowScreen = targetScreen
alternateWindowScreen = secondaryScreen
currentAppWindows = { appWindow, alternateWindow }
currentAppFocusedWindow = nil
currentOrderedWindows = { alternateWindow, appWindow }

summon.summon('Terminal')

assertEqual(alternateWindow.focused, true, 'summon should fall back to global window ordering for app window recall')
assertEqual(appWindow.focused, nil, 'summon should not focus a less recent window when z-order provides a better choice')
assertEqual(#placementCalls, 0, 'summon should not place existing windows when inferring from z-order')

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

assertEqual(appWindow.focused, true, 'summon should clear stale remembered windows and fall back cleanly')
assertEqual(alternateWindow.focused, nil, 'summon should not focus a missing remembered window')
assertEqual(#placementCalls, 0, 'summon should not place existing windows when clearing stale remembered windows')

resetState()
restartSummon()
delayedFocusRemaining = 1

summon.summon('Terminal')

assertEqual(appWindow.focused, nil, 'summon should retry focus when the initial focus call does not stick')
assertEqual(#timerQueue, 1, 'summon should schedule a focus retry when the target app is not frontmost yet')

timerQueue[1].callback()

assertEqual(appWindow.focused, true, 'summon should eventually focus the target window after a retry')
assertEqual(appWindow.raised, true, 'summon should raise the target window before retrying focus')
assertEqual(#placementCalls, 0, 'summon should not place existing windows when focus only needs a retry')

resetState()
restartSummon()
currentMouseScreen = targetScreen
currentFocusedScreen = secondaryScreen

summon.summon('Browser')

assertEqual(#openCalls, 1, 'summon should open unopened apps')
assertEqual(openCalls[1], 'com.brave.Browser', 'summon should open the configured app identifier')
assertEqual(#placementCalls, 1, 'summon should place unopened apps immediately after opening them')
assertEqual(placementCalls[1].screen, 'Studio Display', 'summon should place unopened apps on the invocation screen')

resetState()
restartSummon()

summon.summon('Browser')
summon.summon('Terminal')

assertEqual(#placementCalls, 1, 'opening an unopened app should still place it immediately')
assertEqual(#timerQueue, 1, 'opening an unopened app should still schedule retries when placement fails')
assertEqual(appWindow.focused, true, 'a newer summon should focus an existing window immediately')

timerQueue[1].callback()

assertEqual(#placementCalls, 1, 'stale retries should not run after a newer summon supersedes them')

print('summon_spec ok')
