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
  return ns.ItemCache.KeyAt(location)
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
-- Auctionator's selling tab (its "Selling" tab frame, AuctionatorSellingFrame.SaleItemFrame): the item it's about
-- to post, how many per auction, the listing length, and its unit price box (old-style AH: UnitPrice; new: Price)
Sell.AUCTIONATOR_DURATION = { [12] = 1, [24] = 2, [48] = 3 } -- its duration values -> the game's duration index
local function auctionatorSource()
  local tab = _G.AuctionatorSellingFrame
  local sale = type(tab) == "table" and rawget(tab, "SaleItemFrame")
  if not sale then
    return nil
  end
  local function priceBox()
    return rawget(sale, "UnitPrice") or rawget(sale, "Price")
  end
  return {
    frame = sale,
    auctionator = true,
    read = function()
      local info = rawget(sale, "itemInfo")
      -- the auction house's item key for it names a random suffix (see ns.ItemKey)
      local id = info and info.location and ns.ItemCache.KeyAt(info.location)
      if not id and info and info.itemKey and info.itemKey.itemID then
        id = info.itemLink and ns.ItemCache.Pair(info.itemLink, info.itemKey.itemID, info.itemKey.itemSuffix)
          or ns.ItemKey(info.itemKey.itemID, info.itemKey.itemSuffix)
      end
      id = id or (info and info.itemLink and ns.ItemCache.Learn(info.itemLink))
      if not id then
        return nil
      end
      local qty = 1
      if sale.GetStackSize then
        qty = call(sale, "GetStackSize") or 1
      elseif sale.Quantity then
        qty = call(sale.Quantity, "GetNumber") or 1
      end
      local value = sale.Duration and call(sale.Duration, "GetValue")
      local hours = ns.Posting.DurationHours(Sell.AUCTIONATOR_DURATION[value] or 3)
      return id, math.max(1, qty), hours
    end,
    set = function(price)
      call(priceBox(), "SetAmount", price)
    end,
    get = function()
      return call(priceBox(), "GetAmount")
    end,
  }
end

