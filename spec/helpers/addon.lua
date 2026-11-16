-- Loads addon source files the way the WoW client does: each file chunk receives (addonName, ns).
local M = {}

M.ADDON = "AzerothMercantileExchange"

-- load({"Core/Init.lua", "Core/Stats.lua"}) -> ns
function M.load(files, ns)
  ns = ns or {}
  for _, path in ipairs(files) do
    local chunk = assert(loadfile(path))
    chunk(M.ADDON, ns)
  end
  return ns
end

return M
