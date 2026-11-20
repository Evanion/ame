-- Item tab: chart and stats for one item, the item search box, and Shift-clicked item links.
local _, ns = ...
local L = ns.L

local W = ns.Widgets
local UI = ns.UI
local DAY = ns.DAY
local avgDays, contentArea = UI.AvgDays, UI.ContentArea

-- 2D plots every recent scan, 7D the hourly points (Store:Intraday); the others plot daily history
local RANGES = { { "2D", 2 }, { "7D", 7 }, { "30D", 30 }, { "90D", 90 }, { "1Y", 365 }, { "All", nil, L["All"] } }
local INTRADAY = { ["2D"] = true, ["7D"] = true }
-- hours per candle on the intraday ranges (about 24-28 candles)
local INTRADAY_CANDLE_HOURS = { [2] = 2, [7] = 6 }

---------------------------------------------------------------------------------------------------------------------
-- Item view

-- Layout (UI.Slots): header (icon, name, subtitle, search box), toolbar (ranges, Line | Candles; compact: summary and
-- Details), main (the chart, with its legend as an overlay), right sidebar (verdict, key numbers, post at, watch and
-- alerts), status line (data confidence, last seen, outliers).
UI.ITEM_SIDEBAR = UI.SIDE_PANEL_W
UI.ITEM_SUMMARY_H = 28 -- the compact layout's summary bar under the chart
UI.CONFIDENCE_WORD = { high = L["high"], medium = L["medium"], low = L["low"] }

