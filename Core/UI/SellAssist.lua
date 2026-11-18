-- Posting price help in the auction house's own sell window: a bar under the auction house with one recommendation
-- for the item in the sell slot (Posting:Suggest), why, and what you get. "Fill price" fills it in; you still click
-- Post yourself. Quick / Patient fill the other two prices. Clicking a listing in the sell window (its price lands in
-- the price box) re-targets the bar to just under that listing; a price you type is judged as your own. Works with the
-- default auction house (and the old one); inside other addons' sell tabs the bar shows while the default sell frame
-- is open.
local _, ns = ...
local L = ns.L
local W = ns.Widgets

local Sell = {}
ns.SellAssist = Sell

Sell.REFRESH = 0.5 -- seconds between checks of the sell slot
Sell.RECOMPUTE = 3 -- recompute at least this often (a new search of the item updates its order book)

local function itemIDAt(location)
  local ok, id = pcall(function()
    return C_Item.GetItemID(location)
  end)
  return ok and id or nil
end

local function call(obj, method, ...)
  if obj and obj[method] then
    local ok, v = pcall(obj[method], obj, ...)
    if ok then
      return v
    end
  end
  return nil
end

-- the sell frames of the current auction house:
--   { frame, read() -> itemID, qty, hours; set(price, qty); get() -> the price box (per unit) }
local function sources()
  local out = {}
  local ah = AuctionHouseFrame
  if ah then
    for _, key in ipairs({ "CommoditiesSellFrame", "ItemSellFrame" }) do
      local f = rawget(ah, key) or ah[key]
      if type(f) == "table" then
        out[#out + 1] = {
          frame = f,
          read = function()
            local location = call(f, "GetItem")
            local id = location and itemIDAt(location)
            if not id then
              return nil
            end
            return id, call(f, "GetQuantity") or 1, ns.Posting.DurationHours(call(f, "GetDuration") or 3)
          end,
          set = function(price)
            call(f.PriceInput, "SetAmount", price) -- unit price (commodities) / buyout per item (items)
            call(f, "UpdatePostState")
          end,
          get = function()
            return call(f.PriceInput, "GetAmount")
          end,
        }
      end
    end
  end
  if AuctionFrameAuctions and GetAuctionSellItemInfo then -- the old auction house
    local f = AuctionFrameAuctions
    out[#out + 1] = {
      frame = f,
      read = function()
        local name, _, count, _, _, _, _, _, _, id = GetAuctionSellItemInfo()
        if not (name and id) then
          return nil
        end
        local d = f.duration or 3
        return id, count or 1, d > 3 and math.floor(d / 60) or ns.Posting.DurationHours(d)
      end,
      set = function(price, qty)
        if MoneyInputFrame_SetCopper and BuyoutPrice then
          local total = f.priceType == 1 and price or price * qty -- per unit, or per stack (the classic default)
          MoneyInputFrame_SetCopper(BuyoutPrice, total)
          if StartPrice then
            MoneyInputFrame_SetCopper(StartPrice, total)
          end
        end
      end,
      get = function()
        if not (MoneyInputFrame_GetCopper and BuyoutPrice) then
          return nil
        end
        local total = MoneyInputFrame_GetCopper(BuyoutPrice)
        local _, _, count = GetAuctionSellItemInfo()
        if f.priceType == 1 or not (total and count and count > 0) then
          return total
        end
        return math.floor(total / count + 0.5)
      end,
    }
  end
  return out
end

-- recompute on the next check (new listings for the item in the sell slot)
function Sell:Invalidate()
  self.key = nil
end

function Sell:Active()
  for _, src in ipairs(sources()) do
    if src.frame and src.frame.IsVisible and src.frame:IsVisible() then
      return src
    end
  end
  return nil
end

