-- Arbitrage tab: items to buy at one auction house and sell at another, after the selling house's cut and deposit.
-- Layout (UI.Slots): toolbar (buy ⇄ sell, minimum profit and margin, data age), the routes table, and a right
-- sidebar for the selected route (price → cut → deposit → net, each side's age, sell rate, Search at the buy house).
-- Narrow window: the sidebar opens over the table from a Details button.
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
  { 1, L["Up to 1 day"] },
  { 3, L["Up to 3 days"] },
  { 7, L["Up to 7 days"] },
  { false, L["Any age"] },
}
UI.ARB_SIDEBAR = UI.SIDE_PANEL_W
UI.ARB_POST_UNITS = 20 -- deposit basis when the route's depth isn't known: one post of up to this many

local function ageText(days)
  if not days or days <= 0 then
    return L["today"]
  elseif days == 1 then
    return L["1 day"]
  end
  return L["%d days"]:format(days)
end
UI.AgeText = ageText

local COLUMNS = {
  { key = "name", label = L["Item"], width = 180, item = true, sortKey = false },
  { key = "buy", label = L["Buy"], width = 80, format = "money", term = "arbBuy" },
  { key = "sell", label = L["Sell"], width = 80, format = "money", term = "arbSell" },
  {
    key = "net",
    money = true,
    label = L["Net"],
    width = 80,
    term = "arbNet",
    text = function(e)
      return W.SignedMoney(e.net)
    end,
  },
  {
    key = "margin",
    label = L["Margin"],
    width = 56,
    term = "arbMargin",
    text = function(e)
      return W.Percent(e.margin, 0)
    end,
  },
  {
    -- profitable units of those listed at the buy house ("12 of 40"); "? of 40" until the item is searched there
    key = "units",
    drop = 3,
    label = L["Units"],
    width = 72,
    term = "arbUnits",
    sortKey = "buyQty",
    text = function(e)
      return L["%s of %s"]:format(e.units and W.Count(e.units) or W.Dim("?"), W.Count(e.buyQty))
    end,
  },
  { key = "sellRate", drop = 2, label = L["Sales/day"], width = 58, format = "rate", term = "arbSellRate" },
  {
    key = "age",
    drop = 1,
    label = L["Data age"],
    width = 60,
    term = "arbAge",
    text = function(e)
      return ageText(e.age)
    end,
  },
}

-- deposit per unit at the sell house: one post of the route's profitable units (or up to UI.ARB_POST_UNITS)
function UI:ArbDeposit(e)
  local info = ns.ItemCache.Get(e.itemID)
  if not info.sellPrice then
    return nil
  end
  local n = e.units or math.min(e.buyQty or 1, UI.ARB_POST_UNITS)
  n = math.max(1, n)
  local dep = ns.Arbitrage.Deposit(info.sellPrice * n, self.arb.sell, ns.Settings:Get("listingHours"))
  return dep / n
