-- The session tracker (board SessionTracker): out in the world, what this outing has gathered and looted at what the
-- auction house would net (or a vendor, when that pays more), an hour's rate, what your bags hold now and how many
-- slots are free, and the three best finds. A small frame of its own, drawn by its own layout renderer; drag it
-- anywhere; it hides in combat. The numbers come from Core/Session.lua.
--
--   SessionTracker.Tree(summary, bags) -> layout tree   summary: Session:Summary; bags { value, free }
--   SessionTracker.Toggle(), .Show(), .Hide()
--   SessionTracker.NewSession()
local _, ns = ...
local L = ns.L

local Layout, Kit = ns.Layout, ns.Kit

local T = { W = 280, H = 214 }
ns.SessionTracker = T

function T.Tree(sum, bags)
  bags = bags or {}
  local children = {
    {
      id = "session.title",
      type = "frametitle",
      props = { title = L["This session"], note = ns.Session.Duration(sum.elapsed) },
      meta = { h = 20 },
    },
    {
      id = "session.total",
      type = "keyvalue",
      props = { label = L["Gathered and looted"], copper = sum.total, signed = true, big = true },
      meta = { h = 20 },
    },
    {
      id = "session.rate",
      type = "keyvalue",
      props = { label = L["An hour"], copper = sum.perHour },
      meta = { h = 18 },
    },
    {
      id = "session.bags",
      type = "keyvalue",
      props = {
        label = L["Bags now"],
        copper = bags.value or 0,
        note = bags.free and (bags.free == 1 and L["1 slot free"] or L["%d slots free"]:format(bags.free)) or nil,
        noteTone = "dim",
      },
      meta = { h = 18 },
    },
    { id = "session.rule", type = "divider", meta = { h = 7 } },
  }
  for i, f in ipairs(sum.top or {}) do
    children[#children + 1] = {
      id = "session.top" .. i,
      type = "keyvalue",
      props = { item = f.key, count = f.count, copper = f.value },
      meta = { h = 18 },
    }
  end
  if #(sum.top or {}) == 0 then
    children[#children + 1] = {
      id = "session.none",
      type = "text",
      props = { text = L["Nothing gathered yet"], color = "dim", size = 11 },
      meta = { h = 18 },
    }
  end
  children[#children + 1] = { id = "session.space", type = "spacer", meta = { grow = 1 } }
  children[#children + 1] = {
    id = "session.buttons",
    type = "row",
    props = { gap = 6 },
    meta = { h = 24 },
    children = {
      { id = "session.new", type = "button", props = { label = L["New session"], action = "newSession" } },
      { id = "session.open", type = "button", props = { label = L["Open AME"], action = "openAME" } },
    },
  }
  return { id = "session", type = "column", props = { gap = 4, pad = 9 }, children = children }
end

-- ------------------------------------------------------------------------------------------------ in game

local function saved()
  AME_DB.sessionTracker = AME_DB.sessionTracker or {}
  return AME_DB.sessionTracker
end

local function session()
  AME_DB.sessions = AME_DB.sessions or {}
  local me = ns.Trading and ns.Trading.CharKey and ns.Trading.CharKey() or "me"
  AME_DB.sessions[me] = AME_DB.sessions[me] or {}
  return ns.Session.New(AME_DB.sessions[me])
end

-- what your bags hold, by item key, and how many general slots are free
function T.ReadBags()
  local C = C_Container
  if not (C and C.GetContainerNumSlots and C.GetContainerItemInfo) then
    return {}, nil
  end
  local counts, free = {}, 0
  local reagent = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or (NUM_BAG_SLOTS or 4)
  for bag = 0, math.max(NUM_BAG_SLOTS or 4, reagent) do
    for slot = 1, C.GetContainerNumSlots(bag) or 0 do
      local info = C.GetContainerItemInfo(bag, slot)
      if info and info.itemID then
        counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
      end
    end
    if bag <= (NUM_BAG_SLOTS or 4) and C.GetContainerNumFreeSlots then
      local n, family = C.GetContainerNumFreeSlots(bag)
      if (family or 0) == 0 then
        free = free + (n or 0)
      end
    end
  end
  return counts, free
end

local function worthFn()
  local AME = ns.AME
  local index = AME and AME.FactionIndex and AME:FactionIndex()
  local q = index and ns.Quote.For(AME:FactionShard(), index, { fresh = false })
  return function(key)
    if q then
      return (q:BestSale(key))
    end
    local info = ns.ItemCache and ns.ItemCache.Get(key)
    return info and info.sellPrice
  end
end

local function money()
  return _G.GetMoney and _G.GetMoney() or 0
end

local function now()
  return GetServerTime and GetServerTime() or 0
end

-- what you're doing that moves items without gathering them
local busy, quietUntil = {}, 0
local function isBusy()
  if next(busy) ~= nil then
    return true
  end
  return (GetTime and GetTime() or 0) < quietUntil
end

function T.Observe()
  if not (ns.App and ns.App.Enabled and ns.App.Enabled()) then
    return
  end
  local bags = T.ReadBags()
  local s = session()
  if not s:Active(now()) then
    s:Start(now(), bags, money())
  else
    s:Observe(bags, money(), now(), isBusy())
  end
  T.Render()
end

function T.NewSession()
  local bags = T.ReadBags()
  session():Start(now(), bags, money())
  T.Render()
end

local handlers = {
  close = function()
    T.Hide()
  end,
  newSession = function()
    T.NewSession()
  end,
  openAME = function()
    if ns.App and ns.App.Enabled and ns.App.Enabled() then
      ns.App:Show()
    elseif ns.UI and ns.UI.Toggle then
      ns.UI:Toggle()
    end
  end,
}

function T.Create()
  if T.frame then
    return T.frame
  end
  local f = CreateFrame("Frame", "AMESessionTracker", UIParent, "BackdropTemplate")
  Kit.Box(f, "bg", "frame")
  f:SetSize(T.W, T.H)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local pos = saved()
    pos.x, pos.y = self:GetLeft(), self:GetTop()
  end)
  local pos = saved()
  if pos.x then
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
  else
    f:SetPoint("RIGHT", UIParent, "RIGHT", -240, 80)
  end
  f:Hide()
  T.ctx = Layout.Context(handlers, { sources = {} })
  T.renderer = Layout.Renderer(f, T.ctx)
  T.frame = f
  return f
