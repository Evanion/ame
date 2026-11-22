-- Loads addon source files the way the WoW client does: each file chunk receives (addonName, ns).
local M = {}

M.ADDON = "AzerothMercantileExchange"

-- load({"Core/Init.lua", "Core/Stats.lua"}) -> ns. Core/Events.lua (the change signal every module may fire) comes
-- right after Core/Init.lua, as in the TOC.
function M.load(files, ns)
  ns = ns or {}
  for _, path in ipairs(files) do
    local chunk = assert(loadfile(path))
    chunk(M.ADDON, ns)
    if path == "Core/Init.lua" and not ns.Events then
      assert(loadfile("Core/Events.lua"))(M.ADDON, ns)
    end
  end
  return ns
end

return M
