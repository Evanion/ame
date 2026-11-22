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

---------------------------------------------------------------------------------------------------------------------
-- Item view

-- Layout (UI.Slots): header (icon, name, subtitle, search box), toolbar (ranges, Line | Candles; compact: summary and
-- Details), main (the chart, with its legend as an overlay), right sidebar (verdict, key numbers, post at, watch and
-- alerts), status line (data confidence, last seen, outliers).
UI.ITEM_SIDEBAR = UI.SIDE_PANEL_W
UI.ITEM_SUMMARY_H = 28 -- the compact layout's summary bar under the chart
UI.CONFIDENCE_WORD = { high = L["high"], medium = L["medium"], low = L["low"] }

-- a small up or down triangle in a text role's colour, before a change (the game's font has no triangle glyphs)
local function arrow(up, tone)
  return W.SignalIcon(up and "buy" or "sell", 9, ns.HEX[tone]) .. " "
end

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
      UI.rangePicked = true -- yours from now on; until then each item opens on 2D or 7D (FillItem)
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
  v.details = W.Button(sumBar, L["Details"] .. W.ARROW_DOWN, 76, 20, function()
    slots:ToggleDetails()
    v.details:SetSelected(slots.details)
  end)
  v.details:SetPoint("RIGHT", -4, 0)
  -- the pieces, left to right: the market price and its change, the signal's badge, what to post at
  v.summaryMarket = W.Text(sumBar, "GameFontHighlightSmall")
  v.summaryMarket:SetPoint("LEFT", 10, 0)
  v.summaryMarket:SetWordWrap(false)
  v.summaryBadge = W.SignalBadge(sumBar)
  v.summaryBadge:SetPoint("LEFT", v.summaryMarket, "RIGHT", 12, 0)
  v.summaryPost = W.Text(sumBar, "GameFontHighlightSmall")
  v.summaryPost:SetPoint("RIGHT", v.details, "LEFT", -8, 0)
  v.summaryPost:SetWordWrap(false)

  -- main: the chart fills it
  local holder = CreateFrame("Frame", nil, slots.main, "BackdropTemplate")
  W.Skin(holder, W.COLORS.chart.bg, W.COLORS.border)
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
    -- the title: the slot's span (every series' values in it are merged into what follows)
    local size = UI.slotSize or DAY
    local from, to = x - size / 2, x + size / 2
    local title
    if size < DAY then
      title = date("%a %b %d, %H:%M", from) .. " - " .. date("%H:%M", to)
    elseif size == DAY then
      title = date("%a %b %d, %Y", from)
    else
      title = date("%b %d", from) .. " - " .. date("%b %d, %Y", to - DAY)
    end
    local lines = { W.Color("white", title) }
    local c = rows.candles and UI.candles
    if c and rows.candles.x == x then
      local i = rows.candles.index
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
    if rows.fast and rows.fast.x == x then
      lines[#lines + 1] = { W.Dim(UI.fastLabel or ""), W.Money(rows.fast.y) }
    end
    if rows.qty and rows.qty.x == x then
      lines[#lines + 1] = { W.Dim(L["Supply"]), W.Count(rows.qty.y) }
    end
    if UI.vendorLine then
      lines[#lines + 1] = { W.Dim(L["Vendor price"]), W.Money(UI.vendorLine) }
    end
    return lines
  end)
  self.chart = chart
  -- zooming in or out far enough changes the slot size: the series are merged into the new slots
  if chart.RegisterCallback then
    chart.RegisterCallback(UI, "RangeChanged", function()
      local e = UI.slotExtent
      if UI.series and e and UI:ChartSlotSize(e[1], e[2], e.intraday) ~= UI.slotSize then
        UI:DrawItemChart()
      end
    end)
  end
  -- legend: a box in the chart's top-left corner, one line per series; out of the way while you hover the plot
  local legend = CreateFrame("Frame", nil, holder, "BackdropTemplate")
  W.Skin(legend, W.COLORS.chart.legendBg, W.COLORS.chart.legendBorder)
  legend:SetPoint("TOPLEFT", 10, -10)
  legend:SetFrameLevel(chart.frame:GetFrameLevel() + 3)
  legend:EnableMouse(true)
  -- rows of swatch + label in two aligned columns; notes (no swatch) sit under the label column, dimmed.
  -- v.legend holds the same lines as text (hover checks and specs read it).
  v.legend = W.Text(legend, "GameFontHighlightSmall")
  v.legend:Hide()
  legend.rows = {}
  v.legendBox = legend
  -- narrow: the legend folds into a small "Legend" button in the corner (the chart is small); click to open it
  v.legendToggle = W.Button(holder, L["Legend"] .. W.ARROW_RIGHT, 72, 18, function()
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
    self.legendToggle:SetText(L["Legend"] .. (self.legendOpen and W.ARROW_DOWN or W.ARROW_RIGHT))
    self.legendBox:ClearAllPoints()
    if compact then
      self.legendBox:SetPoint("TOPLEFT", self.legendToggle, "BOTTOMLEFT", 0, -4)
    else
      self.legendBox:SetPoint("TOPLEFT", 10, -10)
    end
    -- hovering the plot fades it (still there to click: the mouse over it leaves the plot)
    self.legendBox:SetShown(has and (not compact or self.legendOpen))
    self.legendBox:SetAlpha(hovering and 0.25 or 1)
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
  -- v.cards are the label / value rows in the old card order: market, lowest, average, volatility, supply, sales
  local col = UI.Stack(side.content, 0)
  local cards = {}
  -- the call: "Verdict ... + BUY", a headline, and why in plain words
  local callCard = col:Card(0)
  W.EnableLinks(callCard) -- "make X and sell it" names the item as a link
  local st = callCard.stack
  v.callRow = st:Pair(L["Verdict"], "signal")
  v.call = v.callRow.value
  v.callHead = st:Text("GameFontHighlight", 4)
  v.callWhy = st:Text("GameFontHighlightSmall", 6)
  v.callWhy:SetSpacing(3)
  -- market price: now (large), against its average, the confidence under it; the signal's badge and the market's
  -- phase at the top right
  local marketCard = col:Card()
  v.marketCard = marketCard
  marketCard:SetContent({ subtitle = L["Market price"], rows = { { label = L["Now"], big = true }, {} } })
  v.phase = W.Text(marketCard, "GameFontDisableSmall", "RIGHT")
  v.phase:SetPoint("TOPRIGHT", -8, -8)
  v.badge = W.SignalBadge(marketCard)
  v.badge:EnableMouse(true)
  ns.Help.Explain(v.badge, "signal")
  cards[1] = marketCard.rows[1]
  -- key numbers
  local statsCard = col:Card()
  v.statsCard = statsCard
  statsCard:SetContent({
    rows = {
      { label = L["Lowest listing"], term = "min" },
      { label = L["Average"], term = "avg" },
      { label = L["Volatility"], term = "vol30" },
      { label = L["Supply"], term = "qty" },
      { label = L["Sells per day"], term = "sellRate" },
    },
  })
  for i = 1, 5 do
    cards[i + 1] = statsCard.rows[i]
  end
  v.cards = cards
  -- posting price (Pricing / Posting): "Post at (24 h listing) ... N ahead", Normal large, what you net, then
  -- Quick / Patient; a warning or a word on the book under them
  local postCard = col:Card()
  W.EnableLinks(postCard) -- "Make X first" names the item as a link
  postCard:SetContent({
    rows = {
      { label = L["Post at"], term = "posting" },
      { label = L["Normal"], big = true, term = "posting" },
      {},
      { label = L["Quick"], term = "posting" },
      { label = L["Patient"], term = "posting" },
    },
  })
  v.post = postCard
  v.postHead, v.postNet = postCard.rows[1].label, postCard.rows[3].label
  -- watch and alerts
  st = col:Card().stack
  local watchRow = st:Row(22)
  v.watch = W.Button(watchRow, L["Watch"] .. W.ARROW_DOWN, 100, 22, function(self)
    UI:WatchMenu(self, UI.itemID)
  end, { icon = 14 })
  v.watch:SetPoint("LEFT")
  v.watch:SetPoint("RIGHT")
  v.watch.star = v.watch.icon
  W.SetStar(v.watch.star, false)
  local function goldAlert(row, field, hint)
    return W.MoneyInput(row, hint, function(copper, user)
      if user and UI.itemID then
        ns.AME.watch:SetAlert(UI.itemID, { [field] = copper or false })
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
  if self.series then
    self:DrawItemChart() -- the slot size depends on the range
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

-- a scan-by-scan range (2D, 7D) whose points aren't loaded yet (they wait while a scan is being stored): the chart
-- shows the daily points meanwhile, over the same span, so it isn't empty and doesn't jump in scale
function UI:IntradayPending()
  return self.intradayMode
      and not (self.intraday and self.intradayItem == self.itemID and (self.intradayDays or 0) >= (self.rangeDays or 0))
    or false
end

-- the loaded points within the current range. Over 7D, the days before the first scan or hourly point (hourly
-- prices only go back a week from when AME started keeping them) are filled with their daily points, so the chart
-- spans the whole range.
function UI:IntradayPoints()
  local days = self.rangeDays or 2
  local from = GetServerTime() - days * DAY
  local out = {}
  for _, p in ipairs(self.intraday or {}) do
    if p.t >= from then
      out[#out + 1] = p
    end
  end
  self.intradayDaily = false
  if days > 2 and #out > 0 then
    local first, fill = out[1].t, {}
    for _, p in ipairs(self.series or {}) do
      local t = p.day and p.res ~= "week" and p.day * DAY + DAY / 2
      if t and t >= from and (p.day + 1) * DAY <= first then
        fill[#fill + 1] = { t = t, market = p.market, min = p.min, qty = p.qty, daily = true }
      end
    end
    if #fill > 0 then
      self.intradayDaily = true
      for _, p in ipairs(out) do
        fill[#fill + 1] = p
      end
      out = fill
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
    self.chart.range = nil -- the range first (SetXRange below): the slot size depends on it
    if self:ShowingIntraday() or self:IntradayPending() then
      self.chart.range = { now - days * DAY, now + 3600 }
    elseif days > 2 then
      self.chart.range = { now - days * DAY, now + DAY }
    end
    self:DrawItemChart()
    if self:ShowingIntraday() then
      self.chart:SetMessage(nil)
      self.chart:SetXRange(now - days * DAY, now + 3600)
    elseif self:IntradayPending() then
      self.chart:SetMessage(nil) -- the daily points meanwhile, over the range's span
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
  show() -- the points being reloaded while they load, or that they're loading
  -- reloading what's on screen (a search of this item was just stored): only the scans after its newest point -
  -- reading every scan of the last two days again took seconds of background work after each search
  local have = self.intradayStale
    and self.intradayItem == itemID
    and (self.intradayDays or 0) >= days
    and self.intraday
    and #self.intraday > 0
    and self.intraday
  local from = have and (have[#have].t + 1) or (GetServerTime() - days * DAY)
  ns.AME:WithStore("intraday-" .. itemID .. "-" .. days, self:ViewShard(), function(store)
    return store:Intraday(itemID, from)
  end, function(ok, points)
    if not ok then
      ns.AME:ReportError("recent scans", points)
    end
    if self.itemID ~= itemID or not self.intradayMode or (self.rangeDays or 2) > days then
      return
    end
    points = ok and points or {}
    if have and ok then
      local merged = {}
      for i, p in ipairs(have) do
        merged[i] = p
      end
      for _, p in ipairs(points) do
        merged[#merged + 1] = p
      end
      table.sort(merged, function(a, b)
        return a.t < b.t
      end)
      points = merged
    end
    self.intraday, self.intradayItem, self.intradayDays = points, itemID, have and self.intradayDays or days
    self.intradayStale = nil
    show()
  end)
end

-- Your own trades in an item, as dots on its price chart: what you paid / got per unit, when (ledger entries).
UI.TRADE_COLORS = { buy = W.COLORS.chart.bought, sale = W.COLORS.chart.sold }

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

-- A rolling average over `hours` (default 168, a week) at each of xs: every hour before counts once - its scan or
-- hourly price (the last in that hour), kept for up to UI.CARRY_HOURS when an hour has none, else that day's daily
-- price (byDay[day]). So a scan moves it by about 1/168th, and a gap or a day boundary doesn't make it jump.
-- Returns ys aligned with xs (nil where there's nothing to average).
UI.ROLL_HOURS, UI.CARRY_HOURS = 168, 6
function UI.RollingAverage(xs, values, byDay, hours)
  hours = hours or UI.ROLL_HOURS
  local hourly = {}
  for i, x in ipairs(xs) do
    if values[i] then
      hourly[math.floor(x / 3600)] = values[i]
    end
  end
  local out = {}
  if #xs == 0 then
    return out
  end
  local first = math.floor(xs[1] / 3600) - hours + 1
  local last = math.floor(xs[#xs] / 3600)
  -- each hour's value, then running sums over the window
  local sum, n, vals, seen, seenAt = {}, {}, {}, nil, nil
  local s, c = 0, 0
  for h = first, last do
    local v = hourly[h]
    if v then
      seen, seenAt = v, h
    elseif seen and h - seenAt <= UI.CARRY_HOURS then
      v = seen
    else
      v = byDay[math.floor(h / 24)]
    end
    vals[h] = v
    if v then
      s, c = s + v, c + 1
    end
    local drop = vals[h - hours]
    if drop then
      s, c = s - drop, c - 1
    end
    sum[h], n[h] = s, c
  end
  for i, x in ipairs(xs) do
    local h = math.floor(x / 3600)
    if values[i] and n[h] and n[h] > 0 then
      out[i] = sum[h] / n[h]
    end
  end
  return out
end

UI.SMA_COLOR = W.COLORS.chart.average
UI.FAST_COLOR = W.COLORS.chart.fast
UI.FAST_CANDLES = 20

-- Chart layers you switch on and off by clicking them in the legend (Settings chartLayers: key -> true / false).
-- All start on.
UI.LAYERS_OFF = {}
function UI:LayerShown(key)
  local on = ns.Settings:Table("chartLayers")[key]
  if on == nil then
    return not UI.LAYERS_OFF[key]
  end
  return on
end

function UI:ToggleLayer(key)
  ns.Settings:Table("chartLayers")[key] = not self:LayerShown(key)
  self:DrawItemChart()
end

-- the vendor price line: drawn when the vendor pays at least this share of the lowest price on the chart
UI.VENDOR_LINE_SHARE = 0.33
UI.VENDOR_COLOR = W.COLORS.chart.vendor

-- The chart's slot size: from the span on screen (the zoom, else the range, else all the data), clipped to the
-- points there are. Never smaller than the points' own spacing: 15 minutes for scans, a day for daily history.
UI.SLOT_TARGET = 60
function UI:ChartSlotSize(firstX, lastX, intraday)
  local from, to
  local r = self.chart and self.chart.range
  if r then
    from, to = r[1], r[2]
  elseif self.rangeDays then
    to = GetServerTime()
    from = to - self.rangeDays * DAY
  end
  from, to = math.max(from or firstX, firstX), math.min(to or lastX, lastX)
  return ns.Analytics.SlotSize(to - from, UI.SLOT_TARGET, intraday and 15 * 60 or DAY)
end

-- a slot's length in words: "15 min", "6 h", "1 day", "3 days"
function UI.SlotText(size)
  if size < 3600 then
    return L["%d min"]:format(size / 60)
  elseif size < DAY then
    return L["%d h"]:format(size / 3600)
  elseif size == DAY then
    return L["1 day"]
  end
  return L["%d days"]:format(math.floor(size / DAY + 0.5))
end

-- (Re)draw the item chart in the current style from self.series. Every series is merged into one grid of time
-- slots (Analytics.Slot), so the candles, lines, averages and supply bars all sit at the same x: hovering a slot
-- shows them all. The slot size follows the zoom (UI:ChartSlotSize); zooming redraws when it changes.
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
  -- the points as they are, with the 7-day average at each: by day, each day's average of it and the 6 before; on
  -- the scan-by-scan ranges (a 7-point average of scans isn't a 7-day average), the average over the 168 hours
  -- before it (UI.RollingAverage) - each hour moves it by 1/168
  local xs, market = {}, {}
  for i, p in ipairs(series) do
    xs[i] = p.t or (p.day * DAY + (p.res == "week" and 3.5 * DAY or DAY / 2))
    market[i] = p.market
  end
  local avg
  if intraday then
    local byDay = {}
    for _, p in ipairs(self.series or {}) do
      if p.day and p.res ~= "week" then
        byDay[p.day] = p.market
      end
    end
    avg = UI.RollingAverage(xs, market, byDay)
  else
    avg = {}
    for i = 1, #market do
      avg[i] = ns.Analytics.SMA(market, math.min(7, i), i)
    end
  end
  local points = {}
  for i, p in ipairs(series) do
    points[i] = { x = xs[i], market = p.market, min = p.min, high = p.high, qty = p.qty, avg = avg[i] }
  end
  local size = self:ChartSlotSize(xs[1], xs[#xs], intraday)
  local s = ns.Analytics.Slot(points, size)
  self.slotSize, self.slots, self.slotExtent = size, s, { xs[1], xs[#xs], intraday = intraday }
  local range = chart.range
  chart.range = nil
  chart:ClearSeries()
  local legend = {} -- { color, label } rows, or { note = text }
  -- a slot's values where it has one (a line skips a slot without)
  local function present(ys)
    local oxs, oys = {}, {}
    for i, x in ipairs(s.xs) do
      if ys[i] then
        oxs[#oxs + 1], oys[#oys + 1] = x, ys[i]
      end
    end
    return oxs, oys
  end
  -- supply: one bar per slot, its last reading (like the close)
  local qxs, qys = present(s.qty)
  chart:SetSeries("qty", { xs = qxs, ys = qys, kind = "bars", axis = "volume", color = W.COLORS.chart.supply })
  if candles then
    local c = { xs = s.xs, open = s.open, high = s.high, low = s.low, close = s.close, period = size }
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
      xs = s.xs,
      ys = s.market,
      kind = "area",
      axis = "price",
      color = W.COLORS.chart.market,
      marker = true,
    })
    local lxs, lys = present(s.min)
    chart:SetSeries("min", { xs = lxs, ys = lys, kind = "line", axis = "price", color = W.COLORS.chart.lowest })
    legend[#legend + 1] = { W.COLORS.chart.market, L["Market"], kind = "line", key = "market" }
    legend[#legend + 1] = { W.COLORS.chart.lowest, L["Lowest"], kind = "line", key = "min" }
  end
  -- the 7-day average: where it stood at the end of each slot
  local smaXs, smaYs = present(s.avg)
  if #smaXs > 1 then
    legend[#legend + 1] = { UI.SMA_COLOR, L["7-day average"], kind = "line", key = "sma" }
  end
  -- MA 20, as trading apps draw it: the simple average of the last UI.FAST_CANDLES slots' closes, so it follows the
  -- zoom - 20 hours on hourly slots, 20 days on daily ones
  local fastXs, fastYs = {}, {}
  for i = 2, #s.xs do
    fastXs[#fastXs + 1], fastYs[#fastYs + 1] = s.xs[i], ns.Analytics.SMA(s.close, math.min(UI.FAST_CANDLES, i), i)
  end
  local span = UI.FAST_CANDLES * size
  UI.fastLabel = L["MA %d (%s)"]:format(
    UI.FAST_CANDLES,
    span < 3 * DAY and L["%d hours"]:format(span / 3600) or L["%d days"]:format(math.floor(span / DAY + 0.5))
  )
  if #fastXs > 1 then
    legend[#legend + 1] = { UI.FAST_COLOR, UI.fastLabel, kind = "line", key = "fast" }
  end
  -- what a vendor pays: a dashed line when it's near the prices (where selling to a vendor can beat the auction
  -- house); far below them, a line would squash the chart, so the legend just says it
  local vendor = self.itemID and ns.ItemCache.Get(self.itemID).sellPrice
  self.vendorLine = nil
  if vendor and vendor > 0 then
    local lowest
    for i = 1, #s.xs do
      for _, y in ipairs({ s.low[i], s.market[i] }) do
        if y and y > 0 and (not lowest or y < lowest) then
          lowest = y
        end
      end
    end
    if lowest and vendor >= lowest * UI.VENDOR_LINE_SHARE then
      self.vendorLine = vendor
      chart:SetSeries("vendor", {
        xs = { s.xs[1], math.max(s.xs[#s.xs], GetServerTime() + DAY) },
        ys = { vendor, vendor },
        hover = false, -- a level, not a reading: the hover names it on every slot
        kind = "line",
        axis = "price",
        color = UI.VENDOR_COLOR,
        width = 1.2,
        dash = { 6, 4 },
      })
      legend[#legend + 1] = { UI.VENDOR_COLOR, L["Vendor price"], kind = "dash", key = "vendor" }
    else
      legend[#legend + 1] = { note = L["Vendor price %s (below the chart)"]:format(W.Money(vendor, true)) }
    end
  end
  legend[#legend + 1] = { W.COLORS.chart.supply, L["Supply"], kind = "square", key = "qty" }
  legend[#legend + 1] = { note = L["(one point per %s)"]:format(UI.SlotText(size)) }
  if intraday and self.intradayDaily then
    legend[#legend + 1] = { note = L["(older days: one point a day)"] }
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
    legend[#legend + 1] = { UI.TRADE_COLORS.buy, L["You bought"], kind = "dot", key = "trades" }
    legend[#legend + 1] = { UI.TRADE_COLORS.sale, L["You sold"], kind = "dot", key = "trades" }
  end
  self:SetLegend(legend)
  if #smaXs > 1 then
    chart:SetSeries("sma", {
      xs = smaXs,
      ys = smaYs,
      kind = "line",
      axis = "price",
      color = { UI.SMA_COLOR[1], UI.SMA_COLOR[2], UI.SMA_COLOR[3], 0.9 },
      width = 1.5,
    })
  end
  if #fastXs > 1 then
    chart:SetSeries("fast", {
      xs = fastXs,
      ys = fastYs,
      kind = "line",
      axis = "price",
      color = { UI.FAST_COLOR[1], UI.FAST_COLOR[2], UI.FAST_COLOR[3], 0.9 },
      width = 1.3,
    })
  end
  -- the lines switched off in the legend
  local order = {}
  for _, key in ipairs(chart.order) do
    if UI:LayerShown(key) then
      order[#order + 1] = key
    else
      chart.series[key] = nil
    end
  end
  chart.order = order
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
    if not r.click then
      -- the whole row: click to show / hide its line
      r.click = CreateFrame("Button", nil, box)
      r.click:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -7 - (i - 1) * UI.LEGEND_ROW)
      r.click:SetPoint("RIGHT", box, "RIGHT", -4, 0)
      r.click:SetHeight(UI.LEGEND_ROW)
      r.click:SetScript("OnClick", function(btn)
        if btn.key then
          UI:ToggleLayer(btn.key)
        end
      end)
      W.Tooltip(r.click, function(tip)
        local key = r.click.key
        W.TipText(tip, r.click.label or "", UI:LayerShown(key) and L["Click to hide it."] or L["Click to show it."])
      end)
    end
    r.click.key, r.click.label = e.key, e[2]
    r.click:SetShown(e.key ~= nil)
    local on = not e.key or UI:LayerShown(e.key)
    r.swatch:SetAlpha(on and 1 or 0.3)
    r.swatch2:SetAlpha(on and 1 or 0.3)
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
      r.text:SetText(on and e[2] or W.Dim(e[2]))
      lines[#lines + 1] = e[2]
    end
    r.text:Show()
    widest = math.max(widest, r.text:GetStringWidth() or 60)
  end
  for i = #entries + 1, #rows do
    if rows[i].click then
      rows[i].click:Hide()
    end
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
  local own = ns.AHSelling and ns.AHSelling.panel -- AME's Selling tab
  if own and own:IsVisible() then
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
  self.autoRangeFor = nil
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
UI.RECENT_DAYS = 2 -- an item with a scan this recent opens on 2D, else on 7D

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
    -- nothing to show: every figure a dash, no badge, no phase, no confidence
    v.marketCard:SetContent({
      subtitle = L["Market price"],
      rows = { { label = L["Now"], text = W.NONE, big = true }, { label = "", text = "" } },
    })
    for _, c in ipairs(v.cards) do
      c.value:SetText(W.NONE)
    end
    v.badge:Hide()
    v.phase:SetText("")
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
  -- Until you pick a range: 2D (every scan of the last two days) when the item has a recent one, else 7D. Chosen
  -- once per item shown, so the scale stays put as new scans and searches come in.
  if not self.rangePicked and self.autoRangeFor ~= self.itemID then
    self.autoRangeFor = self.itemID
    local recent = latest and latest.t and GetServerTime() - latest.t <= UI.RECENT_DAYS * DAY
    self.rangeDays, self.rangeKey = recent and 2 or 7, recent and "2D" or "7D"
  end
  if self.rangeKey == "All" then
    self:SetRange(nil, "All")
  else
    self:SetRange(self.rangeDays or 2, self.rangeKey or "2D")
  end

  local s = ns.Analytics.Summarize(series)
  -- the latest raw scan can itself be a bad print (one overpriced listing): fall back to the cleaned series
  if latest and factor and s.avg30 and s.avg30 > 0 and latest.market then
    if latest.market > s.avg30 * factor or latest.market < s.avg30 / factor then
      latest, dropped = nil, dropped + 1
    end
  end
  if latest then -- the posting prices (here and on the sell bar) go by the same market as this page
    ns.Posting:NoteMarket(self:ViewShard(), self.itemID, latest.market, latest.t)
  end
  local avg = s["avg" .. avgDays()] or s.avg30
  local market = latest and latest.market or s.market
  local change = market and avg and avg > 0 and market / avg - 1 or nil
  -- against the average: an arrow and how far, in the gain / loss colour
  local changeText = W.NONE
  if change then
    local pct = math.floor(math.abs(change) * 100 + 0.5)
    if pct == 0 then
      changeText = W.Dim(L["right at it"])
    else
      local tone = change > 0 and "good" or "bad"
      changeText = arrow(change > 0, tone)
        .. W.Color(tone, (change > 0 and L["%d%% above"] or L["%d%% below"]):format(pct))
    end
  end
  local today = math.floor(GetServerTime() / DAY)
  local level = ns.Analytics.Confidence(s, today)
  local scans = L["%d scans this week"]:format(s.scans7 or 0)
  v.marketCard:SetContent({
    subtitle = L["Market price"],
    rows = {
      { label = L["Now"], copper = market, text = W.NONE, big = true },
      { label = L["vs %d-day average"]:format(avgDays()), text = changeText },
    },
    note = L["Confidence %s %s"]:format(W.Confidence(level), UI.CONFIDENCE_WORD[level] or "") .. "  ·  " .. scans,
  })
  -- the signal's badge, the market's phase after it
  v.phase:SetText(s.phase and ns.Analytics.PHASE_LABEL[s.phase]:lower() or "")
  v.badge:SetShown(s.signal and s.signal ~= "none" and true or false)
  v.badge:SetSignal(s.signal)
  v.badge:ClearAllPoints()
  if (v.phase:GetText() or "") ~= "" then
    v.badge:SetPoint("RIGHT", v.phase, "LEFT", -4, 0)
  else
    v.badge:SetPoint("TOPRIGHT", -8, -7)
  end
  -- supply with its weekly trend: rising supply is bad for sellers (red), falling good (green)
  local trend = s.supplyTrend30 and s.supplyTrend30 * 7
  local supply = W.Count(latest and latest.qty or s.qty or 0)
  if trend and math.abs(trend) >= 0.005 then
    local tone = trend > 0 and "bad" or "good"
    supply = supply
      .. "  "
      .. arrow(trend > 0, tone)
      .. W.Color(tone, L["%d%%/wk"]:format(math.floor(math.abs(trend) * 100 + 0.5)))
  end
  v.statsCard:SetContent({
    rows = {
      { label = L["Lowest listing"], copper = latest and latest.min or s.min, text = W.NONE, term = "min" },
      {
        label = L["%d-day average"]:format(avgDays()),
        copper = s["avg" .. avgDays()] or s.avg30,
        text = W.NONE,
        term = "avg",
      },
      { label = L["Volatility"], text = s.vol30 and ("%.1f%%"):format(s.vol30 * 100) or W.NONE, term = "vol30" },
      { label = L["Supply"], text = supply, term = "qty" },
      {
        label = L["Sells per day"],
        text = s.soldPerDay and ("~" .. W.Count(s.soldPerDay)) or W.NONE,
        term = "sellRate",
      },
    },
  })
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
  local signal = indexed and indexed.signal or s.signal
  -- vendoring it: is making something of it first worth more? (a recipe one of your characters knows)
  self.craftInstead = signal == "vendor" and self.CraftInstead and self:CraftInstead(self.itemID) or nil
  self:FillVerdict(s, {
    signal = signal,
    craft = self.craftInstead,
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
-- today, craft (UI:CraftInstead) }. Returns signal, headline, { sentences }.
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
  local sold = s.soldPerDay
  if sold then
    if sold >= 20 then
      why[#why + 1] = L["Sells fast: ~%s a day."]:format(W.Count(sold))
    elseif sold >= 1 then
      why[#why + 1] = L["Sells ~%s a day."]:format(W.Count(sold))
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
  if signal == "vendor" and ctx.craft then
    why[#why + 1] = UI.CraftInsteadText(ctx.craft)
  elseif ACTION[signal] then
    why[#why + 1] = ACTION[signal]
  end
  return signal, HEADLINE[signal] or L["No call yet"], why
end

-- "Better: make Silk Bandage and vendor it (Tyken) - ~2s per item instead of 1s 50c." The product is an item link
-- (it works as one where the text's frame has links switched on: W.EnableLinks).
function UI.CraftInsteadText(c)
  local name = W.LinkText(c.product)
  local text = c.where == "vendor" and L["Better: make %s and vendor it - ~%s per item instead of %s."]
    or L["Better: make %s and sell it - ~%s per item after the cut, instead of %s."]
  local who = c.crafter and (" " .. W.Dim("(" .. c.crafter .. ")")) or ""
  return text:format(name, W.Money(c.each), W.Money(c.raw)) .. who
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

-- the compact layout's gist of the sidebar, in pieces: the market price and its change, the signal's badge, what
-- to post at
function UI:UpdateItemSummary()
  local v, facts = self.itemView, self.itemFacts or {}
  v.summaryMarket:SetText(
    W.Dim(L["Market"]) .. " " .. W.Money(facts.market) .. (facts.change and " " .. W.Percent(facts.change, 0) or "")
  )
  local signal = facts.signal and facts.signal ~= "none" and facts.signal or nil
  v.summaryBadge:SetSignal(signal)
  v.summaryBadge:SetShown(signal ~= nil)
  v.summaryPost:ClearAllPoints()
  v.summaryPost:SetPoint("LEFT", signal and v.summaryBadge or v.summaryMarket, "RIGHT", 12, 0)
  v.summaryPost:SetPoint("RIGHT", v.details, "LEFT", -8, 0)
  v.summaryPost:SetText(
    facts.post
        and (W.Dim(L["Post at"]) .. " " .. W.Money(facts.post) .. (facts.postHours and " " .. W.Dim(
          W.Hours(facts.postHours)
        ) or ""))
      or ""
  )
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
  local head = {
    label = L["Post at"] .. "  " .. W.Dim("(" .. L["%d h listing"]:format(hours or 24) .. ")"),
    text = "",
    term = "posting",
  }
  self.itemFacts = self.itemFacts or {}
  self.itemFacts.post = advice and advice.normal.price
  self.itemFacts.postHours = advice and advice.normal.hours
  if not advice then
    v.post:SetContent({
      rows = { head, { label = L["Normal"], text = W.Dim(L["not enough data yet"]), big = true, term = "posting" } },
      note = L["Search for it at the auction house, or run a full scan."],
    })
  else
    local n = advice.normal
    head.text = W.Dim(L["%d ahead"]:format(n.ahead))
    local cut = ns.Quote.Cut(ns.Quote.ShardHouse(shard))
    local net = ns.Quote.PostNet(shard, n.price, advice.deposit, advice.qty)
    -- under the prices: a warning, or why Quick and Patient are the same
    local notes = {}
    local info = ns.ItemCache.Get(self.itemID)
    local vendor = info and info.sellPrice
    if vendor and vendor > 0 and net < vendor and self.craftInstead then
      local c = self.craftInstead
      notes[#notes + 1] =
        W.Color("warn", L["Make %s first: ~%s per item"]:format(W.LinkText(c.product), W.Money(c.each)))
    elseif vendor and vendor > 0 and net < vendor then
      notes[#notes + 1] = W.Color("bad", L["Vendor it: a vendor pays %s"]:format(W.Money(vendor)))
    elseif advice.hold then
      notes[#notes + 1] = W.Color("bad", L["unlikely to sell soon: consider holding"])
    elseif advice.cheap then
      notes[#notes + 1] = W.Color("warn", L["well below its usual price"])
    end
    if advice.quick.price == advice.patient.price then
      local onlyLowest = n.ahead == 0 and (advice.book and #advice.book.prices or 0) > 0
      if onlyLowest then
        notes[#notes + 1] = L["more is listed than sells in one listing time: only the lowest price sells soon"]
      end
    end
    -- how long each takes goes with its name; the prices line up on the right
    local function when(label, hrs)
      return label .. W.Dim("  ·  " .. W.Hours(hrs))
    end
    local rows = {
      head,
      {
        label = L["Normal"] .. W.Dim("  ·  " .. L["sells in %s"]:format(W.Hours(n.hours))),
        copper = n.price,
        big = true,
        term = "posting",
      },
      { label = L["You net, after the %d%% cut"]:format(W.CutPct(cut)), copper = net },
    }
    -- Quick no cheaper than Normal: one option, shown once
    if not advice.quickSame then
      rows[#rows + 1] = { label = when(L["Quick"], advice.quick.hours), copper = advice.quick.price, term = "posting" }
    end
    rows[#rows + 1] =
      { label = when(L["Patient"], advice.patient.hours), copper = advice.patient.price, term = "posting" }
    v.post:SetContent({ rows = rows, note = #notes > 0 and table.concat(notes, "\n") or nil })
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
      item = h.itemID, -- icon, quality colour and its tooltip
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
  if ns.AHShopping and ns.AHShopping:OnItemLink(link) then -- the auction house's Shopping tab is up: search it
    return
  end
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
