-- Item tab: chart and stats for one item, the item search box, and Shift-clicked item links.
local _, ns = ...
local L = ns.L

local W = ns.Widgets
local UI = ns.UI
local DAY = ns.DAY
local avgDays, contentArea = UI.AvgDays, UI.ContentArea

-- 2D plots every recent scan (intraday); the others plot daily history
local RANGES = { { "2D", 2 }, { "7D", 7 }, { "30D", 30 }, { "90D", 90 }, { "1Y", 365 }, { "All", nil, L["All"] } }
local INTRADAY = "2D"

---------------------------------------------------------------------------------------------------------------------
-- Item view

function UI:CreateItemView(parent)
  local v = contentArea(parent)

  -- search / header
  local box
  box = W.Input(v, {
    width = 230,
    hint = L["Item name, ID, or Shift-click an item"],
    onChange = function(text, _, user)
      if user then
        UI:SuggestItems(box, text)
      end
    end,
    onEnter = function(self)
      local id = ns.ItemIDFrom(self:GetText())
      if not id then
        local best = UI:ItemSuggestions(self:GetText(), 1)[1]
        id = best and best.itemID
      end
      self:ClearFocus()
      W.HideMenu(self)
      if id then
        self:SetText("")
        UI:ShowItem(id)
      end
    end,
    clearOnEscape = true,
    onEscape = W.HideMenu,
  })
  box:SetPoint("TOPRIGHT", -2, 0)
  box:HookScript("OnEditFocusGained", function()
    UI:WarmItemNames()
  end)
  self.searchBox = box
  -- Shift-clicking an item (chat link, bags, AH) opens it while the Item tab is up. Every modified item click goes
  -- through HandleModifiedItemClick (hooked in Tooltip); the chat-insert hooks are a fallback for older clients.
  local function onInsert(link)
    UI:OnItemLinkClicked(link, true)
  end
  if ChatFrameUtil and ChatFrameUtil.InsertLink then
    pcall(hooksecurefunc, ChatFrameUtil, "InsertLink", onInsert)
  end
  if ChatEdit_InsertLink then
    pcall(hooksecurefunc, "ChatEdit_InsertLink", onInsert)
  end

  -- watch + alerts (second header row, right-aligned under the search box)
  v.alertSignal = W.Check(v, L["on buy/sell signal"], function(on)
    if UI.itemID then
      ns.AME.watch:SetAlert(UI.itemID, { signal = on })
      UI:UpdateWatchControls()
    end
  end)
  v.alertSignal:SetPoint("TOPRIGHT", -96, -25) -- inputs: 3 px under search, 5 over cards
  local function goldAlert(field, hint)
    return W.GoldInput(v, hint, function(g, user)
      if user and UI.itemID then
        ns.AME.watch:SetAlert(UI.itemID, { [field] = g and g * 10000 or false })
        UI:UpdateWatchControls(true)
      end
    end)
  end
  v.alertAbove = goldAlert("above", L["above g"])
  v.alertAbove:SetPoint("RIGHT", v.alertSignal, "LEFT", -8, 0)
  v.alertBelow = goldAlert("below", L["below g"])
  v.alertBelow:SetPoint("RIGHT", v.alertAbove, "LEFT", -8, 0)
  v.alertLabel = W.Text(v, "GameFontDisableSmall", "RIGHT")
  v.alertLabel:SetPoint("RIGHT", v.alertBelow, "LEFT", -8, 0)
  v.alertLabel:SetText(L["Alert when"])
  v.watch = W.Button(v, L["Watch"], 84, 20, function(self)
    UI:WatchMenu(self, UI.itemID)
  end, { icon = 14 })
  v.watch.star = v.watch.icon
  W.SetStar(v.watch.star, false)
  v.watch:SetPoint("RIGHT", v.alertLabel, "LEFT", -12, 0)

  v.icon = v:CreateTexture(nil, "ARTWORK")
  v.icon:SetSize(32, 32)
  v.icon:SetPoint("TOPLEFT", 0, 0)
  v.name = W.Text(v, "GameFontNormalLarge")
  v.name:SetPoint("TOPLEFT", v.icon, "TOPRIGHT", 8, -2)
  v.sub = W.Text(v, "GameFontDisableSmall")
  v.sub:SetPoint("BOTTOMLEFT", v.icon, "BOTTOMRIGHT", 8, 2)

  -- stat cards
  v.cardRow = W.CardRow(v, {
    { L["Market"], term = "market" },
    { L["Lowest"], term = "min" },
    { L["Average"], term = "avg" },
    { L["7d change"], term = "change7" },
    { L["Volatility"], term = "vol30" },
    { L["Supply  ·  sells/day"], term = "sellRate" },
    { L["Signal"], term = "signal" },
  }, { width = UI.WIDTH - 20 })
  v.cardRow:SetPoint("TOPLEFT", v.icon, "BOTTOMLEFT", 0, -16)
  v.cardRow:SetPoint("RIGHT", 0, 0)
  v.cards = v.cardRow.cards

  -- range buttons
  local ranges, days = {}, {}
  for i, r in ipairs(RANGES) do
    ranges[i], days[r[1]] = { r[1], r[3] or r[1] }, r[2]
  end
  v.ranges = W.Segmented(v, ranges, {
    minWidth = 44,
    onSelect = function(key)
      UI:SetRange(days[key], key)
    end,
  })
  v.ranges:SetPoint("TOPLEFT", v.cardRow, "BOTTOMLEFT", 0, -10)
  v.rangeButtons = v.ranges.buttons
  v.style = W.Button(v, L["Candles"], 64, 20, function()
    local style = ns.Settings:Get("chartStyle") == "candles" and "line" or "candles"
    ns.Settings:Set("chartStyle", style)
    UI:DrawItemChart()
  end)
  v.style:SetPoint("LEFT", v.ranges, "RIGHT", 12, 0)
  ns.Help.Explain(v.style, "candles")
  v.legend = W.Text(v, "GameFontDisableSmall")
  v.legend:SetPoint("LEFT", v.style, "RIGHT", 12, 0)

  -- chart
  local holder = CreateFrame("Frame", nil, v, "BackdropTemplate")
  W.Skin(holder, { 0.07, 0.08, 0.1, 1 }, W.COLORS.border)
  W.InnerGlow(holder)
  self.chartHolder = holder
  holder:SetPoint("TOPLEFT", v.ranges, "BOTTOMLEFT", 0, -8)
  holder:SetPoint("BOTTOMRIGHT", 0, 22)

  -- posting price suggestion (Pricing / Posting), under the chart
  v.post = CreateFrame("Frame", nil, v)
  v.post:SetPoint("BOTTOMLEFT", 0, 0)
  v.post:SetPoint("BOTTOMRIGHT", -UI.FOOTER_SPACE, 0) -- the version sits at the right end of this row
  v.post:SetHeight(18)
  v.post:EnableMouse(true)
  ns.Help.Explain(v.post, "posting")
  v.post.text = W.Text(v.post, "GameFontHighlightSmall")
  v.post.text:SetAllPoints()
  v.post.text:SetJustifyH("LEFT")
  v.post.text:SetWordWrap(false)
  local chart = LibStub("LibAMEChart-1.0"):New(holder, {
    panes = { { axis = "price", weight = 3 }, { axis = "volume", weight = 1 } },
  })
  chart.frame:SetPoint("TOPLEFT", 4, -4)
  chart.frame:SetPoint("BOTTOMRIGHT", -4, 4)
  chart:SetAxisFormatter("price", function(val)
    return W.Money(val, true)
  end)
  chart:SetAxisFormatter("volume", function(val)
    return val >= 1000 and ("%.1fk"):format(val / 1000) or tostring(math.floor(val))
  end)
  chart:SetHoverFormatter(function(_, x, rows)
    local lines = { W.Color("white", date(UI.intradayMode and "%a %b %d, %H:%M" or "%a %b %d, %Y", x)) }
    local c = rows.candles and UI.candles
    if c and rows.candles.x == x then
      local i = rows.candles.index
      if c.period > DAY then
        lines[1] =
          W.Color("white", date("%b %d", x - c.period / 2) .. " - " .. date("%b %d, %Y", x + c.period / 2 - DAY))
      end
      lines[#lines + 1] = L["Open"] .. "  " .. W.Money(c.open[i])
      lines[#lines + 1] = L["High"] .. "  " .. W.Money(c.high[i])
      lines[#lines + 1] = L["Low (cheapest)"] .. "  " .. W.Money(c.low[i])
      lines[#lines + 1] = L["Close"] .. "  " .. W.Money(c.close[i])
    end
    if rows.market and rows.market.x == x then
      lines[#lines + 1] = L["Market"] .. "  " .. W.Money(rows.market.y)
    end
    if rows.min and rows.min.x == x then
      lines[#lines + 1] = L["Lowest"] .. "  " .. W.Money(rows.min.y)
    end
    if rows.sma and rows.sma.x == x then
      lines[#lines + 1] = L["7d avg"] .. "  " .. W.Money(rows.sma.y)
    end
    if rows.qty and rows.qty.x == x then
      lines[#lines + 1] = L["Supply"] .. "  " .. rows.qty.y
    end
    return lines
  end)
  self.chart = chart
  self.itemView = v
  return v
end

function UI:SetRange(days, key)
  self.rangeDays, self.rangeKey = days, key
  self.itemView.ranges:Select(key, true)
  local wasIntraday = self.intradayMode
  self.intradayMode = key == INTRADAY
  if self.intradayMode then
    self:LoadIntraday()
    return
  end
  if wasIntraday and self.series then
    self:DrawItemChart()
  end
  if days then
    local now = GetServerTime()
    self.chart:SetXRange(now - days * DAY, now + DAY)
  else
    self.chart:SetXRange(nil)
  end
  if ns.Settings:Get("chartStyle") == "candles" and self.series then
    self:DrawItemChart() -- candle period depends on the range
  end
end

-- the last 2 days scan by scan (full scans and searches), from the scans kept in full
function UI:LoadIntraday()
  local itemID = self.itemID
  if not itemID then
    return
  end
  local function show()
    local now = GetServerTime()
    self:DrawItemChart()
    if #(self.intraday or {}) == 0 then
      self.chart:SetMessage(L["No scans of this item in the last 2 days. Daily history is on the other ranges."])
    else
      self.chart:SetMessage(nil)
      self.chart:SetXRange(now - 2 * DAY, now + 3600)
    end
  end
  if self.intradayItem == itemID and self.intraday then
    return show()
  end
  self.chart:SetMessage(L["Loading recent scans..."])
  ns.AME:WithStore("intraday-" .. itemID, self:ViewShard(), function(store)
    return store:Intraday(itemID, GetServerTime() - 2 * DAY)
  end, function(ok, points)
    if not ok then
      ns.AME:ReportError("recent scans", points)
    end
    if self.itemID ~= itemID or not self.intradayMode then
      return
    end
    self.intraday, self.intradayItem = ok and points or {}, itemID
    show()
  end)
end

-- days per candle so a range shows at most ~60 candles
-- Your own trades in an item, as dots on its price chart: what you paid / got per unit, when (ledger entries).
UI.TRADE_COLORS = { buy = { 0.35, 0.65, 1, 1 }, sale = { 1, 0.45, 0.85, 1 } }

local function tradePoints(itemID)
  local ledger = ns.AME.ledger
  if not (ledger and itemID) then
    return nil
  end
  local name = ns.ItemCache.Name(itemID)
  local xs, ys, colors = {}, {}, {}
  for _, e in ipairs(ledger.db.entries) do
    local mine = e.itemID == itemID or (name and e.name == name)
    if mine and (e.kind == "buy" or e.kind == "sale") and (e.qty or 0) > 0 and e.amount then
      xs[#xs + 1], ys[#ys + 1], colors[#colors + 1] = e.t, e.amount / e.qty, UI.TRADE_COLORS[e.kind]
    end
  end
  return #xs > 0 and { xs = xs, ys = ys, colors = colors } or nil
end
UI.TradePoints = tradePoints

local function candlePeriod(series, rangeDays)
  local span = rangeDays
  if not span and #series > 0 then
    span = series[#series].day - series[1].day + 1
  end
  return math.max(1, math.ceil((span or 1) / 60))
end

-- (Re)draw the item chart in the current style from self.series.
function UI:DrawItemChart()
  local intraday = self.intradayMode
  local series, v, chart = intraday and self.intraday or self.series, self.itemView, self.chart
  if not series or #series == 0 then
    chart:ClearSeries()
    return
  end
  local candles = ns.Settings:Get("chartStyle") == "candles"
  v.style.label:SetText(candles and L["Line"] or L["Candles"])
  local xs, market, low, qty, sma = {}, {}, {}, {}, {}
  for i, p in ipairs(series) do
    xs[i] = p.t or (p.day * DAY + (p.res == "week" and 3.5 * DAY or DAY / 2))
    market[i], low[i], qty[i] = p.market, p.min, p.qty
  end
  for i = 1, #market do
    sma[i] = ns.Analytics.SMA(market, math.min(7, i), i)
  end
  local range = chart.range
  chart.range = nil
  chart:ClearSeries()
  local legend
  chart:SetSeries("qty", { xs = xs, ys = qty, kind = "bars", axis = "volume", color = { 0.53, 0.53, 0.67, 1 } })
  if candles then
    local c
    if intraday then
      -- hourly candles from the individual scans (2 hours each over 2 days)
      local hourly = {}
      for i, p in ipairs(series) do
        hourly[i] = { day = math.floor(p.t / 3600), market = p.market, min = p.min }
      end
      c = ns.Analytics.Candles(hourly, 2, 3600)
    else
      c = ns.Analytics.Candles(series, candlePeriod(series, self.rangeDays))
    end
    self.candles = c
    chart:SetSeries("candles", {
      kind = "candles",
      axis = "price",
      xs = c.xs,
      open = c.open,
      high = c.high,
      low = c.low,
      close = c.close,
      period = c.period,
      marker = true,
      color = W.COLORS.up,
      upColor = W.COLORS.up,
      downColor = W.COLORS.down,
    })
    legend = W.Swatch(W.COLORS.up)
      .. " "
      .. L["up"]
      .. "  "
      .. W.Swatch(W.COLORS.down)
      .. " "
      .. L["down  (wick = cheapest)"]
      .. "   "
  else
    self.candles = nil
    chart:SetSeries("market", {
      xs = xs,
      ys = market,
      kind = "area",
      axis = "price",
      color = { 0.2, 0.8, 1, 1 },
      marker = true,
    })
    chart:SetSeries("min", { xs = xs, ys = low, kind = "line", axis = "price", color = { 0.4, 0.87, 0.47, 0.9 } })
    legend = W.Swatch(0.2, 0.8, 1)
      .. " "
      .. L["market"]
      .. "   "
      .. W.Swatch(0.4, 0.87, 0.47)
      .. " "
      .. L["lowest"]
      .. "   "
  end
  if not intraday then -- a 7-point average of scans isn't a 7-day average
    legend = legend .. W.Swatch(1, 0.67, 0.2) .. " " .. L["7d average"] .. "   "
  end
  legend = legend
    .. W.Swatch(0.53, 0.53, 0.67)
    .. " "
    .. L["supply"]
    .. "      "
    .. L["wheel: zoom, drag: pan, double-click: reset"]
  if intraday then
    legend = legend .. "   " .. L["(each point is one scan)"]
  end
  local trades = tradePoints(self.itemID)
  if trades then
    chart:SetSeries("trades", {
      xs = trades.xs,
      ys = trades.ys,
      colors = trades.colors,
      kind = "points",
      axis = "price",
      size = 8,
    })
    legend = legend
      .. "   "
      .. W.Swatch(UI.TRADE_COLORS.buy)
      .. " "
      .. L["you bought"]
      .. "  "
      .. W.Swatch(UI.TRADE_COLORS.sale)
      .. " "
      .. L["you sold"]
  end
  v.legend:SetText(legend)
  if not intraday then -- a 7-point average of scans isn't a 7-day average
    chart:SetSeries("sma", {
      xs = xs,
      ys = sma,
      kind = "line",
      axis = "price",
      color = { 1, 0.67, 0.2, 0.9 },
      width = 1.5,
    })
  end
  chart.range = range
  chart:Refresh()
end

-- Fresh listings for some items were recorded (a search, e.g. the item you're about to sell): the item on screen
-- reloads its numbers, chart and posting price in place - they may have come from an hours-old scan.
function UI:OnItemListings(ids)
  for _, id in ipairs(ids) do
    if id == self.itemID and self.frame and self.frame:IsShown() then
      self:ReloadItem()
    end
  end
  if ns.SellAssist and ns.SellAssist.Invalidate then
    ns.SellAssist:Invalidate()
  end
end

-- The auction house searched one item (you picked it to post or buy, in the game's window or an addon's): while the
-- Item tab is open, show that item - unless you're typing in AME's search box.
function UI:FollowAuctionItem(itemID)
  if not (self.frame and self.frame:IsShown() and self.current == "item") or itemID == self.itemID then
    return
  end
  if self.searchBox and self.searchBox:HasFocus() then
    return
  end
  self:ShowItem(itemID)
end

function UI:ShowItem(itemID)
  self:Create()
  self.frame:Show()
  self:ShowTab("item")
  self.itemID = itemID
  self.intraday, self.intradayItem = nil, nil
  local v = self.itemView

  local function header()
    local name, _, quality, icon = W.ItemInfo(itemID)
    v.icon:SetTexture(icon or 134400)
    v.name:SetText(W.QualityText(quality, name or ("item:" .. itemID)))
  end
  header()
  W.OnItemLoaded(itemID, header)
  self:UpdateWatchControls()

  for _, c in ipairs(v.cards) do
    c.value:SetText("...")
  end
  v.sub:SetText(L["loading history..."])
  self.chart:ClearSeries()
  self.chart:SetMessage(L["Loading history..."])

  ns.AME:WithStore("chart-" .. itemID, self:ViewShard(), function(store)
    return { series = store:Series(itemID), latest = store:Latest(itemID) }
  end, function(ok, res)
    if self.itemID ~= itemID then
      return
    end
    if not ok then
      self.chart:SetMessage(L["Could not load history: %s"]:format(tostring(res)))
      return
    end
    self:FillItem(itemID, res.series, res.latest)
  end)
end

-- reload the item on screen without clearing it first (no "loading" flash)
function UI:ReloadItem()
  local itemID = self.itemID
  if not itemID then
    return
  end
  self.intraday, self.intradayItem = nil, nil
  ns.AME:WithStore("chart-" .. itemID, self:ViewShard(), function(store)
    return { series = store:Series(itemID), latest = store:Latest(itemID) }
  end, function(ok, res)
    if ok and self.itemID == itemID then
      self:FillItem(itemID, res.series, res.latest)
    end
  end)
end

function UI:FillItem(_, series, latest)
  local v = self.itemView
  if #series == 0 then
    self.series = nil
    self.chart:SetMessage(L["No history for this item yet. Search for it at the auction house, or run a full scan."])
    v.sub:SetText(ns.ShardLabel(self:ViewShard()))
    for _, c in ipairs(v.cards) do
      c.value:SetText("-")
    end
    return
  end
  self.chart:SetMessage(nil)
  local factor = ns.Settings:Get("outlierFactor")
  local dropped
  series, dropped = ns.Analytics.Clean(series, factor)
  self.series = series
  self:DrawItemChart()
  if self.rangeKey == "All" then
    self:SetRange(nil, "All")
  else
    self:SetRange(self.rangeDays or 7, self.rangeKey or "7D")
  end

  local s = ns.Analytics.Summarize(series)
  -- the latest raw scan can itself be a bad print (one overpriced listing): fall back to the cleaned series
  if latest and factor and s.avg30 and s.avg30 > 0 and latest.market then
    if latest.market > s.avg30 * factor or latest.market < s.avg30 / factor then
      latest, dropped = nil, dropped + 1
    end
  end
  local cards = v.cards
  cards[1].value:SetText(W.Money(latest and latest.market or s.market))
  cards[2].value:SetText(W.Money(latest and latest.min or s.min))
  cards[3].label:SetText(L["%d-day average"]:format(avgDays()))
  cards[3].value:SetText(W.Money(s["avg" .. avgDays()] or s.avg30))
  cards[4].value:SetText(W.Percent(s.change7))
  cards[5].value:SetText(s.vol30 and ("%.1f%%"):format(s.vol30 * 100) or "-")
  cards[6].value:SetText(
    tostring(latest and latest.qty or s.qty or 0)
      .. " "
      .. W.Percent(s.supplyTrend30 and s.supplyTrend30 * 7, 0)
      .. (s.sellRate and "  " .. W.Dim(W.Rate(s.sellRate)) or "")
  )
  cards[7].label:SetText(s.phase and ns.Analytics.PHASE_LABEL[s.phase] or L["Signal"])
  cards[7].value:SetText(W.Signal(s.signal) .. "  " .. W.Dim(("%+d"):format(s.score or 0)))
  v.sub:SetText(
    L["%s  ·  %d days of history  ·  data %s %s%s%s"]:format(
      ns.ShardLabel(self:ViewShard()),
      #series,
      W.Confidence(ns.Analytics.Confidence(s, math.floor(GetServerTime() / DAY))),
      L["%d scans in 7 days"]:format(s.scans7 or 0),
      latest and ("  ·  " .. L["last seen %s"]:format(date("%b %d %H:%M", latest.t))) or "",
      dropped > 0
          and "  ·  " .. W.Color(
            "warn",
            (dropped == 1 and L["%d outlier price ignored"] or L["%d outlier prices ignored"]):format(dropped)
          )
        or ""
    )
  )
  self:UpdatePostAdvice()
end

-- what to post the viewed item at (one unit, your usual listing time) at the viewed auction house
function UI:UpdatePostAdvice()
  local v = self.itemView
  if not (v and v.post and self.itemID) then
    return
  end
  local ok, advice =
    pcall(ns.Posting.Suggest, ns.Posting, self:ViewShard(), self.itemID, 1, ns.Settings:Get("listingHours"))
  if not ok then
    ns.AME:ReportError("posting price", advice)
  end
  v.post.text:SetText(W.PostAdvice(ok and advice or nil))
end

---------------------------------------------------------------------------------------------------------------------
-- Item search box: suggestions by name, Shift-click links

function UI:WarmItemNames()
  local index = self:ViewIndex()
  if index and self.warmedIndex ~= index then
    self.warmedIndex = index
    local ids = {}
    for id in pairs(index.items) do
      ids[#ids + 1] = id
    end
    ns.ItemCache.Warm(ids)
  end
end

function UI:ItemSuggestions(text, limit)
  if not text or text == "" or ns.ItemIDFrom(text) then
    return {}
  end
  return ns.MarketFilter.FindByName((self:ViewIndex()), text, function(id)
    return ns.ItemCache.Get(id)
  end, limit or 10)
end

function UI:SuggestItems(box, text)
  local hits = #(text or "") >= 2 and self:ItemSuggestions(text, 10) or {}
  if #hits == 0 then
    W.HideMenu(box)
    return
  end
  local entries = {}
  for i, h in ipairs(hits) do
    entries[i] = {
      text = W.QualityText(h.quality, h.name),
      func = function()
        box:SetText("")
        box:ClearFocus()
        UI:ShowItem(h.itemID)
      end,
    }
  end
  W.Menu(box, entries, { refresh = true })
end

-- Shift-click on an item link anywhere: opens it on the Item tab, or searches for it on the Market tab, when AME is
-- the obvious target (its box has focus, or no chat box is open). fromInsert: called from a chat-insert hook.
function UI:OnItemLinkClicked(link, fromInsert)
  if not (link and self.frame and self.frame:IsShown()) then
    return
  end
  local id = ns.ItemIDFrom(link)
  if not id then
    return
  end
  -- several hooks can report the same click
  local now = GetTime and GetTime() or 0
  if self.lastLink == link and now - (self.lastLinkAt or 0) < 0.3 then
    return
  end
  local chatOpen = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
  if self.current == "item" and (self.searchBox:HasFocus() or (not chatOpen and not fromInsert)) then
    self.lastLink, self.lastLinkAt = link, now
    self.searchBox:SetText("")
    self.searchBox:ClearFocus()
    self:ShowItem(id)
  elseif self.current == "market" and self.marketView.search:HasFocus() then
    self.lastLink, self.lastLinkAt = link, now
    local name = ns.ItemCache.Get(id).name or link:match("%[(.-)%]")
    if name then
      self.marketView.search:SetText(name)
      self.mq.text = name
      self.offset = 0
      self:RefreshMarket(true)
    end
  end
end
