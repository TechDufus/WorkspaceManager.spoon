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

local function newScreen(config)
  local screen = {
    _uuid = config.uuid,
    _id = config.id,
    _name = config.name,
    _frame = config.frame,
    _mode = config.mode,
    _availableModes = config.availableModes or { config.mode },
  }

  function screen:getUUID()
    return self._uuid
  end

  function screen:id()
    return self._id
  end

  function screen:name()
    return self._name
  end

  function screen:frame()
    return self._frame
  end

  function screen:currentMode()
    return self._mode
  end

  function screen:availableModes()
    return self._availableModes
  end

  function screen:toUnitRect(frame)
    local screenFrame = self._frame
    return {
      x = (frame.x - screenFrame.x) / screenFrame.w,
      y = (frame.y - screenFrame.y) / screenFrame.h,
      w = frame.w / screenFrame.w,
      h = frame.h / screenFrame.h,
    }
  end

  function screen:fromUnitRect(unitRect)
    local screenFrame = self._frame
    return {
      x = screenFrame.x + (unitRect.x * screenFrame.w),
      y = screenFrame.y + (unitRect.y * screenFrame.h),
      w = unitRect.w * screenFrame.w,
      h = unitRect.h * screenFrame.h,
    }
  end

  return screen
end

local function newApp(config)
  local app = {
    _bundleID = config.bundleID,
    _name = config.name,
    _windows = {},
  }

  function app:bundleID()
    return self._bundleID
  end

  function app:name()
    return self._name
  end

  function app:allWindows()
    return self._windows
  end

  function app:focusedWindow()
    return self._windows[1]
  end

  function app:activate()
    self._activated = true
  end

  return app
end

local function buildEnvironment()
  local timerCalls = {}
  local storedSettings = {}
  local alerts = {}
  local operations = {}
  local openedApps = {}
  local focusedWindow = nil
  local chooserCallback = nil
  local chooserChoices = nil

  local builtin = newScreen({
    uuid = 'builtin-uuid',
    id = 1,
    name = 'Built-in Retina Display',
    frame = { x = 0, y = 0, w = 1512, h = 982 },
    mode = { w = 1512, h = 982 },
  })

  local external = newScreen({
    uuid = 'external-uuid',
    id = 2,
    name = 'Studio Display',
    frame = { x = 1512, y = 0, w = 3840, h = 2160 },
    mode = { w = 3840, h = 2160 },
    availableModes = {
      { w = 2560, h = 1440 },
      { w = 3840, h = 2160 },
    },
  })

  local allScreens = { builtin, external }
  local screenPositions = {
    [builtin] = { x = 0, y = 0 },
    [external] = { x = 1, y = 0 },
  }

  local function resolveScreen(ref)
    if type(ref) == 'table' then
      return ref
    end

    for _, screen in ipairs(allScreens) do
      if ref == screen:getUUID() or ref == screen:name() or ref == tostring(screen:id()) then
        return screen
      end
    end

    return nil
  end

  local terminalApp = newApp({
    bundleID = 'com.mitchellh.ghostty',
    name = 'Terminal',
  })

  local window = {
    _id = 101,
    _app = terminalApp,
    _screen = builtin,
    _frame = { x = 0, y = 0, w = 1200, h = 800 },
  }

  function window:id()
    return self._id
  end

  function window:application()
    return self._app
  end

  function window:screen()
    return self._screen
  end

  function window:frame()
    return self._frame
  end

  function window:setTopLeft(x, y)
    table.insert(operations, string.format('setTopLeft:%s,%s', tostring(x), tostring(y)))
    self._frame.x = x
    self._frame.y = y

    for _, screen in ipairs(allScreens) do
      local frame = screen:frame()
      if frame.x == x and frame.y == y then
        self._screen = screen
      end
    end
  end

  function window:setFrame(frame)
    table.insert(operations, string.format('setFrame:%s', self._screen:name()))
    self._frame = frame
    return self
  end

  function window:isStandard()
    return true
  end

  function window:focus()
    focusedWindow = self
    table.insert(operations, 'focus')
    return self
  end

  terminalApp._windows = { window }
  focusedWindow = window

  local appsById = {
    ['com.mitchellh.ghostty'] = terminalApp,
  }

  hs = {
    spoons = {
      resourcePath = function(name)
        return './' .. name
      end,
    },
    screen = {
      allScreens = function()
        return allScreens
      end,
      screenPositions = function()
        return screenPositions
      end,
      primaryScreen = function()
        return builtin
      end,
      mainScreen = function()
        return builtin
      end,
      find = resolveScreen,
    },
    application = {
      get = function(identifier)
        return appsById[identifier]
      end,
      find = function(identifier)
        return appsById[identifier]
      end,
      open = function(identifier)
        openedApps[identifier] = (openedApps[identifier] or 0) + 1
        return appsById[identifier]
      end,
      frontmostApplication = function()
        return terminalApp
      end,
    },
    window = {
      focusedWindow = function()
        return focusedWindow
      end,
    },
    settings = {
      get = function(key)
        return storedSettings[key]
      end,
      set = function(key, value)
        storedSettings[key] = value
      end,
    },
    timer = {
      doAfter = function(delay, fn)
        table.insert(timerCalls, delay)
        return {
          stop = function() end,
          callback = fn,
        }
      end,
    },
    grid = {
      set = function(targetWindow, cell, targetScreen)
        table.insert(operations, 'grid.set:' .. targetScreen:name())
        targetWindow._screen = targetScreen
        targetWindow._cell = cell
      end,
    },
    geometry = {
      new = function(value)
        return value
      end,
    },
    chooser = {
      new = function(callback)
        chooserCallback = callback
        return {
          searchSubText = function(self)
            return self
          end,
          choices = function(self, value)
            chooserChoices = value
            return self
          end,
          query = function(self)
            return self
          end,
          show = function(self)
            return self
          end,
        }
      end,
    },
    alert = {
      show = function(message)
        table.insert(alerts, message)
      end,
    },
  }

  return {
    builtin = builtin,
    external = external,
    terminalApp = terminalApp,
    window = window,
    operations = operations,
    timerCalls = timerCalls,
    alerts = alerts,
    openedApps = openedApps,
    storedSettings = storedSettings,
    chooserChoices = function()
      return chooserChoices
    end,
    choose = function(choice)
      if chooserCallback then
        chooserCallback(choice)
      end
    end,
  }