end

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
    sortKey = "net",
    ascending = false,
  }
  local slots = UI.Slots(v, { toolbar = 22, chips = 14, right = UI.ARB_SIDEBAR, rightCards = true, status = true })
  v.summary = W.Text(slots.chips, "GameFontDisableSmall")
  v.summary:SetPoint("LEFT", 0, 0)
  v.summary:SetPoint("RIGHT", 0, 0)
  v.summary:SetWordWrap(false)
  v.slots = slots
  local bar = slots.toolbar

  v.buy = W.Dropdown(bar, 104, HOUSES, function(value)
    UI.arb.buy = value
    UI:RefreshArbitrage()
  end, { neutral = true })
  W.Labeled(bar, L["Buy at"], v.buy):SetPoint("LEFT", 0, 0)
  v.swap = W.Button(bar, L["Swap"], 50, 20, function()
    UI.arb.buy, UI.arb.sell = UI.arb.sell, UI.arb.buy
    UI:RefreshArbitrage()
  end)
  v.swap:SetWidth(math.ceil(v.swap.label:GetStringWidth() or 34) + 16) -- fits the translated label
  v.swap:SetPoint("LEFT", v.buy, "RIGHT", 6, 0)
  v.sell = W.Dropdown(bar, 104, HOUSES, function(value)
    UI.arb.sell = value
    UI:RefreshArbitrage()
  end, { neutral = true })
  W.Labeled(bar, L["Sell at"], v.sell):SetPoint("LEFT", v.swap, "RIGHT", 8, 0)

  v.minProfit = W.MoneyInput(bar, L["min profit g"], function(copper)
    UI.arb.minProfit = copper or 1
    UI:RefreshArbitrage(true)
  end)
  v.minProfit:SetPoint("LEFT", v.sell, "RIGHT", 12, 0)
  v.minProfit:SetWidth(84) -- room for the hint
  v.minMargin = W.Input(bar, {
    width = 64,
    numeric = true,
    hint = L["min margin %"],
    onChange = function(_, p) -- whole percent
      UI.arb.minMargin = (p or 10) / 100
      UI:RefreshArbitrage(true)
    end,
  })
  v.minMargin:SetPoint("LEFT", v.minProfit, "RIGHT", 6, 0)
  v.minMargin:SetWidth(90)
  v.age = W.Dropdown(bar, 104, AGES, function(value)
    UI.arb.maxAge = value
    UI:RefreshArbitrage(true)
  end, { neutral = true })
  v.age:SetPoint("LEFT", v.minMargin, "RIGHT", 6, 0)
  v.details = W.Button(bar, L["Details"], 64, 20, function()
    slots:ToggleDetails()
    v.details:SetSelected(slots.details)
  end)
  v.details:SetPoint("RIGHT", 0, 0)

  -- the list (shared DataTable component)
  v.table = ns.DataTable.New(slots.main, {
    columns = COLUMNS,
    rows = 16,
    fill = true, -- rows fill the tab down to the status line
    top = 0,
    itemID = function(e)
      return e.itemID
    end,
    itemMenu = { hide = true },
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
      enabled = function()
        return UI:AtBuyHouse()
      end,
      onClick = function(e)
        ns.AME:SearchAuctionHouse(e.itemID)
      end,
    },
    selected = function(e)
      return UI.arbSelected == e.itemID
    end,
    onClick = function(e)
      if IsShiftKeyDown() and UI:AtBuyHouse() then
        ns.AME:SearchAuctionHouse(e.itemID)
      else
        UI:SelectRoute(e)
      end
    end,
  })
  v.headers, v.rows, v.status = v.table.headers, v.table.rows, slots.status
  self:CreateRouteSidebar(v, slots.right)

  function v:SetCompact(on)
    slots:SetCompact(on)
    self.details:SetShown(on)
    self.details:SetSelected(false)
  end
  v:SetCompact(slots.compact)

  v:SetScript("OnShow", function()
    UI:RefreshArbitrage(true) -- coming back (e.g. from an item chart): keep the scroll position
    if v.hint == nil then
      v.hint = W.Hint(
        slots.toolbar,
        "arbitrage",
        L["Routes compare two auction houses' prices. Scan both (alts count), then search the buy house before buying: the Units column shows how many units still pay."]
      ) or false
    end
  end)
  return v
end

---------------------------------------------------------------------------------------------------------------------
-- the selected route

