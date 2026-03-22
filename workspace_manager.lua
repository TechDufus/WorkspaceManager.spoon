local M = {}

local screens = dofile(hs.spoons.resourcePath('screens.lua'))

local apps = {}
local layouts = {}
local screenLayouts = {}

local layoutEngine = nil
local reapplyTimer = nil
local settingsKey = 'workspaces.screen_state.v1'
local openAppReapplyDelaySeconds = 0.5
local screenChangeDelaySeconds = 1

local state = {
  screens = {},
  preferred_windows = {},
}

local defaultLayoutKeys = {
  builtin = 'fullscreen',
  fourk = 'fourk',
  standard = 'hd',
  ultrawide = 'standard',
}

local layoutsByKey = {}

local function rebuildLayoutIndex()
  layoutsByKey = {}

  for index, layout in ipairs(layouts or {}) do
    if type(layout) == 'table' and layout.key and layout.name then
      layoutsByKey[layout.key] = layout
      layoutsByKey[layout.name:lower()] = layout
      layoutsByKey[tostring(index)] = layout
    end
  end
end

local function resolveLayout(layoutRef)
  if type(layoutRef) == 'table' then
    return layoutRef
  end

  if layoutRef == nil then
    return nil
  end

  return layoutsByKey[tostring(layoutRef):lower()]
end

local function validateConfig()
  if not layoutEngine then
    error('WorkspaceManager requires config.layoutEngine', 2)
  end

  if type(apps) ~= 'table' then
    error('WorkspaceManager requires config.apps', 2)
  end

  if type(layouts) ~= 'table' or #layouts == 0 then
    error('WorkspaceManager requires config.layouts', 2)
  end
end

function M.configure(config)
  config = config or {}

  apps = config.apps or apps or {}
  layouts = config.layouts or layouts or {}
  screenLayouts = config.screenLayouts or screenLayouts or {}
  layoutEngine = config.layoutEngine or layoutEngine
  settingsKey = config.settingsKey or settingsKey
  openAppReapplyDelaySeconds = tonumber(config.openAppReapplyDelaySeconds) or openAppReapplyDelaySeconds
  screenChangeDelaySeconds = tonumber(config.screenChangeDelaySeconds) or screenChangeDelaySeconds

  if type(config.defaultLayoutKeys) == 'table' then
    for profile, layoutKey in pairs(config.defaultLayoutKeys) do
      defaultLayoutKeys[profile] = layoutKey
    end
  end

  rebuildLayoutIndex()

  return M
end

local function appObject(appName)
  local appConfig = apps[appName]
  if not appConfig then
    return nil
  end

  return hs.application.get(appConfig.id) or hs.application.find(appConfig.id)
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

local function sanitizeAppOverrides(appOverrides)
  local normalized = {}

  for layoutRef, bucket in pairs(appOverrides or {}) do
    local layout = resolveLayout(layoutRef)

    if layout and type(bucket) == 'table' then
      for appName, cellIndex in pairs(bucket) do
        local numericCellIndex = tonumber(cellIndex)

        if apps[appName] and numericCellIndex and layout.cells and layout.cells[numericCellIndex] then
          normalized[layout.key] = normalized[layout.key] or {}
          normalized[layout.key][appName] = numericCellIndex
        end
      end
    end
  end

  return normalized
end

local function sanitizeWindowOverrides(windowOverrides)
  local normalized = {}

  for layoutRef, bucket in pairs(windowOverrides or {}) do
    local layout = resolveLayout(layoutRef)

    if layout and type(bucket) == 'table' then
      for windowId, config in pairs(bucket) do
        local normalizedWindowId = windowIdKey(windowId)
        local appName = config and config.app_name
        local numericCellIndex = tonumber(config and config.cell_index)

        if normalizedWindowId
          and apps[appName]
          and numericCellIndex
          and layout.cells
          and layout.cells[numericCellIndex] then
          normalized[layout.key] = normalized[layout.key] or {}
          normalized[layout.key][normalizedWindowId] = {
            app_name = appName,
            cell_index = numericCellIndex,
          }
        end
      end
    end
  end

  return normalized
end

