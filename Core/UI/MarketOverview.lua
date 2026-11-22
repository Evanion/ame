-- Market tab, Overview mode: the whole auction house at a glance (MarketStats). Layout (UI.Slots): toolbar = Screener |
-- Overview and the change period; header = stat cards (market index, CPI, listed value, turnover, auctions, breadth);
-- main = the 30-day chart with risers and fallers under it, and categories by listed value with the largest items on
-- the right. Narrow windows keep the chart and the categories.
local _, ns = ...
local L = ns.L

local W = ns.Widgets
local UI = ns.UI
local DAY = ns.DAY

local ROW_H = 18 -- the lists' rows: denser than the screener's, so the lists fit under the chart
local RIGHT_W = 400
local LARGEST_ROWS = 3
-- The chart keeps its height; the lists under it take what's left, more rows in a taller window. Narrow windows
-- have a shorter chart over the categories.
local CHART_H, CHART_H_COMPACT = 200, 130
local KPI_H, KPI_H_COMPACT = 62, 42 -- tall enough for a card's breadth bar and note; compact cards have neither

UI.MARKET_MODES = {
  { "screener", L["Screener"] },
  { "overview", L["Overview"] },
}
local PERIODS = {
  { 1, L["1 day"] },
  { 7, L["7 days"] },
  { 30, L["30 days"] },
}
-- the period's name ("7 days"), the heading of what changed over it
local function periodText(p)
  return PERIODS[(p == 1 and 1) or (p == 30 and 3) or 2][2]
end
local CHARTS = {
  { "index", L["Market index"] },
  { "cpi", L["CPI"] },
  { "value", L["Listed value"] },
  { "auctions", L["Auctions"] },
}

function UI:MarketMode()
  if not ns.Settings:Get("marketOverview") then
    return "screener"
  end
  return self.marketMode or ns.Settings:Get("marketMode") or "screener"
end

-- Settings: the Overview switched on or off. On: rebuild the market data with statistics (in the background; the
-- Overview says so meanwhile). Off: back to the screener, and statistics are dropped from the next builds.
function UI:MarketOverviewChanged(on)
  self:SyncModes()
  local area = self.views and self.views.market
  if area and area.screener.PlaceSignals then
    area.screener:SetCompact(area.screener.slots.compact)
  end
  if on then
    for shard in pairs(ns.AME.indexes) do
      ns.AME:RefreshIndex(shard)
    end
  else
    for _, index in pairs(ns.AME.indexes) do
      index.stats = nil
    end
    if self.marketMode == "overview" then
      self:SetMarketMode("screener")
      self.marketMode = nil
      ns.Settings:Set("marketMode", nil)
    end
  end
end

-- Screener | Overview: a button group on a wide toolbar, a dropdown on a narrow one. Both stay in step (SyncModes).
function UI:MarketModeSwitch(bar)
  local seg = W.Segmented(bar, UI.MARKET_MODES, {
    minWidth = 64,
    onSelect = function(mode)
      UI:SetMarketMode(mode)
    end,
  })
  local drop = W.Dropdown(bar, 92, UI.MARKET_MODES, function(mode)
    UI:SetMarketMode(mode)
  end, { neutral = true, default = "screener" })
  self.modeSwitches = self.modeSwitches or {}
  table.insert(self.modeSwitches, { seg = seg, drop = drop })
  return seg, drop
end

function UI:SyncModes()
  local mode = self:MarketMode()
  for _, s in ipairs(self.modeSwitches or {}) do
    s.seg:Select(mode, true)
    s.drop:SetValue(mode)
  end
end

-- switch the Market tab between the screener and the overview (remembered)
function UI:SetMarketMode(mode)
  local area = self.views and self.views.market
  self.marketMode = mode
  ns.Settings:Set("marketMode", mode)
  self:SyncModes()
  if not area then
    return
  end
  local overview = mode == "overview"
  area.screener:SetShown(not overview)
  area.overview:SetShown(overview)
  area.slots = overview and area.overview.slots or area.screener.slots -- the footer reads the shown mode's text
  W.HideMenu()
  if overview then
    self:RefreshOverview()
  else
    self:RefreshMarket(true)
  end
  self:UpdateFooter()
end

-- the screener, filtered to a category (clicked in the overview)
function UI:ShowMarketCategory(classID)
  local q = self.mq
  q.list, q.only, q.classID, q.subClassID = nil, nil, classID, nil
  self.offset = 0
  self:SetMarketMode("screener")
  self:RenderCategories()
  self:RefreshMarket(true)
