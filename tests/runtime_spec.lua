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

local function parseGridCell(value)
  if type(value) ~= 'string' then
    return value
  end

  local x, y, w, h = value:match('^(%-?%d+),(%-?%d+)%s+(%-?%d+)x(%-?%d+)$')
  if not x then
    return value
  end

  return {
    x = tonumber(x),
    y = tonumber(y),
    w = tonumber(w),
    h = tonumber(h),
  }
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

  local unmanagedApp = newApp({
    bundleID = 'com.example.unmanaged',
    name = 'Unmanaged',
  })

  local function createWindow(config)
    local window = {
      _id = config.id,
      _app = config.app,
      _screen = config.screen,
      _frame = config.frame,
      _gridCell = parseGridCell(config.gridCell),
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

    return window
  end

  local window = createWindow({
    id = 101,
    app = terminalApp,
    screen = builtin,
    frame = { x = 0, y = 0, w = 1200, h = 800 },
    gridCell = '0,0 40x40',
  })

  local unmanagedWindow = createWindow({
    id = 202,
    app = unmanagedApp,
    screen = builtin,
    frame = { x = 0, y = 0, w = 1000, h = 700 },
    gridCell = '0,0 40x40',
  })

  terminalApp._windows = { window }
  unmanagedApp._windows = { unmanagedWindow }
  focusedWindow = window

  local appsById = {
    ['com.mitchellh.ghostty'] = terminalApp,
    ['com.example.unmanaged'] = unmanagedApp,
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
        targetWindow._gridCell = cell
      end,
      get = function(targetWindow)
        return targetWindow._gridCell
      end,
    },
    geometry = {
      new = function(value)
        return parseGridCell(value)
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
    unmanagedApp = unmanagedApp,
    window = window,
    unmanagedWindow = unmanagedWindow,
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
    focusWindow = function(targetWindow)
      focusedWindow = targetWindow
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
  buildEnvironment()
  local runtime = loadRuntime()
  local ok, err = pcall(function()
    runtime.start({
      layoutEngine = newLayoutEngine(),
      apps = standardApps(),
      layouts = {
        {
          name = 'Fullscreen',
          cells = {
            { '0,0 80x40' },
          },
          apps = {
            Terminal = { cell = 1 },
          },
        },
      },
    })
  end)

  assertEqual(ok, false, 'start() should fail when a layout key is missing')
  assertContains(err, '.key', 'start() should explain the missing layout key')
end

do
  buildEnvironment()
  local runtime = loadRuntime()
  local ok, err = pcall(function()
    runtime.start({
      layoutEngine = newLayoutEngine(),
      apps = standardApps(),
      layouts = {
        {
          key = 'fullscreen',
          name = 'Fullscreen',
          cells = {
            { '0,0 80x40' },
          },
          apps = {
            Browser = { cell = 1 },
          },
        },
      },
    })
  end)

  assertEqual(ok, false, 'start() should fail when a layout references an unknown app')
  assertContains(err, 'unknown app', 'start() should explain the unknown app reference')
end

do
  buildEnvironment()
  local runtime = loadRuntime()
  local ok, err = pcall(function()
    runtime.start({
      layoutEngine = newLayoutEngine(),
      apps = standardApps(),
      layouts = standardLayouts(),
      screenLayouts = {
        layouts = {
          primary = 'does-not-exist',
        },
      },
    })
  end)

  assertEqual(ok, false, 'start() should fail when screenLayouts references an unknown layout')
  assertContains(err, 'unknown layout', 'start() should explain the invalid screen layout mapping')
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

  assertEqual(runtime.defaultLayoutKey(env.builtin), 'fullscreen', 'the first layout should be the fallback default when screenLayouts is absent')
  assertEqual(runtime.defaultLayoutKey(env.external), 'fullscreen', 'the first layout should be the fallback default for every screen when screenLayouts is absent')
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
        all = 'hd',
      },
    },
  })

  runtime.start({
    layoutEngine = newLayoutEngine(),
    apps = standardApps(),
    layouts = standardLayouts(),
  })

  assertEqual(runtime.defaultLayoutKey(env.builtin), 'fullscreen', 'start() should not leak prior config across reconfiguration')
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
    captureWindowStateOnStart = false,
  })
  reloadedRuntime.apply()

  assertEqual(reloadedEngine.layouts[1].cells[1][1].cell, '40,0 40x40', 'reloaded state should restore the persisted per-window override cell')
