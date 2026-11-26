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
    -- its own scale times its parents' (a frame put out of sight at a speck's scale, as the game does)
    GetEffectiveScale = function(self)
      local s, f = 1, self
      while type(f) == "table" do
        local own = rawget(f, "scale")
        s = s * (type(own) == "number" and own or 1)
        f = rawget(f, "parent")
      end
      return s
    end,
    SetVertexOffset = function(self, corner, x, y)
      self.offsets = rawget(self, "offsets") or {}
      self.offsets[corner] = { x, y }
    end,
    GetFrameLevel = function()
      return 1
    end,
    SetText = function(self, t)
      self.text = t
    end,
    GetText = function(self)
      return rawget(self, "text")
    end,
    -- as the game measures it: far wider at a speck's scale (the font can't shrink below a few pixels)
    GetStringWidth = function(self)
      local w, s = #(rawget(self, "text") or "") * 6, self:GetEffectiveScale()
      return s < 0.05 and w * 0.05 / s or w
    end,
    GetStringHeight = function()
      return 12
    end,
    CreateTexture = function()
      return newObject("Texture")
    end,
    CreateFontString = function(self, _, _, font)
      local fs = newObject("FontString")
      fs._font = font
      fs.parent = self
      return fs
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
    -- anchors are recorded (the last SetPoint is points[#points]); ClearAllPoints empties them
    SetPoint = function(self, ...)
      -- SetPoint("TOPLEFT", other, "BOTTOMLEFT", ...) with other still nil (made later): the game anchors to the
      -- screen instead and the layout breaks ("anchor family connection")
      -- (a field read off a stub frame before it's set is one of the stub's catch-all functions, not nil)
      local point, rel, relPoint = ...
      if select("#", ...) >= 3 and type(relPoint) == "string" and type(rel) ~= "table" and type(rel) ~= "string" then
        error("SetPoint(" .. tostring(point) .. ") anchored to " .. type(rel) .. ", not a frame", 2)
      end
      self.points[#self.points + 1] = { ... }
    end,
    ClearAllPoints = function(self)
      self.points = {}
    end,
    SetAlpha = function(self, a)
      self.alpha = a
    end,
    GetAlpha = function(self)
      return rawget(self, "alpha") or 1
    end,
    SetScale = function(self, s)
      self.scale = s
    end,
    GetScale = function(self)
      return rawget(self, "scale") or 1
    end,
    -- colours are recorded, so widget specs can check a look (backdrop, border, text, fill)
    SetBackdropColor = function(self, r, g, b, a)
      self._backdrop = { r, g, b, a }
    end,
    SetBackdropBorderColor = function(self, r, g, b, a)
      self._border = { r, g, b, a }
    end,
    SetTextColor = function(self, r, g, b, a)
      self._textColor = { r, g, b, a }
    end,
    SetFontObject = function(self, font)
      self._font = font
    end,
    EnableMouse = function(self, on)
      self.mouse = on
    end,
    SetTexture = function(self, t)
      self._texture = t
    end,
    SetColorTexture = function(self, r, g, b, a)
      self._color = { r, g, b, a }
    end,
    SetVerticalScroll = function(self, y)
      self.vscroll = y
    end,
    GetVerticalScroll = function(self)
      return rawget(self, "vscroll") or 0
    end,
  }
  return setmetatable(o, {
    __index = function(_, k)
      -- a method the stub lacks is a no-op (the game has hundreds); an unset field of our own (lower case) is nil
      if methods[k] then
        return methods[k]
      end
      if type(k) == "string" and k:match("^%u") then
        return function() end
      end
    end,
  })
end
M.newObject = newObject

-- fake C_AuctionHouse (rows: { itemID, buyout, count })
local function newAuctionHouse()
  local a = { rows = {}, commodities = {} }
  function a.ReplicateItems() end
  function a.PostCommodity() end -- hooked by the addon: your posts feed the pricing model
  function a.PostItem() end
  -- your auctions: a.owned = { { auctionID =, itemKey = { itemID = }, quantity =, buyoutAmount =, status = 0 }, ... }
  a.owned = {}
  function a.GetNumOwnedAuctions()
    return #a.owned
  end
  function a.GetOwnedAuctionInfo(i)
    return a.owned[i]
  end
  function a.CancelAuction() end -- hooked by the addon: a cancel counts for sell-through
  -- browse results: a.browse = { { itemID, minPrice, totalQuantity }, ... }; a.browseFull
  a.browse, a.browseFull = {}, true
  function a.SendBrowseQuery() end
  function a.HasFullBrowseResults()
    return a.browseFull
  end
  function a.GetBrowseResults()
    local out = {}
    for i, r in ipairs(a.browse) do
      out[i] = { itemKey = { itemID = r[1], itemLevel = 0, itemSuffix = 0 }, minPrice = r[2], totalQuantity = r[3] }
    end
    return out
  end
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

  set("CreateFrame", function(kind, _, parent)
    local f = newObject(kind)
    f.parent = parent
    return f
  end)
  local screen = newObject("Frame")
  screen.w, screen.h = 1365, 768 -- a 1080p screen at the default UI scale, in UI units
  set("UIParent", screen)
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
  set("GetTime", function()
    return env.now
  end)
  set("GetServerTime", function()
    return env.now
  end)
  set("debugprofilestop", function()
    env.clock = env.clock + 0.05
    return env.clock
  end)
  set("date", os.date)
  set("GetNormalizedRealmName", function()
    return opts.realm or "TestRealm"
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
  set("StaticPopupDialogs", {})
  set("StaticPopup_Show", function(name)
    env.popup = name
  end)
  set("ReloadUI", function()
    env.reloads = env.reloads + 1
  end)
  set("SlashCmdList", {})
  set("securecallfunction", function(f, ...) -- CallbackHandler dispatches through it
    return f(...)
  end)
  -- real libraries, registered through the real LibStub (like embeds.xml does)
  set("LibStub", nil)
  dofile("Libs/Ace3/LibStub/LibStub.lua")
  dofile("Libs/Ace3/CallbackHandler-1.0/CallbackHandler-1.0.lua")
  dofile("Libs/LibDataBroker-1.1/LibDataBroker-1.1.lua")
  dofile("Libs/LibDeflate/LibDeflate.lua")
  dofile("LibAMEChart-1.0/LibAMEChart-1.0.lua")
  -- UI globals
  set("IsInGuild", function()
    return env.inGuild
  end)
  set("UISpecialFrames", {})
  set("tinsert", table.insert)
  set("ITEM_QUALITY_COLORS", { [1] = { hex = "|cffffffff" }, [3] = { hex = "|cff0070dd" } })
  set("GameTooltip", newObject("GameTooltip"))
  set("ChatEdit_InsertLink", function() end)
  -- env.modified = "CHATLINK" (Shift), "DRESSUP" (Ctrl): the modified click the next click counts as
  set("HandleModifiedItemClick", function(link)
    env.modifiedLinks = env.modifiedLinks or {}
    env.modifiedLinks[#env.modifiedLinks + 1] = link
  end)
  set("IsModifiedClick", function(kind)
    return env.modified ~= nil and env.modified == kind
  end)
  set("IsAltKeyDown", function()
    return env.altDown
  end)
  set("IsShiftKeyDown", function()
    return env.shiftDown
  end)
  set("IsControlKeyDown", function()
    return false
  end)
  set("GetCursorPosition", function()
    return 50, 50
  end)
  set("BackdropTemplateMixin", {})
  set("Mixin", function(o, ...)
    for _, m in ipairs({ ... }) do
      for k, v in pairs(m) do
        o[k] = v
      end
    end
    return o
  end)
  set("C_Item", {
    GetItemID = function(location) -- item locations are faked as { itemID = id }
      return location and location.itemID
    end,
    -- env.sellPrices[id]: what a vendor pays (the 11th value)
    GetItemInfo = function(id)
      return "Item " .. id, "|Hitem:" .. id .. "|h", 1, nil, nil, nil, nil, nil, nil, 134400, env.sellPrices[id]
    end,
    GetItemInfoInstant = function(id)
      return id, "Trade Goods", "Cloth", "", 134400, 7, id % 2 == 0 and 5 or 6
    end,
    GetItemClassInfo = function(classID)
      return "Class" .. classID
    end,
    GetItemSubClassInfo = function(classID, subID)
      return "Sub" .. classID .. "." .. subID
    end,
    RequestLoadItemDataByID = function() end,
  })
  set("C_AuctionHouse", env.ah)
  -- legacy AH API (Forever): env.legacyRows = { { itemID, buyout, count } }, 1-based; env.legacyTotal: results of the
  -- whole search when the list holds one page of it (default: the rows)
  env.legacyRows = {}
  env.sellPrices = {}
  set("QueryAuctionItems", function() end)
  set("GetNumAuctionItems", function()
    return #env.legacyRows, env.legacyTotal or #env.legacyRows
  end)
  set("GetAuctionItemInfo", function(_, i)
    local r = env.legacyRows[i]
    if r then
      return "x", nil, r[3], 1, true, 1, "", 0, 0, r[2], 0, false, nil, nil, nil, 0, r[1], true
    end
  end)
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
    -- name, title, notes, loadable, reason: only AME's history addon is installed. As in the client, a load-on-demand
    -- addon not loaded yet says it isn't loadable, with reason DEMAND_LOADED; env.addons[name] = reason adds others
    GetAddOnInfo = function(name)
      local reason = name == "AzerothMercantileExchange_History" and "DEMAND_LOADED" or env.addons and env.addons[name]
      if reason and reason ~= "MISSING" then
        return name, name, "", false, reason
      end
      return nil, nil, nil, false, "MISSING"
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
