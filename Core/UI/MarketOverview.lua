-- Market tab, Overview mode: the whole auction house at a glance (MarketStats). Layout (UI.Slots): toolbar = Screener |
-- Overview and the change period; header = stat cards (market index, CPI, listed value, turnover, auctions, breadth);
-- main = the 30-day chart with risers and fallers under it, and categories by listed value with the largest items on
-- the right. Narrow windows keep the chart and the categories.
local _, ns = ...
local L = ns.L

local W = ns.Widgets
local UI = ns.UI
local DAY = ns.DAY

local ROW_H = 16
local RIGHT_W = 400
local LARGEST_ROWS = 3
local MOVER_ROWS = 5
local CATEGORY_ROWS = 12

UI.MARKET_MODES = {
  { "screener", L["Screener"] },
  { "overview", L["Overview"] },
}
local PERIODS = {
  { 1, L["1 day"] },
  { 7, L["7 days"] },
  { 30, L["30 days"] },
}
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

local function panel(parent)
  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  W.Skin(f, W.COLORS.panel)
  return f
end

local function heading(parent, text, note)
  local h = W.Text(parent, "GameFontNormal")
  h:SetPoint("TOPLEFT", 8, -6)
  h:SetText(text)
  if note then
    local n = W.Text(parent, "GameFontDisableSmall")
    n:SetPoint("LEFT", h, "RIGHT", 6, 0)
    n:SetText(note)
    h.note = n
  end
  return h
end

-- A fixed list of rows under a heading: cols = { { width, justify }, ... } after the first (which takes the rest).
-- rows[i].cells[k] are font strings; rows[i].data is what the row shows (onClick(data), tooltip(tip, data)).
local function rowList(parent, count, cols, top, opts)
  opts = opts or {}
  local rows = {}
  for i = 1, count do
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 6, top - (i - 1) * ROW_H)
    r:SetPoint("RIGHT", -6, 0)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(r)
    W.Fill(hl, W.COLORS.rowHover)
    r.cells = {}
    local right = -4
    for k = #cols, 1, -1 do
      local c = cols[k]
      local fs = W.Text(r, c.font or "GameFontHighlightSmall", c.justify or "RIGHT")
      fs:SetWidth(c.width)
      fs:SetPoint("RIGHT", right, 0)
      right = right - c.width - 6
      r.cells[k + 1] = fs
    end
    local name = W.Text(r, "GameFontHighlightSmall", "LEFT")
    name:SetPoint("LEFT", 4, 0)
    name:SetPoint("RIGHT", right, 0)
    W.Truncated(name)
    r.cells[1] = name
    if opts.bar then -- a share bar in the column it names
      r.bar = r:CreateTexture(nil, "ARTWORK")
      r.bar:SetHeight(7)
      r.bar:SetPoint("LEFT", r.cells[opts.bar], "LEFT", 0, 0)
      W.Fill(r.bar, W.COLORS.accent)
    end
    r:SetScript("OnClick", function(self)
      if self.data and opts.onClick then
        opts.onClick(self.data)
      end
    end)
    if opts.tooltip then
      W.Tooltip(r, function(tip, self)
        if not self.data then
          return false
        end
        return opts.tooltip(tip, self.data)
      end)
    end
    r:Hide()
    rows[i] = r
  end
  return rows
end