local function normalizeScreenState(screenState)
  local layout = screenState and resolveLayout(screenState.layout_key) or nil

  return {
    layout_key = layout and layout.key or nil,
    variant = math.max(1, tonumber(screenState and screenState.variant) or 1),
    app_overrides = sanitizeAppOverrides(screenState and screenState.app_overrides),
    window_overrides = sanitizeWindowOverrides(screenState and screenState.window_overrides),
  }
end

local function persistState()
  local persisted = {
    screens = {},
  }

  for screenId, screenState in pairs(state.screens) do
    if type(screenId) == 'string' and type(screenState) == 'table' then
      local normalized = normalizeScreenState(screenState)

      if normalized.layout_key then
        persisted.screens[screenId] = normalized
      end
    end
  end

  hs.settings.set(settingsKey, persisted)
end

local function loadState()
  local persisted = hs.settings.get(settingsKey)

  state.screens = {}
  state.preferred_windows = {}

  if type(persisted) ~= 'table' or type(persisted.screens) ~= 'table' then
    return
  end

  for screenId, screenState in pairs(persisted.screens) do
    if type(screenId) == 'string' and type(screenState) == 'table' then
      state.screens[screenId] = normalizeScreenState(screenState)
    end
  end
end

local function appNameForWindow(window)
  local application = window and window:application()
  local bundleId = application and application:bundleID()
  local name = application and application:name()

  for appName, appConfig in pairs(apps) do
    if bundleId == appConfig.id or name == appConfig.id or name == appName then
      return appName
    end
  end

  return nil
end

local function preferredWindowBucket(screen, create)
  local screenId = screens.id(screen)
  if not screenId then
    return nil
  end

  local bucket = state.preferred_windows[screenId]
  if not bucket and create then
    bucket = {}
    state.preferred_windows[screenId] = bucket
  end

  return bucket
end

local function setPreferredWindow(screen, appName, window)
  local bucket = preferredWindowBucket(screen, true)
  local windowId = windowIdKey(window)

  if bucket and appName and windowId then
    bucket[appName] = windowId
  end
end

local function clearPreferredWindow(screen, appName, windowId)
  local bucket = preferredWindowBucket(screen, false)
  if not bucket or not appName then
    return
  end

  local preferredId = windowIdKey(bucket[appName])
  local requestedId = windowIdKey(windowId)

  if windowId == nil or preferredId == requestedId then
    bucket[appName] = nil
  end
end

local function windowsForAppOnScreen(appName, screen)
  local application = appObject(appName)
  local targetScreenId = screens.id(screen)
  local windows = {}

  if not application then
    return nil, windows
  end

  for _, window in ipairs(application:allWindows()) do
    if window:isStandard() and screens.id(window:screen()) == targetScreenId then
      table.insert(windows, window)
    end
  end

  return application, windows
end

local function chooseDefaultWindowForAppOnScreen(appName, screen, application, windows, assignedWindowIds)
  local windowsById = {}

  for _, window in ipairs(windows) do
    local windowId = windowIdKey(window)
    if windowId then
      windowsById[windowId] = window
    end
  end

  local preferredId = preferredWindowBucket(screen, false)
  preferredId = preferredId and windowIdKey(preferredId[appName]) or nil
  if preferredId then
    if windowsById[preferredId] and not assignedWindowIds[preferredId] then
      return windowsById[preferredId]
    end

    if not windowsById[preferredId] then
      clearPreferredWindow(screen, appName, preferredId)
    end
  end

  local targetScreenId = screens.id(screen)
  local focusedWindow = hs.window.focusedWindow()
  local focusedWindowId = windowIdKey(focusedWindow)
  if focusedWindow
    and focusedWindow:isStandard()
    and focusedWindowId
    and not assignedWindowIds[focusedWindowId]
    and appNameForWindow(focusedWindow) == appName
    and screens.id(focusedWindow:screen()) == targetScreenId then
    return focusedWindow
  end

  local appFocusedWindow = application:focusedWindow()
  local appFocusedWindowId = windowIdKey(appFocusedWindow)
  if appFocusedWindow
    and appFocusedWindow:isStandard()
    and appFocusedWindowId
    and not assignedWindowIds[appFocusedWindowId]
    and screens.id(appFocusedWindow:screen()) == targetScreenId then
    return appFocusedWindow
  end

  for _, window in ipairs(windows) do
    local windowId = windowIdKey(window)
    if windowId and not assignedWindowIds[windowId] then
      return window
    end
  end

  return nil
