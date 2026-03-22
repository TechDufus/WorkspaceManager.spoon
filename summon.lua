local defaultPlacementDelaySeconds = 0.2
local defaultPlacementAttempts = 10

return function(workspaceManager)
  local M = {}

  local apps = {}
  local previousApp = nil
  local currentApp = nil
  local focusWatcher = nil
  local placementDelaySeconds = defaultPlacementDelaySeconds
  local placementAttempts = defaultPlacementAttempts

  local function appIdentity(app)
    if not app then
      return nil
    end

    return app:bundleID() or app:name()
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

    local bundleId = app:bundleID()
    local name = app:name()

    return bundleId == identifier or name == identifier or bundleId == fallbackName or name == fallbackName
  end

  local function preferredWindow(app, targetScreen)
    if not app then
      return nil
    end

    for _, window in ipairs(app:allWindows()) do
      if window:isStandard() and window:screen() == targetScreen then
        return window
      end
    end

    local focusedWindow = app:focusedWindow()
    if focusedWindow and focusedWindow:isStandard() then
      return focusedWindow
    end

    for _, window in ipairs(app:allWindows()) do
      if window:isStandard() then
        return window
      end
    end

    return nil
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
    local app = win and win:application()
    local identity = appIdentity(app)

    if not identity or identity == currentApp then
      return
    end

    if currentApp then
      previousApp = currentApp
    end

    currentApp = identity
  end

  function M.start(config)
    config = config or {}
    apps = config.apps or {}
    local summonConfig = config.summon or {}
    placementDelaySeconds = tonumber(summonConfig.placementDelaySeconds) or defaultPlacementDelaySeconds
    placementAttempts = tonumber(summonConfig.placementAttempts) or defaultPlacementAttempts

    if not focusWatcher then
      focusWatcher = hs.window.filter.new():subscribe(hs.window.filter.windowFocused, trackFocusedWindow)
    end

    return M
  end

  function M.stop()
    if focusWatcher then
      focusWatcher:unsubscribeAll()
      focusWatcher = nil
    end

    return M
  end

  function M.summon(appName)
    local target = apps[appName] or {}
    local id = target.id or appName
    local frontmostApp = hs.application.frontmostApplication()
    local app = resolveApp(id) or resolveApp(appName)
    local focusedWindow = hs.window.focusedWindow()
    local targetScreen = (focusedWindow and focusedWindow:screen()) or hs.screen.mainScreen() or hs.screen.primaryScreen()

    if appMatches(frontmostApp, id, appName) and previousApp and not appMatches(frontmostApp, previousApp, previousApp) then
      local previous = resolveApp(previousApp)
      if previous then
        previous:activate()
      else
        hs.application.open(previousApp)
      end
    elseif app and next(app:allWindows()) then
      local window = preferredWindow(app, targetScreen)
      app:activate()
      if window then
        window:focus()
      end
      placeApp(appName, targetScreen, window, placementAttempts)
    else
      local opened = hs.application.open(id)
      if not opened and appName ~= id then
        hs.application.open(appName)
      end
      placeApp(appName, targetScreen, nil, placementAttempts)
    end

    return M
  end

  return M
end