-- Where the item's prices come from (the footer): the newest full scan of the market and who ran it, and a later
-- search of the item.
function UI:PriceSource(latest)
  local AME, shard = ns.AME, self:ViewShard()
  local data = AME:HistoryLoaded() and AME.history.shards[shard]
  local full
  for _, e in ipairs(data and data.raw or {}) do
    if e.k == "full" and (not full or e.t > full.t) then
      full = e
    end
  end
  local now, me = GetServerTime(), UnitName("player")
  local parts = {}
  if full then
    local mine = not full.src or full.src == me
    parts[1] = mine and L["Prices from your full scan %s"]:format(W.Ago(full.t, now))
      or L["Prices from %s's full scan %s"]:format(full.src, W.Ago(full.t, now))
  else
    parts[1] = ns.ShardLabel(shard)
  end
  if latest and latest.t and (not full or latest.t > full.t + 60) then
    parts[#parts + 1] = L["searched %s"]:format(W.Ago(latest.t, now))
  end
  return table.concat(parts, "  ·  ")
end

function UI:CreateItemView(parent)
  local v = contentArea(parent)
  local slots = UI.Slots(v, { header = 34, right = UI.ITEM_SIDEBAR, rightCards = true, status = true })
  v.slots = slots
  local head, side = slots.header, slots.right
  -- the chart's controls (ranges; Line | Candles) belong to the chart: a row above it, spanning its width
  local bar = CreateFrame("Frame", nil, slots.main)
  bar:SetHeight(22)
  bar:SetPoint("TOPLEFT")
  bar:SetPoint("TOPRIGHT")
  v.chartBar = bar

  -- header: icon, name, subtitle; search box on the right
  local box
  box = W.Input(head, {
    width = UI.ITEM_SIDEBAR,
    hint = L["Search item, or Shift-click one"],
    onChange = function(text, _, user)
      if user then
        UI:SuggestItems(box, text)
      end
    end,
    onEnter = function(self)
      local id = ns.ItemCache.Learn(self:GetText())
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
  box:SetPoint("RIGHT", -2, 0)
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

  v.icon = head:CreateTexture(nil, "ARTWORK")
  v.icon:SetSize(32, 32)
  v.icon:SetPoint("TOPLEFT", 0, 0)
  v.name = W.Text(head, "GameFontNormalLarge")
  v.name:SetPoint("TOPLEFT", v.icon, "TOPRIGHT", 8, -2)
  v.name:SetPoint("RIGHT", box, "LEFT", -12, 0)
  v.name:SetWordWrap(false)
  v.nameHover = W.ItemHover(head, v.icon, v.name) -- the game's item tooltip over the icon and name
  -- subtitle: market and history (truncated; full text on hover)
  v.sub = W.Text(head, "GameFontDisableSmall")
  v.sub:SetPoint("BOTTOMLEFT", v.icon, "BOTTOMRIGHT", 8, 2)
  v.sub:SetPoint("RIGHT", box, "LEFT", -12, 0)
  v.sub:SetWordWrap(false)
  W.Truncated(v.sub)

  -- toolbar: ranges, Line | Candles
  local ranges, days = {}, {}
  for i, r in ipairs(RANGES) do
    ranges[i], days[r[1]] = { r[1], r[3] or r[1] }, r[2]
  end
  v.ranges = W.Segmented(bar, ranges, {
    minWidth = 40,
    onSelect = function(key)
      UI:SetRange(days[key], key)
    end,
  })
  v.ranges:SetPoint("LEFT", 0, 0)
  v.rangeButtons = v.ranges.buttons
  v.style = W.Segmented(bar, { { "line", L["Line"] }, { "candles", L["Candles"] } }, {
    minWidth = 48,
    onSelect = function(key)
      ns.Settings:Set("chartStyle", key)
      UI:DrawItemChart()
    end,
  })
  ns.Help.Explain(v.style, "candles") -- right-aligned, apart from the ranges (placed in SetCompact)
  v.style:SetPoint("RIGHT", 0, 0)

  -- compact: a bar under the chart with the sidebar's gist (market, change, signal, post at) and a Details button
  -- that opens the sidebar over the chart (the bar stays above it, so Details can close it again)
  local sumBar = CreateFrame("Frame", nil, slots.main, "BackdropTemplate")
  W.Skin(sumBar, W.COLORS.panel)
  sumBar:SetHeight(UI.ITEM_SUMMARY_H)
  sumBar:SetPoint("BOTTOMLEFT", 0, 0)
  sumBar:SetPoint("BOTTOMRIGHT", 0, 0)
  v.summaryBar = sumBar
  v.details = W.Button(sumBar, L["Details"], 70, 20, function()
    slots:ToggleDetails()
    v.details:SetSelected(slots.details)
  end)
  v.details:SetPoint("RIGHT", -4, 0)
  v.summary = W.Text(sumBar, "GameFontHighlightSmall")
  v.summary:SetPoint("LEFT", 10, 0)
  v.summary:SetPoint("RIGHT", v.details, "LEFT", -8, 0)
  v.summary:SetWordWrap(false)

  -- main: the chart fills it
  local holder = CreateFrame("Frame", nil, slots.main, "BackdropTemplate")
  W.Skin(holder, { 0.07, 0.08, 0.1, 1 }, W.COLORS.border)
  W.InnerGlow(holder)
  holder:SetPoint("TOPLEFT", 0, -(22 + UI.SLOT_GAP)) -- under the chart's controls
  holder:SetPoint("BOTTOMRIGHT") -- above the summary bar when narrow (SetCompact)
  self.chartHolder = holder
  local chart = LibStub("LibAMEChart-1.0"):New(holder, {
    panes = { { axis = "price", weight = 3 }, { axis = "volume", weight = 1 } },
  })
  chart.frame:SetPoint("TOPLEFT", 4, -4)
  chart.frame:SetPoint("BOTTOMRIGHT", -4, 4)
  chart:SetAxisFormatter("price", function(val)
    return W.Money(val, true)
  end)
  chart:SetAxisFormatter("volume", function(val)
    return W.Count(val)
  end)
  chart:SetHoverFormatter(function(_, x, rows)
    local lines = { W.Color("white", date(UI:ShowingIntraday() and "%a %b %d, %H:%M" or "%a %b %d, %Y", x)) }
    local c = rows.candles and UI.candles
    if c and rows.candles.x == x then
      local i = rows.candles.index
      if c.period > DAY then
        lines[1] =
          W.Color("white", date("%b %d", x - c.period / 2) .. " - " .. date("%b %d, %Y", x + c.period / 2 - DAY))
      end
      lines[#lines + 1] = { W.Dim(L["Open"]), W.Money(c.open[i]) }
      lines[#lines + 1] = { W.Dim(L["High"]), W.Money(c.high[i]) }
      lines[#lines + 1] = { W.Dim(L["Low (cheapest)"]), W.Money(c.low[i]) }
      lines[#lines + 1] = { W.Dim(L["Close"]), W.Money(c.close[i]) }
    end
    if rows.market and rows.market.x == x then
      lines[#lines + 1] = { W.Dim(L["Market"]), W.Money(rows.market.y) }
    end
    if rows.min and rows.min.x == x then
      lines[#lines + 1] = { W.Dim(L["Lowest"]), W.Money(rows.min.y) }
    end
    if rows.sma and rows.sma.x == x then
      lines[#lines + 1] = { W.Dim(L["7-day average"]), W.Money(rows.sma.y) }
    end
    if rows.qty and rows.qty.x == x then
      lines[#lines + 1] = { W.Dim(L["Supply"]), W.Count(rows.qty.y) }
    end
    return lines
  end)
  self.chart = chart
  -- legend: a box in the chart's top-left corner, one line per series; out of the way while you hover the plot
  local legend = CreateFrame("Frame", nil, holder, "BackdropTemplate")
  W.Skin(legend, { 0.06, 0.07, 0.09, 0.85 }, { 1, 1, 1, 0.08 })
  legend:SetPoint("TOPLEFT", 10, -10)
  legend:SetFrameLevel(chart.frame:GetFrameLevel() + 3)
  -- rows of swatch + label in two aligned columns; notes (no swatch) sit under the label column, dimmed.
  -- v.legend holds the same lines as text (hover checks and specs read it).
  v.legend = W.Text(legend, "GameFontHighlightSmall")
  v.legend:Hide()
  legend.rows = {}
  v.legendBox = legend
  -- narrow: the legend folds into a small "Legend" button in the corner (the chart is small); click to open it
  v.legendToggle = W.Button(holder, L["Legend"], 64, 18, function()
    v.legendOpen = not v.legendOpen
    v:ShowLegend()
  end)
  v.legendToggle:SetPoint("TOPLEFT", 10, -10)
  v.legendToggle:SetFrameLevel(chart.frame:GetFrameLevel() + 3)
  v.legendOpen = false
  function v:ShowLegend(hovering)
    local has = self.legend:GetText() ~= nil and self.legend:GetText() ~= ""
    local compact = slots.compact
    self.legendToggle:SetShown(compact and has and not hovering)
    self.legendBox:ClearAllPoints()
    if compact then
      self.legendBox:SetPoint("TOPLEFT", self.legendToggle, "BOTTOMLEFT", 0, -4)
    else
      self.legendBox:SetPoint("TOPLEFT", 10, -10)
    end
    self.legendBox:SetShown(has and not hovering and (not compact or self.legendOpen))
  end
  chart.frame:HookScript("OnEnter", function()
    v:ShowLegend(true)
  end)
  chart.frame:HookScript("OnLeave", function()
    v:ShowLegend(false)
  end)
  v.hint = W.Text(holder, "GameFontDisableSmall")
  v.hint:SetPoint("BOTTOMRIGHT", -70, 26)
  v.hint:SetJustifyH("RIGHT")
  v.hint:SetText(L["Scroll to zoom  ·  drag to pan  ·  double-click to reset"])
  v.hint:SetAlpha(0.6)

  -- right sidebar: a column of cards - the call and why, market price, key numbers, posting price, watch and alerts.
  -- v.cards keeps the old card order (label / value): market, lowest, average, 7d change, volatility, supply, signal
  local col = UI.Stack(side.content, 0)
  local cards = {}
  -- the call: "Verdict ... + BUY", a headline, and why in plain words
  local callCard = col:Card(0)
  local st = callCard.stack
  v.callRow = st:Pair(L["Verdict"], "signal")
  v.call = v.callRow.value
  v.callHead = st:Text("GameFontHighlight", 4)
  v.callWhy = st:Text("GameFontHighlightSmall", 6)
  v.callWhy:SetSpacing(3)
  -- market price, with the signal and phase beside the label
  local marketCard = col:Card()
  st = marketCard.stack
  cards[7] = st:Pair(L["Market price"], "signal")
  cards[1] = { label = cards[7].label, value = st:Text("GameFontHighlightLarge", 2) }
  v.change = st:Text("GameFontHighlightSmall", 2)
  v.confidence = st:Text("GameFontDisableSmall", 4)
  -- key numbers
  st = col:Card().stack
  cards[2] = st:Pair(L["Lowest listing"], "min")
  cards[3] = st:Pair(L["Average"], "avg")
  cards[4] = st:Pair(L["Volatility"], "vol30")
  cards[5] = st:Pair(L["Supply"], "qty")
  cards[6] = st:Pair(L["Sales per day"], "sellRate")
  v.cards = cards
  -- posting price (Pricing / Posting): "Post at (24 h listing) ... N ahead", Normal large, then Quick / Patient
  st = col:Card().stack
  v.postHeadRow = st:Pair(L["Post at"], "posting")
  v.postHead = v.postHeadRow.label
  v.post = st:Pair(L["Normal"], "posting", 4)
  v.post:SetHeight(20)
  v.post.label:SetFontObject("GameFontHighlight")
  v.post.value:SetFontObject("GameFontHighlight")
  v.post.text = v.post.value
  v.postNet = st:Text("GameFontDisableSmall", 2)
  v.postNet:SetJustifyH("RIGHT")
  v.postQuick = st:Pair(L["Quick"], "posting", 4)
  v.postQuick.label:SetFontObject("GameFontHighlightSmall")
  v.postPatient = st:Pair(L["Patient"], "posting")
  v.postPatient.label:SetFontObject("GameFontHighlightSmall")
  v.postAlt = st:Text("GameFontHighlightSmall", 4)
  v.postWarn = st:Text("GameFontHighlightSmall", 4)
  -- watch and alerts
  st = col:Card().stack
  local watchRow = st:Row(22)
  v.watch = W.Button(watchRow, L["Watch"], 100, 22, function(self)
    UI:WatchMenu(self, UI.itemID)
  end, { icon = 14 })
  v.watch:SetPoint("LEFT")
  v.watch:SetPoint("RIGHT")
  v.watch.star = v.watch.icon
  W.SetStar(v.watch.star, false)
  local function goldAlert(row, field, hint)
    return W.GoldInput(row, hint, function(g, user)
      if user and UI.itemID then
        ns.AME.watch:SetAlert(UI.itemID, { [field] = g and g * 10000 or false })
        UI:UpdateWatchControls(true)
      end
    end)
  end
  local alertRow = st:Row(20, 8)
  v.alertBelow = goldAlert(alertRow, "below", L["Alert below g"])
  v.alertBelow:SetPoint("LEFT")
  v.alertBelow:SetPoint("RIGHT", alertRow, "CENTER", -3, 0)
  v.alertAbove = goldAlert(alertRow, "above", L["Alert above g"])
  v.alertAbove:SetPoint("LEFT", alertRow, "CENTER", 3, 0)
  v.alertAbove:SetPoint("RIGHT")
  local signalRow = st:Row(16, 8)
  v.alertSignal = W.Check(signalRow, L["Alert on a buy or sell signal"], function(on)
    if UI.itemID then
      ns.AME.watch:SetAlert(UI.itemID, { signal = on })
      UI:UpdateWatchControls()
    end
  end)
  v.alertSignal:SetPoint("LEFT")
  -- hide from the Market, Arbitrage and Portfolio lists (or unhide)
  local hideRow = st:Row(20, 8)
  v.hide = W.Button(hideRow, L["Hide from lists"], 100, 20, function()
    if UI.itemID then
      UI:SetHidden(UI.itemID, not ns.AME.watch:IsHidden(UI.itemID))
    end
  end)
  v.hide:SetPoint("LEFT")
  v.hide:SetPoint("RIGHT")
  W.Tooltip(v.hide, function(tip)
    W.TipText(
      tip,
      L["Hidden items stay out of the Market, Arbitrage and Portfolio lists and their totals. AME keeps recording them; find them under Hidden on the Market tab."]
    )
  end)
  v.column = col
  -- cards size themselves to their text (which wraps with the sidebar's width)
  function v:FitCards()
    col:Height(side.content:GetWidth())
    side.pane:Measure()
  end
  side.content:HookScript("OnSizeChanged", function()
    v:FitCards()
  end)
  v.sidebar = side

  function v:SetCompact(on)
    slots:SetCompact(on)
    self.summaryBar:SetShown(on)
    self.details:SetSelected(false)
    self.summaryBar:SetFrameLevel((slots.right:GetFrameLevel() or 1) + 5) -- above the Details panel
    holder:ClearAllPoints()
    holder:SetPoint("TOPLEFT", 0, -(22 + UI.SLOT_GAP))
    holder:SetPoint("BOTTOMRIGHT", 0, on and (UI.ITEM_SUMMARY_H + 6) or 0)
    box:SetWidth(on and 200 or UI.ITEM_SIDEBAR)
    -- the Details panel stops above the summary bar
    slots.right:ClearAllPoints()
    slots.right:SetPoint("TOPRIGHT", 0, slots.top)
    slots.right:SetPoint("BOTTOMRIGHT", 0, slots.bottom + (on and (UI.ITEM_SUMMARY_H + 6) or 0))
    self.legendOpen = false
    self:ShowLegend()
    -- narrow: no 1Y range (All covers it); the subtitle gets its short form
    local b = self.rangeButtons
    b[5]:SetShown(not on)
    b[6]:ClearAllPoints()
    b[6]:SetPoint("LEFT", on and b[4] or b[5], "RIGHT", 4, 0)
    if on and UI.rangeKey == "1Y" then
      UI:SetRange(nil, "All")
    end
    if UI.itemID and UI.series and self:IsShown() then
      UI:ReloadItem()
    end
  end
  v:SetCompact(slots.compact)
  chart:SetMessage(L["Pick an item: search above, Shift-click one anywhere, or click a row on the Market tab."])
  self.itemView = v
  return v
end

function UI:SetRange(days, key)
  self.rangeDays, self.rangeKey = days, key
  self.itemView.ranges:Select(key, true)
  local wasIntraday = self.intradayMode
  self.intradayMode = INTRADAY[key] or false
  if self.intradayMode then
    self:LoadIntraday()
    return
  end
  self.chart:SetMessage(nil)
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

-- the scan-by-scan points for the item and range are loaded (and there are some): the chart plots them
function UI:ShowingIntraday()
  return self.intradayMode
      and self.intraday
      and self.intradayItem == self.itemID
      and (self.intradayDays or 0) >= (self.rangeDays or 0)
      and #self:IntradayPoints() > 0
    or false
end

-- the loaded points within the current range
function UI:IntradayPoints()
  local from = GetServerTime() - (self.rangeDays or 2) * DAY
  local out = {}
  for _, p in ipairs(self.intraday or {}) do
    if p.t >= from then
      out[#out + 1] = p
    end
  end
  return out
end

-- 2D: the last 2 days scan by scan (full scans and searches, from the scans kept in full). 7D: those plus the
-- hourly points before them; until they're loaded (or when there are none), its daily points.
function UI:LoadIntraday()
  local itemID, days = self.itemID, self.rangeDays or 2
  if not itemID then
    return
  end
  local function show()
    local now = GetServerTime()
    self:DrawItemChart()
    if self:ShowingIntraday() then
      self.chart:SetMessage(nil)
      self.chart:SetXRange(now - days * DAY, now + 3600)
    elseif days <= 2 then
      self.chart:SetMessage(L["No scans of this item in the last 2 days. Daily history is on the other ranges."])
    else -- the daily points
      self.chart:SetMessage(nil)
      self.chart:SetXRange(now - days * DAY, now + DAY)
    end
  end
  if self.intradayItem == itemID and self.intraday and (self.intradayDays or 0) >= days and not self.intradayStale then
    return show()
  end
  if days <= 2 and not self:ShowingIntraday() then
    self.chart:SetMessage(L["Loading recent scans..."])
  else
    show() -- what's there (the daily points, or the points being reloaded) while they load
  end
  ns.AME:WithStore("intraday-" .. itemID .. "-" .. days, self:ViewShard(), function(store)
    return store:Intraday(itemID, GetServerTime() - days * DAY)
  end, function(ok, points)
    if not ok then
      ns.AME:ReportError("recent scans", points)
    end
    if self.itemID ~= itemID or not self.intradayMode or (self.rangeDays or 2) > days then
      return
    end
    self.intraday, self.intradayItem, self.intradayDays = ok and points or {}, itemID, days
    self.intradayStale = nil
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
  local intraday = self:ShowingIntraday()
  local series, v, chart = intraday and self:IntradayPoints() or self.series, self.itemView, self.chart
  if not series or #series == 0 then
    chart:ClearSeries()
    v.legend:SetText("")
    v:ShowLegend()
    return
  end
  local candles = ns.Settings:Get("chartStyle") == "candles"
  v.style:Select(candles and "candles" or "line", true)
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
  local legend = {} -- { color, label } rows, or { note = text }
  chart:SetSeries("qty", { xs = xs, ys = qty, kind = "bars", axis = "volume", color = { 0.53, 0.53, 0.67, 1 } })
  if candles then
    local c
    if intraday then
      -- candles from the individual scans and hourly points (2 hours each over 2 days, 6 over 7)
      local hourly = {}
      for i, p in ipairs(series) do
        hourly[i] = { day = math.floor(p.t / 3600), market = p.market, min = p.min }
      end
      c = ns.Analytics.Candles(hourly, INTRADAY_CANDLE_HOURS[self.rangeDays] or 2, 3600)
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
    legend[#legend + 1] = { W.COLORS.up, L["Up"], kind = "square" }
    legend[#legend + 1] = { W.COLORS.down, L["Down"], kind = "square" }
    legend[#legend + 1] = { note = L["wick = cheapest listing"] }
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
    legend[#legend + 1] = { { 0.2, 0.8, 1 }, L["Market"], kind = "line" }
    legend[#legend + 1] = { { 0.4, 0.87, 0.47 }, L["Lowest"], kind = "line" }
  end
  if not intraday then -- a 7-point average of scans isn't a 7-day average
    legend[#legend + 1] = { { 1, 0.67, 0.2 }, L["7-day average"], kind = "line" }
  end
  legend[#legend + 1] = { { 0.53, 0.53, 0.67 }, L["Supply"], kind = "square" }
  if intraday then
    legend[#legend + 1] = { note = L["(each point is one scan)"] }
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
    legend[#legend + 1] = { UI.TRADE_COLORS.buy, L["You bought"], kind = "dot" }
    legend[#legend + 1] = { UI.TRADE_COLORS.sale, L["You sold"], kind = "dot" }
  end
  self:SetLegend(legend)
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

-- The chart's legend box: entries = { { color, label, kind = "line" | "dash" | "square" | "dot" }, ...,
-- { note = text } }. Every row is the same height; the swatch column and the label column line up; each swatch is
-- drawn like its series; notes are dim and start at the label column.
UI.LEGEND_ROW, UI.LEGEND_SWATCH = 14, 12
local SWATCH = { line = { 12, 3 }, dash = { 5, 2 }, square = { 8, 8 }, dot = { 9, 9 } }
function UI:SetLegend(entries)
  local v = self.itemView
  local box = v.legendBox
  local rows = box.rows
  local media = LibStub("LibAMEChart-1.0").MEDIA
  local lines, widest = {}, 0
  for i, e in ipairs(entries) do
    local r = rows[i]
    if not r then
      r = {}
      local cy = -8 - (i - 1) * UI.LEGEND_ROW - (UI.LEGEND_ROW - 2) / 2 -- the row's middle
      r.swatch = box:CreateTexture(nil, "OVERLAY")
      r.swatch:SetPoint("LEFT", box, "TOPLEFT", 8, cy)
      r.swatch2 = box:CreateTexture(nil, "OVERLAY") -- the dashed swatch's second dash
      r.swatch2:SetPoint("LEFT", box, "TOPLEFT", 15, cy)
      r.text = W.Text(box, "GameFontHighlightSmall")
      r.text:SetPoint("TOPLEFT", 8 + UI.LEGEND_SWATCH + 6, -8 - (i - 1) * UI.LEGEND_ROW)
      r.text:SetHeight(UI.LEGEND_ROW - 2)
      r.text:SetJustifyV("MIDDLE")
      rows[i] = r
    end
    r.swatch2:Hide()
    if e.note then
      r.swatch:Hide()
      r.text:SetText(W.Dim(e.note))
      lines[#lines + 1] = e.note
    else
      local c, kind = e[1], e.kind or "square"
      local size = SWATCH[kind] or SWATCH.square
      r.swatch:SetSize(size[1], size[2])
      if kind == "dot" and media then
        r.swatch:SetTexture(media .. "Dot")
        r.swatch:SetVertexColor(c[1], c[2], c[3], 1)
      else
        r.swatch:SetColorTexture(c[1], c[2], c[3], 1)
      end
      if kind == "dash" then
        r.swatch2:SetSize(size[1], size[2])
        r.swatch2:SetColorTexture(c[1], c[2], c[3], 1)
        r.swatch2:Show()
      end
      r.swatch:Show()
      r.text:SetText(e[2])
      lines[#lines + 1] = e[2]
    end
    r.text:Show()
    widest = math.max(widest, r.text:GetStringWidth() or 60)
  end
  for i = #entries + 1, #rows do
    rows[i].swatch:Hide()
    rows[i].swatch2:Hide()
    rows[i].text:Hide()
  end
  v.legend:SetText(table.concat(lines, "\n"))
  box:SetSize(8 + UI.LEGEND_SWATCH + 6 + widest + 10, 16 + #entries * UI.LEGEND_ROW - 2)
  v:ShowLegend()
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
-- the frames of the sell windows we know: the game's (SellAssist) and Auctionator's selling tab
UI.SELL_FRAMES = { "AuctionatorSellingFrame", "AuctionatorSellingTabFrame" } -- Auctionator's selling tab

function UI:Selling()
  if ns.SellAssist and ns.SellAssist:Active() then
    return true
  end
  for _, name in ipairs(UI.SELL_FRAMES) do
    local f = _G[name]
    if type(f) == "table" and f.IsVisible and f:IsVisible() then
      return true
    end
  end
  return false
end

function UI:FollowAuctionItem(itemID)
  -- search events name the plain item (Forever's item keys carry no suffix): when you're selling a variant of it, the
  -- sell slot knows which one
  if itemID and not ns.IsVariant(itemID) and ns.SellAssist then
    local ok, selling = pcall(ns.SellAssist.CurrentItem, ns.SellAssist)
    if ok and selling and ns.BaseID(selling) == itemID then
      itemID = selling
    end
  end
  if not (self.frame and self.frame:IsShown()) or itemID == self.itemID then
    return
  end
  -- on the Item tab: always follow; elsewhere: when you're putting it up for sale (Settings), not when buying
  if self.current ~= "item" and not (ns.Settings:Get("sellSwitchesTab") and self:Selling()) then
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
  self.intraday, self.intradayItem, self.intradayStale = nil, nil, nil
  local v = self.itemView

  local function header()
    local name, _, quality, icon = W.ItemInfo(itemID)
    v.icon:SetTexture(icon or 134400)
    v.name:SetText(W.QualityText(quality, name or ("item:" .. itemID)))
    v.nameHover:SetItem(itemID)
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
    return { series = store:Series(itemID), latest = store:Latest(itemID), mixed = store:Mixed(itemID) }
  end, function(ok, res)
    if self.itemID ~= itemID then
      return
    end
    if not ok then
      self.chart:SetMessage(L["Could not load history: %s"]:format(tostring(res)))
      return
    end
    self:FillItem(itemID, res.series, res.latest, res.mixed)
  end)
end

-- reload the item on screen without clearing it first (no "loading" flash)
function UI:ReloadItem()
  local itemID = self.itemID
  if not itemID then
    return
  end
  self.intradayStale = true -- reloaded behind the current points (no flash back to daily)
  ns.AME:WithStore("chart-" .. itemID, self:ViewShard(), function(store)
    return { series = store:Series(itemID), latest = store:Latest(itemID), mixed = store:Mixed(itemID) }
  end, function(ok, res)
    if ok and self.itemID == itemID then
      self:FillItem(itemID, res.series, res.latest, res.mixed)
    end
  end)
end

-- mixed: the item has random suffixes, and each has its own history (see Store:Mixed)
function UI:FillItem(_, series, latest, mixed)
  local v = self.itemView
  if #series == 0 then
    self.series = nil
    self.chart:SetMessage(
      mixed
          and L['Each suffix of this item ("of the Monkey", "of Magic"...) has its own prices. Shift-click one, or search its full name.']
        or L["No history for this item yet. Search for it at the auction house, or run a full scan."]
    )
    v.sub:SetText(ns.ShardLabel(self:ViewShard()))
    for _, c in ipairs(v.cards) do
      c.value:SetText("-")
    end
    v.change:SetText("")
    v.confidence:SetText("")
    self:FillVerdict(nil)
    v.slots.status:SetText("")
    self.itemFacts = {}
    self:UpdatePostAdvice()
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
  cards[4].value:SetText(s.vol30 and ("%.1f%%"):format(s.vol30 * 100) or "-")
  -- supply with its weekly trend: rising supply is bad for sellers (red), falling good (green)
  local trend = s.supplyTrend30 and s.supplyTrend30 * 7
  local trendText = ""
  if trend and math.abs(trend) >= 0.005 then
    trendText = "  " .. W.Color(trend > 0 and "bad" or "good", L["%+d%%/wk"]:format(math.floor(trend * 100 + 0.5)))
  end
  cards[5].value:SetText(W.Count(latest and latest.qty or s.qty or 0) .. trendText)
  cards[6].value:SetText(s.sellRate and ("~" .. W.Count(s.sellRate)) or W.NONE)
  local phaseText = s.phase and W.Dim(ns.Analytics.PHASE_LABEL[s.phase]:lower()) or ""
  if s.signal and s.signal ~= "none" then
    cards[7].value:SetText(W.SignalGlyph(s.signal) .. (phaseText ~= "" and W.Dim("  ·  ") .. phaseText or ""))
  else
    cards[7].value:SetText(phaseText)
  end
  local avg = s["avg" .. avgDays()] or s.avg30
  local market = latest and latest.market or s.market
  local change = market and avg and avg > 0 and market / avg - 1 or nil
  local changeText = ""
  if change then
    local pct = math.floor(math.abs(change) * 100 + 0.5)
    if pct == 0 then
      changeText = W.Dim(L["right at its %d-day average"]:format(avgDays()))
    else
      changeText = W.Color(
        change > 0 and "good" or "bad",
        (change > 0 and L["%d%% above its %d-day average"] or L["%d%% below its %d-day average"]):format(pct, avgDays())
      )
    end
  end
  v.change:SetText(changeText)
  local today = math.floor(GetServerTime() / DAY)
  local level = ns.Analytics.Confidence(s, today)
  local scans = L["%d scans this week"]:format(s.scans7 or 0)
  v.confidence:SetText(
    L["Confidence %s %s"]:format(W.Confidence(level), UI.CONFIDENCE_WORD[level] or "") .. "  ·  " .. scans
  )
  -- subtitle: category · market · pips + scans · last seen
  local info = ns.ItemCache.Get(self.itemID)
  local category = info and info.subClassID and ns.ItemCache.SubClassName(info.classID, info.subClassID)
  local sub = {}
  if category then
    sub[#sub + 1] = category
  end
  sub[#sub + 1] = ns.ShardLabel(self:ViewShard())
  if not self.compact then
    sub[#sub + 1] = L["%d days of history"]:format(#series)
  end
  sub[#sub + 1] = W.Confidence(level) .. " " .. scans
  if latest then
    local ago = W.Ago(latest.t, GetServerTime())
    sub[#sub + 1] = self.compact and L["seen %s"]:format(ago)
      or L["last seen %s (%s)"]:format(date("%H:%M", latest.t), ago)
  end
  v.sub:SetText(table.concat(sub, "  ·  "))
  local status = { self:PriceSource(latest) }
  if dropped > 0 then
    status[#status + 1] = W.Color(
      "warn",
      (dropped == 1 and L["%d outlier price ignored"] or L["%d outlier prices ignored"]):format(dropped)
    )
  end
  v.slots.status:SetText(table.concat(status, "  ·  "))
  self.itemFacts = { market = market, change = change, signal = s.signal }
  -- the same call as the Market tab (the index knows the vendor price check); else the series' own
  local index = self:ViewIndex()
  local indexed = index and index.items[self.itemID]
  self:FillVerdict(s, {
    signal = indexed and indexed.signal or s.signal,
    vendorPrice = indexed and indexed.vendorPrice,
    vendorNet = indexed and indexed.vendorNet,
    market = market,
    avg = avg,
    avgDays = avgDays(),
    today = math.floor(GetServerTime() / DAY),
  })
  self.itemFacts.signal = indexed and indexed.signal or s.signal
  self:UpdatePostAdvice()
end

-- The verdict in plain words. Pure: s = the item's summary, ctx = { signal, market, avg, vendorPrice, vendorNet,
-- today }. Returns signal, headline, { sentences }.
local PHASE_WHY = {
  shortage = L["Supply shrinking, price rising: a shortage."],
  demand = L["Rising on steady supply: strong demand."],
  piling = L["Sellers piling in at high prices: a drop often follows."],
  tightening = L["Supply shrinking at a steady price: may start to rise."],
  balanced = L["Price and supply steady."],
  pressure = L["Supply building at a steady price: pressure on the price."],
  withdrawing = L["Fewer sellers, yet the price falls: may be near the bottom."],
  weak = L["Falling on steady supply: weak demand."],
  dumping = L["Sellers dumping: price falling, supply growing."],
}
local HEADLINE = {
  buy = L["Cheaper than usual"],
  sell = L["Pricier than usual"],
  hold = L["A normal price"],
  wait = L["Cheap, but still falling"],
  vendor = L["A vendor pays more"],
}
local ACTION = {
  buy = L["Good time to buy."],
  sell = L["Good time to post."],
  hold = L["No edge: buy only what you need."],
  wait = L["Wait for it to settle."],
  vendor = L["Vendor it instead."],
}

function UI.Verdict(s, ctx)
  ctx = ctx or {}
  if not s then
    return "none", L["No call yet"], { L["No history at this auction house yet."] }
  end
  local signal = ctx.signal or s.signal or "none"
  local why = {}
  local market, avg = ctx.market or s.market, ctx.avg or s.avg30
  local days = ctx.avgDays or 30
  if signal == "vendor" and ctx.vendorPrice then
    why[#why + 1] = L["Posting nets ~%s after cut and deposit; a vendor pays %s."]:format(
      W.Money(ctx.vendorNet),
      W.Money(ctx.vendorPrice)
    )
  elseif market and avg and avg > 0 then
    local d = market / avg - 1
    local moves = s.vol30 and math.floor(s.vol30 * 100 + 0.5)
    local base
    if math.abs(d) < 0.03 then
      base = L["Right at its %d-day average"]:format(days)
    else
      local pct = math.floor(math.abs(d) * 100 + 0.5)
      base = (d > 0 and L["%d%% above its %d-day average (%s)"] or L["%d%% below its %d-day average (%s)"]):format(
        pct,
        days,
        W.Money(avg)
      )
    end
    if moves and moves > 0 and signal ~= "none" then
      base = base .. L["; it usually moves ~%d%% a day"]:format(moves)
    end
    why[#why + 1] = base .. "."
  end
  if s.phase and PHASE_WHY[s.phase] then
    why[#why + 1] = PHASE_WHY[s.phase]
  end
  if s.sellRate then
    if s.sellRate >= 20 then
      why[#why + 1] = L["Sells fast: ~%s a day."]:format(W.Count(s.sellRate))
    elseif s.sellRate >= 1 then
      why[#why + 1] = L["Sells ~%s a day."]:format(W.Count(s.sellRate))
    else
      why[#why + 1] = L["Rarely sells (under 1 a day)."]
    end
  end
  if signal == "none" then
    why[#why + 1] = L["Needs %d days of history (has %d)."]:format(ns.Analytics.MIN_DAYS, s.days or 0)
  end
  local level = ns.Analytics.Confidence(s, ctx.today)
  if level == "low" then
    why[#why + 1] = L["Few recent scans: scan again."]
  else
    why[#why + 1] = L["From %d scans this week."]:format(s.scans7 or 0)
  end
  if ACTION[signal] then
    why[#why + 1] = ACTION[signal]
  end
  return signal, HEADLINE[signal] or L["No call yet"], why
end

function UI:FillVerdict(s, ctx)
  local v = self.itemView
  local signal, head, why = UI.Verdict(s, ctx)
  v.call:SetText(signal ~= "none" and W.SignalGlyph(signal) or W.Dim(L["No call yet"]))
  v.callRow.label:SetText(L["Verdict"])
  v.callHead:SetText(signal ~= "none" and head or "")
  v.callWhy:SetText(table.concat(why, " "))
  v:FitCards()
end

-- the compact layout's one-line gist of the sidebar
function UI:UpdateItemSummary()
  local v, facts = self.itemView, self.itemFacts or {}
  local parts =
    { W.Dim(L["Market"]) .. " " .. W.Money(facts.market) .. (facts.change and " " .. W.Percent(facts.change, 0) or "") }
  if facts.signal and facts.signal ~= "none" then
    parts[#parts + 1] = W.SignalGlyph(facts.signal)
  end
  if facts.post then
    parts[#parts + 1] = W.Dim(L["Post at"])
      .. " "
      .. W.Money(facts.post)
      .. (facts.postHours and " " .. W.Dim(W.Hours(facts.postHours)) or "")
  end
  v.summary:SetText(table.concat(parts, "     "))
end

-- what to post the viewed item at (one unit, your usual listing time) at the viewed auction house
function UI:UpdatePostAdvice()
  local v = self.itemView
  if not (v and v.post and self.itemID) then
    return
  end
  local hours = ns.Settings:Get("listingHours")
  local shard = self:ViewShard()
  local ok, advice = pcall(ns.Posting.Suggest, ns.Posting, shard, self.itemID, 1, hours)
  if not ok then
    ns.AME:ReportError("posting price", advice)
    advice = nil
  end
  v.postHead:SetText(L["Post at"] .. "  " .. W.Dim("(" .. L["%d h listing"]:format(hours or 24) .. ")"))
  v.postHeadRow.value:SetText("")
  self.itemFacts = self.itemFacts or {}
  self.itemFacts.post = advice and advice.normal.price
  self.itemFacts.postHours = advice and advice.normal.hours
  if not advice then
    v.post.text:SetText(W.Dim(L["not enough data yet"]))
    v.postNet:SetText(L["Search for it at the auction house, or run a full scan."])
    v.postQuick.value:SetText(W.NONE)
    v.postPatient.value:SetText(W.NONE)
    v.postAlt:SetText("")
    v.postWarn:SetText("")
  else
    local n = advice.normal
    v.post.text:SetText(W.Money(n.price))
    v.postHeadRow.value:SetText(W.Dim(L["%d ahead"]:format(n.ahead)))
    local function choice(c)
      return W.Money(c.price) .. W.Dim("  ·  " .. W.Hours(c.hours))
    end
    v.postQuick.value:SetText(choice(advice.quick))
    v.postPatient.value:SetText(choice(advice.patient))
    local _, house = ns.SplitShard(shard)
    local cut = ns.Settings:AuctionCut(house or ns.AME:CurrentHouse())
    local net = n.price * (1 - (cut or 0)) - (advice.deposit or 0) / (advice.qty or 1)
    v.postNet:SetText(
      L["sells in %s  ·  you net %s after the %d%% cut"]:format(
        W.Hours(n.hours),
        W.Money(net),
        math.floor((cut or 0) * 100 + 0.5)
      )
    )
    if advice.quick.price == advice.patient.price then
      local onlyLowest = n.ahead == 0 and (advice.book and #advice.book.prices or 0) > 0
      v.postAlt:SetText(
        onlyLowest and W.Dim(L["more is listed than sells in one listing time: only the lowest price sells soon"]) or ""
      )
    else
      v.postAlt:SetText("")
    end
    local info = ns.ItemCache.Get(self.itemID)
    local vendor = info and info.sellPrice
    if vendor and vendor > 0 and net < vendor then
      v.postWarn:SetText(W.Color("bad", L["Vendor it: a vendor pays %s"]:format(W.Money(vendor))))
    elseif advice.hold then
      v.postWarn:SetText(W.Color("bad", L["unlikely to sell soon: consider holding"]))
    elseif advice.cheap then
      v.postWarn:SetText(W.Color("warn", L["well below its usual price"]))
    else
      v.postWarn:SetText("")
    end
  end
  self:UpdateItemSummary()
  v:FitCards()
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
  local id = ns.ItemCache.Learn(link)
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