end

-- A panel with a gold heading and a dim note after it ("Categories", "by listed value"); its content goes in
-- panel.body, under the heading.
local function headed(parent, title, note)
  local p = W.Panel(parent)
  p.head = W.PageHeading(p)
  p.head:SetPoint("TOPLEFT", 8, -5)
  p.head:SetPoint("RIGHT", -8, 0)
  p.head:Set(title, note)
  p.body = CreateFrame("Frame", nil, p)
  p.body:SetPoint("TOPLEFT", 6, -24)
  p.body:SetPoint("BOTTOMRIGHT", -6, 4)
  return p
end

-- the summary's change field for the picked period
local function changeKey()
  return UI.ovPeriod == 1 and "change1" or UI.ovPeriod == 30 and "change30" or "change7"
end

-- a change as the cards show it: the signed percent (the card colours it) and which way it went
local function delta(x)
  if not x then
    return nil, "mute"
  end
  return ("%+.1f%%"):format(x * 100), x > 0.0005 and "up" or x < -0.0005 and "down" or "mute"
end

-- Risers or fallers: a list without a header row, as tall as its panel. Click an item for its chart.
local function moverTable(parent)
  return ns.DataTable.New(parent, {
    bare = true,
    fill = true,
    rows = 5,
    rowHeight = ROW_H,
    columns = {
      { key = "name", label = L["Item"], width = 120, item = true },
      { key = "market", label = L["Market"], width = 70, format = "money" },
      {
        key = "change",
        label = L["Change"],
        width = 52,
        text = function(s)
          return W.Percent(s[changeKey()])
        end,
      },
    },
    itemID = function(s)
      return s.itemID
    end,
    itemMenu = {},
  })
end