end

function T.Render()
  local f = T.frame
  if not (f and f:IsShown()) then
    return
  end
  local worth = worthFn()
  local bags, free = T.ReadBags()
  local sum = session():Summary(worth, now())
  T.renderer:Render(T.Tree(sum, { value = ns.Session.Value(bags, worth), free = free }))
end

function T.Show()
  T.Create()
  saved().shown = true
  if not (InCombatLockdown and InCombatLockdown()) then
    T.frame:Show()
  end
  T.Observe()
  T.Render()
end

function T.Hide()
  saved().shown = false
  if T.frame then
    T.frame:Hide()
  end
end

function T.Toggle()
  if T.frame and T.frame:IsShown() then
    T.Hide()
  else
    T.Show()
  end
end

if CreateFrame then
  local BUSY = {
    MERCHANT_SHOW = "merchant",
    BANKFRAME_OPENED = "bank",
    MAIL_SHOW = "mail",
    AUCTION_HOUSE_SHOW = "ah",
    TRADE_SHOW = "trade",
    TRADE_SKILL_SHOW = "craft",
  }
  local DONE = {
    MERCHANT_CLOSED = "merchant",
    BANKFRAME_CLOSED = "bank",
    MAIL_CLOSED = "mail",
    AUCTION_HOUSE_CLOSED = "ah",
    TRADE_CLOSED = "trade",
    TRADE_SKILL_CLOSE = "craft",
  }
  local events = CreateFrame("Frame")
  local all =
    { "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_MONEY", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }
  for e in pairs(BUSY) do
    all[#all + 1] = e
  end
  for e in pairs(DONE) do
    all[#all + 1] = e
  end
  for _, e in ipairs(all) do
    pcall(events.RegisterEvent, events, e)
  end
  events:SetScript("OnEvent", function(_, event)
    if BUSY[event] then
      T.Observe() -- what you gathered up to here counts, then the baseline holds
      busy[BUSY[event]] = true
    elseif DONE[event] then
      busy[DONE[event]] = nil
      quietUntil = (GetTime and GetTime() or 0) + 2 -- purchases and mail still landing
      T.Observe()
    elseif event == "PLAYER_REGEN_DISABLED" then
      if T.frame and T.frame:IsShown() then
        T.frame:Hide()
        T.hiddenForCombat = true
      end
    elseif event == "PLAYER_REGEN_ENABLED" then
      if T.hiddenForCombat and T.frame then
        T.hiddenForCombat = false
        T.frame:Show()
        T.Render()
      end
    elseif event == "PLAYER_ENTERING_WORLD" then
      T.Observe()
      if
        AME_DB
        and AME_DB.sessionTracker
        and AME_DB.sessionTracker.shown
        and ns.App
        and ns.App.Enabled
        and ns.App.Enabled()
      then
        T.Show()
      end
    else
      T.Observe()
    end
  end)
  -- the duration and the hour's rate move on their own
  if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(30, function()
      T.Render()
    end)
  end
end
