local M = {}

local function modeFor(screen)
  local mode = screen and screen:currentMode()
  if mode and mode.w and mode.h then
    return mode
  end

  local frame = screen and screen:frame() or { w = 0, h = 0 }
  return {
    w = frame.w or 0,
    h = frame.h or 0,
  }
end

local function maxModeFor(screen)
  local mode = modeFor(screen)
  local availableModes = screen and screen:availableModes() or {}
  local maxWidth = mode.w or 0
  local maxHeight = mode.h or 0

  for _, candidate in pairs(availableModes) do
    local width = tonumber(candidate.w) or 0
    local height = tonumber(candidate.h) or 0

    if width > maxWidth then
      maxWidth = width
    end

    if height > maxHeight then
      maxHeight = height
    end
  end

  return {
    w = maxWidth,
    h = maxHeight,
  }
end

function M.id(screen)
  if not screen then
    return nil
  end

  return screen:getUUID() or tostring(screen:id()) or screen:name()
end

function M.isBuiltInDisplay(screen)
  local name = ((screen and screen:name()) or ''):lower()

  return name:find('built%-in', 1, false) ~= nil
    or name:find('internal', 1, true) ~= nil
    or name:find('color lcd', 1, true) ~= nil
    or name:find('liquid retina', 1, true) ~= nil
end

function M.profile(screen)
  if not screen or M.isBuiltInDisplay(screen) then
    return 'builtin'
  end

  local mode = maxModeFor(screen)
  local aspectRatio = mode.w / math.max(mode.h, 1)

  if mode.w >= 5000 or aspectRatio >= 2.8 then
    return 'ultrawide'
  end

  if mode.w >= 3840 or mode.h >= 2160 then
    return 'fourk'
  end

  return 'standard'
end

function M.label(screen)
  if not screen then
    return 'unknown screen'
  end

  return screen:name() or ('screen ' .. tostring(screen:id()))
end

function M.focused()
  local focusedWindow = hs.window.focusedWindow()
  return (focusedWindow and focusedWindow:screen()) or hs.screen.mainScreen() or hs.screen.primaryScreen()
end

function M.ordered()
  local ordered = {}
  local positions = hs.screen.screenPositions()

  for _, screen in ipairs(hs.screen.allScreens()) do
    table.insert(ordered, screen)
  end

  table.sort(ordered, function(a, b)
    local posA = positions[a] or { x = 0, y = 0 }
    local posB = positions[b] or { x = 0, y = 0 }

    if posA.x ~= posB.x then
      return posA.x < posB.x
    end

    if posA.y ~= posB.y then
      return posA.y < posB.y
    end

    return M.label(a) < M.label(b)
  end)

  return ordered
end

function M.index(screen)
  local screenId = M.id(screen)

  for index, candidate in ipairs(M.ordered()) do
    if M.id(candidate) == screenId then
      return index
    end
  end

  return nil
end

function M.next(screen)
  local ordered = M.ordered()
  if #ordered < 2 then
    return screen
  end

  local currentIndex = M.index(screen) or 1
  local nextIndex = (currentIndex % #ordered) + 1

  return ordered[nextIndex]
end

function M.previous(screen)
  local ordered = M.ordered()
  if #ordered < 2 then
    return screen
  end

  local currentIndex = M.index(screen) or 1
  local previousIndex = currentIndex - 1
  if previousIndex < 1 then
    previousIndex = #ordered
  end

  return ordered[previousIndex]
end

function M.identifiers(screen)
  if not screen then
    return {}
  end

  local identifiers = {}
  local screenId = M.id(screen)
  local index = M.index(screen)
  local name = screen:name()

  if screenId then
    table.insert(identifiers, screenId)
  end

  if name then
    table.insert(identifiers, name)
  end

  if screen == hs.screen.primaryScreen() then
    table.insert(identifiers, 'primary')
  end

  if index then
    table.insert(identifiers, 'screen:' .. tostring(index))
  end

  return identifiers
end

return M