function UI:CreateMarketOverview(area)
  local v = CreateFrame("Frame", nil, area)
  v:SetAllPoints(area)
  v:Hide()
  self.overviewView = v
  self.ovPeriod, self.ovChart = 7, "index"
  local slots = UI.Slots(v, { toolbar = 22, header = KPI_H, headerBelow = true, status = true })
  v.slots = slots
  local bar = slots.toolbar

  -- toolbar: the mode switch, then the period the changes are measured over
  v.mode, v.modeDrop = self:MarketModeSwitch(bar)
  v.mode:SetPoint("LEFT", 0, 0)
  v.modeDrop:SetPoint("LEFT", 0, 0)
  v.period = W.Segmented(bar, PERIODS, {
    minWidth = 56,
    onSelect = function(p)
      UI.ovPeriod = p
      UI:RefreshOverview()
    end,
  })
  v.period:SetPoint("RIGHT", 0, 0)
  v.period:Select(7, true)
  v.periodLabel = W.Text(bar, "GameFontDisableSmall")
  v.periodLabel:SetPoint("RIGHT", v.period, "LEFT", -8, 0)
  v.periodLabel:SetText(L["Change over"])
  v.periodDrop = W.Dropdown(bar, 96, PERIODS, function(p)
    UI.ovPeriod = p
    UI:RefreshOverview()
  end, { neutral = true, default = 7 })
  v.periodDrop:SetPoint("RIGHT", 0, 0)
  -- risers and fallers: from every category, or one
  v.moversLabel = W.Text(bar, "GameFontDisableSmall")
  v.moversLabel:SetPoint("LEFT", v.mode, "RIGHT", 16, 0)
  v.moversLabel:SetText(L["Movers in"])
  v.moverClass = W.Dropdown(bar, 140, { { false, L["All categories"] } }, function(classID)
    UI.ovMoverClass = classID or nil
    UI:RefreshOverview()
  end, { neutral = true, default = false })
  v.moverClass:SetPoint("LEFT", v.moversLabel, "RIGHT", 6, 0)

  -- the headline figures
  v.cardRow = W.CardRow(slots.header, {
    { L["Market index"], term = "mxIndex" },
    { L["CPI"], term = "mxCpi" },
    { L["Listed value"], term = "mxValue" },
    { L["Turnover (estimate)"], term = "mxTurnover" },
    { L["Auctions"], term = "mxAuctions" },
    { L["Breadth"], term = "mxBreadth" },
  }, { width = UI.WIDTH - 20, height = KPI_H })
  v.cardRow:SetPoint("TOPLEFT", 0, 0)
  v.cardRow:SetPoint("RIGHT", 0, 0)
  v.cards = v.cardRow.cards

  local main = slots.main
  -- right column: categories (as tall as there's room for), the largest items under them
  v.right = CreateFrame("Frame", nil, main)
  v.right:SetPoint("TOPRIGHT", 0, 0)
  v.right:SetPoint("BOTTOMRIGHT", 0, 0)
  v.right:SetWidth(RIGHT_W)
  v.largest = headed(v.right, L["Largest by value"], L["what the total leans on"])
  v.largest:SetPoint("BOTTOMLEFT", 0, 0)
  v.largest:SetPoint("BOTTOMRIGHT", 0, 0)
  v.largest:SetHeight(28 + LARGEST_ROWS * ROW_H)
  v.largestTable = ns.DataTable.New(v.largest.body, {
    bare = true,
    rows = LARGEST_ROWS,
    rowHeight = ROW_H,
    columns = {
      { key = "name", label = L["Item"], width = 120, item = true },
      {
        key = "qty",
        label = L["Listed"],
        width = 120,
        text = function(t)
          return W.Count(t.qty) .. " x " .. W.Money(t.price, true)
        end,
      },
      {
        key = "value",
        label = L["Value"],
        width = 110,
        text = function(t)
          return W.BigMoney(t.value, 10000) .. (t.raw and W.Dim(" " .. L["capped"]) or "")
        end,
      },
    },
    itemID = function(t)
      return t.id
    end,
    itemMenu = {},
    tooltip = function(tip, t)
      tip:AddLine(" ")
      if t.raw then
        tip:AddLine(
          L["Listed at %s each; counted at %s (the outlier limit: %dx its 30-day average)."]:format(
            W.Money(t.raw),
            W.Money(t.price),
            ns.Settings:Get("outlierFactor") or 0
          ),
          0.85,
          0.85,
          0.85,
          true
        )
      else
        W.TipPair(tip, L["Listed"], W.Thousands(t.qty) .. " x " .. W.Money(t.price))
      end
    end,
  })
  v.largestRows = v.largestTable.rows

  v.sectors = headed(v.right, L["Categories"], L["by listed value"])
  v.sectors:SetPoint("TOPLEFT", 0, 0)
  v.sectors:SetPoint("TOPRIGHT", 0, 0)
  v.sectors:SetPoint("BOTTOM", v.largest, "TOP", 0, UI.SLOT_GAP)
  v.sectorTable = ns.DataTable.New(v.sectors.body, {
    fill = true,
    rows = 8,
    rowHeight = ROW_H,
    flex = "name",
    note = L["Click a category to open it in the screener."],
    columns = {
      {
        key = "name",
        label = L["Category"],
        width = 90,
        align = "LEFT",
        text = function(c)
          return c.name
        end,
      },
      {
        key = "value",
        label = L["Value"],
        width = 64,
        text = function(c)
          return W.BigMoney(c.value, 10000)
        end,
      },
      { key = "share", label = L["Share"], width = 100, format = "share" },
      { -- the change over the period picked on the toolbar, named after it
        key = "change",
        label = function()
          return periodText(UI.ovPeriod)
        end,
        width = 52,
        format = "pct",
      },
      {
        key = "turnover",
        label = L["Turnover"],
        width = 64,
        text = function(c)
          return c.turnover and ("~" .. W.BigMoney(c.turnover, 10000)) or W.NONE
        end,
      },
    },
    onClick = function(c)
      if c.classID ~= ns.MarketStats.OTHER then
        UI:ShowMarketCategory(c.classID)
      end
    end,
    tooltip = function(tip, c)
      W.TipText(tip, c.name, L["Click to open this category in the screener."])
      W.TipPair(tip, L["Listed value"], W.Money(c.value))
      if c.turnover then
        W.TipPair(tip, L["Turnover (estimate)"], W.Money(c.turnover) .. W.Dim(L["/day"]))
      end
    end,
  })
  v.sectorRows = v.sectorTable.rows

  -- left: the chart, risers and fallers under it
  v.left = CreateFrame("Frame", nil, main)
  v.left:SetPoint("TOPLEFT", 0, 0)
  v.left:SetPoint("BOTTOMRIGHT", v.right, "BOTTOMLEFT", -UI.SLOT_GAP, 0)
  v.chartPanel = W.Panel(v.left)
  v.chartPanel:SetPoint("TOPLEFT", 0, 0)
  v.chartPanel:SetPoint("TOPRIGHT", 0, 0)
  v.chartPanel:SetHeight(CHART_H)
  v.movers = CreateFrame("Frame", nil, v.left)
  v.movers:SetPoint("TOPLEFT", v.chartPanel, "BOTTOMLEFT", 0, -UI.SLOT_GAP)
  v.movers:SetPoint("BOTTOMRIGHT", 0, 0)
  v.risers = headed(v.movers, L["Biggest risers"], "")
  v.fallers = headed(v.movers, L["Biggest fallers"], "")
  v.risers:SetPoint("TOPLEFT", 0, 0)
  v.risers:SetPoint("BOTTOMRIGHT", v.movers, "BOTTOM", -UI.SLOT_GAP / 2, 0)
  v.fallers:SetPoint("TOPRIGHT", 0, 0)
  v.fallers:SetPoint("BOTTOMLEFT", v.movers, "BOTTOM", UI.SLOT_GAP / 2, 0)
  v.risersHead, v.fallersHead = v.risers.head, v.fallers.head
  v.riserTable, v.fallerTable = moverTable(v.risers.body), moverTable(v.fallers.body)
  v.riserRows, v.fallerRows = v.riserTable.rows, v.fallerTable.rows

  v.chartHead = W.Heading(v.chartPanel, L["Last 30 days"], 8, -6)
  v.chartModes = W.Segmented(v.chartPanel, CHARTS, {
    minWidth = 48,
    height = 18,
    onSelect = function(key)
      UI.ovChart = key
      UI:RenderOverviewChart()
    end,
  })
  v.chartModes:SetPoint("TOPRIGHT", -6, -4)
  v.chartModes:Select("index", true)
  local chart = LibStub("LibAMEChart-1.0"):New(v.chartPanel, { panes = { { axis = "y", weight = 1 } } })
  chart.frame:SetPoint("TOPLEFT", 4, -26)
  chart.frame:SetPoint("BOTTOMRIGHT", -4, 4)
  chart:SetAxisFormatter("y", function(val)
    if UI.ovChart == "value" then
      return W.Plain(W.BigMoney(val))
    elseif UI.ovChart == "auctions" then
      return W.Count(val)
    end
    return ("%.1f"):format(val)
  end)
  chart:SetHoverFormatter(function(_, x, rows)
    local row = rows.y
    if not (row and row.x == x) then
      return { W.Color("white", date("%a %b %d", x)) }
    end
    local label, value = v.chartModes.byKey[UI.ovChart].label:GetText(), row.y
    if UI.ovChart == "value" then
      value = W.BigMoney(value)
    elseif UI.ovChart == "auctions" then
      value = W.Thousands(value)
    else
      value = ("%.1f"):format(value)
    end
    return { W.Color("white", date("%a %b %d", x)), { W.Dim(label), value } }
  end)
  v.chart = chart

  v.message = W.Text(main, "GameFontDisable")
  v.message:SetPoint("TOPLEFT", 20, -40)
  v.message:SetPoint("RIGHT", -20, 0)
  v.message:SetJustifyH("CENTER")

  -- Narrow, as the compact design has it: the Screener | Overview buttons stay, the period becomes a dropdown,
  -- the cards are smaller and Breadth gives way, and the chart sits over the categories in one column (risers,
  -- fallers and the largest items are left out).
  function v:SetCompact(on)
    slots:SetCompact(on)
    slots:SetBarHeight(slots.header, on and KPI_H_COMPACT or KPI_H)
    self.cardRow:SetCardHeight(on and KPI_H_COMPACT or KPI_H)
    self.cardRow:SetCompact(on)
    self.cards[6]:SetShown(not on)
    self.cardRow:Relayout()
    self.modeDrop:Hide()
    self.mode:Show()
    self.period:SetShown(not on)
    self.periodLabel:SetShown(not on)
    self.periodDrop:SetShown(on)
    self.moversLabel:SetShown(not on)
    self.moverClass:SetShown(not on)
    self.movers:SetShown(not on)
    self.largest:SetShown(not on)
    self.right:ClearAllPoints()
    self.left:ClearAllPoints()
    if on then
      self.left:SetPoint("TOPLEFT", 0, 0)
      self.left:SetPoint("TOPRIGHT", 0, 0)
      self.left:SetHeight(CHART_H_COMPACT)
      self.chartPanel:SetHeight(CHART_H_COMPACT)
      self.right:SetPoint("TOPLEFT", self.left, "BOTTOMLEFT", 0, -UI.SLOT_GAP)
      self.right:SetPoint("BOTTOMRIGHT", 0, 0)
      self.sectors:SetPoint("BOTTOM", self.right, "BOTTOM", 0, 0)
    else
      self.right:SetPoint("TOPRIGHT", 0, 0)
      self.right:SetPoint("BOTTOMRIGHT", 0, 0)
      self.right:SetWidth(RIGHT_W)
      self.left:SetPoint("TOPLEFT", 0, 0)
      self.left:SetPoint("BOTTOMRIGHT", self.right, "BOTTOMLEFT", -UI.SLOT_GAP, 0)
      self.chartPanel:SetHeight(CHART_H)
      self.sectors:SetPoint("BOTTOM", self.largest, "TOP", 0, UI.SLOT_GAP)
    end
    -- last: anchor the mode switch again (laying out the rows re-anchors the toolbar; see MarketView)
    self.mode:ClearAllPoints()
    self.mode:SetPoint("LEFT", bar, "LEFT", 0, 0)
    self.modeDrop:ClearAllPoints()
    self.modeDrop:SetPoint("LEFT", bar, "LEFT", 0, 0)
  end
  v:SetCompact(slots.compact)
  -- lay the toolbar out again when shown, and once more on the next frame (anchors set before the toolbar was first
  -- drawn could stay unresolved in game)
  local function relayout()
    v:SetCompact(slots.compact) -- re-anchors the switch last
  end
  v:SetScript("OnShow", function()
    relayout()
    C_Timer.After(0, function()
      if v:IsVisible() then
        relayout()
      end
    end)
    UI:RefreshOverview()
  end)
  ns.ItemCache.OnNamesChanged(function()
    if v:IsShown() then
      UI:RenderOverview()
    end
  end)
  return v
end

local function itemClass(id)
  return ns.ItemCache.Get(id).classID
end

-- rebuild the summary for the viewed auction house and period, then draw it
function UI:RefreshOverview()
  local v = self.overviewView
  if not (v and v:IsShown()) then
    return
  end
  local index, why = self:ViewIndex()
  local hide = ns.AME.watch and ns.AME.watch:Hidden() or nil
  self.overview = index
      and ns.MarketStats.Summary(
        index,
        self.ovPeriod,
        itemClass,
        hide,
        ns.Settings:Get("outlierFactor"),
        self.ovMoverClass
      )
    or nil
  self.overviewIndex = index
  if not index then
    if not ns.AME:HistoryLoaded() then
      ns.AME:LoadHistory()
      ns.AME:RebuildIndex()
    end
    self.overviewWhy = why == "empty" and "empty" or "loading"
  elseif not index.stats then
    -- built while the Overview was off, or saved by an older version: rebuild it with statistics
    self.overviewWhy = "building"
    ns.AME:RefreshIndex(self:ViewShard())
  elseif not self.overview then
    self.overviewWhy = "noscan"
  end
  self:RenderOverview()
end

function UI:RenderOverview()
  local v = self.overviewView
  if not (v and v:IsShown()) then
    return
  end
  v.period:Select(self.ovPeriod, true)
  v.periodDrop:SetValue(self.ovPeriod)
  local o = self.overview
  local shown = o and true or false
  v.cardRow:SetShown(shown)
  v.left:SetShown(shown)
  v.right:SetShown(shown)
  v.message:SetShown(not shown)
  local house = ns.HOUSE_LABEL[self:ViewHouse()] or self:ViewHouse()
  if not o then
    local why = self.overviewWhy
    v.message:SetText(
      why == "empty"
          and L["No price history for the %s yet: scan there (any character on this account counts)."]:format(house)
        or why == "noscan" and L["No full scan of the %s in the last 30 days. Market totals need one: run a full scan there (any scanner)."]:format(
          house
        )
        or why == "building" and L["Building market statistics..."]
        or (ns.AME:HistoryLoaded() and L["Building market index..."] or L["Loading history..."])
    )
    v.slots.status:SetText("")
    return
  end

  -- the cards: the figure, its change over the period (coloured by the card) and a note on what it counts
  local c = v.cards
  local function set(card, value, change, note)
    local text, kind = delta(change)
    card:Set({ value = value, delta = text, deltaKind = kind, note = note })
  end
  set(
    c[1],
    o.level and ("%.1f"):format(o.level) or W.NONE,
    o.levelChange,
    L["%s steadily listed items · 30 days ago = 100"]:format(W.Thousands(o.basket or 0))
  )
  set(
    c[2],
    o.cpi and ("%.1f"):format(o.cpi) or W.NONE,
    o.cpiChange,
    o.cpiWeights == "turnover" and L["weighted by spending"] or L["weighted by listed value"]
  )
  local factor = ns.Settings:Get("outlierFactor")
  set(
    c[3],
    W.BigMoney(o.value),
    o.valueChange,
    (factor and factor > 1) and L["each price capped at %dx its 30-day average"]:format(factor) or nil
  )
  c[4]:Set({
    value = "~" .. W.BigMoney(o.turnover),
    delta = L["/day"],
    deltaKind = "mute",
    note = L["units sold a day x price"],
  })
  set(
    c[5],
    W.Thousands(o.auctions),
    o.auctionsChange,
    L["%s items · %s units"]:format(W.Thousands(o.items or 0), W.Count(o.units or 0))
  )
  local moved = o.up + o.down
  c[6]:Set({
    value = moved > 0 and ("%d%%"):format(math.floor(100 * o.up / moved + 0.5)) or W.NONE,
    delta = moved > 0 and L["rising"] or nil,
    deltaKind = "mute",
    rise = o.up,
    fall = o.down,
    note = L["%s up · %s down · %s Buy · %s Sell"]:format(
      W.Thousands(o.up),
      W.Thousands(o.down),
      W.Thousands(o.buy or 0),
      W.Thousands(o.sell or 0)
    ),
  })

  -- movers
  local scope = self.ovMoverClass and ns.ItemCache.ClassName(self.ovMoverClass) or L["steadily listed items"]
  local note = ("%s, %s"):format(periodText(self.ovPeriod), scope)
  v.risersHead:Set(L["Biggest risers"], note)
  v.fallersHead:Set(L["Biggest fallers"], note)
  v.riserTable:SetData(o.risers)
  v.riserTable:Render()
  v.fallerTable:SetData(o.fallers)
  v.fallerTable:Render()

  -- the movers' category choice: the categories listed now
  local choices = { { false, L["All categories"] } }
  for _, sct in ipairs(o.sectors) do
    if sct.classID ~= ns.MarketStats.OTHER then
      choices[#choices + 1] = { sct.classID, ns.ItemCache.ClassName(sct.classID) }
    end
  end
  v.moverClass:SetOptions(choices)
  v.moverClass:SetValue(self.ovMoverClass or false)

  -- categories: the share bars are full at the biggest category's share
  for _, sct in ipairs(o.sectors) do
    sct.name = sct.classID == ns.MarketStats.OTHER and L["Other"] or ns.ItemCache.ClassName(sct.classID)
  end
  local t = v.sectorTable
  t.opts.columns[3].max = math.max(o.sectors[1] and o.sectors[1].share or 1, 0.01)
  t:SetData(o.sectors)
  t:Render()

  -- largest items
  v.largestTable:SetData(o.top)
  v.largestTable:Render()

  self:RenderOverviewChart()
  local parts = {
    ns.ShardLabel(self:ViewShard()),
    L["totals from the full scan of %s"]:format(date("%b %d", o.day * DAY)),
    L["index: %d steady items"]:format(o.basket or 0),
  }
  if o.cpiBasket and o.cpiBasket > 0 then
    parts[#parts + 1] = (
      o.cpiWeights == "turnover" and L["CPI: %d items, weighted by spending"]
      or L["CPI: %d items, weighted by listed value"]
    ):format(o.cpiBasket)
  end
  v.slots.status:SetText(table.concat(parts, W.SEP))
end

function UI:RenderOverviewChart()
  local v, o = self.overviewView, self.overview
  if not (v and o) then
    return
  end
  v.chartModes:Select(self.ovChart, true)
  local s = o.series
  local days, ys
  if self.ovChart == "index" then
    days, ys = s.levelDays, s.level
  elseif self.ovChart == "cpi" then
    days, ys = s.cpiDays, s.cpi
  elseif self.ovChart == "value" then
    days, ys = s.days, s.value
  else
    days, ys = s.days, s.auctions
  end
  local xs = {}
  for i, d in ipairs(days) do
    xs[i] = d * DAY
  end
  local chart = v.chart
  chart:ClearSeries()
  if #xs < 2 then
    chart:SetMessage(L["Not enough days yet: the chart fills in with a full scan a day."])
    return
  end
  chart:SetMessage(nil)
  chart:SetSeries("y", { xs = xs, ys = ys, kind = "area", color = W.COLORS.chart.market, marker = true })
end