local function sources()
  local out = {}
  local auctionator = auctionatorSource()
  if auctionator then
    out[#out + 1] = auctionator
  end
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
        id = ns.ItemCache.KeyFor(id, name) -- the slot gives the variant's full name, not its link
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

-- the item in a shown sell slot (an item key: Auctionator's slot and the item sell frame have its link), or nil
function Sell:CurrentItem()
  local src = self:Active()
  if src then
    return (src.read())
  end
  return nil
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
      return L["Just under %d listed at %s"]:format(book.qtys[k], W.Money(p))
    end
  end
  return #book.prices > 0 and L["Above every listing"] or L["No listings right now"]
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
  bar:SetHeight(50)
  bar.parent = parent
  Sell.Place(bar)
  bar:EnableMouse(true)
  -- hover: what the posting price is, and the chance it sells in the listing time
  W.Tooltip(bar, function(tip)
    local term = ns.Help.TERMS.posting
    W.TipText(tip, term[1], term[2])
    if Sell.chance then
      tip:AddLine(" ")
      tip:AddLine(L["%d%% chance to sell in %dh"]:format(Sell.chance, Sell.advice and Sell.advice.hours or 24), 1, 1, 1)
    end
  end, "ANCHOR_TOP")
  local function fill(price, target, key)
    local src, a = Sell.src, Sell.advice
    if src and a and price then
      Sell.filled, Sell.target, Sell.seen, Sell.picked = price, target, price, key
      src.set(price, a.qty)
      Sell:Draw()
    end
  end
  -- the bar's own button: "Use X" (just under a listing you clicked) or "Post anyway at X" (a vendor pays more)
  bar.fill = W.Button(bar, L["Fill price"], 110, 24, function()
    if Sell.vendorCase then
      fill(Sell.shown, Sell.target, nil)
    else
      fill(Sell.advice and Sell.advice.market and Sell.advice.market.price, nil, "market")
    end
  end)
  bar.fill:SetPoint("RIGHT", -8, 0)
  W.Primary(bar.fill)
  bar.patient = W.Button(bar, "", 130, 20, function()
    fill(Sell.advice and Sell.advice.patient.price, nil, "patient")
  end)
  bar.patient:SetPoint("RIGHT", bar.fill, "LEFT", -8, 0)
  bar.quick = W.Button(bar, "", 130, 20, function()
    fill(Sell.advice and Sell.advice.quick.price, nil, "quick")
  end)
  bar.quick:SetPoint("RIGHT", bar.patient, "LEFT", -6, 0)
  bar.reset = W.Button(bar, "", 130, 20, function()
    fill(Sell.advice and Sell.advice.normal.price, nil, "normal")
  end)
  bar.reset:SetPoint("RIGHT", bar.quick, "LEFT", -6, 0)
  bar.tag = W.Text(bar, "GameFontNormal")
  bar.tag:SetPoint("TOPLEFT", 12, -9)
  bar.tag:SetText("AME")
  bar.title = W.Text(bar, "GameFontHighlight")
  bar.title:SetPoint("LEFT", bar.tag, "RIGHT", 12, 0)
  bar.title:SetWordWrap(false)
  -- confidence: just the bars after the title (what they mean is on hover)
  bar.confHover = CreateFrame("Frame", nil, bar)
  bar.conf = W.Text(bar.confHover, "GameFontHighlightSmall")
  bar.conf:SetPoint("LEFT", bar.confHover, "LEFT", 0, 0)
  bar.confHover:SetSize(30, 16)
  bar.confHover:SetPoint("LEFT", bar.title, "RIGHT", 8, 0)
  bar.confHover:EnableMouse(true)
  ns.Help.Explain(bar.confHover, "confidence")
  -- the reason line: the whole width under the title and the buttons
  bar.info = W.Text(bar, "GameFontDisableSmall")
  bar.info:SetPoint("BOTTOMLEFT", 12, 8)
  bar.info:SetPoint("RIGHT", -10, 0)
  bar.info:SetWordWrap(false)
  bar:Hide()
  return bar
end

-- The auction house's tabs (Buy / Sell / Auctions, and those other addons add) hang below its frame: the bar goes
-- under the lowest of them. Placed again whenever it shows (addons add tabs late).
function Sell.Tabs(parent)
  local tabs = {}
  for i = 1, 20 do
    local t = _G["AuctionFrameTab" .. i]
    if t then
      tabs[#tabs + 1] = t
    end
  end
  if type(parent.Tabs) == "table" then -- the retail-style auction house
    for _, t in ipairs(parent.Tabs) do
      tabs[#tabs + 1] = t
    end
  end
  return tabs
end

function Sell.Place(bar)
  local parent = bar.parent
  local gap = 0
  local bottom = parent.GetBottom and parent:GetBottom()
  if bottom then
    for _, t in ipairs(Sell.Tabs(parent)) do
      local b = t.IsShown and t:IsShown() and t.GetBottom and t:GetBottom()
      if type(b) == "number" and bottom - b > gap then
        gap = bottom - b
      end
    end
  end
  bar.tabGap = gap
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, -(gap + 4))
  bar:SetPoint("TOPRIGHT", parent, "BOTTOMRIGHT", 0, -(gap + 4))
end

-- redraw from Sell.advice and Sell.target
function Sell:Draw()
  local bar, advice = self.bar, self.advice
  local pips = W.Confidence(advice and advice.confidence or "low")
  self.chance = nil
  if not advice then
    bar.title:SetText(W.Dim(L["Posting price: not enough data on this item yet."]))
    bar.info:SetText(L["Search for it at the auction house, or run a full scan."])
    bar.conf:SetText("")
    self.shown = nil
    for _, b in ipairs({ bar.fill, bar.quick, bar.patient, bar.reset }) do
      b:Hide()
    end
    Sell.LayoutButtons(bar)
    return
  end
  bar.conf:SetText(pips)
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
    self.underListing = listed
    title = (listed and L["Under that listing: post at %s"] or L["Your price: %s"]):format(W.Money(choice.price))
  else
    choice = advice.normal
    self.underListing = false
    title = L["Post at %s"]:format(W.Money(choice.price))
  end
  title = title .. " " .. W.Dim(L["per unit"])
  self.shown = choice.price
  local net = Sell.Net(advice, choice.price)
  local info = ns.ItemCache.Get(self.itemID or 0)
  local vendor = info and info.sellPrice
  self.chance = choice.chance and math.floor(choice.chance * 100 + 0.5)
  local _, house = ns.SplitShard(ns.AME:CurrentShard())
  local cutPct = W.CutPct(ns.Settings:AuctionCut(house or ns.AME:CurrentHouse()))
  bar.fill:Show()
  if vendor and vendor > 0 and net < vendor then
    -- the auction house nets less than a vendor: say so; posting anyway is the only (secondary) button
    bar.title:SetText(W.Color("vendor", L["Vendor it: a vendor pays more"]))
    bar.info:SetText(
      L["The AH nets %s a unit after the cut and the %s deposit  ·  a vendor pays %s"]:format(
        W.Money(net),
        W.Money(advice.deposit or 0),
        W.Money(vendor)
      )
    )
    self.vendorCase = true
    bar.fill.label:SetText(L["Post anyway at %s"]:format(W.Money(choice.price)))
    W.Primary(bar.fill, false) -- posting is the wrong move here: not the main action
    bar.fill:SetSelected(false)
    bar.quick:Hide()
    bar.patient:Hide()
    bar.reset:Hide()
  else
    local parts = { Sell.Reason(advice, choice.price) }
    parts[#parts + 1] = L["sells in %s"]:format(W.Hours(choice.hours))
    parts[#parts + 1] = L["you net %s after the %d%% cut"]:format(W.Money(net), cutPct)
    if vendor and vendor > 0 then
      parts[#parts + 1] = L["vendor pays %s"]:format(W.Money(vendor))
    end
    if not target and advice.hold then
      parts[#parts + 1] = W.Color("bad", L["unlikely to sell soon: consider holding"])
    end
    bar.title:SetText(title)
    bar.info:SetText(table.concat(parts, "  ·  "))
    -- Quick / Normal / Patient fill their own prices; the extra button only when you clicked a listing: just under it
    self.vendorCase = false
    -- the three prices stay put (nothing appears or disappears as you click); ONE is highlighted: the one you
    -- clicked if the box still holds its price, else the first that matches the box (Normal before Quick, Patient -
    -- two choices can have the same price)
    local box = self.src and self.src.get and self.src.get()
    local lit
    if box and self.picked and advice[self.picked] and advice[self.picked].price == box then
      lit = self.picked
    else
      for _, key in ipairs({ "normal", "quick", "patient", "market" }) do
        if not lit and box and advice[key] and advice[key].price == box then
          lit = key
        end
      end
    end
    for _, it in ipairs({
      { bar.quick, "quick", L["Quick %s"] },
      { bar.reset, "normal", L["Normal %s"] },
      {
        bar.patient,
        "patient",
        L["Patient %s"],
      },
    }) do
      local b, key = it[1], it[2]
      b:Show()
      b.label:SetText(it[3]:format(W.Money(advice[key].price)))
      b:SetSelected(key == lit)
    end
    -- Market: the item's market price, the fourth choice
    bar.fill:SetShown(advice.market ~= nil)
    if advice.market then
      bar.fill.label:SetText(L["Market %s"]:format(W.Money(advice.market.price)))
      W.Primary(bar.fill)
      bar.fill:SetSelected(lit == "market")
    end
  end
  Sell.LayoutButtons(bar)
end

-- buttons sized to their labels, right to left: Market (or Post anyway), Patient, Normal, Quick
function Sell.LayoutButtons(bar)
  local prev
  for _, b in ipairs({ bar.fill, bar.patient, bar.reset, bar.quick }) do
    b:SetWidth(math.max(60, math.ceil(b.label:GetStringWidth() or 40) + 20))
    b:SetHeight(24)
    if b:IsShown() then
      b:ClearAllPoints()
      if prev then
        b:SetPoint("RIGHT", prev, "LEFT", -6, 0)
      else
        b:SetPoint("TOPRIGHT", -10, -5)
      end
      prev = b
    end
  end
  -- the title stops short of the buttons (it ends in "..." when it must)
  bar.title:SetPoint("RIGHT", prev or bar, prev and "LEFT" or "RIGHT", prev and -44 or -44, 0)
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
  elseif not self.seen or self.seen == 0 then
    self.seen = price -- the box got its first price only now (filled in after the item arrived)
  elseif price and price > 0 and price ~= self.seen then
    self.seen = price
    if price ~= self.filled then
      self.target = price -- you clicked a listing or typed a price
      self.key = nil
    end
  end
  local key = tostring(id) .. ":" .. qty .. ":" .. hours -- item keys can exceed %d's range
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
  if not bar:IsShown() then
    Sell.Place(bar)
  end
  bar:Show()
  if not self.hint then
    self.hint = W.Hint(
      bar,
      "sellBar",
      L["AME suggests a price from how fast this item sells, instead of undercutting by 1c. Click a price to put it in the box; you still click Post."]
    ) or false
  end
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
