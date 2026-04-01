local M = {}

local screens = dofile(hs.spoons.resourcePath('screens.lua'))

local apps = {}
local layouts = {}
local screenLayouts = {}

local layoutEngine = nil
local reapplyTimer = nil
local defaultSettingsKey = 'WorkspaceManager.spoon.screen_state.v1'
local defaultOpenAppReapplyDelaySeconds = 0.5
local defaultScreenChangeDelaySeconds = 1
local defaultCaptureWindowStateOnStart = true
local settingsKey = defaultSettingsKey
local openAppReapplyDelaySeconds = defaultOpenAppReapplyDelaySeconds
local screenChangeDelaySeconds = defaultScreenChangeDelaySeconds
local captureWindowStateOnStart = defaultCaptureWindowStateOnStart

local state = {
  screens = {},
  preferred_windows = {},
}

local layoutsByKey = {}

local function isNonEmptyString(value)
  return type(value) == 'string' and value ~= ''
end

local function isPositiveInteger(value)
  return type(value) == 'number' and value >= 1 and value % 1 == 0
end

local function configError(message)
  error('WorkspaceManager invalid config: ' .. message, 3)
end

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
  if layoutEngine == nil then
    configError('requires config.layoutEngine')
  end

  if type(layoutEngine) ~= 'table' then
    configError('config.layoutEngine must be a GridLayout-like table')
  end

  for _, methodName in ipairs({ 'setApps', 'setLayouts', 'selectLayout' }) do
    if type(layoutEngine[methodName]) ~= 'function' then
      configError("config.layoutEngine must respond to '" .. methodName .. "()'")
    end
  end

  if type(apps) ~= 'table' then
    configError('requires config.apps')
  end

  if type(layouts) ~= 'table' or #layouts == 0 then
    configError('requires config.layouts')
  end

  if not isNonEmptyString(settingsKey) then
    configError('config.settingsKey must be a non-empty string')
  end

  if type(openAppReapplyDelaySeconds) ~= 'number' or openAppReapplyDelaySeconds < 0 then
    configError('config.openAppReapplyDelaySeconds must be a non-negative number')
  end

  if type(screenChangeDelaySeconds) ~= 'number' or screenChangeDelaySeconds < 0 then
    configError('config.screenChangeDelaySeconds must be a non-negative number')
  end

  if type(captureWindowStateOnStart) ~= 'boolean' then
    configError('config.captureWindowStateOnStart must be a boolean')
  end

  for appName, appConfig in pairs(apps) do
    if not isNonEmptyString(appName) then
      configError('config.apps keys must be non-empty strings')
    end

    if type(appConfig) ~= 'table' then
      configError("config.apps['" .. appName .. "'] must be a table")
    end

    if not isNonEmptyString(appConfig.id) then
      configError("config.apps['" .. appName .. "'].id must be a non-empty string")
    end
  end

  local seenLayoutKeys = {}
  local seenLayoutNames = {}

  for index, layout in ipairs(layouts) do
    if type(layout) ~= 'table' then
      configError('config.layouts[' .. tostring(index) .. '] must be a table')
    end

    if not isNonEmptyString(layout.key) then
      configError('config.layouts[' .. tostring(index) .. '].key must be a non-empty string')
    end

    if not isNonEmptyString(layout.name) then
      configError("layout '" .. layout.key .. "' must define a non-empty name")
    end

    if seenLayoutKeys[layout.key] then
      configError("duplicate layout key '" .. layout.key .. "'")
    end

    local loweredName = layout.name:lower()
    if seenLayoutNames[loweredName] then
      configError("duplicate layout name '" .. layout.name .. "'")
    end

    seenLayoutKeys[layout.key] = true
    seenLayoutNames[loweredName] = true

    if type(layout.cells) ~= 'table' or #layout.cells == 0 then
      configError("layout '" .. layout.key .. "' must define at least one cell")
    end

    for cellIndex, cellVariants in ipairs(layout.cells) do
      if type(cellVariants) ~= 'table' then
        configError("layout '" .. layout.key .. "' cell " .. tostring(cellIndex) .. ' must be a variant array')
      end

      local variantCount = 0
      for variantIndex, cellVariant in ipairs(cellVariants) do
        variantCount = variantCount + 1

        if type(cellVariant) == 'string' then
          if cellVariant == '' then
            configError("layout '" .. layout.key .. "' cell " .. tostring(cellIndex) .. ' contains an empty string variant')
          end
        elseif type(cellVariant) == 'table' then
          if not isNonEmptyString(cellVariant.cell) then
            configError(
              "layout '" .. layout.key .. "' cell " .. tostring(cellIndex) .. ' variant ' .. tostring(variantIndex)
              .. " must provide a non-empty 'cell' string"
            )
          end
        else
          configError(
            "layout '" .. layout.key .. "' cell " .. tostring(cellIndex) .. ' variant ' .. tostring(variantIndex)
            .. " must be a string or { cell = '...' } table"
          )
        end
      end

      if variantCount == 0 then
        configError("layout '" .. layout.key .. "' cell " .. tostring(cellIndex) .. ' must define at least one variant')
      end
    end

    if layout.apps ~= nil and type(layout.apps) ~= 'table' then
      configError("layout '" .. layout.key .. "'.apps must be a table")
    end

    for appName, appConfig in pairs(layout.apps or {}) do
      if not apps[appName] then
        configError("layout '" .. layout.key .. "' references unknown app '" .. tostring(appName) .. "'")
      end

      if type(appConfig) ~= 'table' then
        configError("layout '" .. layout.key .. "' app '" .. tostring(appName) .. "' config must be a table")
      end

      if not isPositiveInteger(appConfig.cell) then
        configError("layout '" .. layout.key .. "' app '" .. tostring(appName) .. "' must use a positive integer cell index")
      end

      if not layout.cells[appConfig.cell] then
        configError(
          "layout '" .. layout.key .. "' app '" .. tostring(appName) .. "' references missing cell "
          .. tostring(appConfig.cell)
        )
      end

      if appConfig.open ~= nil and type(appConfig.open) ~= 'boolean' then
        configError("layout '" .. layout.key .. "' app '" .. tostring(appName) .. "'.open must be a boolean when set")
      end
    end
  end

  rebuildLayoutIndex()

  local function validateLayoutMapping(mapping, label)
    for identifier, layoutRef in pairs(mapping or {}) do
      if not isNonEmptyString(identifier) then
        configError(label .. ' keys must be non-empty strings')
      end

      if not resolveLayout(layoutRef) then
        configError(
          label .. "['" .. identifier .. "'] references unknown layout '" .. tostring(layoutRef) .. "'"
        )
      end
    end
  end

  if type(screenLayouts) ~= 'table' then
    configError('config.screenLayouts must be a table when provided')
  end

  local configuredLayouts = screenLayouts.layouts
  if configuredLayouts ~= nil then
    if type(configuredLayouts) ~= 'table' then
      configError('config.screenLayouts.layouts must be a table')
    end

    validateLayoutMapping(configuredLayouts, 'config.screenLayouts.layouts')
  else
    validateLayoutMapping(screenLayouts, 'config.screenLayouts')
  end