end

local function ensureOpenApps()
  local opened = false

  for _, screen in ipairs(screens.ordered()) do
    local layout = M.currentLayout(screen)
    for appName, appConfig in pairs(layout.apps or {}) do
      if appConfig.open and not appObject(appName) then
        hs.application.open(apps[appName].id or appName)
        opened = true
      end
    end
  end

  return opened
end

local function ensureScreenState(screen)
  local screenId = screens.id(screen)
  if not screenId then
    return nil
  end

  local screenState = state.screens[screenId]
  if screenState then
    if not resolveLayout(screenState.layout_key) then
      screenState.layout_key = M.defaultLayoutKey(screen)
      screenState.variant = 1
      screenState.app_overrides = sanitizeAppOverrides(screenState.app_overrides)
      screenState.window_overrides = sanitizeWindowOverrides(screenState.window_overrides)
      persistState()
    end

    return screenState
  end

  screenState = normalizeScreenState({
    layout_key = M.defaultLayoutKey(screen),
    variant = 1,
    app_overrides = {},
    window_overrides = {},
  })

  state.screens[screenId] = screenState
  persistState()

  return screenState
end

local function currentVariantForLayout(screen, layout)
  local screenState = ensureScreenState(screen)
  local variant = screenState and screenState.variant or 1
  local firstCell = layout and layout.cells and layout.cells[1]
  local maxVariant = firstCell and #firstCell or 1

  if variant < 1 then
    variant = 1
  end

  if variant > maxVariant then
    variant = 1
  end

  if screenState and screenState.variant ~= variant then
    screenState.variant = variant
    persistState()
  end

  return variant
end

local function appOverrideBucket(screen, layoutKey, create)
  local screenState = ensureScreenState(screen)
  if not screenState then
    return nil
  end

  local bucket = screenState.app_overrides[layoutKey]
  if not bucket and create then
    bucket = {}
    screenState.app_overrides[layoutKey] = bucket
  end

  return bucket
end

local function windowOverrideBucket(screen, layoutKey, create)
  local screenState = ensureScreenState(screen)
  if not screenState then
    return nil
  end

  local bucket = screenState.window_overrides[layoutKey]
  if not bucket and create then
    bucket = {}
    screenState.window_overrides[layoutKey] = bucket
  end

  return bucket
end

local function windowOverrideConfig(screen, layoutKey, window)
  local bucket = windowOverrideBucket(screen, layoutKey, false)
  local windowId = windowIdKey(window)

  if not bucket or not windowId then
    return nil
  end

  return bucket[windowId]
end

local function clearWindowOverride(screen, layoutKey, window)
  local bucket = windowOverrideBucket(screen, layoutKey, false)
  local windowId = windowIdKey(window)

  if bucket and windowId then
    bucket[windowId] = nil
  end
end

local function resolvedAppCellIndex(appName, screen, layout)
  if not layout or not layout.apps or not layout.apps[appName] then
    return nil
  end

  local overrides = appOverrideBucket(screen, layout.key, false)
  return (overrides and overrides[appName]) or layout.apps[appName].cell
end

local function resolvedCellIndex(appName, screen, layout, window)
  if not layout or not layout.apps or not layout.apps[appName] then
    return nil
  end

  local override = window and windowOverrideConfig(screen, layout.key, window) or nil
  if override and override.app_name == appName then
    return override.cell_index
  end

  return resolvedAppCellIndex(appName, screen, layout)
end

local function resolvedCellVariantForIndex(cellIndex, screen, layout)
  local variant = currentVariantForLayout(screen, layout)
  local cellVariants = cellIndex and layout and layout.cells and layout.cells[cellIndex] or nil
  local cell = cellVariants and cellVariants[variant] or nil

  if type(cell) == 'table' and cell.cell ~= nil then
    local explicitScreen = cell.screen and hs.screen.find(cell.screen) or nil
    return cell.cell, explicitScreen or screen, variant
  end

  return cell, screen, variant
end