end

local function newLayoutEngine()
  return {
    setApps = function(self, value)
      self.apps = value
      return self
    end,
    setLayouts = function(self, value)
      self.layouts = value
      return self
    end,
    selectLayout = function(self, layoutIndex, variantIndex)
      self.selected = { layoutIndex = layoutIndex, variantIndex = variantIndex }
      return self
    end,
  }
end

local function standardLayouts()
  return {
    {
      key = 'fullscreen',
      name = 'Fullscreen',
      cells = {
        { '0,0 80x40' },
      },
      apps = {
        Terminal = { cell = 1 },
      },
    },
    {
      key = 'fourk',
      name = '4K Workspace',
      cells = {
        { '0,0 80x40' },
      },
      apps = {
        Terminal = { cell = 1 },
      },
    },
    {
      key = 'hd',
      name = 'HD Workspace',
      cells = {
        { '0,0 80x40' },
      },
      apps = {
        Terminal = { cell = 1 },
      },
    },
  }
end

local function standardApps()
  return {
    Terminal = {
      id = 'com.mitchellh.ghostty',
    },
  }
end

local function twoCellLayouts()
  return {
    {
      key = 'fullscreen',
      name = 'Fullscreen',
      cells = {
        { '0,0 40x40' },
        { '40,0 40x40' },
      },
      apps = {
        Terminal = { cell = 1 },
      },
    },
  }
end

local function loadRuntime()
  return dofile('./workspace_manager.lua')
end

do
  buildEnvironment()
  local runtime = loadRuntime()
  local ok, err = pcall(function()
    runtime.start({
      apps = standardApps(),
      layouts = standardLayouts(),
    })
  end)

  assertEqual(ok, false, 'start() should fail without a layout engine')
  assertContains(err, 'layoutEngine', 'start() should mention the missing layout engine')
end

do
  local env = buildEnvironment()
  local runtime = loadRuntime()

  runtime.start({
    layoutEngine = newLayoutEngine(),
    apps = standardApps(),
    layouts = standardLayouts(),
    screenLayouts = {
      layouts = {
        ['external-uuid'] = 'fullscreen',
        ['profile:fourk'] = 'fourk',
        all = 'hd',
      },
    },
  })

  assertEqual(runtime.defaultLayoutKey(env.external), 'fullscreen', 'exact screen mapping should win over profile/all defaults')
  assertEqual(runtime.defaultLayoutKey(env.builtin), 'hd', 'shared all mapping should apply when no exact or profile match exists')
end

do
  local env = buildEnvironment()
  local runtime = loadRuntime()

  runtime.start({
    layoutEngine = newLayoutEngine(),
    apps = standardApps(),
    layouts = standardLayouts(),
    screenChangeDelaySeconds = 2.5,
  })

  runtime.handleScreenChange()
  assertEqual(env.timerCalls[#env.timerCalls], 2.5, 'custom screen change delay should be respected')
end

do
  local env = buildEnvironment()
  local runtime = loadRuntime()

  runtime.start({
    layoutEngine = newLayoutEngine(),
    apps = standardApps(),
    layouts = standardLayouts(),
  })

  runtime.moveFocusedWindowToNextScreen()

  assertEqual(env.operations[1], 'setTopLeft:1512,0', 'window should be moved onto the target screen before resizing')
  assertEqual(env.operations[2], 'grid.set:Studio Display', 'window should be snapped on the target screen after the move')
  assertEqual(env.window:screen():name(), 'Studio Display', 'window should end up on the external display')
end

do
  local env = buildEnvironment()
  local runtime = loadRuntime()

  runtime.start({
    layoutEngine = newLayoutEngine(),
    apps = standardApps(),
    layouts = twoCellLayouts(),
    settingsKey = 'workspace-manager.runtime-spec',
  })

  runtime.bindFocusedWindowToCell()
  assertEqual(#env.chooserChoices(), 2, 'bind chooser should offer each layout cell as a target')

  env.choose({
    cell_index = 2,
  })

  local persisted = env.storedSettings['workspace-manager.runtime-spec']
  local screenState = persisted.screens['builtin-uuid']
  local windowOverride = screenState.window_overrides.fullscreen['101']

  assertEqual(windowOverride.app_name, 'Terminal', 'binding should persist the logical app name for the focused window override')
  assertEqual(windowOverride.cell_index, 2, 'binding should persist the selected cell for the focused window override')

  local reloadedRuntime = loadRuntime()
  local reloadedEngine = newLayoutEngine()

  reloadedRuntime.start({
    layoutEngine = reloadedEngine,
    apps = standardApps(),
    layouts = twoCellLayouts(),
    settingsKey = 'workspace-manager.runtime-spec',
  })
  reloadedRuntime.apply()

  assertEqual(reloadedEngine.layouts[1].cells[1][1].cell, '40,0 40x40', 'reloaded state should restore the persisted per-window override cell')
end

print('runtime_spec ok')