-- the selected route, as cards: the item and the route; what it pays (buy, sell, cut, deposit, you net); how fresh
-- each side is and how fast it sells there; then the main button
function UI:CreateRouteSidebar(v, side)
  local col = UI.Stack(side.content, 0)
  local r = {}
  local st = col:Card(0).stack
  r.name = st:Text("GameFontNormalLarge")
  r.name:SetWordWrap(false)
  r.nameHover = W.ItemHover(side.content, r.name, r.name) -- the game's item tooltip over the name
  r.hint = st:Text("GameFontDisableSmall", 4)
  st = col:Card().stack
  r.buy = st:Pair(L["Buy at"], "arbBuy")
  r.sell = st:Pair(L["Sells for"], "arbSell")
  r.cut = st:Pair(L["AH cut"], nil)
  r.deposit = st:Pair(L["Deposit if unsold"], "arbDeposit")
  r.rule = st:Row(1, 6) -- a line above "You net"
  local line = r.rule:CreateTexture(nil, "ARTWORK")
  line:SetAllPoints()
  W.Fill(line, W.COLORS.border)
  r.net = st:Pair(L["You net"], "arbNet", 6)
  r.net.label:SetFontObject("GameFontNormal")
  r.net.value:SetFontObject("GameFontHighlight")
  r.margin = st:Pair(L["Margin"], "arbMargin")
  st = col:Card().stack
  r.buyAge = st:Pair(L["Buy-side data"], "arbAge")
  r.sellAge = st:Pair(L["Sell-side data"], "arbAge")
  r.rate = st:Pair(L["Sales per day there"], "arbSellRate")
  r.depth = st:Pair(L["Depth"], "arbDepth")
  r.warn = st:Text("GameFontDisableSmall", 6)
  local actions = col:Row(26, 10)
  r.search = W.Button(actions, L["Search"], 140, 26, function()
    if UI.arbRoute then
      ns.AME:SearchAuctionHouse(UI.arbRoute.itemID)
    end
  end)
  r.search:SetPoint("LEFT")
  r.search:SetPoint("RIGHT", -70, 0)
  r.search:SetSelected(true)
  r.chart = W.Button(actions, L["Chart"], 64, 26, function()
    if UI.arbRoute then
      UI:ShowItem(UI.arbRoute.itemID)
    end
  end)
  r.chart:SetPoint("RIGHT")
  r.searchHint = col:Text("GameFontDisableSmall", 6)
  v.route = r
  v.sidebar = side
  v.routeColumn = col
end

-- an auction house's newest full scan: { t, src } or nil
function UI:LastFull(shard)
  local AME = ns.AME
  local data = AME:HistoryLoaded() and AME.history.shards[shard]
  local full
  for _, e in ipairs(data and data.raw or {}) do
    if e.k == "full" and (not full or e.t > full.t) then
      full = e
    end
  end
  return full
end

-- one side's data: "your scan · 2 h", "Klydig · 1 day" (age in hours under a day)
function UI:SideData(house, days)
  local full = self:LastFull(ns.ShardKey(ns.AME:MarketRealmName(), house))
  local me = UnitName("player")
  local who = full and ((not full.src or full.src == me) and L["your scan"] or full.src) or L["searches"]
  local age
  if (days or 0) <= 0 and full then
    age = W.Ago(full.t, GetServerTime())
  else
    age = ageText(days)
  end
  return who .. "  ·  " .. age
end

function UI:SelectRoute(e)
  self.arbSelected = e and e.itemID or nil
  self:RenderRoute()
  self.arbView.table:Render()
end