end

function M.configure(config)
  config = config or {}

  if config.apps ~= nil and type(config.apps) ~= 'table' then
    configError('config.apps must be a table')
  end

  if config.layouts ~= nil and type(config.layouts) ~= 'table' then
    configError('config.layouts must be an array-like table')
  end

  if config.screenLayouts ~= nil and type(config.screenLayouts) ~= 'table' then
    configError('config.screenLayouts must be a table')
  end

  apps = config.apps or {}
  layouts = config.layouts or {}
  screenLayouts = config.screenLayouts or {}
  layoutEngine = config.layoutEngine
  settingsKey = config.settingsKey or defaultSettingsKey
  openAppReapplyDelaySeconds = config.openAppReapplyDelaySeconds or defaultOpenAppReapplyDelaySeconds
  screenChangeDelaySeconds = config.screenChangeDelaySeconds or defaultScreenChangeDelaySeconds
  if config.captureWindowStateOnStart == nil then
    captureWindowStateOnStart = defaultCaptureWindowStateOnStart
  else
    captureWindowStateOnStart = config.captureWindowStateOnStart
  end

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
        local source = config and config.source

        if normalizedWindowId
          and apps[appName]
          and numericCellIndex
          and layout.cells
          and layout.cells[numericCellIndex] then
          normalized[layout.key] = normalized[layout.key] or {}
          normalized[layout.key][normalizedWindowId] = {
            app_name = appName,
            cell_index = numericCellIndex,
            source = source == 'captured' and 'captured' or nil,
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

local function geometryMatches(left, right)
  if type(left) ~= 'table' or type(right) ~= 'table' then
    return false
  end

  return tonumber(left.x) == tonumber(right.x)
    and tonumber(left.y) == tonumber(right.y)
    and tonumber(left.w) == tonumber(right.w)
    and tonumber(left.h) == tonumber(right.h)
end

local function gridCellForWindow(window)
  if not window or not hs.grid or type(hs.grid.get) ~= 'function' then
    return nil
  end

  local ok, cell = pcall(hs.grid.get, window)
  if not ok then
    return nil
  end

  if type(cell) ~= 'table' or cell.x == nil or cell.y == nil or cell.w == nil or cell.h == nil then
    return nil
  end

  return cell
end

local function cellGeometry(cell)
  if cell == nil or not hs.geometry or type(hs.geometry.new) ~= 'function' then
    return nil
  end

  local ok, geometry = pcall(hs.geometry.new, cell)
  if not ok then
    return nil
  end

  if type(geometry) ~= 'table' or geometry.x == nil or geometry.y == nil or geometry.w == nil or geometry.h == nil then
    return nil
  end

  return geometry
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

local function cellChoicesForLayout(layout)
  local choices = {}

  for cellIndex, _ in ipairs(layout.cells or {}) do
    local assignedApps = {}

    for assignedApp, appConfig in pairs(layout.apps or {}) do
      if appConfig.cell == cellIndex then
        table.insert(assignedApps, assignedApp)
      end
    end

    table.sort(assignedApps)
    table.insert(choices, {
      text = 'Cell ' .. tostring(cellIndex),
      subText = (#assignedApps > 0 and table.concat(assignedApps, ', ')) or '(empty)',
      cell_index = cellIndex,
    })
  end

  return choices
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
    local appOverrides = appOverrideBucket(screen, layout.key, false)
    local appOverrideCellIndex = appOverrides and appOverrides[appName] or nil
    local defaultCellIndex = layout.apps[appName].cell

    if override.source == 'captured'
      and appOverrideCellIndex
      and override.cell_index == defaultCellIndex
      and appOverrideCellIndex ~= override.cell_index then
      return appOverrideCellIndex
    end

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

local function cellIndexForWindow(appName, screen, layout, window)
  local windowScreen = window and window:screen() or nil
  local targetScreenId = screens.id(windowScreen)
  local windowCell = gridCellForWindow(window)

  if not targetScreenId or not windowCell or not layout or not layout.apps or not layout.apps[appName] then
    return nil
  end

  for cellIndex, _ in ipairs(layout.cells or {}) do
    local cell, cellScreen = resolvedCellVariantForIndex(cellIndex, screen, layout)
    local destinationScreen = cellScreen or screen

    if screens.id(destinationScreen) == targetScreenId and geometryMatches(cellGeometry(cell), windowCell) then
      return cellIndex
    end
  end

  return nil
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
    local effectiveCellIndex = override and resolvedCellIndex(appName, screen, layout, window) or nil

    if windowId
      and not assignedWindowIds[windowId]
      and override
      and override.app_name == appName then
      assignedWindowIds[windowId] = true
      table.insert(assignments, {
        window = window,
        cell_index = effectiveCellIndex,
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
          local destinationScreen = cellScreen or screen
          local targetScreenId = screens.id(destinationScreen) or screenId
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
                screen = destinationScreen,
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

local function captureLiveWindowState()
  state.preferred_windows = {}

  for _, screen in ipairs(screens.ordered()) do
    local screenId = screens.id(screen)
    local layout = M.currentLayout(screen)
    local screenState = ensureScreenState(screen)

    if screenId and layout and screenState then
      local nextWindowOverrides = {}
      state.preferred_windows[screenId] = {}

      for appName, _ in pairs(layout.apps or {}) do
        local application, windows = windowsForAppOnScreen(appName, screen)
        local preferredWindow = nil

        for _, window in ipairs(windows) do
          local windowId = windowIdKey(window)
          local cellIndex = cellIndexForWindow(appName, screen, layout, window)
          local existingOverride = windowId and windowOverrideConfig(screen, layout.key, window) or nil

          if cellIndex and windowId then
            nextWindowOverrides[windowId] = {
              app_name = appName,
              cell_index = cellIndex,
              source = 'captured',
            }
          elseif existingOverride and windowId and existingOverride.app_name == appName then
            nextWindowOverrides[windowId] = {
              app_name = appName,
              cell_index = existingOverride.cell_index,
              source = existingOverride.source,
            }
          elseif not preferredWindow then
            preferredWindow = window
          end
        end

        if application and not preferredWindow then
          local appFocusedWindow = application:focusedWindow()
          if appFocusedWindow
            and appFocusedWindow:isStandard()
            and screens.id(appFocusedWindow:screen()) == screenId then
            preferredWindow = appFocusedWindow
          end
        end

        if not preferredWindow then
          local focusedWindow = hs.window.focusedWindow()
          if focusedWindow
            and focusedWindow:isStandard()
            and appNameForWindow(focusedWindow) == appName
            and screens.id(focusedWindow:screen()) == screenId then
            preferredWindow = focusedWindow
          end
        end

        if preferredWindow then
          setPreferredWindow(screen, appName, preferredWindow)
        end
      end

      screenState.window_overrides[layout.key] = nextWindowOverrides
    end
  end

  persistState()
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

  return layouts[1].key
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

  local choices = cellChoicesForLayout(layout)

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
        source = nil,
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

function M.setAppCell(appName, cellIndex, targetScreen)
  local screen = targetScreen or screens.focused()
  local layout = screen and M.currentLayout(screen)
  local numericCellIndex = tonumber(cellIndex)

  if not screen or not layout or not layout.apps or not layout.apps[appName] then
    return false
  end

  if not numericCellIndex or numericCellIndex < 1 or numericCellIndex % 1 ~= 0 or not layout.cells[numericCellIndex] then
    return false
  end

  local appOverrides = appOverrideBucket(screen, layout.key, true)
  local defaultCellIndex = layout.apps[appName].cell

  if numericCellIndex == defaultCellIndex then
    appOverrides[appName] = nil
  else
    appOverrides[appName] = numericCellIndex
  end

  persistState()
  M.scheduleReapply(0)

  return true
end

function M.clearAppCell(appName, targetScreen)
  local screen = targetScreen or screens.focused()
  local layout = screen and M.currentLayout(screen)
  local appOverrides = layout and appOverrideBucket(screen, layout.key, false) or nil

  if not screen or not layout or not layout.apps or not layout.apps[appName] then
    return false
  end

  if appOverrides then
    appOverrides[appName] = nil
  end

  persistState()
  M.scheduleReapply(0)

  return true
end

function M.bindFocusedAppToCell()
  local window = hs.window.focusedWindow()
  local screen = window and window:screen()
  local appName = window and appNameForWindow(window)
  local layout = screen and M.currentLayout(screen)

  if not window or not screen or not appName or not layout or not layout.apps[appName] then
    hs.alert.show('Focused app is not managed by the current screen layout')
    return
  end

  local chooser = hs.chooser.new(function(choice)
    if choice then
      M.setAppCell(appName, choice.cell_index, screen)
    end
  end)

  chooser:searchSubText(true):choices(cellChoicesForLayout(layout)):query(''):show()
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
  if captureWindowStateOnStart then
    captureLiveWindowState()
  end
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
