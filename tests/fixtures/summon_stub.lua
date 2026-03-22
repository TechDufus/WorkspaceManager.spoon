local state = assert(rawget(_G, '__workspaceManagerInitTest'), 'missing init test state')

local function record(name, ...)
  state.calls[name] = (state.calls[name] or 0) + 1
  state.lastArgs[name] = { ... }
end

return function(runtime)
  state.summonRuntime = runtime

  local M = {}

  function M.start(config)
    record('summon.start', config)
    return M
  end

  function M.stop()
    record('summon.stop')
    return M
  end

  function M.summon(appName)
    record('summon.summon', appName)
    return M
  end

  return M
end
