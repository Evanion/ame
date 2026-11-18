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

-- Layout (UI.Slots): header (icon, name, subtitle, search box), toolbar (ranges, Line | Candles; compact: summary and
-- Details), main (the chart, with its legend as an overlay), right sidebar (verdict, key numbers, post at, watch and
-- alerts), status line (data confidence, last seen, outliers).
UI.ITEM_SIDEBAR = 280

function UI:CreateItemView(parent)
  local v = contentArea(parent)
  local slots = UI.Slots(v, { header = 34, toolbar = 22, right = UI.ITEM_SIDEBAR, rightCards = true, status = true })
  v.slots = slots
  local head, bar, side = slots.header, slots.toolbar, slots.right

  -- header: icon, name, subtitle; search box on the right
  local box
  box = W.Input(head, {
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

  v.icon = head:CreateTexture(nil, "ARTWORK")
  v.icon:SetSize(32, 32)
  v.icon:SetPoint("TOPLEFT", 0, 0)
  v.name = W.Text(head, "GameFontNormalLarge")
  v.name:SetPoint("TOPLEFT", v.icon, "TOPRIGHT", 8, -2)
  v.name:SetPoint("RIGHT", box, "LEFT", -12, 0)
  v.name:SetWordWrap(false)
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
  -- compact: the sidebar's gist on the toolbar, and a button for the whole sidebar
  v.details = W.Button(bar, L["Details"], 64, 20, function()
    slots:ToggleDetails()
    v.details:SetSelected(slots.details)
  end)
  v.details:SetPoint("RIGHT", 0, 0)
  v.summary = W.Text(bar, "GameFontHighlightSmall", "RIGHT")
  v.summary:SetPoint("LEFT", v.ranges, "RIGHT", 12, 0)
  v.summary:SetPoint("RIGHT", v.style, "LEFT", -12, 0)
  v.summary:SetWordWrap(false)

  -- main: the chart fills it
  local holder = CreateFrame("Frame", nil, slots.main, "BackdropTemplate")
  W.Skin(holder, { 0.07, 0.08, 0.1, 1 }, W.COLORS.border)
  W.InnerGlow(holder)
  holder:SetAllPoints()
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
      lines[#lines + 1] = L["Supply"] .. "  " .. W.Count(rows.qty.y)
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
  chart.frame:HookScript("OnEnter", function()
    legend:Hide()
  end)
  chart.frame:HookScript("OnLeave", function()
    legend:SetShown(v.legend:GetText() ~= nil and v.legend:GetText() ~= "")
  end)
  v.hint = W.Text(holder, "GameFontDisableSmall")
  v.hint:SetPoint("BOTTOMLEFT", 12, 26)
  v.hint:SetText(L["Scroll to zoom  ·  drag to pan  ·  double-click to reset"])
  v.hint:SetAlpha(0.6)

  -- right sidebar: a column of cards - the call and why, market price, key numbers, posting price, watch and alerts.
  -- v.cards keeps the old card order (label / value): market, lowest, average, 7d change, volatility, supply, signal
  local col = UI.Stack(side.content, 0)
  local cards = {}
  -- the call: Buy / Hold / Sell / Wait / Vendor, a headline, and why in plain words
  local callCard = col:Card(0)
  local st = callCard.stack
  v.call = st:Text("GameFontNormalHuge")
  v.call:SetWordWrap(false)
  v.callHead = st:Text("GameFontHighlight", 2)
  v.callWhy = st:Text("GameFontHighlightSmall", 6)
  v.callWhy:SetSpacing(3)
  -- market price, with the signal and phase beside the label
  local marketCard = col:Card()
  st = marketCard.stack
  cards[7] = st:Pair(L["Market price"], "signal")
  cards[1] = { label = cards[7].label, value = st:Text("GameFontHighlightLarge", 2) }
  v.change = st:Text("GameFontHighlightSmall", 2)
  v.confidence = st:Pair(L["Data"], "confidence", 4)
  -- key numbers
  st = col:Card().stack
  cards[2] = st:Pair(L["Lowest"], "min")
  cards[3] = st:Pair(L["Average"], "avg")
  cards[4] = st:Pair(L["7d change"], "change7")
  cards[5] = st:Pair(L["Volatility"], "vol30")
  cards[6] = st:Pair(L["Supply  ·  sales/day"], "sellRate")
  v.cards = cards
  -- posting price (Pricing / Posting): "Post at (24 h listing) ... N ahead", Normal large, then Quick / Patient
  st = col:Card().stack
  v.postHeadRow = st:Pair(L["Post at"], "posting")
  v.postHead = v.postHeadRow.label
  v.post = st:Pair(L["Normal"], "posting", 4)
  v.post:SetHeight(20)
  v.post.label:SetFontObject("GameFontHighlight")
  v.post.value:SetFontObject("GameFontHighlightLarge")
  v.post.text = v.post.value
  v.postNet = st:Text("GameFontDisableSmall", 2)
  v.postNet:SetJustifyH("RIGHT")
  v.postQuick = st:Pair(L["Quick"], "posting", 4)
  v.postPatient = st:Pair(L["Patient"], "posting")
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
  v.column = col
  -- cards size themselves to their text (which wraps with the sidebar's width)
  function v:FitCards()
    col:Height()
    side.pane:Measure()
  end
  side.content:HookScript("OnSizeChanged", function()
    v:FitCards()
  end)
  v.sidebar = side

  function v:SetCompact(on)
    slots:SetCompact(on)
    self.summary:SetShown(on)
    self.details:SetShown(on)
    self.details:SetSelected(false)
    -- Line | Candles at the right end; in compact, left of the Details button
    self.style:ClearAllPoints()
    if on then
      self.style:SetPoint("RIGHT", self.details, "LEFT", -8, 0)
    else
      self.style:SetPoint("RIGHT", 0, 0)
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
    v.legend:SetText("")
    v.legendBox:Hide()
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
    legend[#legend + 1] = { W.COLORS.up, L["up"] }
    legend[#legend + 1] = { W.COLORS.down, L["down"] }
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
    legend[#legend + 1] = { { 0.2, 0.8, 1 }, L["market"] }
    legend[#legend + 1] = { { 0.4, 0.87, 0.47 }, L["lowest"] }
  end
  if not intraday then -- a 7-point average of scans isn't a 7-day average
    legend[#legend + 1] = { { 1, 0.67, 0.2 }, L["7d average"] }
  end
  legend[#legend + 1] = { { 0.53, 0.53, 0.67 }, L["supply"] }
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
    legend[#legend + 1] = { UI.TRADE_COLORS.buy, L["you bought"] }
    legend[#legend + 1] = { UI.TRADE_COLORS.sale, L["you sold"] }
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

-- The chart's legend box: entries = { { color, label }, ..., { note = text } }. Every row is the same height; the
-- swatch column and the label column line up; notes are dim and start at the label column.
UI.LEGEND_ROW, UI.LEGEND_SWATCH = 14, 8
function UI:SetLegend(entries)
  local v = self.itemView
  local box = v.legendBox
  local rows = box.rows
  local lines, widest = {}, 0
  for i, e in ipairs(entries) do
    local r = rows[i]
    if not r then
      r = {}
      r.swatch = box:CreateTexture(nil, "OVERLAY")
      r.swatch:SetSize(UI.LEGEND_SWATCH, UI.LEGEND_SWATCH)
      r.swatch:SetPoint("TOPLEFT", 8, -8 - (i - 1) * UI.LEGEND_ROW - 2)
      r.text = W.Text(box, "GameFontHighlightSmall")
      r.text:SetPoint("TOPLEFT", 8 + UI.LEGEND_SWATCH + 6, -8 - (i - 1) * UI.LEGEND_ROW)
      r.text:SetHeight(UI.LEGEND_ROW - 2)
      r.text:SetJustifyV("MIDDLE")
      rows[i] = r
    end
    if e.note then
      r.swatch:Hide()
      r.text:SetText(W.Dim(e.note))
      lines[#lines + 1] = e.note
    else
      local c = e[1]
      r.swatch:SetColorTexture(c[1], c[2], c[3], 1)
      r.swatch:Show()
      r.text:SetText(e[2])
      lines[#lines + 1] = e[2]
    end
    r.text:Show()
    widest = math.max(widest, r.text:GetStringWidth() or 60)
  end
  for i = #entries + 1, #rows do
    rows[i].swatch:Hide()
    rows[i].text:Hide()
  end
  v.legend:SetText(table.concat(lines, "\n"))
  box:SetSize(8 + UI.LEGEND_SWATCH + 6 + widest + 10, 16 + #entries * UI.LEGEND_ROW - 2)
  box:SetShown(#entries > 0)
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
UI.SELL_FRAMES = { "AuctionatorSellingFrame", "AuctionatorSellingTabFrame" }

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
    v.change:SetText("")
    v.confidence.value:SetText("-")
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
  cards[4].value:SetText(W.Percent(s.change7))
  cards[5].value:SetText(s.vol30 and ("%.1f%%"):format(s.vol30 * 100) or "-")
  cards[6].value:SetText(
    W.Count(latest and latest.qty or s.qty or 0)
      .. " "
      .. W.Percent(s.supplyTrend30 and s.supplyTrend30 * 7, 0)
      .. (s.sellRate and "  " .. W.Dim(W.Rate(s.sellRate)) or "")
  )
  cards[7].value:SetText(
    W.SignalGlyph(s.signal) .. (s.phase and W.Dim("  ·  " .. ns.Analytics.PHASE_LABEL[s.phase]:lower()) or "")
  )
  local avg = s["avg" .. avgDays()] or s.avg30
  local market = latest and latest.market or s.market
  local change = market and avg and avg > 0 and market / avg - 1 or nil
  v.change:SetText(change and L["%s vs the %d-day average"]:format(W.Percent(change), avgDays()) or "")
  v.confidence.value:SetText(
    W.Confidence(ns.Analytics.Confidence(s, math.floor(GetServerTime() / DAY)))
      .. "  "
      .. L["%d scans in 7 days"]:format(s.scans7 or 0)
  )
  v.sub:SetText(L["%s  ·  %d days of history"]:format(ns.ShardLabel(self:ViewShard()), #series))
  local status = { ns.ShardLabel(self:ViewShard()) }
  if latest then
    status[#status + 1] = L["last seen %s"]:format(date("%b %d %H:%M", latest.t))
  end
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
    avg = s.avg30,
    today = math.floor(GetServerTime() / DAY),
  })
  self.itemFacts.signal = indexed and indexed.signal or s.signal
  self:UpdatePostAdvice()
end

-- The verdict in plain words. Pure: s = the item's summary, ctx = { signal, market, avg, vendorPrice, vendorNet,
-- today }. Returns signal, headline, { sentences }.
local PHASE_WHY = {
  shortage = L["Supply is shrinking while the price rises: there's a shortage."],
  demand = L["The price rises on steady supply: demand is strong."],
  piling = L["Sellers are piling in at these higher prices: that often comes before a drop."],
  tightening = L["Supply is shrinking at a steady price: it may start to rise."],
  balanced = L["Price and supply are both steady."],
  pressure = L["Supply is building up at a steady price: pressure on the price."],
  withdrawing = L["The price falls while sellers pull out: it may be near the bottom."],
  weak = L["The price falls on steady supply: demand is weak."],
  dumping = L["Sellers are dumping: the price falls while supply grows."],
}
local HEADLINE = {
  buy = L["Cheaper than usual"],
  sell = L["Pricier than usual"],
  hold = L["A normal price"],
  wait = L["Cheap, but still falling"],
  vendor = L["A vendor pays more"],
}
local ACTION = {
  buy = L["A good time to buy, if you'll use it or can resell it."],
  sell = L["If you hold some, a good time to post (see Post at below)."],
  hold = L["No edge either way: keep what you have, and buy only what you need."],
  wait = L["Wait for the price to settle before buying."],
  vendor = L["Sell it to a vendor instead of posting it."],
}

function UI.Verdict(s, ctx)
  ctx = ctx or {}
  if not s then
    return "none", L["No call yet"], { L["There's no history for this item at this auction house yet."] }
  end
  local signal = ctx.signal or s.signal or "none"
  local why = {}
  local market, avg = ctx.market or s.market, ctx.avg or s.avg30
  if signal == "vendor" and ctx.vendorPrice then
    why[#why + 1] = L["After the auction house cut and the deposit, a listing nets about %s; a vendor pays %s."]:format(
      W.Money(ctx.vendorNet),
      W.Money(ctx.vendorPrice)
    )
  elseif market and avg and avg > 0 then
    local d = market / avg - 1
    local moves = s.vol30 and math.floor(s.vol30 * 100 + 0.5)
    local base
    if math.abs(d) < 0.03 then
      base = L["At %s it's right at its 30-day average."]:format(W.Money(market))
    elseif d > 0 then
      base = L["At %s it's %d%% above its 30-day average of %s."]:format(
        W.Money(market),
        math.floor(d * 100 + 0.5),
        W.Money(avg)
      )
    else
      base = L["At %s it's %d%% below its 30-day average of %s."]:format(
        W.Money(market),
        math.floor(-d * 100 + 0.5),
        W.Money(avg)
      )
    end
    why[#why + 1] = base
    if moves and moves > 0 and signal ~= "none" then
      why[#why + 1] = (
        (signal == "hold") and L["Its price usually moves about %d%% a day, so that's within its normal range."]
        or L["Its price usually moves only about %d%% a day, so that's unusual."]
      ):format(moves)
    end
  end
  if s.phase and PHASE_WHY[s.phase] then
    why[#why + 1] = PHASE_WHY[s.phase]
  end
  if s.sellRate then
    if s.sellRate >= 20 then
      why[#why + 1] = L["About %s sell a day, so it sells quickly."]:format(W.Count(s.sellRate))
    elseif s.sellRate >= 1 then
      why[#why + 1] = L["About %s sell a day."]:format(W.Count(s.sellRate))
    else
      why[#why + 1] = L["It rarely sells (under one a day): selling takes time."]
    end
  end
  if signal == "none" then
    why[#why + 1] = L["It needs %d days of history for a call; it has %d."]:format(ns.Analytics.MIN_DAYS, s.days or 0)
  end
  local level = ns.Analytics.Confidence(s, ctx.today)
  if level == "low" then
    why[#why + 1] = L["Few recent scans: treat this with care, and scan again."]
  else
    why[#why + 1] = L["Based on %d scans in the last 7 days."]:format(s.scans7 or 0)
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
  v.callHead:SetText(signal ~= "none" and head or "")
  v.callWhy:SetText(table.concat(why, " "))
  v:FitCards()
end

-- the compact layout's one-line gist of the sidebar
function UI:UpdateItemSummary()
  local v, facts = self.itemView, self.itemFacts or {}
  local parts = { L["Market"] .. " " .. W.Money(facts.market) }
  if facts.change then
    parts[#parts + 1] = W.Percent(facts.change)
  end
  if facts.signal then
    parts[#parts + 1] = W.Signal(facts.signal)
  end
  if facts.post then
    parts[#parts + 1] = L["Post at"] .. " " .. W.Money(facts.post)
  end
  v.summary:SetText(table.concat(parts, "  ·  "))
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
  v.postHead:SetText(L["Post at"] .. "  " .. W.Dim("(" .. L["%dh listing"]:format(hours or 24) .. ")"))
  v.postHeadRow.value:SetText("")
  self.itemFacts = self.itemFacts or {}
  self.itemFacts.post = advice and advice.normal.price
  if not advice then
    v.post.text:SetText(W.Dim(L["not enough data yet"]))
    v.postNet:SetText(L["Search for it at the auction house, or run a full scan."])
    v.postQuick.value:SetText(W.NONE)
    v.postPatient.value:SetText(W.NONE)
    v.postAlt:SetText("")
    v.postWarn:SetText("")
  else
    local n = advice.normal
    v.post.text:SetText(W.Money(n.price) .. "  " .. W.Confidence(advice.confidence))
    v.postHeadRow.value:SetText(L["%d ahead"]:format(n.ahead))
    v.postQuick.value:SetText(W.PostChoice(advice.quick))
    v.postPatient.value:SetText(W.PostChoice(advice.patient))
    local _, house = ns.SplitShard(shard)
    local cut = ns.Settings:AuctionCut(house or ns.AME:CurrentHouse())
    local net = n.price * (1 - (cut or 0)) - (advice.deposit or 0) / (advice.qty or 1)
    v.postNet:SetText(L["sells in %s  ·  you get %s after the cut"]:format(W.Hours(n.hours), W.Money(net)))
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