local function resolvedCellVariant(appName, screen, layout, window)
  local cellIndex = resolvedCellIndex(appName, screen, layout, window)
  local cell, cellScreen = resolvedCellVariantForIndex(cellIndex, screen, layout)
  return cell, cellScreen, cellIndex
end

local function moveWindowToScreen(window, targetScreen)
  if not window or not targetScreen then
    return false
  end

  local targetFrame = targetScreen:frame()
  window:setTopLeft(targetFrame.x, targetFrame.y)

  return true
end

local function placeWindowOnScreen(window, targetScreen)
  if not window or not targetScreen then
    return false
  end

  local currentScreen = window:screen()
  if not currentScreen then
    return false
  end

  local targetFrame = targetScreen:fromUnitRect(currentScreen:toUnitRect(window:frame()))
  moveWindowToScreen(window, targetScreen)
  window:setFrame(targetFrame, 0)

  return true
end

local function placeManagedWindow(window, appName, targetScreen)
  local screen = targetScreen or screens.focused()
  local layout = M.currentLayout(screen)

  if not window or not appName or not layout or not layout.apps or not layout.apps[appName] then
    return false
  end

  local cell, cellScreen = resolvedCellVariant(appName, screen, layout, window)
  if not cell then
    return false
  end

  local destinationScreen = cellScreen or screen
  moveWindowToScreen(window, destinationScreen)
  hs.grid.set(window, hs.geometry.new(cell), destinationScreen)
  setPreferredWindow(destinationScreen, appName, window)

  return true
end

local function managedWindowsForAppOnScreen(appName, screen, layout)
  local application, windows = windowsForAppOnScreen(appName, screen)
  if not application or #windows == 0 then
    return {}
  end

  local assignments = {}
  local assignedWindowIds = {}

  local windowOverrides = windowOverrideBucket(screen, layout.key, false) or {}
  for _, window in ipairs(windows) do
    local windowId = windowIdKey(window)
    local override = windowId and windowOverrides[windowId] or nil

    if windowId
      and not assignedWindowIds[windowId]
      and override
      and override.app_name == appName then
      assignedWindowIds[windowId] = true
      table.insert(assignments, {
        window = window,
        cell_index = override.cell_index,
      })
    end
  end

  local defaultCellIndex = resolvedAppCellIndex(appName, screen, layout)
  local defaultWindow = chooseDefaultWindowForAppOnScreen(appName, screen, application, windows, assignedWindowIds)
  local defaultWindowId = windowIdKey(defaultWindow)

  if defaultWindow and defaultWindowId and defaultCellIndex then
    assignedWindowIds[defaultWindowId] = true
    table.insert(assignments, 1, {
      window = defaultWindow,
      cell_index = defaultCellIndex,
    })
  end

  return assignments
end

local function syntheticLayout()
  local combinedLayout = {
    name = 'Per-Screen Active Layouts',
    hide = false,
    cells = {},
    apps = {},
  }

  local syntheticApps = {}
  local cellIndexes = {}

  for _, screen in ipairs(screens.ordered()) do
    local screenId = screens.id(screen)
    local layout = M.currentLayout(screen)
    currentVariantForLayout(screen, layout)

    for appName, _ in pairs(layout.apps or {}) do
      for _, assignment in ipairs(managedWindowsForAppOnScreen(appName, screen, layout)) do
        local cell, cellScreen, variant = resolvedCellVariantForIndex(assignment.cell_index, screen, layout)

        if cell then
          local targetScreenId = screens.id(cellScreen or screen) or screenId
          local compositeCellKey = table.concat({
            targetScreenId,
            layout.key,
            tostring(variant),
            tostring(assignment.cell_index),
          }, ':')

          local compositeCellIndex = cellIndexes[compositeCellKey]
          if not compositeCellIndex then
            table.insert(combinedLayout.cells, {
              {
                cell = cell,
                screen = targetScreenId,
              },
            })
            compositeCellIndex = #combinedLayout.cells
            cellIndexes[compositeCellKey] = compositeCellIndex
          end

          local syntheticKey = table.concat({
            appName,
            screenId,
            tostring(assignment.window:id()),
          }, ':')

          syntheticApps[syntheticKey] = {
            id = apps[appName].id,
            window = assignment.window,
          }

          combinedLayout.apps[syntheticKey] = {
            cell = compositeCellIndex,
          }
        end
      end
    end
  end

  return combinedLayout, syntheticApps
