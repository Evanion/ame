-- Baganator (bag addon) plugins, from its API (Baganator.API, when it's installed):
--   two icon corner widgets - "AME: signal" (the item's market signal, as its icon) and "AME: value" (what the stack
--   is worth: Quote:BestSale x count, as the Selling tab values it). Players pick corners in Baganator's settings
--   (Icons); AME places none by itself.
--   "AME: tip" - what to do with it, the Selling tab's Tip (Sell, Arb, DE, Vend): it only marks the slot, nothing
--   moves to another category.
--   No junk rule: what's junk is Baganator's own (or another addon's) to say.
--   a sort - "AME: worth": the most valuable stacks first (Baganator's reverse: last), regular bags only, moved a
--   swap at a time as the game unlocks them; never in combat.
-- Built on AME's public API (Core/API.lua), so it shows the same numbers as AME's tooltip and tabs.
local _, ns = ...
local L = ns.L
local W = ns.Widgets

local Bag = {}
ns.Baganator = Bag

-- what fits on a bag slot: one unit, rounded - "1.2kg", "12g", "2.5g", "45s", "8c"
function Bag.SlotMoney(copper)
  if not copper or copper <= 0 then
    return nil
  end
  local g = copper / 10000
  local text, unit
  if g >= 1000 then
    local k = g / 1000
    text, unit = k < 10 and ("%.1fk"):format(math.floor(k * 10) / 10) or ("%dk"):format(math.floor(k)), "g"
  elseif g >= 10 then
    text, unit = tostring(math.floor(g + 0.5)), "g"
  elseif g >= 1 then
    local t = math.floor(g * 10 + 0.5) / 10
    text, unit = (t == math.floor(t)) and tostring(t) or ("%.1f"):format(t), "g"
  elseif copper >= 100 then
    text, unit = tostring(math.floor(copper / 100 + 0.5)), "s"
  else
    text, unit = tostring(math.floor(copper + 0.5)), "c"
  end
  text = text:gsub("%.0([kg]?)$", "%1")
  return "|cff" .. W.COIN_HEX[unit] .. text .. unit .. "|r"
end

-- the Selling tab's Tip for an item (AHSelling S.Tip): "craft" (a VENDOR item a recipe of yours makes worth more:
-- Arbitrate), "vendor" or "disenchant" (its signal), "sell" (listing it beats a vendor), or nil (no price)
function Bag.Tip(api, item, instead)
  local signal = api.GetSignal(item)
  if signal == "vendor" then
    local key = ns.API and ns.API.KeyOf(item) or item
    if instead and key and instead(key) then
      return "craft"
    end
    return "vendor"
  elseif signal == "disenchant" then
    return "disenchant"
  end
  local _, where = api.GetWorth(item)
  return where == "ah" and "sell" or nil
end

-- a tip as the corner draws it: a short word in its colour (a text role)
Bag.TIP_TEXT = {
  sell = { L["Sell"], "white" },
  craft = { L["Arb"], "warn" },
  disenchant = { L["DE"], "disenchant" },
  vendor = { L["Vend"], "vendor" },
}

-- Pure: the swaps that put the most valuable stacks first. cells: the bags' slots in order, each { key, worth } or
-- false (empty); reverse: from the last slot instead. Stacks of one item are interchangeable (swapping two would
-- merge them), so only different items swap places. -> { { i, j }, ... } in order, each a swap of two slots
function Bag.SortPlan(cells, reverse)
  local n = #cells
  local order = {}
  for i = 1, n do
    order[i] = i
  end
  if reverse then
    for i = 1, math.floor(n / 2) do
      order[i], order[n + 1 - i] = order[n + 1 - i], order[i]
    end
  end
  -- what goes where: the items by worth, most first (ties: by item, so stacks of one item sit together); empties last
  local items = {}
  for _, c in ipairs(cells) do
    if c then
      items[#items + 1] = c
    end
  end
  table.sort(items, function(a, b)
    if (a.worth or 0) ~= (b.worth or 0) then
      return (a.worth or 0) > (b.worth or 0)
    end
    return tostring(a.key) < tostring(b.key)
  end)
  local current = {}
  for i = 1, n do
    current[i] = cells[i] and cells[i].key or false
  end
  local swaps = {}
  for t = 1, n do
    local pos = order[t]
    local want = items[t] and items[t].key or false
    if current[pos] ~= want then
      -- the nearest later slot holding what goes here
      for u = t + 1, n do
        local from = order[u]
        if current[from] == want then
          swaps[#swaps + 1] = { from, pos }
          current[pos], current[from] = current[from], current[pos]
          break
        end
      end
    end
  end
  return swaps
end

-- the value corner's text: the stack's worth or one item's (Settings: baganatorValue); blank without a price
function Bag.ValueText(each, count)
  if not each then
    return nil
  end
  local amount = ns.Settings:Get("baganatorValue") == "each" and each or each * (count or 1)
  return Bag.SlotMoney(amount)
end

-- What a slot's corners need of an item - its worth, where that's from, its signal, its tip - per item link, worked
-- out ahead: Bag:Prime, a background job over your bags (and the bank while it's open) when new market data arrives
-- or your bags change. The corners only read it (Baganator calls them for every slot on every redraw), so they're
-- registered as fast. A new index doesn't clear it: the old values show until the job has redone them. An item the
-- job hasn't seen (a guild bank tab, another character's bags) is worked out when it's first drawn.
Bag.values = {}

-- one item's entry: { each, where, signal, tip } (false: none)
-- the game hasn't sent the item's details yet (its vendor price, whether it binds): any answer now would be wrong
function Bag.Loading(link)
  local key = ns.API and ns.API.KeyOf(link)
  local info = key and ns.ItemCache and ns.ItemCache.Get(key)
  return info ~= nil and info.name == nil
end

-- (an item still loading gets { loading = true }: never kept, asked again on the next draw)
-- step (optional): the background job's pause (job:Checkpoint), called between the pieces of one item's work
function Bag.Compute(api, link, step)
  if Bag.Loading(link) then
    return { loading = true }
  end
  local each, where = api.GetWorth(link)
  local e = { each = each, where = where, signal = api.GetSignal(link) or false }
  if step then
    step()
  end
  e.tip = Bag.Tip(
    {
      GetSignal = function()
        return e.signal or nil
      end,
      GetWorth = function()
        return e.each, e.where
      end,
    },
    link,
    function(key)
      return Bag.Instead(key, step)
    end
  ) or false
  return e
end

function Bag.Lookup(api, link)
  local e = Bag.values[link]
  if not e then
    e = Bag.Compute(api, link)
    if not e.loading then
      Bag.values[link] = e
    end
  end
  return e
end

-- Bag.Cached(api): the API's GetWorth / GetSignal, answered from the entries
function Bag.Cached(api)
  return {
    GetWorth = function(link)
      local e = Bag.Lookup(api, link)
      return e.each, e.where
    end,
    GetSignal = function(link)
      return Bag.Lookup(api, link).signal or nil
    end,
    Tip = function(link)
      return Bag.Lookup(api, link).tip or nil
    end,
    -- still loading: the corners answer nil, and Baganator asks again in a moment
    Loading = function(link)
      return Bag.Lookup(api, link).loading == true
    end,
  }
end

-- the item links in your bags, and the bank's while it's open
function Bag.HeldLinks()
  local C = _G.C_Container or {}
  local bags = {}
  for bag = 0, (_G.NUM_BAG_SLOTS or 4) do
    bags[#bags + 1] = bag
  end
  if ns.Trading and ns.Trading.bankOpen then
    bags[#bags + 1] = -1
    for bag = (_G.NUM_BAG_SLOTS or 4) + 1, (_G.NUM_BAG_SLOTS or 4) + (_G.NUM_BANKBAGSLOTS or 7) do
      bags[#bags + 1] = bag
    end
  end
  local seen, out = {}, {}
  for _, bag in ipairs(bags) do
    for slot = 1, (C.GetContainerNumSlots and C.GetContainerNumSlots(bag) or 0) do
      local info = C.GetContainerItemInfo and C.GetContainerItemInfo(bag, slot)
      local link = info and info.hyperlink
      if link and not seen[link] then
        seen[link] = true
        out[#out + 1] = link
      end
    end
  end
  return out
end

-- Work the entries out in the background: all of them for new market data (fresh), else only items not seen yet
-- (bags changed). Baganator redraws once they're in.
function Bag:Prime(fresh)
  local AME, public = ns.AME, ns.API and ns.API.v1
  if not (AME and AME.jobs and public) then
    return
  end
  if self.priming then
    self.primeAgain = self.primeAgain or fresh or "missing"
    return
  end
  self.priming = true
  AME.jobs:Add("bags-corners", function(job)
    local out = {}
    local function step()
      job:Checkpoint()
    end
    for _, link in ipairs(Bag.HeldLinks()) do
      if fresh or not Bag.values[link] then
        local e = Bag.Compute(public, link, step)
        if not e.loading then
          out[link] = e
        end
        step()
      end
    end
    return out
  end, function(ok, out)
    self.priming = false
    if ok and out then
      if fresh then
        Bag.values = {} -- everything else is worked out again when it's drawn
      end
      for link, e in pairs(out) do
        Bag.values[link] = e
      end
      local B = _G.Baganator
      if (fresh or next(out)) and B and B.API and B.API.RequestItemButtonsRefresh then
        B.API.RequestItemButtonsRefresh()
      end
    elseif not ok and AME.ReportError then
      AME:ReportError("bag corners", out)
    end
    local again = self.primeAgain
    self.primeAgain = nil
    if again then
      self:Prime(again == true)
    end
  end)
end

-- CraftModel.Instead, kept while the market data and your recipes stay the same (Baganator asks for every slot on
-- every redraw). step: as Compute's
local insteadCache, insteadStamp = {}, nil
function Bag.Instead(key, step)
  local CM = ns.CraftModel
  if not (CM and CM.Instead) then
    return nil
  end
  local index = ns.AME and ns.AME.FactionIndex and ns.AME:FactionIndex()
  local stamp = tostring(index) .. ":" .. tostring(ns.Recipes and ns.Recipes.Stamp and ns.Recipes.Stamp())
  if stamp ~= insteadStamp then
    insteadCache, insteadStamp = {}, stamp
  end
  local hit = insteadCache[key]
  if hit == nil then
    hit = CM.Instead(key, step) or false
    insteadCache[key] = hit
  end
  return hit or nil
end

-- the setting (General, Other addons): off, the corners show nothing and the sort does nothing (Baganator keeps
-- listing them until a /reload: it can't take them back)
function Bag.On()
  return ns.Settings:Get("baganator") ~= false
end

-- Baganator is loaded (the setting's card says so)
function Bag.Present()
  local B = _G.Baganator
  return B ~= nil and B.API ~= nil and B.API.RegisterCornerWidget ~= nil
end

-- the setting changed: plug in now (on), and Baganator redraws its slots either way
function Bag:SettingChanged(on)
  if on then
    self:Install()
  end
  local B = _G.Baganator
  if B and B.API and B.API.RequestItemButtonsRefresh then
    B.API.RequestItemButtonsRefresh()
  end
end

-- where each corner goes the first time (Baganator's defaultPosition; a priority past its list's end appends): the
-- signal top left, the value top right, clear of the game's stack count; the tip isn't placed (players add it)
Bag.CORNERS = {
  ame_signal = { corner = "top_left", priority = 99 },
  ame_value = { corner = "top_right", priority = 99 },
}

function Bag:Install()
  local B = _G.Baganator
  local public = ns.API and ns.API.v1
  if self.installed or not Bag.On() or not (Bag.Present() and public) then
    return
  end
  self.installed = true
  local api = Bag.Cached(public) -- the corners' lookups, kept per item until new prices arrive

  B.API.RegisterCornerWidget(L["AME: tip"], "ame_tip", function(text, details)
    if not Bag.On() then
      return false
    end
    if not details.itemLink then
      return nil
    end
    if api.Loading(details.itemLink) then
      return nil -- Baganator asks again in a moment
    end
    local kind = api.Tip(details.itemLink)
    if kind == "sell" and not ns.Settings:Get("baganatorSellTip") then
      kind = nil -- most of a bag: only marked when asked for (Settings, General, Other addons)
    end
    local tip = Bag.TIP_TEXT[kind or ""]
    if not tip then
      return false
    end
    text:SetText(W.Color(tip[2], tip[1]))
    return true
  end, function(button)
    local text = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    text.sizeFont = true
    return text
  end, Bag.CORNERS.ame_tip, true)

  B.API.RegisterCornerWidget(L["AME: signal"], "ame_signal", function(icon, details)
    if not Bag.On() then
      return false
    end
    if not details.itemLink then
      return nil
    end
    if api.Loading(details.itemLink) then
      return nil -- Baganator asks again in a moment
    end
    local signal = api.GetSignal(details.itemLink)
    if (signal == "hold" or signal == "wait") and not ns.Settings:Get("baganatorAllSignals") then
      signal = nil -- nothing to do yet: on most of a bag, so only shown when asked for (Settings, Other addons)
    end
    local file = signal and W.SIGNAL_ICON[signal]
    if not file then
      return false
    end
    icon.glyph:SetTexture(W.SIGNAL_MEDIA .. file)
    icon.outline:SetTexture(W.SIGNAL_MEDIA .. file)
    local c = W.RGB(W.SignalRole(signal))
    icon.glyph:SetVertexColor(c[1], c[2], c[3])
    return true
  end, function(button)
    -- the icon on a black copy of itself a little larger: an outline, so a red or green triangle reads on any
    -- item's art (Baganator places this frame in the corner)
    local icon = CreateFrame("Frame", nil, button)
    icon:SetSize(12, 12)
    icon.padding = 0
    icon.outline = icon:CreateTexture(nil, "OVERLAY", nil, 6)
    icon.outline:SetSize(15, 15)
    icon.outline:SetPoint("CENTER", 0, 0)
    icon.outline:SetVertexColor(0, 0, 0, 0.9)
    icon.glyph = icon:CreateTexture(nil, "OVERLAY", nil, 7)
    icon.glyph:SetAllPoints()
    return icon
  end, Bag.CORNERS.ame_signal, true)

  B.API.RegisterCornerWidget(L["AME: value"], "ame_value", function(text, details)
    if not Bag.On() then
      return false
    end
    if not details.itemLink then
      return nil
    end
    if api.Loading(details.itemLink) then
      return nil -- Baganator asks again in a moment
    end
    local shown = Bag.ValueText(api.GetWorth(details.itemLink), details.itemCount)
    if not shown then
      return false
    end
    text:SetText(shown)
    return true
  end, function(button)
    local text = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    text.sizeFont = true
    return text
  end, Bag.CORNERS.ame_value, true)

  if B.API.RegisterContainerSort then
    B.API.RegisterContainerSort(L["AME: worth"], "ame_worth", function(isReverse, containerType)
      Bag:Sort(isReverse, containerType)
    end)
  end

  -- new prices: Baganator redraws its slots
  -- new prices: the entries are worked out again in the background, then Baganator redraws (Bag:Prime); bags that
  -- changed or the bank opened: only the items not seen yet
  public.RegisterForUpdates("Baganator", function()
    self:Prime(true)
  end)
  local events = CreateFrame("Frame")
  events:RegisterEvent("BAG_UPDATE_DELAYED")
  pcall(events.RegisterEvent, events, "BANKFRAME_OPENED")
  events:SetScript("OnEvent", function()
    if Bag.On() then
      self:Prime(false)
    end
  end)
  self:Prime(true)
end

---------------------------------------------------------------------------------------------------------------------
-- the worth sort, in game

Bag.SORT_TIMEOUT = 20 -- seconds: give up when the game keeps the slots locked this long

local function container()
  return _G.C_Container or {}
end

-- your bags' regular slots in order (special bags - herbs, soul shards, ammo - left alone): { bag, slot } each
function Bag.SortSlots()
  local C = container()
  local out = {}
  for bag = 0, (_G.NUM_BAG_SLOTS or 4) do
    local family = 0
    if C.GetContainerNumFreeSlots then
      family = select(2, C.GetContainerNumFreeSlots(bag)) or 0
    end
    if family == 0 then
      for slot = 1, (C.GetContainerNumSlots and C.GetContainerNumSlots(bag) or 0) do
        out[#out + 1] = { bag = bag, slot = slot }
      end
    end
  end
  return out
end

-- an item link's item part ("item:2589:..."): what tells two stacks apart (suffix and all)
local function stackKey(link)
  return link:match("item:[%-%d:]+") or link
end

function Bag:Sort(isReverse, containerType)
  local say = ns.AME and ns.AME.Say or print
  if not Bag.On() then
    return
  end
  if containerType and containerType ~= "backpack" then
    return say(L["The worth sort sorts your bags, not the bank."])
  end
  if InCombatLockdown and InCombatLockdown() then
    return say(L["Not in combat: sort your bags by worth after the fight."])
  end
  local api = ns.API and ns.API.v1
  if not api or self.sorting then
    return
  end
  local C = container()
  local slots = Bag.SortSlots()
  local cells = {}
  for i, s in ipairs(slots) do
    local info = C.GetContainerItemInfo and C.GetContainerItemInfo(s.bag, s.slot)
    if info and info.hyperlink then
      local each = api.GetWorth(info.hyperlink) or 0
      cells[i] = { key = stackKey(info.hyperlink), worth = each * (info.stackCount or 1) }
    else
      cells[i] = false
    end
  end
  local swaps = Bag.SortPlan(cells, isReverse)
  if #swaps == 0 then
    return
  end
  -- one swap at a time: both slots unlocked, the cursor empty, out of combat
  local sorting = { swaps = swaps, i = 1, started = GetTime() }
  self.sorting = sorting
  local function locked(s)
    local info = C.GetContainerItemInfo and C.GetContainerItemInfo(s.bag, s.slot)
    return info and info.isLocked
  end
  local frame = self.sortFrame or CreateFrame("Frame")
  self.sortFrame = frame
  frame:SetScript("OnUpdate", function()
    local done = sorting.i > #sorting.swaps
    local stuck = GetTime() - sorting.started > Bag.SORT_TIMEOUT
    local busy = (InCombatLockdown and InCombatLockdown()) or (_G.GetCursorInfo and _G.GetCursorInfo())
    if done or stuck or busy then
      frame:SetScript("OnUpdate", nil)
      self.sorting = nil
      if (stuck or busy) and not done then
        say(L["Sorting by worth stopped part way: sort again to finish."])
      end
      return
    end
    local sw = sorting.swaps[sorting.i]
    local a, b = slots[sw[1]], slots[sw[2]]
    if locked(a) or locked(b) then
      return
    end
    C.PickupContainerItem(a.bag, a.slot)
    C.PickupContainerItem(b.bag, b.slot)
    sorting.i = sorting.i + 1
  end)
end