function UI:RenderRoute()
  local v = self.arbView
  local r, a = v.route, self.arb
  local e
  for _, row in ipairs(self.arbRows or {}) do
    if row.itemID == self.arbSelected then
      e = row
    end
  end
  self.arbRoute = e
  local parts = { r.sell, r.cut, r.deposit, r.buy, r.net, r.margin, r.depth, r.rate, r.buyAge, r.sellAge }
  local buyHouse, sellHouse = ns.HOUSE_LABEL[a.buy], ns.HOUSE_LABEL[a.sell]
  if not e then
    r.name:SetText(W.Dim(L["Select a route"]))
    r.nameHover:SetItem(false)
    r.hint:SetText(
      L["Click a row to see what the route pays after the cut and the deposit, and how fresh both prices are."]
    )
    for _, p in ipairs(parts) do
      p.value:SetText("-")
    end
    r.warn:SetText("")
    r.search:Hide()
    r.chart:Hide()
    r.searchHint:SetText("")
    v.routeColumn:Height(v.sidebar.content:GetWidth())
    v.sidebar.pane:Measure()
    return
  end
  local name, _, quality = W.ItemInfo(e.itemID)
  r.name:SetText(W.QualityText(quality, name or ("item:" .. e.itemID)))
  r.nameHover:SetItem(e.itemID)
  r.hint:SetText(L["%s to %s"]:format(buyHouse, sellHouse))
  r.buy.label:SetText(L["Buy at the %s"]:format(buyHouse))
  r.buy.value:SetText(W.Money(e.buy))
  r.sell.label:SetText(L["Sells at the %s"]:format(sellHouse))
  r.sell.value:SetText(W.Money(e.sell))
  r.cut.label:SetText(L["%d%% cut"]:format(math.floor((self.arbCut or 0) * 100 + 0.5)))
  r.cut.value:SetText(W.Color("bad", "- " .. W.Money(e.fee)))
  r.deposit.value:SetText(e.deposit and W.Money(e.deposit) or W.NONE)
  r.net.value:SetText(
    W.Color(e.net >= 0 and "good" or "bad", (e.net >= 0 and "+" or "-") .. W.Plain(W.Money(math.abs(e.net))))
  )
  r.margin.value:SetText(W.Percent(e.margin, 0))
  r.depth.value:SetText(self:DepthText(e))
  r.rate.value:SetText(e.sellRate and ("~" .. W.Count(e.sellRate)) or W.NONE)
  r.buyAge.value:SetText(self:SideData(a.buy, e.buyAge))
  r.sellAge.value:SetText(self:SideData(a.sell, e.sellAge))
  local old = math.max(e.buyAge or 0, e.sellAge or 0)
  if old > UI.STALE_DAYS then
    r.warn:SetText(W.Color("warn", L["One side is %d days old: scan both auction houses before you buy."]:format(old)))
  elseif (e.buyAge or 0) >= 1 then
    r.warn:SetText(L["The buy price is a day or more old: search it before you travel."])
  else
    r.warn:SetText(L["Search the buy house to see how many units still pay (Depth)."])
  end
  r.search:Show()
  r.chart:Show()
  r.search.label:SetText(L["Search at the %s"]:format(buyHouse))
  local here = self:AtBuyHouse()
  r.search:SetEnabled(here)
  r.search:SetAlpha(here and 1 or 0.5)
  r.searchHint:SetText(here and "" or L["Visit the %s to search and buy it there."]:format(buyHouse))
  v.routeColumn:Height(v.sidebar.content:GetWidth())
  v.sidebar.pane:Measure()
end

-- Load both houses' indexes (built in the background if needed), then compute the routes.
function UI:RefreshArbitrage(keepOffset)
  local v = self.arbView
  if not (v and v:IsShown()) then
    return
  end
  local a = self.arb
  v.buy:SetValue(a.buy)
  v.sell:SetValue(a.sell)
  v.age:SetValue(a.maxAge)
  if not keepOffset then
    self.arbOffset = 0
  end
  local AME = ns.AME
  local realm = AME:MarketRealmName()
  local buyShard, sellShard = ns.ShardKey(realm, a.buy), ns.ShardKey(realm, a.sell)
  if not keepOffset then
    self.arbRows = nil -- a new comparison: show "loading"; a refresh keeps the rows until the new ones are in
  end
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
      local rows, transfers = ns.Arbitrage.Find(buyIndex, sellIndex, {
        cut = cut,
        minProfit = a.minProfit,
        minMargin = a.minMargin,
        maxAge = a.maxAge or nil,
        today = ns.Today(GetServerTime()),
        sortKey = a.sortKey == "net" and "profit" or a.sortKey,
        ascending = a.ascending,
        hide = ns.AME.watch and ns.AME.watch:Hidden(),
      })
      -- what's left after the deposit too
      for _, e in ipairs(rows) do
        e.units = self:DepthUnits(e)
        e.deposit = self:ArbDeposit(e)
        e.net = e.profit - (e.deposit or 0)
      end
      if a.sortKey == "net" then
        table.sort(rows, function(x, y)
          if x.net == y.net then
            return x.itemID < y.itemID
          end
          if a.ascending then
            return x.net < y.net
          end
          return x.net > y.net
        end)
      end
      self.arbRows, self.arbTransfers = rows, transfers
      self:RenderArbitrage()
    end)
  end)