-- A price to post at, judged by the model: units ahead, chance to sell in the listing time, hours to sell.
function Sell.Evaluate(advice, price, now)
  local params = advice.params
  local need = ns.Pricing.Ahead(advice.book, price) + (advice.qty or 1)
  return {
    price = price,
    ahead = need - (advice.qty or 1),
    chance = params and ns.Pricing.Chance(params, need, advice.hours or 24, now) or nil,
    hours = params and ns.Pricing.Hours(params, need, now) or nil,
  }
end

-- why this price: the listings just above it
function Sell.Reason(advice, price)
  local book = advice.book
  for k, p in ipairs(book.prices) do
    if p > price then
      return L["below %d listed at %s"]:format(book.qtys[k], W.Money(p))
    end
  end
  return #book.prices > 0 and L["above every listing"] or L["no listings right now"]
end

-- your money per unit after the cut and the deposit
function Sell.Net(advice, price)
  local _, house = ns.SplitShard(ns.AME:CurrentShard())
  local cut = ns.Settings:AuctionCut(house or ns.AME:CurrentHouse()) or 0
  return price * (1 - cut) - (advice.deposit or 0) / (advice.qty or 1)
end

function Sell:Build(parent)
  local bar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  W.Skin(bar, W.COLORS.bg or W.COLORS.panel, W.COLORS.border)
  bar:SetHeight(46)
  bar:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, -2)
  bar:SetPoint("TOPRIGHT", parent, "BOTTOMRIGHT", 0, -2)
  bar:EnableMouse(true)
  ns.Help.Explain(bar, "posting")
  local function fill(price, target)
    local src, a = Sell.src, Sell.advice
    if src and a and price then
      Sell.filled, Sell.target = price, target
      src.set(price, a.qty)
      Sell:Draw()
    end
  end
  bar.fill = W.Button(bar, L["Fill price"], 110, 24, function()
    fill(Sell.shown, Sell.target)
  end)
  bar.fill:SetPoint("RIGHT", -8, 0)
  bar.fill:SetSelected(true)
  bar.patient = W.Button(bar, "", 130, 20, function()
    fill(Sell.advice and Sell.advice.patient.price)
  end)
  bar.patient:SetPoint("RIGHT", bar.fill, "LEFT", -8, 0)
  bar.quick = W.Button(bar, "", 130, 20, function()
    fill(Sell.advice and Sell.advice.quick.price)
  end)
  bar.quick:SetPoint("RIGHT", bar.patient, "LEFT", -6, 0)
  bar.reset = W.Button(bar, "", 130, 20, function()
    fill(Sell.advice and Sell.advice.normal.price)
  end)
  bar.reset:SetPoint("RIGHT", bar.quick, "LEFT", -6, 0)
  bar.title = W.Text(bar, "GameFontNormal")
  bar.title:SetPoint("TOPLEFT", 10, -8)
  bar.title:SetPoint("RIGHT", bar.reset, "LEFT", -10, 0)
  bar.title:SetWordWrap(false)
  bar.info = W.Text(bar, "GameFontDisableSmall")
  bar.info:SetPoint("TOPLEFT", bar.title, "BOTTOMLEFT", 0, -5)
  bar.info:SetPoint("RIGHT", bar.reset, "LEFT", -10, 0)
  bar.info:SetWordWrap(false)
  bar:Hide()
  return bar
end