end

function M.defaultLayoutKey(screen)
  local configuredLayouts = (screenLayouts and (screenLayouts.layouts or screenLayouts)) or {}
  local screenProfile = screens.profile(screen)

  for _, identifier in ipairs(screens.identifiers(screen)) do
    local layout = resolveLayout(configuredLayouts[identifier])
    if layout then
      return layout.key
    end
  end

  local profileDefault = resolveLayout(configuredLayouts['profile:' .. screenProfile] or configuredLayouts[screenProfile])
  if profileDefault then
    return profileDefault.key
  end

  local sharedDefault = resolveLayout(configuredLayouts.all)
  if sharedDefault then
    return sharedDefault.key
  end

  return defaultLayoutKeys[screenProfile] or layouts[1].key
end

function M.ensureScreenStates()
  for _, screen in ipairs(screens.ordered()) do
    ensureScreenState(screen)
  end
end

function M.currentLayout(screen)
  local screenState = ensureScreenState(screen)
  local layout = screenState and resolveLayout(screenState.layout_key) or nil
  return layout or layouts[1]
end

function M.currentLayoutKey(screen)
  return M.currentLayout(screen).key
end

function M.currentVariant(screen)
  return currentVariantForLayout(screen, M.currentLayout(screen))
end

function M.scheduleReapply(delaySeconds)
  if reapplyTimer then
    reapplyTimer:stop()
    reapplyTimer = nil
  end

  reapplyTimer = hs.timer.doAfter(delaySeconds or 0, function()
    reapplyTimer = nil
    M.apply()
  end)
end

function M.apply()
  if not layoutEngine then
    return
  end

  M.ensureScreenStates()

  if ensureOpenApps() then
    M.scheduleReapply(openAppReapplyDelaySeconds)
  end

  local combinedLayout, syntheticApps = syntheticLayout()

  layoutEngine
    :setApps(syntheticApps)
    :setLayouts({ combinedLayout })
    :selectLayout(1, 1)
end

function M.selectLayout(layoutRef, targetScreen)
  local layout = resolveLayout(layoutRef)
  local screen = targetScreen or screens.focused()
  local screenState = ensureScreenState(screen)

  if not layout or not screenState then
    return
  end

  screenState.layout_key = layout.key
  screenState.variant = 1
  persistState()

  M.scheduleReapply(0)
end

function M.selectNextVariant(targetScreen)
  local screen = targetScreen or screens.focused()
  local layout = M.currentLayout(screen)
  local screenState = ensureScreenState(screen)
  local firstCell = layout and layout.cells and layout.cells[1]
  local maxVariant = firstCell and #firstCell or 1

  if not screenState or maxVariant < 2 then
    return
  end

  screenState.variant = screenState.variant + 1
  if screenState.variant > maxVariant then
    screenState.variant = 1
  end
  persistState()

  M.scheduleReapply(0)
end

function M.resetLayout(targetScreen)
  local screen = targetScreen or screens.focused()
  local screenState = ensureScreenState(screen)
  local layout = M.currentLayout(screen)

  if not screenState or not layout then
    return
  end

  screenState.variant = 1
  screenState.app_overrides[layout.key] = {}
  screenState.window_overrides[layout.key] = {}
  state.preferred_windows[screens.id(screen)] = {}
  persistState()

  M.scheduleReapply(0)
end

function M.showLayoutPicker(targetScreen)
  local screen = targetScreen or screens.focused()
  local currentLayoutKey = M.currentLayoutKey(screen)
  local choices = {}

  for index, layout in ipairs(layouts) do
    local prefix = layout.key == currentLayoutKey and '* ' or ''
    table.insert(choices, {
      text = prefix .. layout.name,
      subText = 'Apply to ' .. screens.label(screen),
      layout_key = layout.key,
      order = index,
    })
  end

  local chooser = hs.chooser.new(function(choice)
    if choice then
      M.selectLayout(choice.layout_key, screen)
    end
  end)

  chooser:searchSubText(true):choices(choices):query(''):show()
end