end

-- How far the route goes at the buy house, from its latest order book (a search there in the last 6 hours):
-- "37 +12g" = buy 37 units for 12g profit. "-" until the item has been searched there.
UI.DEPTH_MAX_AGE = 6 * 3600
function UI:DepthRoute(e)
  local shard = ns.ShardKey(ns.AME:MarketRealmName(), self.arb.buy)
  local book = ns.AME:BookFor(shard, e.itemID, UI.DEPTH_MAX_AGE)
  if not book then
    return nil
  end
  return ns.Depth.Route(book, e.sell * (1 - (self.arbCut or 0)))
end

function UI:DepthUnits(e)
  local units = self:DepthRoute(e)
  return units and units > 0 and units or nil
end

function UI:DepthText(e)
  local units, _, profit = self:DepthRoute(e)
  if not units then
    return W.Color("none", L["search"])
  end
  if units == 0 then
    return W.Color("bad", "0")
  end
  return units .. " " .. W.SignedMoney(profit)
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
  local rows = self.arbRows or {}
  local message, status, summary
  if a.buy == a.sell then
    message = L["Pick two different auction houses."]
  elseif not self.arbRows then
    message = L["Loading market data..."]
  elseif self.arbMissing then
    message =
      L["No price history for the %s yet: scan there (any character on this account counts) to compare."]:format(
        self.arbMissing
      )
  else
    summary = (#rows == 1 and L["1 route"] or L["%d routes"]:format(#rows))
      .. W.SEP
      .. L["buy at the %s (%d%% cut), sell at the %s (%d%% cut)"]:format(
        ns.HOUSE_LABEL[a.buy],
        W.CutPct(ns.Settings:AuctionCut(a.buy)),
        ns.HOUSE_LABEL[a.sell],
        W.CutPct(self.arbCut)
      )
      .. W.SEP
      .. L["deposits for %d h listings counted in net"]:format(ns.Settings:Get("listingHours"))
    if (self.arbTransfers or 0) > 0 then
      summary = summary
        .. W.SEP
        .. L["%d hidden as likely gold transfers (over 2000%% margin)"]:format(self.arbTransfers)
    end
    status = ns.HOUSE_LABEL[a.buy]
      .. ": "
      .. self:SideData(a.buy, nil)
      .. W.SEP
      .. ns.HOUSE_LABEL[a.sell]
      .. ": "
      .. self:SideData(a.sell, nil)
    if self:AtBuyHouse() and #rows > 0 then
      status = status .. W.SEP .. L["you're at the buy AH: Search (or Shift-click a row) to buy"]
    end
  end
  -- keep the selection when it's still a route; else pick the first
  local keep = false
  for _, e in ipairs(rows) do
    keep = keep or e.itemID == self.arbSelected
  end
  if not keep then
    self.arbSelected = rows[1] and rows[1].itemID or nil
  end
  local t = v.table
  t.sort.key, t.sort.ascending = a.sortKey, a.ascending
  t:SetData(message and {} or rows)
  t:Render()
  t:SetMessage(message)
  v.status:SetText(status or "")
  v.summary:SetText(summary or "")
  self:RenderRoute()
end
