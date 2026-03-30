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

local appWindow = {
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

local app = {
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
    filter = {
      windowFocused = 'windowFocused',
      new = function()
        return {
          subscribe = function(self)
            return self
          end,
          unsubscribeAll = function() end,
        }
      end,
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
end

local summon = dofile('./summon.lua')(workspaceManager)

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

summon.start({
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
})

resetState()
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
currentMouseScreen = targetScreen
currentFocusedScreen = secondaryScreen
currentWindowScreen = secondaryScreen

summon.summon('Terminal')

assertEqual(app.activated, nil, 'summon should not pre-activate an existing standard window before placement')
assertEqual(appWindow.focused, nil, 'summon should not focus an off-screen window before placement')
assertEqual(#placementCalls, 1, 'mouse-targeted summon should still attempt placement immediately')
assertEqual(placementCalls[1].screen, 'Built-in Retina Display', 'summon should keep an existing app on its current screen even when the mouse is elsewhere')

resetState()
currentMouseScreen = aliasedTargetScreen
currentFocusedScreen = secondaryScreen
currentWindowScreen = secondaryScreen
alternateWindowScreen = targetScreen
currentAppWindows = { appWindow, alternateWindow }
currentAppFocusedWindow = appWindow

summon.summon('Terminal')

assertEqual(#placementCalls, 1, 'summon should attempt placement when multiple windows exist')
assertEqual(placementCalls[1].screen, 'Studio Display', 'summon should prefer a window already on the target screen')
assertEqual(placementCalls[1].preferred, alternateWindow, 'summon should pick the matching on-screen window even when screen objects differ')

resetState()
currentMouseScreen = targetScreen
currentFocusedScreen = secondaryScreen

summon.summon('Browser')

assertEqual(#openCalls, 1, 'summon should open unopened apps')
assertEqual(openCalls[1], 'com.brave.Browser', 'summon should open the configured app identifier')
assertEqual(#placementCalls, 1, 'summon should place unopened apps immediately after opening them')
assertEqual(placementCalls[1].screen, 'Studio Display', 'summon should place unopened apps on the invocation screen')

print('summon_spec ok')
