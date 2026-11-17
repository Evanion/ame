-- Arbitrage tab: items to buy at one auction house and sell at another, after the selling house's cut.
local _, ns = ...
local L = ns.L

local W = ns.Widgets
local UI = ns.UI

local HOUSES = {
  { "Alliance", L["Alliance AH"] },
  { "Horde", L["Horde AH"] },
  { "Neutral", L["Goblin AH"] },
}
local AGES = {
  { 1, L["Seen today/yesterday"] },
  { 3, L["Seen in 3 days"] },
  { 7, L["Seen in 7 days"] },
  { false, L["Any age"] },
}

local function indexOf(values, value)
  for i, o in ipairs(values) do
    if o[1] == value then
      return i
    end
  end
  return 1
end

local function ageText(days)
  if not days or days <= 0 then
    return L["today"]
  elseif days == 1 then
    return L["1 day"]
  end
  return L["%d days"]:format(days)
end

local COLUMNS = {
  { key = "name", label = L["Item"], width = 180, item = true, sortKey = false },
  { key = "buy", label = L["Buy at"], width = 86, format = "money", term = "arbBuy" },
  { key = "sell", label = L["Sells for"], width = 86, format = "money", term = "arbSell" },
  {
    key = "profit",
    label = L["Profit"],
    width = 86,
    term = "arbProfit",
    text = function(e)
      return "|cff4dd973+|r" .. W.Money(e.profit, true)
    end,
  },
  {
    key = "margin",
    label = L["Margin"],
    width = 60,
    term = "arbMargin",
    text = function(e)
      return W.Percent(e.margin, 0)
    end,
  },
  {
    key = "supply",
    label = L["Supply"],
    width = 60,
    term = "arbSupply",
    sortKey = "sellQty",
    text = function(e)
      return ("%s / %s"):format(tostring(e.buyQty or "-"), tostring(e.sellQty or "-"))
    end,
  },
  {
    key = "deposit",
    label = L["Deposit"],
    width = 70,
    term = "arbDeposit",
    sortKey = false,
    text = function(e)
      local info = ns.ItemCache.Get(e.itemID)
      local dep = ns.Arbitrage.Deposit(info.sellPrice, UI.arb.sell, ns.Settings:Get("listingHours"))
      return dep and W.Money(dep, true) or "-"
    end,
  },
  {
    key = "depth",
    label = L["Depth"],
    width = 90,
    term = "arbDepth",
    sortKey = false,
    text = function(e)
      return UI:DepthText(e)
    end,
  },
  { key = "sellRate", label = L["Sells/d"], width = 58, format = "rate", term = "arbSellRate" },
  {
    key = "age",
    label = L["Data"],
    width = 48,
    term = "arbAge",
    text = function(e)
      return ageText(e.age)
    end,
  },
}
local ROWS = 16

