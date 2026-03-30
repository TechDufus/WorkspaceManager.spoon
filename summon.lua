local defaultPlacementDelaySeconds = 0.2
local defaultPlacementAttempts = 10

return function(workspaceManager)
  local M = {}

  local apps = {}
  local previousApp = nil
  local currentApp = nil
  local preferredWindowIdsByApp = {}
  local appFocusWatchersByIdentity = {}
  local focusWatcher = nil
  local placementDelaySeconds = defaultPlacementDelaySeconds
  local placementAttempts = defaultPlacementAttempts

  local function configError(message)
    error('WorkspaceManager invalid summon config: ' .. message, 3)
  end

  local function applicationBundleId(app)
    if not app or type(app.bundleID) ~= 'function' then
      return nil
    end

    local ok, bundleId = pcall(function()
      return app:bundleID()
    end)

    return ok and bundleId or nil
  end

  local function applicationName(app)
    if not app or type(app.name) ~= 'function' then
      return nil
    end

    local ok, name = pcall(function()
      return app:name()
    end)

    return ok and name or nil
  end

  local function appIdentity(app)
    return applicationBundleId(app) or applicationName(app)
  end

  local function resolveApp(identifier)
    if not identifier then
      return nil
    end

    return hs.application.get(identifier) or hs.application.find(identifier)
  end

  local function appMatches(app, identifier, fallbackName)
    if not app then
      return false
    end

    local bundleId = applicationBundleId(app)
    local name = applicationName(app)

    return bundleId == identifier or name == identifier or bundleId == fallbackName or name == fallbackName
  end

  local function appHasIdentity(app, identity)
    if not app or not identity then
      return false
    end

    local bundleId = applicationBundleId(app)
    local name = applicationName(app)

    return bundleId == identity or name == identity
  end

  local function windowIdKey(windowOrId)
    local numericWindowId = nil

    if type(windowOrId) == 'table' or type(windowOrId) == 'userdata' then
      local ok, windowId = pcall(function()
        return windowOrId:id()
      end)
      numericWindowId = ok and tonumber(windowId) or nil
    else
      numericWindowId = tonumber(windowOrId)
    end

    if not numericWindowId then
      return nil
    end

    return tostring(numericWindowId)
  end

  local function screenIdentity(screen)
    if not screen then
      return nil
    end

    if type(screen.getUUID) == 'function' then
      local uuid = screen:getUUID()
      if uuid then
        return uuid
      end
    end

    if type(screen.id) == 'function' then
      local id = screen:id()
      if id ~= nil then
        return tostring(id)
      end
    end

    if type(screen.name) == 'function' then
      return screen:name()
    end

    return nil
  end

  local function screensMatch(left, right)
    if left == right then
      return true
    end

    local leftIdentity = screenIdentity(left)
    local rightIdentity = screenIdentity(right)

    return leftIdentity ~= nil and leftIdentity == rightIdentity
  end

  local function preferredWindow(app, targetScreen)
    if not app then
      return nil
    end

    local identity = appIdentity(app)
    local preferredWindowId = identity and preferredWindowIdsByApp[identity] or nil
    if preferredWindowId then
      for _, window in ipairs(app:allWindows()) do
        if window:isStandard() and windowIdKey(window) == preferredWindowId then
          return window
        end
      end

      preferredWindowIdsByApp[identity] = nil
    end

    local focusedWindow = app:focusedWindow()
    if focusedWindow and focusedWindow:isStandard() then
      return focusedWindow
    end

    if hs.window and type(hs.window.orderedWindows) == 'function' then
      for _, window in ipairs(hs.window.orderedWindows()) do
        if window and type(window.isStandard) == 'function' and window:isStandard() then
          local candidateApp = type(window.application) == 'function' and window:application() or nil
          if appHasIdentity(candidateApp, identity) then
            local orderedWindowId = windowIdKey(window)
            if orderedWindowId then
              preferredWindowIdsByApp[identity] = orderedWindowId
            end
            return window
          end
        end
      end
    end

    for _, window in ipairs(app:allWindows()) do
      if window:isStandard() and screensMatch(window:screen(), targetScreen) then
        return window
      end
    end

    for _, window in ipairs(app:allWindows()) do
      if window:isStandard() then
        return window
      end
    end

    return nil
  end

  local function summonTargetScreen()
    local mouse = hs.mouse
    if mouse and type(mouse.getCurrentScreen) == 'function' then
      local mouseScreen = mouse.getCurrentScreen()
      if mouseScreen then
        return mouseScreen
      end
    end

    local focusedWindow = hs.window.focusedWindow()
    return (focusedWindow and focusedWindow:screen()) or hs.screen.mainScreen() or hs.screen.primaryScreen()
  end

  local function placementScreenForWindow(targetScreen, window)
    if not window or not window.isStandard or not window:isStandard() then
      return targetScreen
    end

    local windowScreen = window:screen()
    return windowScreen or targetScreen
  end

  local function placeApp(appName, targetScreen, preferred, remainingAttempts)
    if workspaceManager.placeApp(appName, targetScreen, preferred) or remainingAttempts <= 0 then
      return
    end

    hs.timer.doAfter(placementDelaySeconds, function()
      placeApp(appName, targetScreen, preferred, remainingAttempts - 1)
    end)
  end

  local function trackFocusedWindow(win)
    local app = nil
    if win and type(win.application) == 'function' then
      app = win:application()
    end
    local identity = appIdentity(app)

    if not identity then
      return
    end

    if win and type(win.isStandard) == 'function' and win:isStandard() then
      local windowId = windowIdKey(win)
      if windowId then
        preferredWindowIdsByApp[identity] = windowId
      end
    end

    if identity == currentApp then
      return
    end

    if currentApp then
      previousApp = currentApp
    end

    currentApp = identity
  end

  local function stopAppFocusWatcher(identity)
    local watcherEntry = appFocusWatchersByIdentity[identity]
    if not watcherEntry then
      return
    end

    if watcherEntry.watcher and type(watcherEntry.watcher.stop) == 'function' then
      pcall(function()
        watcherEntry.watcher:stop()
      end)
    end

    appFocusWatchersByIdentity[identity] = nil
  end

  local function stopAppFocusWatchers()
    for identity in pairs(appFocusWatchersByIdentity) do
      stopAppFocusWatcher(identity)
    end
  end

  local function ensureAppFocusWatcher(app)
    if (type(app) ~= 'table' and type(app) ~= 'userdata')
      or not hs.uielement
      or not hs.uielement.watcher
      or type(app.newWatcher) ~= 'function'
      or hs.uielement.watcher.focusedWindowChanged == nil then
      return
    end

    local identity = appIdentity(app)
    if not identity then
      return
    end

    local pid = nil
    if type(app.pid) == 'function' then
      pid = app:pid()
    end

    local existingWatcher = appFocusWatchersByIdentity[identity]
    if existingWatcher and existingWatcher.pid == pid then
      return
    end

    stopAppFocusWatcher(identity)

    local ok, watcher = pcall(function()
      return app:newWatcher(function(element, event)
        if event == hs.uielement.watcher.focusedWindowChanged then
          trackFocusedWindow(element)
        end
      end)
    end)

    if not ok or not watcher then
      return
    end

    local started = pcall(function()
      watcher:start({ hs.uielement.watcher.focusedWindowChanged })
    end)

    if not started then
      pcall(function()
        watcher:stop()
      end)
      return
    end

    appFocusWatchersByIdentity[identity] = {
      pid = pid,
      watcher = watcher,
    }
  end

  local function ensureConfiguredAppFocusWatchers()
    for appName, appConfig in pairs(apps) do
      local identifier = (type(appConfig) == 'table' and appConfig.id) or appName
      local app = resolveApp(identifier) or resolveApp(appName)
      if app then
        ensureAppFocusWatcher(app)
      end
    end
  end

  function M.start(config)
    config = config or {}

    if config.apps ~= nil and type(config.apps) ~= 'table' then
      configError('config.apps must be a table')
    end

    local summonConfig = config.summon or {}
    if config.summon ~= nil and type(config.summon) ~= 'table' then
      configError('config.summon must be a table')
    end

    if summonConfig.placementDelaySeconds ~= nil then
      local configuredDelay = tonumber(summonConfig.placementDelaySeconds)
      if not configuredDelay or configuredDelay < 0 then
        configError('config.summon.placementDelaySeconds must be a non-negative number')
      end
      placementDelaySeconds = configuredDelay
    else
      placementDelaySeconds = defaultPlacementDelaySeconds
    end

    if summonConfig.placementAttempts ~= nil then
      local configuredAttempts = tonumber(summonConfig.placementAttempts)
      if not configuredAttempts or configuredAttempts < 0 or configuredAttempts % 1 ~= 0 then
        configError('config.summon.placementAttempts must be a non-negative integer')
      end
      placementAttempts = configuredAttempts
    else
      placementAttempts = defaultPlacementAttempts
    end

    apps = config.apps or {}
    previousApp = nil
    currentApp = nil
    preferredWindowIdsByApp = {}
    stopAppFocusWatchers()

    if not focusWatcher then
      focusWatcher = hs.window.filter.new():subscribe(hs.window.filter.windowFocused, trackFocusedWindow)
    end

    trackFocusedWindow(hs.window.focusedWindow())
    ensureConfiguredAppFocusWatchers()

    return M
  end

  function M.stop()
    if focusWatcher then
      focusWatcher:unsubscribeAll()
      focusWatcher = nil
    end

    previousApp = nil
    currentApp = nil
    preferredWindowIdsByApp = {}
    stopAppFocusWatchers()

    return M
  end

  function M.summon(appName)
    local target = apps[appName] or {}
    local id = target.id or appName
    local frontmostApp = hs.application.frontmostApplication()
    local app = resolveApp(id) or resolveApp(appName)
    local targetScreen = summonTargetScreen()

    if app then
      ensureAppFocusWatcher(app)
    end

    if appMatches(frontmostApp, id, appName) and previousApp and not appMatches(frontmostApp, previousApp, previousApp) then
      local previous = resolveApp(previousApp)
      if previous then
        previous:activate()
      else
        hs.application.open(previousApp)
      end
    elseif app and next(app:allWindows()) then
      local window = preferredWindow(app, targetScreen)
      local placementScreen = placementScreenForWindow(targetScreen, window)
      if not window then
        app:activate()
      end
      placeApp(appName, placementScreen, window, placementAttempts)
    else
      local opened = hs.application.open(id)
      ensureAppFocusWatcher(opened or resolveApp(id) or resolveApp(appName))
      if not opened and appName ~= id then
        hs.application.open(appName)
        ensureAppFocusWatcher(resolveApp(appName))
      end
      placeApp(appName, targetScreen, nil, placementAttempts)
    end

    return M
  end

  return M
end