function M.bindFocusedWindowToCell()
  local window = hs.window.focusedWindow()
  local screen = window and window:screen()
  local appName = window and appNameForWindow(window)
  local layout = screen and M.currentLayout(screen)

  if not window or not screen or not appName or not layout or not layout.apps[appName] then
    hs.alert.show('Focused window is not managed by the current screen layout')
    return
  end

  local choices = {}

  for cellIndex, _ in ipairs(layout.cells or {}) do
    local assignedApps = {}
    for assignedApp, appConfig in pairs(layout.apps or {}) do
      if appConfig.cell == cellIndex then
        table.insert(assignedApps, assignedApp)
      end
    end

    table.insert(choices, {
      text = 'Cell ' .. tostring(cellIndex),
      subText = (#assignedApps > 0 and table.concat(assignedApps, ', ')) or '(empty)',
      cell_index = cellIndex,
    })
  end

  local chooser = hs.chooser.new(function(choice)
    if not choice then
      return
    end

    local defaultCellIndex = resolvedAppCellIndex(appName, screen, layout)
    local windowOverrides = windowOverrideBucket(screen, layout.key, true)
    local windowId = windowIdKey(window)

    if choice.cell_index == defaultCellIndex then
      clearWindowOverride(screen, layout.key, window)
      setPreferredWindow(screen, appName, window)
    elseif windowId then
      windowOverrides[windowId] = {
        app_name = appName,
        cell_index = choice.cell_index,
      }
      clearPreferredWindow(screen, appName, window:id())
    end

    persistState()

    if placeManagedWindow(window, appName, screen) then
      window:focus()
    end
  end)

  chooser:searchSubText(true):choices(choices):query(''):show()
end

function M.placeApp(appName, targetScreen, preferredWindow)
  local screen = targetScreen or screens.focused()
  local application = appObject(appName)

  if not application then
    return false
  end

  local candidate = preferredWindow

  if not candidate or not candidate:isStandard() then
    for _, window in ipairs(application:allWindows()) do
      if window:isStandard() and screens.id(window:screen()) == screens.id(screen) then
        candidate = window
        break
      end
    end
  end

  if not candidate or not candidate:isStandard() then
    candidate = application:focusedWindow()
  end

  if not candidate or not candidate:isStandard() then
    for _, window in ipairs(application:allWindows()) do
      if window:isStandard() then
        candidate = window
        break
      end
    end
  end

  if not candidate or not candidate:isStandard() then
    return false
  end

  clearPreferredWindow(candidate:screen(), appName, candidate:id())

  if placeManagedWindow(candidate, appName, screen) then
    candidate:focus()
    return true
  end

  local moved = placeWindowOnScreen(candidate, screen)
  if moved then
    setPreferredWindow(screen, appName, candidate)
    candidate:focus()
  end

  return moved
end

function M.moveFocusedWindowToScreen(targetScreen)
  local window = hs.window.focusedWindow()
  if not window or not targetScreen then
    return
  end

  local appName = appNameForWindow(window)
  local currentScreen = window:screen()

  clearPreferredWindow(currentScreen, appName, window:id())

  if not placeManagedWindow(window, appName, targetScreen) then
    placeWindowOnScreen(window, targetScreen)
    setPreferredWindow(targetScreen, appName, window)
  end

  window:focus()
end

function M.moveFocusedWindowToNextScreen()
  local window = hs.window.focusedWindow()
  local currentScreen = window and window:screen()
  if not window or not currentScreen then
    return
  end

  M.moveFocusedWindowToScreen(screens.next(currentScreen))
end

function M.moveFocusedWindowToPreviousScreen()
  local window = hs.window.focusedWindow()
  local currentScreen = window and window:screen()
  if not window or not currentScreen then
    return
  end

  M.moveFocusedWindowToScreen(screens.previous(currentScreen))
end

function M.handleScreenChange()
  M.ensureScreenStates()
  M.scheduleReapply(screenChangeDelaySeconds)
end

function M.start(config)
  M.configure(config)
  validateConfig()
  loadState()
  M.ensureScreenStates()
  return M
end

function M.stop()
  if reapplyTimer then
    reapplyTimer:stop()
    reapplyTimer = nil
  end

  return M
end

M.appNameForWindow = appNameForWindow

return M