function UI:CreateArbitrageView(parent, contentArea)
  local v = contentArea(parent)
  self.arbView = v
  local own = ns.AME:CurrentHouse()
  self.arb = {
    buy = own == "Neutral" and (UnitFactionGroup("player") or "Horde") or own,
    sell = "Neutral",
    minProfit = 1,
    minMargin = 0.1,
    maxAge = 3,
    sortKey = "profit",
    ascending = false,
  }

  local function label(text, anchor, x)
    local t = W.Text(v, "GameFontHighlightSmall")
    t:SetPoint("LEFT", anchor, "RIGHT", x or 10, 0)
    t:SetText(text)
    return t
  end

  local buyLabel = W.Text(v, "GameFontHighlightSmall")
  buyLabel:SetPoint("TOPLEFT", 0, -4)
  buyLabel:SetText(L["Buy at"])
  v.buy = W.Dropdown(v, 104, HOUSES, function(value)
    UI.arb.buy = value
    UI:RefreshArbitrage()
  end)
  v.buy.neutral = true
  v.buy:SetPoint("LEFT", buyLabel, "RIGHT", 6, 0)
  v.swap = W.Button(v, L["Swap"], 50, 20, function()
    UI.arb.buy, UI.arb.sell = UI.arb.sell, UI.arb.buy
    UI:RefreshArbitrage()
  end)
  v.swap:SetPoint("LEFT", v.buy, "RIGHT", 6, 0)
  local sellLabel = label(L["Sell at"], v.swap)
  v.sell = W.Dropdown(v, 104, HOUSES, function(value)
    UI.arb.sell = value
    UI:RefreshArbitrage()
  end)
  v.sell.neutral = true
  v.sell:SetPoint("LEFT", sellLabel, "RIGHT", 6, 0)

  local function goldInput(hint, onChange)
    local input = W.Input(v)
    input:SetSize(66, 20)
    input:SetNumeric(true)
    input.hint = W.Text(input, "GameFontDisableSmall")
    input.hint:SetPoint("LEFT", 6, 0)
    input.hint:SetPoint("RIGHT", -6, 0) -- clipped to the box (translations run longer)
    input.hint:SetJustifyH("LEFT")
    input.hint:SetWordWrap(false)
    input.hint:SetText(hint)
    input:SetScript("OnTextChanged", function(self)
      self.hint:SetShown(self:GetText() == "")
      onChange(tonumber(self:GetText()))
    end)
    input:SetScript("OnEnterPressed", input.ClearFocus)
    return input
  end
  v.minProfit = goldInput(L["profit g"], function(g)
    UI.arb.minProfit = g and g * 10000 or 1
    UI:RefreshArbitrage(true)
  end)
  v.minProfit:SetPoint("LEFT", v.sell, "RIGHT", 16, 0)
  v.minMargin = goldInput(L["margin %"], function(p)
    UI.arb.minMargin = (p or 10) / 100
    UI:RefreshArbitrage(true)
  end)
  v.minMargin:SetPoint("LEFT", v.minProfit, "RIGHT", 6, 0)
  v.age = W.Dropdown(v, 140, AGES, function(value)
    UI.arb.maxAge = value
    UI:RefreshArbitrage(true)
  end)
  v.age.neutral = true
  v.age:SetPoint("LEFT", v.minMargin, "RIGHT", 6, 0)

  -- the list (shared DataTable component)
  v.table = ns.DataTable.New(v, {
    columns = COLUMNS,
    rows = ROWS,
    top = -32,
    itemID = function(e)
      return e.itemID
    end,
    sort = { key = self.arb.sortKey, ascending = self.arb.ascending },
    onSort = function(key, ascending)
      UI.arb.sortKey, UI.arb.ascending = key, ascending
      UI:RefreshArbitrage(true)
    end,
    offset = {
      get = function()
        return UI.arbOffset
      end,
      set = function(n)
        UI.arbOffset = n
      end,
    },
    -- Search: shown while you're at the buy auction house
    action = {
      label = L["Search"],
      width = 56,
      shown = function()
        return UI:AtBuyHouse()
      end,
      onClick = function(e)
        ns.AME:SearchAuctionHouse(e.itemID)
      end,
    },
    onClick = function(e)
      if IsShiftKeyDown() and UI:AtBuyHouse() then
        ns.AME:SearchAuctionHouse(e.itemID)
      else
        UI:ShowItem(e.itemID)
      end
    end,
  })
  v.headers, v.rows = v.table.headers, v.table.rows
  v.status = W.Text(v, "GameFontDisableSmall", "LEFT")
  v.status:SetPoint("BOTTOMLEFT", 0, 0)
  v.status:SetWidth(940)

  v:SetScript("OnShow", function()
    UI:RefreshArbitrage(true) -- coming back (e.g. from an item chart): keep the scroll position
  end)
  return v
end