-- an item's name; one the client hasn't loaded yet is asked for, and the overview redraws once it arrives
local pendingNames = {}
local redrawQueued = false
local function itemName(key)
  local name, _, quality = W.ItemInfo(key)
  name = name or ns.ItemCache.Name(key)
  if not name and not pendingNames[key] then
    pendingNames[key] = true -- asked once a session (an item that never loads mustn't redraw forever)
    W.OnItemLoaded(key, function()
      if not redrawQueued then
        redrawQueued = true
        C_Timer.After(0.2, function()
          redrawQueued = false
          UI:RenderOverview()
        end)
      end
    end)
  end
  return W.QualityText(quality, name or ("item:" .. tostring(key)))
end

local function changeText(x)
  return x and W.Percent(x) or W.Dim("-")
end

local function itemTip(tip, s)
  W.SetItemTip(tip, s.itemID or s.id)
end

function UI:CreateMarketOverview(area)
  local v = CreateFrame("Frame", nil, area)
  v:SetAllPoints(area)
  v:Hide()
  self.overviewView = v
  self.ovPeriod, self.ovChart = 7, "index"
  local slots = UI.Slots(v, { toolbar = 22, header = 42, headerBelow = true, status = true })
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

  -- the stat cards
  v.cardRow = W.CardRow(slots.header, {
    { L["Market index"], term = "mxIndex" },
    { L["CPI"], term = "mxCpi" },
    { L["Listed value"], term = "mxValue" },
    { L["Turnover (estimate)"], term = "mxTurnover" },
    { L["Auctions"], term = "mxAuctions" },
    { L["Breadth"], term = "mxBreadth" },
  }, { width = UI.WIDTH - 20 })
  v.cardRow:SetPoint("TOPLEFT", 0, 0)
  v.cardRow:SetPoint("RIGHT", 0, 0)
  v.cards = v.cardRow.cards

  local main = slots.main
  -- right column: categories, the largest items
  v.right = CreateFrame("Frame", nil, main)
  v.right:SetPoint("TOPRIGHT", 0, 0)
  v.right:SetPoint("BOTTOMRIGHT", 0, 0)
  v.right:SetWidth(RIGHT_W)
  v.largest = panel(v.right)
  v.largest:SetPoint("BOTTOMLEFT", 0, 0)
  v.largest:SetPoint("BOTTOMRIGHT", 0, 0)
  v.largest:SetHeight(28 + LARGEST_ROWS * ROW_H)
  heading(v.largest, L["Largest by value"], L["what the total leans on"])
  v.largestRows = rowList(v.largest, LARGEST_ROWS, { { width = 120 }, { width = 110 } }, -24, {
    onClick = function(t)
      UI:ShowItem(t.id)
    end,
    tooltip = function(tip, t)
      W.SetItemTip(tip, t.id)
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

  v.sectors = panel(v.right)
  v.sectors:SetPoint("TOPLEFT", 0, 0)
  v.sectors:SetPoint("TOPRIGHT", 0, 0)
  v.sectors:SetPoint("BOTTOM", v.largest, "TOP", 0, UI.SLOT_GAP)
  heading(v.sectors, L["Categories"], L["by listed value"])
  local SECTOR_COLS = {
    { width = 64 }, -- value
    { width = 76 }, -- share: a bar on the left, the % on the right
    { width = 46 }, -- change
    { width = 64 }, -- turnover
  }
  v.sectorHead = rowList(v.sectors, 1, SECTOR_COLS, -24)[1]
  v.sectorHead:EnableMouse(false)
  for k, text in ipairs({ L["Category"], L["Value"], L["Share"], L["Change"], L["Turnover"] }) do
    v.sectorHead.cells[k]:SetText(W.Color("gold", text))
  end
  v.sectorHead:Show()
  v.sectorRows = rowList(v.sectors, CATEGORY_ROWS, SECTOR_COLS, -24 - ROW_H - 2, {
    bar = 3,
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

  -- left: the chart, risers and fallers
  v.left = CreateFrame("Frame", nil, main)
  v.left:SetPoint("TOPLEFT", 0, 0)
  v.left:SetPoint("BOTTOMRIGHT", v.right, "BOTTOMLEFT", -UI.SLOT_GAP, 0)
  local moversH = 28 + MOVER_ROWS * ROW_H
  v.movers = CreateFrame("Frame", nil, v.left)
  v.movers:SetPoint("BOTTOMLEFT", 0, 0)
  v.movers:SetPoint("BOTTOMRIGHT", 0, 0)
  v.movers:SetHeight(moversH)
  v.risers, v.fallers = panel(v.movers), panel(v.movers)
  v.risers:SetPoint("TOPLEFT", 0, 0)
  v.risers:SetPoint("BOTTOMRIGHT", v.movers, "BOTTOM", -UI.SLOT_GAP / 2, 0)
  v.fallers:SetPoint("TOPRIGHT", 0, 0)
  v.fallers:SetPoint("BOTTOMLEFT", v.movers, "BOTTOM", UI.SLOT_GAP / 2, 0)
  v.risersHead = heading(v.risers, L["Biggest risers"], "")
  v.fallersHead = heading(v.fallers, L["Biggest fallers"], "")
  local moverOpts = {
    onClick = function(s)
      UI:ShowItem(s.itemID)
    end,
    tooltip = itemTip,
  }
  v.riserRows = rowList(v.risers, MOVER_ROWS, { { width = 70 }, { width = 52 } }, -24, moverOpts)
  v.fallerRows = rowList(v.fallers, MOVER_ROWS, { { width = 70 }, { width = 52 } }, -24, moverOpts)

  v.chartPanel = panel(v.left)
  v.chartPanel:SetPoint("TOPLEFT", 0, 0)
  v.chartPanel:SetPoint("TOPRIGHT", 0, 0)
  v.chartPanel:SetPoint("BOTTOM", v.movers, "TOP", 0, UI.SLOT_GAP)
  v.chartHead = heading(v.chartPanel, L["Last 30 days"])
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

  function v:SetCompact(on)
    slots:SetCompact(on)
    self.mode:SetShown(not on)
    self.modeDrop:SetShown(on)
    self.period:SetShown(not on)
    self.periodLabel:SetShown(not on)
    self.periodDrop:SetShown(on)
    self.moversLabel:SetShown(not on) -- narrow windows leave risers and fallers out
    self.moverClass:SetShown(not on)
    -- narrow: the chart over the categories, one column
    self.movers:SetShown(not on)
    self.largest:SetShown(not on)
    self.right:ClearAllPoints()
    self.left:ClearAllPoints()
    self.chartPanel:ClearAllPoints()
    if on then
      self.left:SetPoint("TOPLEFT", 0, 0)
      self.left:SetPoint("TOPRIGHT", 0, 0)
      self.left:SetHeight(130)
      self.chartPanel:SetAllPoints(self.left)
      self.right:SetPoint("TOPLEFT", self.left, "BOTTOMLEFT", 0, -UI.SLOT_GAP)
      self.right:SetPoint("BOTTOMRIGHT", 0, 0)
      self.sectors:SetPoint("BOTTOM", self.right, "BOTTOM", 0, 0)
    else
      self.right:SetPoint("TOPRIGHT", 0, 0)
      self.right:SetPoint("BOTTOMRIGHT", 0, 0)
      self.right:SetWidth(RIGHT_W)
      self.left:SetPoint("TOPLEFT", 0, 0)
      self.left:SetPoint("BOTTOMRIGHT", self.right, "BOTTOMLEFT", -UI.SLOT_GAP, 0)
      self.chartPanel:SetPoint("TOPLEFT", 0, 0)
      self.chartPanel:SetPoint("TOPRIGHT", 0, 0)
      self.chartPanel:SetPoint("BOTTOM", self.movers, "TOP", 0, UI.SLOT_GAP)
      self.sectors:SetPoint("BOTTOM", self.largest, "TOP", 0, UI.SLOT_GAP)
    end
  end
  v:SetCompact(slots.compact)
  v:SetScript("OnShow", function()
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

local function setCard(card, value, delta)
  card.value:SetText(value .. (delta and ("  " .. W.Percent(delta)) or ""))
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

  local c = v.cards
  setCard(c[1], o.level and ("%.1f"):format(o.level) or W.NONE, o.levelChange)
  setCard(c[2], o.cpi and ("%.1f"):format(o.cpi) or W.NONE, o.cpiChange)
  setCard(c[3], W.BigMoney(o.value), o.valueChange)
  c[4].value:SetText("~" .. W.BigMoney(o.turnover) .. W.Dim(L["/day"]))
  setCard(c[5], W.Thousands(o.auctions), o.auctionsChange)
  local moved = o.up + o.down
  c[6].value:SetText(
    moved > 0 and (("%d%%"):format(math.floor(100 * o.up / moved + 0.5)) .. W.Dim(" " .. L["rising"])) or W.NONE
  )

  -- movers
  local periodText = PERIODS[(self.ovPeriod == 1 and 1) or (self.ovPeriod == 30 and 3) or 2][2]
  local scope = self.ovMoverClass and ns.ItemCache.ClassName(self.ovMoverClass) or L["steadily listed items"]
  for _, h in ipairs({ v.risersHead, v.fallersHead }) do
    h.note:SetText(("%s, %s"):format(periodText, scope))
  end
  local key = self.ovPeriod == 1 and "change1" or self.ovPeriod == 30 and "change30" or "change7"
  local function fill(rows, list)
    for i, r in ipairs(rows) do
      local s = list[i]
      r.data = s
      r:SetShown(s and true or false)
      if s then
        r.cells[1]:SetText(itemName(s.itemID))
        r.cells[2]:SetText(W.Money(s.market, true))
        r.cells[3]:SetText(W.Percent(s[key]))
      end
    end
  end
  fill(v.riserRows, o.risers)
  fill(v.fallerRows, o.fallers)

  -- the movers' category choice: the categories listed now
  local choices = { { false, L["All categories"] } }
  for _, sct in ipairs(o.sectors) do
    if sct.classID ~= ns.MarketStats.OTHER then
      choices[#choices + 1] = { sct.classID, ns.ItemCache.ClassName(sct.classID) }
    end
  end
  v.moverClass:SetOptions(choices)
  v.moverClass:SetValue(self.ovMoverClass or false)

  -- categories
  local top = o.sectors[1] and o.sectors[1].share or 1
  for i, r in ipairs(v.sectorRows) do
    local sct = o.sectors[i]
    r.data = sct
    r:SetShown(sct and true or false)
    if sct then
      sct.name = sct.classID == ns.MarketStats.OTHER and L["Other"] or ns.ItemCache.ClassName(sct.classID)
      r.cells[1]:SetText(W.Color("gold", sct.name))
      r.cells[2]:SetText(W.BigMoney(sct.value, 10000))
      r.cells[3]:SetText(("%d%%"):format(math.floor(sct.share * 100 + 0.5)))
      r.bar:SetWidth(math.max(1, 40 * sct.share / math.max(top, 0.01)))
      r.cells[4]:SetText(changeText(sct.change))
      r.cells[5]:SetText(sct.turnover and ("~" .. W.BigMoney(sct.turnover, 10000)) or W.Dim("-"))
    end
  end

  -- largest items
  for i, r in ipairs(v.largestRows) do
    local t = o.top[i]
    r.data = t
    r:SetShown(t and true or false)
    if t then
      r.cells[1]:SetText(itemName(t.id))
      r.cells[2]:SetText(W.Count(t.qty) .. " x " .. W.Money(t.price, true))
      r.cells[3]:SetText(W.BigMoney(t.value, 10000) .. (t.raw and W.Dim(" " .. L["capped"]) or ""))
    end
  end

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
  chart:SetSeries("y", { xs = xs, ys = ys, kind = "area", color = { 0.3, 0.85, 0.78, 1 }, marker = true })
end
