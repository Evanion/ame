-- Minimal stubbed WoW client for integration specs: frames with scripts/events, timers, slash commands, LibStub,
-- C_AddOns.LoadAddOn, a fake C_AuctionHouse, and a chat log. Enough to load the addon's TOC files and drive events.
local M = {}

local function readToc(path)
  local files = {}
  for line in io.lines(path) do
    line = line:gsub("\r", "")
    if line ~= "" and not line:match("^#") and not line:match("%.xml$") then
      files[#files + 1] = line:gsub("\\", "/")
    end
  end
  return files
end
M.readToc = readToc

-- Generic frame/region: any unknown method is a no-op returning nil; a few return sensible values.
local function newObject(kind)
  local o = { kind = kind, scripts = {}, events = {}, shown = true, points = {}, w = 100, h = 100, children = {} }
  local methods = {
    SetScript = function(self, name, fn)
      self.scripts[name] = fn
    end,
    GetScript = function(self, name)
      return self.scripts[name]
    end,
    HookScript = function(self, name, fn)
      local old = self.scripts[name]
      self.scripts[name] = function(...)
        if old then
          old(...)
        end
        fn(...)
      end
    end,
    RegisterEvent = function(self, e)
      if M.unknownEvents and M.unknownEvents[e] then
        error("Attempt to register unknown event " .. e)
      end
      self.events[e] = true
      M.frames[self] = true
    end,
    UnregisterEvent = function(self, e)
      self.events[e] = nil
    end,
    Show = function(self)
      self.shown = true
    end,
    Hide = function(self)
      self.shown = false
    end,
    IsShown = function(self)
      return self.shown
    end,
    IsVisible = function(self)
      return self.shown
    end,
    SetShown = function(self, v)
      self.shown = not not v
    end,
    SetSize = function(self, w, h)
      self.w, self.h = w, h
    end,
    SetWidth = function(self, w)
      self.w = w
    end,
    SetHeight = function(self, h)
      self.h = h
    end,
    GetWidth = function(self)
      return self.w
    end,
    GetHeight = function(self)
      return self.h
    end,
    GetSize = function(self)
      return self.w, self.h
    end,
    GetLeft = function()
      return 0
    end,
    GetBottom = function()
      return 0
    end,
    GetTop = function(self)
      return self.h
    end,
    GetRight = function(self)
      return self.w
    end,
    GetEffectiveScale = function()
      return 1
    end,
    GetFrameLevel = function()
      return 1
    end,
    SetText = function(self, t)
      self.text = t
    end,
    GetText = function(self)
      return self.text
    end,
    GetStringWidth = function(self)
      return #(self.text or "") * 6
    end,
    CreateTexture = function()
      return newObject("Texture")
    end,
    CreateFontString = function()
      return newObject("FontString")
    end,
    CreateLine = function()
      return newObject("Line")
    end,
    IsMouseOver = function()
      return false
    end,
    GetParent = function(self)
      return self.parent
    end,
  }
  return setmetatable(o, {
    __index = function(_, k)
      return methods[k] or function() end
    end,
  })
end
M.newObject = newObject

-- fake C_AuctionHouse (rows: { itemID, buyout, count })
local function newAuctionHouse()
  local a = { rows = {}, commodities = {} }
  function a.ReplicateItems() end
  function a.GetNumReplicateItems()
    return #a.rows
  end
  function a.GetReplicateItemInfo(i)
    local r = a.rows[i + 1]
    return nil, nil, r[3], 1, true, 1, "", 0, 0, r[2], 0, false, nil, nil, nil, 0, r[1], false
  end
  function a.HasFullCommoditySearchResults()
    return true
  end
  function a.GetNumCommoditySearchResults(id)
    return #(a.commodities[id] or {})
  end
  function a.GetCommoditySearchResultInfo(id, i)
    local r = a.commodities[id][i]
    return { itemID = id, unitPrice = r[1], quantity = r[2] }
  end
  function a.HasFullItemSearchResults()
    return true
  end
  function a.GetNumItemSearchResults()
    return 0
  end
  return a
end

-- Install globals; returns an env table with helpers. Call env:restore() in after_each.
function M.install(opts)
  opts = opts or {}
  local saved = {}
  local function set(k, v)
    if saved[k] == nil then
      saved[k] = { v = _G[k] }
    end
    _G[k] = v
  end

  M.frames = {}
  M.unknownEvents = opts.unknownEvents
  local env = { chat = {}, timers = {}, now = opts.now or 1794825000, clock = 0, reloads = 0, loaded = {} }
  env.ah = newAuctionHouse()
  local LibDeflate = dofile("Libs/LibDeflate/LibDeflate.lua")

  set("CreateFrame", function(kind, _, parent)
    local f = newObject(kind)
    f.parent = parent
    return f
  end)
  set("UIParent", newObject("Frame"))
  set("hooksecurefunc", function(tbl, name, fn)
    if type(tbl) == "string" then
      tbl, name, fn = _G, tbl, name
    end
    local orig = tbl[name]
    tbl[name] = function(...)
      local r = { orig(...) }
      fn(...)
      return unpack(r)
    end
  end)
  set("C_Timer", {
    After = function(s, fn)
      env.timers[#env.timers + 1] = { at = env.now + s, fn = fn }
    end,
  })
  set("GetServerTime", function()
    return env.now
  end)
  set("debugprofilestop", function()
    env.clock = env.clock + 0.05
    return env.clock
  end)
  set("date", os.date)
  set("GetNormalizedRealmName", function()
    return "TestRealm"
  end)
  set("UnitFactionGroup", function(unit)
    if unit == "npc" then
      return env.npcFaction
    end
    return "Horde"
  end)
  set("UnitName", function()
    return "Tyken"
  end)
  set("DEFAULT_CHAT_FRAME", {
    AddMessage = function(_, msg)
      env.chat[#env.chat + 1] = msg
    end,
  })
  set("GetCoinTextureString", function(c)
    return tostring(c) .. "c"
  end)
  set("SecondsToTime", function(s)
    return tostring(s) .. "s"
  end)
  set("ReloadUI", function()
    env.reloads = env.reloads + 1
  end)
  set("SlashCmdList", {})
  set("LibStub", function(name)
    if name == "LibDeflate" then
      return LibDeflate
    end
    error("LibStub: unknown library " .. tostring(name))
  end)
  set("C_AuctionHouse", env.ah)
  set("C_AddOns", {
    LoadAddOn = function(name)
      if env.loaded[name] then
        return true
      end
      if name == "AzerothMercantileExchange_History" then
        dofile("AzerothMercantileExchange_History/History.lua")
        env.loaded[name] = true
        return true
      end
      return false, "MISSING"
    end,
  })
  set("Enum", { SendAddonMessageResult = { Success = 0 } })
  set("AME_DB", nil)
  set("AME_HistoryDB", nil)
  set("Auctionator", opts.auctionator)

  function env:restore()
    for k, s in pairs(saved) do
      _G[k] = s.v
    end
  end

  function env:fire(event, ...)
    for f in pairs(M.frames) do
      if f.events[event] and f.scripts.OnEvent then
        f.scripts.OnEvent(f, event, ...)
      end
    end
  end

  -- run OnUpdate scripts n times (drives background jobs)
  function env:update(n)
    for _ = 1, n or 1 do
      for _, f in ipairs(env.updaters()) do
        f.scripts.OnUpdate(f, 0.016)
      end
    end
  end

  function env.updaters()
    local list = {}
    for f in pairs(env.allFrames) do
      if f.scripts.OnUpdate then
        list[#list + 1] = f
      end
    end
    return list
  end

  -- advance time, firing due timers
  function env:advance(seconds)
    env.now = env.now + seconds
    local due, keep = {}, {}
    for _, t in ipairs(env.timers) do
      if t.at <= env.now then
        due[#due + 1] = t
      else
        keep[#keep + 1] = t
      end
    end
    env.timers = keep
    for _, t in ipairs(due) do
      t.fn()
    end
  end

  function env:slash(cmd, msg)
    _G.SlashCmdList[cmd](msg or "")
  end

  function env:chatContains(pattern)
    for _, line in ipairs(env.chat) do
      if line:find(pattern) then
        return true
      end
    end
    return false
  end

  -- track every frame created (for OnUpdate drivers)
  env.allFrames = {}
  local create = _G.CreateFrame
  _G.CreateFrame = function(...)
    local f = create(...)
    env.allFrames[f] = true
    return f
  end

  return env
end

-- load the addon's TOC file list with a shared namespace
function M.loadAddon(tocPath, addonName)
  local ns = {}
  for _, path in ipairs(readToc(tocPath)) do
    local chunk = assert(loadfile(path))
    chunk(addonName, ns)
  end
  return ns
end

return M