-- redraw from Sell.advice and Sell.target
function Sell:Draw()
  local bar, advice = self.bar, self.advice
  local pips = W.Confidence(advice and advice.confidence or "low")
  if not advice then
    bar.title:SetText(pips .. " " .. W.Dim(L["Posting price: not enough data on this item yet."]))
    bar.info:SetText(L["Search for it at the auction house, or run a full scan."])
    self.shown = nil
    for _, b in ipairs({ bar.fill, bar.quick, bar.patient, bar.reset }) do
      b:Hide()
    end
    return
  end
  local now = GetServerTime()
  local target = self.target
  local choice, title
  if target then
    -- a listing's price: just under it; anything else: your own price
    local listed = false
    for _, p in ipairs(advice.book.prices) do
      listed = listed or p == target
    end
    choice = Sell.Evaluate(advice, listed and math.max(1, target - 1) or target, now)
    title = (listed and L["Under that listing: post at %s per unit"] or L["Your price: %s per unit"]):format(
      W.Money(choice.price)
    )
  else
    choice = advice.normal
    title = L["Post at %s per unit"]:format(W.Money(choice.price))
  end
  self.shown = choice.price
  local net = Sell.Net(advice, choice.price)
  local info = ns.ItemCache.Get(self.itemID or 0)
  local vendor = info and info.sellPrice
  local parts = { Sell.Reason(advice, choice.price) }
  if choice.chance then
    parts[#parts + 1] = L["%d%% chance to sell in %dh"]:format(math.floor(choice.chance * 100 + 0.5), advice.hours)
  end
  parts[#parts + 1] = L["sells in %s"]:format(W.Hours(choice.hours))
  parts[#parts + 1] = L["you get %s after the cut"]:format(W.Money(net))
  if vendor and vendor > 0 then
    parts[#parts + 1] = L["vendor %s"]:format(W.Money(vendor))
  end
  if vendor and vendor > 0 and net < vendor then
    -- the auction house nets less than a vendor
    bar.title:SetText(pips .. " " .. W.Color("bad", L["Vendor it: a vendor pays more"]))
    bar.fill.label:SetText(L["Post anyway"])
  else
    bar.title:SetText(pips .. " " .. W.Color("gold", title))
    bar.fill.label:SetText(L["Fill price"])
    if not target and advice.hold then
      parts[#parts + 1] = W.Color("bad", L["unlikely to sell soon: consider holding"])
    end
  end
  bar.info:SetText(table.concat(parts, "  ·  "))
  bar.fill:Show()
  local same = advice.quick.price == advice.patient.price
  bar.quick:SetShown(not same)
  bar.patient:SetShown(not same)
  bar.quick.label:SetText(L["Quick %s"]:format(W.Money(advice.quick.price)))
  bar.patient.label:SetText(L["Patient %s"]:format(W.Money(advice.patient.price)))
  bar.reset:SetShown(target ~= nil)
  bar.reset.label:SetText(L["Suggested %s"]:format(W.Money(advice.normal.price)))
end

function Sell:Refresh()
  local bar = self.bar
  local src = self:Active()
  local id, qty, hours
  if src then
    id, qty, hours = src.read()
  end
  if not id then
    bar:Hide()
    self.key, self.advice, self.item = nil, nil, nil
    return
  end
  -- another item in the slot: forget the old target; the price the game fills in first is its own, not a choice
  local price = src.get and src.get() or nil
  if id ~= self.item then
    self.item, self.target, self.filled, self.seen = id, nil, nil, price
  elseif price and price > 0 and price ~= self.seen then
    self.seen = price
    if price ~= self.filled then
      self.target = price -- you clicked a listing or typed a price
      self.key = nil
    end
  end
  local key = ("%d:%d:%d"):format(id, qty, hours)
  local t = GetTime()
  if key == self.key and t - (self.at or 0) < Sell.RECOMPUTE then
    return
  end
  self.key, self.at, self.src, self.itemID = key, t, src, id
  local ok, advice = pcall(ns.Posting.Suggest, ns.Posting, ns.AME:CurrentShard(), id, qty, hours)
  if not ok then
    ns.AME:ReportError("posting price", advice)
  end
  self.advice = ok and advice or nil
  self:Draw()
  bar:Show()
end

-- attach to whichever auction house window the game shows (once)
function Sell:Attach()
  local parent = AuctionHouseFrame or AuctionFrame
  if self.bar or not parent then
    return
  end
  self.bar = self:Build(parent)
  local ticker = CreateFrame("Frame", nil, parent) -- runs only while the auction house is open
  local elapsed = 0
  ticker:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed >= Sell.REFRESH then
      elapsed = 0
      Sell:Refresh()
    end
  end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:SetScript("OnEvent", function()
  Sell:Attach()
end)