-- Load both houses' indexes (built in the background if needed), then compute the routes.
function UI:RefreshArbitrage(keepOffset)
  local v = self.arbView
  if not (v and v:IsShown()) then
    return
  end
  local a = self.arb
  v.buy:SetIndex(indexOf(HOUSES, a.buy))
  v.sell:SetIndex(indexOf(HOUSES, a.sell))
  v.age:SetIndex(indexOf(AGES, a.maxAge))
  if not keepOffset then
    self.arbOffset = 0
  end
  local AME = ns.AME
  local realm = AME:MarketRealmName()
  local buyShard, sellShard = ns.ShardKey(realm, a.buy), ns.ShardKey(realm, a.sell)
  if not keepOffset then
    self.arbRows = nil -- a new comparison: show "loading"; a refresh keeps the rows until the new ones are in
  end
  v.status:SetText(L["Loading market data..."])
  self:RenderArbitrage()
  local token = {}
  self.arbToken = token
  AME:IndexFor(buyShard, function(buyIndex)
    AME:IndexFor(sellShard, function(sellIndex)
      if self.arbToken ~= token then
        return
      end
      self.arbMissing = (not buyIndex and ns.HOUSE_LABEL[a.buy]) or (not sellIndex and ns.HOUSE_LABEL[a.sell]) or nil
      local cut = ns.Settings:AuctionCut(a.sell)
      self.arbCut = cut
      self.arbRows = ns.Arbitrage.Find(buyIndex, sellIndex, {
        cut = cut,
        minProfit = a.minProfit,
        minMargin = a.minMargin,
        maxAge = a.maxAge or nil,
        today = ns.Today(GetServerTime()),
        sortKey = a.sortKey,
        ascending = a.ascending,
      })
      self:RenderArbitrage()
    end)
  end)
end

-- How far the route goes at the buy house, from its latest order book (a search there in the last 6 hours):
-- "37 +12g" = buy 37 units for 12g profit. "-" until the item has been searched there.
UI.DEPTH_MAX_AGE = 6 * 3600
function UI:DepthText(e)
  local a = self.arb
  local shard = ns.ShardKey(ns.AME:MarketRealmName(), a.buy)
  local book = ns.AME:BookFor(shard, e.itemID, UI.DEPTH_MAX_AGE)
  if not book then
    return "|cff777777" .. L["search"] .. "|r"
  end
  local units, _, profit = ns.Depth.Route(book, e.sell * (1 - (self.arbCut or 0)))
  if units == 0 then
    return "|cffff61590|r"
  end
  return ("%d |cff4dd973+|r%s"):format(units, W.Money(profit, true))
end

-- standing at the auction house you'd buy from (so a row can be searched there)
function UI:AtBuyHouse()
  return ns.AME.ahOpen and self.arb and ns.AME:CurrentHouse() == self.arb.buy
end

function UI:RenderArbitrage()
  local v = self.arbView
  if not (v and v:IsShown()) then
    return
  end
  local a = self.arb
  local canSearch = self:AtBuyHouse()
  local rows = self.arbRows or {}
  local total = #rows
  local t = v.table
  t.sort.key, t.sort.ascending = a.sortKey, a.ascending
  t:SetData(rows)
  t:Render()
  local status
  if not self.arbRows then
    status = L["Loading market data..."]
  elseif self.arbMissing then
    status = L["No price history for the %s yet: scan there (any character on this account counts) to compare."]:format(
      self.arbMissing
    )
  else
    status = L["%d routes  -  buy at %s, sell at %s: %d%% cut, deposits for %dh listings"]:format(
      total,
      ns.HOUSE_LABEL[a.buy],
      ns.HOUSE_LABEL[a.sell],
      math.floor((self.arbCut or 0) * 100 + 0.5),
      ns.Settings:Get("listingHours")
    )
  end
  if a.buy == a.sell then
    status = L["Pick two different auction houses."]
  elseif canSearch and self.arbRows and #self.arbRows > 0 then
    status = status .. "  -  " .. L["you're at the buy AH: Search (or Shift-click a row) to buy"]
  end
  v.status:SetText(status)
end
