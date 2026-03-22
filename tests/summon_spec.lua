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

local timerQueue = {}
local openCalls = {}

local targetScreen = {
  name = function()
    return 'Studio Display'
  end,
}

local appWindow = {
  isStandard = function()
    return true
  end,
  screen = function()
    return targetScreen
  end,
  focus = function(self)
    self.focused = true
    return self
  end,
}

local app = {
  bundleID = function()
    return 'com.mitchellh.ghostty'
  end,
  name = function()
    return 'Terminal'
  end,
  allWindows = function()
    return { appWindow }
  end,
  focusedWindow = function()
    return appWindow
  end,
  activate = function(self)
    self.activated = true
  end,
}

local focusedWindow = {
  screen = function()
    return targetScreen
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
  },
  summon = {
    placementDelaySeconds = 0.05,
    placementAttempts = 3,
  },
})

summon.summon('Terminal')

assertEqual(app.activated, true, 'summon should activate an existing app before placing it')
assertEqual(appWindow.focused, true, 'summon should focus the preferred window before placement retries')
assertEqual(#placementCalls, 1, 'summon should attempt placement immediately')
assertEqual(#timerQueue, 1, 'failed placement should schedule a retry')
assertEqual(timerQueue[1].delay, 0.05, 'retry should use configured placement delay')

timerQueue[1].callback()

assertEqual(#placementCalls, 2, 'first retry should attempt placement again')
assertEqual(#timerQueue, 2, 'first retry should schedule a second retry when still failing')

timerQueue[2].callback()

assertEqual(#placementCalls, 3, 'second retry should attempt placement again')
assertEqual(#timerQueue, 2, 'successful placement should stop scheduling additional retries')
assertEqual(#openCalls, 0, 'existing apps should not be reopened')

print('summon_spec ok')