end

do
  local env = buildEnvironment()
  local runtime = loadRuntime()
  local key = 'workspace-manager.unmanaged-window-bind-spec'

  env.focusWindow(env.unmanagedWindow)

  runtime.start({
    layoutEngine = newLayoutEngine(),
    apps = standardApps(),
    layouts = twoCellLayouts(),
    settingsKey = key,
  })

  runtime.bindFocusedWindowToCell()
  assertEqual(#env.chooserChoices(), 2, 'unmanaged focused-window binding should offer each layout cell as a target')
  assertEqual(#env.alerts, 0, 'unmanaged focused-window binding should not alert when the window is outside layout.apps')

  env.choose({
    cell_index = 2,
  })

  local persisted = env.storedSettings[key]
  local screenState = persisted.screens['builtin-uuid']
  local windowOverride = screenState.window_overrides.fullscreen['202']

  assertEqual(windowOverride.app_name, nil, 'unmanaged window bindings should not invent a logical app name')
  assertEqual(windowOverride.app_id, 'com.example.unmanaged', 'unmanaged window bindings should persist the live app identifier')
  assertEqual(windowOverride.cell_index, 2, 'unmanaged window bindings should persist the selected cell')

  local reloadedRuntime = loadRuntime()
  local reloadedEngine = newLayoutEngine()

  reloadedRuntime.start({
    layoutEngine = reloadedEngine,
    apps = standardApps(),
    layouts = twoCellLayouts(),
    settingsKey = key,
  })
  reloadedRuntime.apply()

  local syntheticKey = 'com.example.unmanaged:builtin-uuid:202'
  local syntheticCellIndex = reloadedEngine.layouts[1].apps[syntheticKey].cell

  assertEqual(reloadedEngine.layouts[1].cells[syntheticCellIndex][1].cell, '40,0 40x40', 'startup capture should preserve unmanaged window overrides across reload')
end

do
  local env = buildEnvironment()
  local runtime = loadRuntime()
  local key = 'workspace-manager.unmanaged-screen-affinity-spec'

  env.unmanagedWindow._screen = env.external

  env.storedSettings[key] = {
    screens = {
      ['builtin-uuid'] = {
        layout_key = 'fullscreen',
        variant = 1,
        app_overrides = {},
        window_overrides = {
          fullscreen = {
            ['202'] = {
              app_id = 'com.example.unmanaged',
              cell_index = 1,
            },
          },
        },
      },
      ['external-uuid'] = {
        layout_key = 'fullscreen',
        variant = 1,
        app_overrides = {},
        window_overrides = {
          fullscreen = {
            ['202'] = {
              app_id = 'com.example.unmanaged',
              cell_index = 1,
            },
          },
          fourk = {
            ['202'] = {
              app_id = 'com.example.unmanaged',
              cell_index = 1,
            },
          },
        },
      },
    },
  }

  local engine = newLayoutEngine()

  runtime.start({
    layoutEngine = engine,
    apps = standardApps(),
    layouts = standardLayouts(),
    settingsKey = key,
    captureWindowStateOnStart = false,
  })
  runtime.selectLayout('fourk', env.external)
  runtime.apply()

  local syntheticKey = nil
  for keyName, _ in pairs(engine.layouts[1].apps) do
    if keyName:match(':202$') then
      syntheticKey = keyName
      break
    end
  end

  assertEqual(type(syntheticKey), 'string', 'competing unmanaged overrides should still synthesize a placement for the window')
  local syntheticCellIndex = engine.layouts[1].apps[syntheticKey].cell

  assertEqual(engine.layouts[1].cells[syntheticCellIndex][1].screen, env.external, 'competing unmanaged overrides should keep a live second-screen window on its current screen')
end

do
  local env = buildEnvironment()
  local runtime = loadRuntime()

  runtime.start({
    layoutEngine = newLayoutEngine(),
    apps = standardApps(),
    layouts = twoCellLayouts(),
    settingsKey = 'workspace-manager.app-override-spec',
  })

  runtime.bindFocusedAppToCell()
  assertEqual(#env.chooserChoices(), 2, 'focused-app binding should offer each layout cell as a target')

  env.choose({
    cell_index = 2,
  })

  local persisted = env.storedSettings['workspace-manager.app-override-spec']
  local screenState = persisted.screens['builtin-uuid']

  assertEqual(screenState.app_overrides.fullscreen.Terminal, 2, 'binding should persist the focused app override')

  local reloadedRuntime = loadRuntime()
  local reloadedEngine = newLayoutEngine()

  reloadedRuntime.start({
    layoutEngine = reloadedEngine,
    apps = standardApps(),
    layouts = twoCellLayouts(),
    settingsKey = 'workspace-manager.app-override-spec',
    captureWindowStateOnStart = false,
  })
  reloadedRuntime.apply()

  assertEqual(reloadedEngine.layouts[1].cells[1][1].cell, '40,0 40x40', 'reloaded state should restore the persisted app override cell')
end

do
  local env = buildEnvironment()
  local runtime = loadRuntime()

  runtime.start({
    layoutEngine = newLayoutEngine(),
    apps = standardApps(),
    layouts = twoCellLayouts(),
  })

  runtime.bindFocusedAppToCell()
  env.choose({
    cell_index = 2,
  })

  local persisted = env.storedSettings['WorkspaceManager.spoon.screen_state.v1']

  assertEqual(type(persisted), 'table', 'default state should be persisted under the spoon-specific settings key')
  assertEqual(persisted.screens['builtin-uuid'].app_overrides.fullscreen.Terminal, 2, 'default settings key should preserve persisted overrides')
end

do
  local env = buildEnvironment()
  local runtime = loadRuntime()
  local key = 'workspace-manager.capture-live-state'

  env.window._screen = env.external
  env.window._gridCell = parseGridCell('40,0 40x40')

  env.storedSettings[key] = {
    screens = {
      ['builtin-uuid'] = {
        layout_key = 'fullscreen',
        variant = 1,
        app_overrides = {},
        window_overrides = {
          fullscreen = {
            ['101'] = {
              app_name = 'Terminal',
              cell_index = 1,
            },
          },
        },
      },
      ['external-uuid'] = {
        layout_key = 'fullscreen',
        variant = 1,
        app_overrides = {},
        window_overrides = {},
      },
    },
  }

  local engine = newLayoutEngine()

  runtime.start({
    layoutEngine = engine,
    apps = standardApps(),
    layouts = twoCellLayouts(),
    settingsKey = key,
  })
  runtime.apply()

  local persisted = env.storedSettings[key]
  local builtinOverrides = persisted.screens['builtin-uuid'].window_overrides.fullscreen
  local externalOverrides = persisted.screens['external-uuid'].window_overrides.fullscreen

  assertEqual(builtinOverrides == nil or builtinOverrides['101'] == nil, true, 'startup capture should clear stale window overrides from the old screen')
  assertEqual(externalOverrides['101'].cell_index, 2, 'startup capture should persist the live cell index on the current screen')
  assertEqual(engine.layouts[1].cells[1][1].screen, env.external, 'reapplied layout should target the live screen after reload capture')
  assertEqual(engine.layouts[1].cells[1][1].cell, '40,0 40x40', 'reapplied layout should restore the live cell after reload capture')
end

do
  local env = buildEnvironment()
  local runtime = loadRuntime()
  local key = 'workspace-manager.capture-default-screen-affinity'

  env.window._screen = env.external
  env.window._gridCell = parseGridCell('0,0 40x40')

  local engine = newLayoutEngine()

  runtime.start({
    layoutEngine = engine,
    apps = standardApps(),
    layouts = twoCellLayouts(),
    settingsKey = key,
  })
  runtime.apply()

  local persisted = env.storedSettings[key]
  local builtinOverrides = persisted.screens['builtin-uuid'].window_overrides.fullscreen
  local externalOverrides = persisted.screens['external-uuid'].window_overrides.fullscreen

  assertEqual(builtinOverrides == nil or builtinOverrides['101'] == nil, true, 'startup capture should not keep a default-cell window attached to the old screen')
  assertEqual(externalOverrides['101'].cell_index, 1, 'startup capture should persist default-cell windows on their live screen too')
  assertEqual(engine.layouts[1].cells[1][1].screen, env.external, 'reapplied layout should preserve live screen affinity even for default-slot windows')
  assertEqual(engine.layouts[1].cells[1][1].cell, '0,0 40x40', 'reapplied layout should preserve the default cell on the live screen')
end

print('runtime_spec ok')
