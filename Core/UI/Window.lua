-- Main window: "Item" tab (chart + stats for one item) and "Market" tab (screener over the market index).
local _, ns = ...
local L = ns.L

local W = ns.Widgets
local DAY = 86400

local UI = {}
ns.UI = UI

-- 2D plots every recent scan (intraday); the others plot daily history
local RANGES = { { "2D", 2 }, { "7D", 7 }, { "30D", 30 }, { "90D", 90 }, { "1Y", 365 }, { "All", nil, L["All"] } }
local INTRADAY = "2D"

-- the average period used everywhere (screener column, item card, tooltips): Settings, default 7 days
local function avgDays()
  return ns.Settings:Get("tooltipAvgDays") or 7
end

---------------------------------------------------------------------------------------------------------------------
-- window shell

local contentArea

function UI:Create()
  if self.frame then
    return self.frame
  end
  local f = CreateFrame("Frame", "AMEMainWindow", UIParent, "BackdropTemplate")
  self.frame = f
  f:SetSize(980, 500)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  W.Skin(f)
  f:Hide()
  tinsert(UISpecialFrames, "AMEMainWindow") -- Escape closes

  local logo = f:CreateTexture(nil, "ARTWORK")
  logo:SetTexture(ns.ICON)
  logo:SetSize(18, 18)
  logo:SetPoint("TOPLEFT", 10, -8)
  local title = W.Text(f, "GameFontNormal")
  title:SetPoint("LEFT", logo, "RIGHT", 6, 0)
  self.title = title
  self.shardText = W.Text(f, "GameFontDisableSmall")
  self.shardText:SetPoint("LEFT", title, "RIGHT", 10, 0)
  local houses = { { "Horde", L["Horde AH"] }, { "Alliance", L["Alliance AH"] }, { "Neutral", L["Goblin AH"] } }
  self.viewSelect = W.Dropdown(f, 110, houses, function(value)
    UI.viewHouse = value
    UI:ViewChanged()
  end)
  self.viewSelect.neutral = true
  self.viewSelect.values = houses
  self.viewSelect:SetPoint("LEFT", self.shardText, "RIGHT", 8, 0)

  local close = W.CloseButton(f)
  close:SetPoint("TOPRIGHT", -6, -7)
  self.closeButton = close

  self.tabs = {}
  local function tab(name, label, x)
    local b = W.Button(f, label, 66, 20, function()
      UI:ShowTab(name)
    end)
    b:SetPoint("TOPRIGHT", -(34 + x), -8)
    self.tabs[name] = b
  end
  tab("market", L["Market"], 420)
  tab("arbitrage", L["Arbitrage"], 350)
  tab("portfolio", L["Portfolio"], 280)
  tab("item", L["Item"], 210)
  tab("sync", L["Sync"], 140)
  tab("settings", L["Settings"], 70)
  tab("guide", L["Guide"], 0)

  self.views = {
    item = self:CreateItemView(f),
    market = self:CreateMarketView(f),
    guide = ns.Help.CreateGuide(f, contentArea),
    sync = self:CreateSyncView(f, contentArea),
    arbitrage = self:CreateArbitrageView(f, contentArea),
    portfolio = self:CreatePortfolioView(f, contentArea),
    settings = self:CreateSettingsView(f, contentArea),
  }
  local footer = W.Text(f, "GameFontDisableSmall", "RIGHT")
  footer:SetPoint("BOTTOMRIGHT", -12, 7)
  footer:SetText(
    "Azeroth Mercantile Exchange " .. L["%s  -  created by Tyken Evanion  -  PvP Horde, WoW Forever"]:format(ns.VERSION)
  )
  footer:SetAlpha(0.7)
  self.footer = footer

  f:SetScript("OnShow", function()
    UI:ViewChanged()
    UI:ApplyTheme()
  end)
  self:RefreshViewOptions()
  self:ApplyTheme()
  return f
end

-- Which auction house the Market and Item tabs show: the one you're at, unless picked in the title bar.
function UI:ViewHouse()
  return self.viewHouse or ns.AME:CurrentHouse()
end

function UI:ViewShard()
  return ns.ShardKey(ns.AME:MarketRealmName(), self:ViewHouse())
end

-- market index for the viewed house: nil + "loading" (built in the background, refreshes when ready) or "empty"
function UI:ViewIndex()
  local AME, shard = ns.AME, self:ViewShard()
  if shard == AME.indexShard and AME.index then
    return AME.index
  end
  if AME.indexes[shard] then
    return AME.indexes[shard]
  end
  if AME:HistoryLoaded() and not AME:HasData(shard) then
    return nil, "empty"
  end
  if AME:HistoryLoaded() and self.viewLoading ~= shard then
    self.viewLoading = shard
    AME:IndexFor(shard, function()
      self.viewLoading = nil
      self:RefreshMarket(true)
    end)
  end
  return nil, "loading"
end

-- The title-bar selector lists only auction houses with history (plus the one you're at); with just one it's
-- plain text.
function UI:RefreshViewOptions()
  if not self.frame then
    return
  end
  local AME = ns.AME
  local realm, current = AME:MarketRealmName(), AME:CurrentHouse()
  local options = {}
  for _, house in ipairs({ "Horde", "Alliance", "Neutral" }) do
    local hasData = AME:HasData(ns.ShardKey(realm, house))
    if house == current or hasData then
      options[#options + 1] = { house, ns.HOUSE_LABEL[house] }
    end
  end
  if self.viewHouse then
    local listed = false
    for _, o in ipairs(options) do
      listed = listed or o[1] == self.viewHouse
    end
    if not listed then
      self.viewHouse = nil
    end
  end
  self.viewSelect:SetOptions(options)
  self.viewSelect:SetValue(self:ViewHouse())
  local several = #options > 1
  self.viewSelect:SetShown(several)
  self.shardText:SetText(several and realm or ns.ShardLabel(self:ViewShard()))
end

function UI:ViewChanged()
  if not self.frame then
    return
  end
  self:RefreshViewOptions()
  self:ApplyTheme()
  self.list = nil
  self:RefreshMarket(true)
  if self.current == "item" and self.itemID then
    self:ShowItem(self.itemID)
  end
end

-- Faction colours for the chrome, from the auction house being viewed (by default the one in use, or the character's
-- faction before the first visit).
function UI:ApplyTheme()
  if not self.frame then
    return
  end
  local preferred = ns.Settings:Get("theme")
  W.SetTheme(preferred ~= "auto" and preferred or self:ViewHouse())
  local a = W.COLORS.accent
  self.title:SetText(("|c%sAzeroth|r Mercantile Exchange"):format(W.Hex(a)))
  for n, b in pairs(self.tabs) do
    b:SetSelected(n == self.current)
  end
  if self.chartHolder then
    self.chartHolder:SetBackdropBorderColor(a[1], a[2], a[3], 0.22)
    W.TintInnerGlow(self.chartHolder)
  end
  local iv = self.itemView
  if iv then
    for _, b in ipairs(iv.rangeButtons) do
      b:SetSelected(b.key == self.rangeKey)
    end
  end
  local mv = self.marketView
  if mv then
    for _, line in ipairs(mv.side.lines) do
      line.sel:SetColorTexture(a[1], a[2], a[3], 0.2)
    end
    self:RenderMarket()
  end
end

function UI:ShowTab(name)
  self:Create()
  for n, v in pairs(self.views) do
    v:SetShown(n == name)
    self.tabs[n]:SetSelected(n == name)
  end
  self.current = name
  if name == "market" then
    self:RefreshMarket()
  end
end

function UI:Toggle(itemID)
  self:Create()
  if itemID then
    self.frame:Show()
    self:ShowItem(itemID)
  elseif self.frame:IsShown() then
    self.frame:Hide()
  else
    self.frame:Show()
    self:ShowTab(self.current or "market")
  end
end

function contentArea(parent)
  local v = CreateFrame("Frame", nil, parent)
  v:SetPoint("TOPLEFT", 10, -36)
  v:SetPoint("BOTTOMRIGHT", -10, 24) -- room for the footer
  v:Hide()
  return v
end

---------------------------------------------------------------------------------------------------------------------
-- Item view

local function statCard(parent, label)
  local c = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  W.Skin(c, W.COLORS.panel)
  c:SetSize(118, 40)
  c.label = W.Text(c, "GameFontDisableSmall")
  c.label:SetPoint("TOPLEFT", 8, -6)
  c.label:SetText(label)
  c.value = W.Text(c, "GameFontHighlight")
  c.value:SetPoint("BOTTOMLEFT", 8, 6)
  return c
end

function UI:CreateItemView(parent)
  local v = contentArea(parent)

  -- search / header
  local box = W.Input(v)
  box:SetSize(230, 20)
  box:SetPoint("TOPRIGHT", -2, 0)
  box:SetAutoFocus(false)
  box:SetScript("OnEnterPressed", function(self)
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
  end)
  box.hint = W.Text(box, "GameFontDisableSmall")
  box.hint:SetPoint("LEFT", 6, 0)
  box.hint:SetPoint("RIGHT", -6, 0) -- clipped to the box (translations run longer)
  box.hint:SetJustifyH("LEFT")
  box.hint:SetWordWrap(false)
  box.hint:SetText(L["Item name, ID, or Shift-click an item"])
  box:SetScript("OnTextChanged", function(self, user)
    local text = self:GetText()
    self.hint:SetShown(text == "")
    if user then
      UI:SuggestItems(self, text)
    end
  end)
  box:HookScript("OnEditFocusGained", function()
    UI:WarmItemNames()
  end)
  box:SetScript("OnEscapePressed", function(self)
    self:SetText("")
    self:ClearFocus()
    W.HideMenu(self)
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
  v.alertSignal:SetPoint("TOPRIGHT", -96, -24)
  local function goldAlert(field, hint)
    local input = W.Input(v)
    input:SetSize(64, 18)
    input:SetNumeric(true)
    input.hint = W.Text(input, "GameFontDisableSmall")
    input.hint:SetPoint("LEFT", 6, 0)
    input.hint:SetPoint("RIGHT", -6, 0) -- clipped to the box (translations run longer)
    input.hint:SetJustifyH("LEFT")
    input.hint:SetWordWrap(false)
    input.hint:SetText(hint)
    input:SetScript("OnTextChanged", function(self, user)
      self.hint:SetShown(self:GetText() == "")
      if user and UI.itemID then
        local g = tonumber(self:GetText())
        ns.AME.watch:SetAlert(UI.itemID, { [field] = g and g * 10000 or false })
        UI:UpdateWatchControls(true)
      end
    end)
    input:SetScript("OnEnterPressed", input.ClearFocus)
    return input
  end
  v.alertAbove = goldAlert("above", L["above g"])
  v.alertAbove:SetPoint("RIGHT", v.alertSignal, "LEFT", -8, 0)
  v.alertBelow = goldAlert("below", L["below g"])
  v.alertBelow:SetPoint("RIGHT", v.alertAbove, "LEFT", -4, 0)
  v.alertLabel = W.Text(v, "GameFontDisableSmall", "RIGHT")
  v.alertLabel:SetPoint("RIGHT", v.alertBelow, "LEFT", -6, 0)
  v.alertLabel:SetText(L["Alert when"])
  v.watch = W.Button(v, L["Watch"], 84, 18, function(self)
    UI:WatchMenu(self, UI.itemID)
  end)
  v.watch.star = v.watch:CreateTexture(nil, "OVERLAY")
  W.SetStar(v.watch.star, false)
  v.watch.star:SetSize(14, 14)
  v.watch.star:SetPoint("LEFT", 6, 0)
  v.watch.label:ClearAllPoints()
  v.watch.label:SetPoint("LEFT", 24, 0)
  v.watch:SetPoint("RIGHT", v.alertLabel, "LEFT", -12, 0)

  v.icon = v:CreateTexture(nil, "ARTWORK")
  v.icon:SetSize(32, 32)
  v.icon:SetPoint("TOPLEFT", 0, 0)
  v.name = W.Text(v, "GameFontNormalLarge")
  v.name:SetPoint("TOPLEFT", v.icon, "TOPRIGHT", 8, -2)
  v.sub = W.Text(v, "GameFontDisableSmall")
  v.sub:SetPoint("BOTTOMLEFT", v.icon, "BOTTOMRIGHT", 8, 2)

  -- stat cards
  v.cards = {}
  local labels =
    { L["Market"], L["Lowest"], L["Average"], L["7d change"], L["Volatility"], L["Supply  ·  sells/day"], L["Signal"] }
  local terms = { "market", "min", "avg", "change7", "vol30", "sellRate", "signal" }
  for i, label in ipairs(labels) do
    local c = statCard(v, label)
    c:EnableMouse(true)
    ns.Help.Explain(c, terms[i])
    c:SetSize((980 - 20 - 6 * 6) / 7, 40)
    if i == 1 then
      c:SetPoint("TOPLEFT", v.icon, "BOTTOMLEFT", 0, -10)
    else
      c:SetPoint("LEFT", v.cards[i - 1], "RIGHT", 6, 0)
    end
    v.cards[i] = c
  end

  -- range buttons
  v.rangeButtons = {}
  for i, r in ipairs(RANGES) do
    local b = W.Button(v, r[3] or r[1], 44, 18, function()
      UI:SetRange(r[2], r[1])
    end)
    if i == 1 then
      b:SetPoint("TOPLEFT", v.cards[1], "BOTTOMLEFT", 0, -10)
    else
      b:SetPoint("LEFT", v.rangeButtons[i - 1], "RIGHT", 4, 0)
    end
    b.key = r[1]
    v.rangeButtons[i] = b
  end
  v.style = W.Button(v, L["Candles"], 64, 18, function()
    local style = ns.Settings:Get("chartStyle") == "candles" and "line" or "candles"
    ns.Settings:Set("chartStyle", style)
    UI:DrawItemChart()
  end)
  v.style:SetPoint("LEFT", v.rangeButtons[#RANGES], "RIGHT", 12, 0)
  ns.Help.Explain(v.style, "candles")
  v.legend = W.Text(v, "GameFontDisableSmall")
  v.legend:SetPoint("LEFT", v.style, "RIGHT", 12, 0)

  -- chart
  local holder = CreateFrame("Frame", nil, v, "BackdropTemplate")
  W.Skin(holder, { 0.07, 0.08, 0.1, 1 }, W.COLORS.border)
  W.InnerGlow(holder)
  self.chartHolder = holder
  holder:SetPoint("TOPLEFT", v.rangeButtons[1], "BOTTOMLEFT", 0, -8)
  holder:SetPoint("BOTTOMRIGHT", 0, 22)

  -- posting price suggestion (Pricing / Posting), under the chart
  v.post = CreateFrame("Frame", nil, v)
  v.post:SetPoint("BOTTOMLEFT", 0, 0)
  v.post:SetPoint("BOTTOMRIGHT", 0, 0)
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
    local lines = { "|cffffffff" .. date(UI.intradayMode and "%a %b %d, %H:%M" or "%a %b %d, %Y", x) .. "|r" }
    local c = rows.candles and UI.candles
    if c and rows.candles.x == x then
      local i = rows.candles.index
      if c.period > DAY then
        lines[1] = ("|cffffffff%s - %s|r"):format(
          date("%b %d", x - c.period / 2),
          date("%b %d, %Y", x + c.period / 2 - DAY)
        )
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
  for _, b in ipairs(self.itemView.rangeButtons) do
    b:SetSelected(b.key == key)
  end
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
      color = { 0.3, 0.85, 0.45, 1 },
    })
    legend = W.Swatch(0.3, 0.85, 0.45)
      .. " "
      .. L["up"]
      .. "  "
      .. W.Swatch(1, 0.38, 0.35)
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
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    v.name:SetText((color and color.hex or "|cffffffff") .. (name or ("item:" .. itemID)) .. "|r")
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
      .. (s.sellRate and ("  |cff999999%s|r"):format(W.Rate(s.sellRate)) or "")
  )
  cards[7].label:SetText(s.phase and ns.Analytics.PHASE_LABEL[s.phase] or L["Signal"])
  cards[7].value:SetText(W.Signal(s.signal) .. ("  |cff999999%+d|r"):format(s.score or 0))
  v.sub:SetText(
    L["%s  ·  %d days of history  ·  data %s %s%s%s"]:format(
      ns.ShardLabel(self:ViewShard()),
      #series,
      W.Confidence(ns.Analytics.Confidence(s, math.floor(GetServerTime() / DAY))),
      L["%d scans in 7 days"]:format(s.scans7 or 0),
      latest and ("  ·  " .. L["last seen %s"]:format(date("%b %d %H:%M", latest.t))) or "",
      dropped > 0
          and ("  ·  |cffffcc00%s|r"):format(
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
    local color = h.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[h.quality]
    entries[i] = {
      text = (color and color.hex or "|cffffffff") .. h.name .. "|r",
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

---------------------------------------------------------------------------------------------------------------------
-- Watchlists

-- menu of lists with checkmarks for an item, plus "New list..."
function UI:WatchMenu(anchor, itemID)
  if not itemID then
    return
  end
  local watch = ns.AME.watch
  local entries = {}
  for i, l in ipairs(watch:Lists()) do
    entries[#entries + 1] = {
      text = l.name,
      checked = watch:Has(i, itemID),
      func = function()
        watch:Toggle(i, itemID)
        UI:WatchChanged()
      end,
    }
  end
  entries[#entries + 1] = {
    text = "|cff999999" .. L["New list..."] .. "|r",
    func = function()
      UI:PromptNewList(itemID)
    end,
  }
  W.Menu(anchor, entries)
end

-- star click: with one list toggle directly, otherwise choose from the menu
function UI:StarClicked(anchor, itemID)
  local watch = ns.AME.watch
  if #watch:Lists() == 1 then
    watch:Toggle(1, itemID)
    self:WatchChanged()
  else
    self:WatchMenu(anchor, itemID)
  end
end

function UI:PromptNewList(itemID)
  StaticPopupDialogs.AME_NEW_LIST = StaticPopupDialogs.AME_NEW_LIST
    or {
      text = L["Name for the new watchlist:"],
      button1 = ACCEPT or "Accept",
      button2 = CANCEL or "Cancel",
      hasEditBox = true,
      OnAccept = function(popup, data)
        local box = popup.editBox or popup.EditBox
        local i = ns.AME.watch:AddList(box and box:GetText())
        if i and data then
          ns.AME.watch:Toggle(i, data)
        end
        UI:WatchChanged()
      end,
      EditBoxOnEnterPressed = function(box)
        local popup = box:GetParent()
        StaticPopupDialogs.AME_NEW_LIST.OnAccept(popup, popup.data)
        popup:Hide()
      end,
      timeout = 0,
      whileDead = true,
      hideOnEscape = true,
      preferredIndex = 3,
    }
  StaticPopup_Show("AME_NEW_LIST", nil, nil, itemID)
end

-- right-click on one of your lists: share with the guild, delete
function UI:ListMenu(anchor, i)
  local watch = ns.AME.watch
  local l = watch:Lists()[i]
  if not l then
    return
  end
  W.Menu(anchor, {
    {
      text = L["Share with guild"],
      checked = l.shared == true,
      func = function()
        watch:SetShared(i, not l.shared)
        ns.SyncService:QueueShare(not l.shared and { l.name } or nil)
        UI:WatchChanged()
      end,
    },
    {
      text = L["Delete list..."],
      disabled = #watch:Lists() <= 1,
      func = function()
        UI:PromptDeleteList(i)
      end,
    },
  })
end

function UI:PromptDeleteList(i)
  local l = ns.AME.watch:Lists()[i]
  if not l then
    return
  end
  StaticPopupDialogs.AME_DELETE_LIST = StaticPopupDialogs.AME_DELETE_LIST
    or {
      text = L['Delete the watchlist "%s"?'],
      button1 = DELETE or "Delete",
      button2 = CANCEL or "Cancel",
      OnAccept = function(_, data)
        local doomed = ns.AME.watch:Lists()[data]
        local wasShared = doomed and doomed.shared and doomed.name
        if ns.AME.watch:RemoveList(data) then
          if wasShared then
            ns.SyncService:QueueShare({ wasShared })
          end
          local q = UI.mq
          if q and q.list then
            q.list, q.only = nil, nil
          end
          UI:WatchChanged()
        end
      end,
      timeout = 0,
      whileDead = true,
      hideOnEscape = true,
      preferredIndex = 3,
    }
  StaticPopup_Show("AME_DELETE_LIST", l.name, nil, i)
end

-- after any watchlist change: re-filter a shown watchlist, redraw stars, sidebar and item controls
function UI:WatchChanged()
  local q = self.mq
  if q and q.list then
    local l
    if type(q.list) == "string" then
      l = ns.AME.watch.db.guild[q.list:sub(3)]
    else
      l = ns.AME.watch:Lists()[q.list]
    end
    q.only = l and l.items or nil
    if not l then
      q.list = nil
    end
  end
  if #ns.AME.watch:SharedLists() > 0 and ns.SyncService.QueueShare then
    ns.SyncService:QueueShare()
  end
  if self.marketView then
    self:RenderCategories()
    self:RefreshMarket(true)
  end
  self:UpdateWatchControls()
end

function UI:UpdateWatchControls(keepInputs)
  local v, id = self.itemView, self.itemID
  if not (v and id and ns.AME.watch) then
    return
  end
  local watch = ns.AME.watch
  local inList = false
  for i in ipairs(watch:Lists()) do
    inList = inList or watch:Has(i, id)
  end
  v.watch.label:SetText(inList and L["Watching"] or L["Watch"])
  v.watch:SetSelected(inList)
  W.SetStar(v.watch.star, inList)
  local a = watch:Alert(id) or {}
  if not keepInputs then
    v.alertBelow:SetText(a.below and tostring(math.floor(a.below / 10000)) or "")
    v.alertAbove:SetText(a.above and tostring(math.floor(a.above / 10000)) or "")
  end
  v.alertSignal:SetChecked(a.signal)
end

---------------------------------------------------------------------------------------------------------------------
-- Market view (screener)

local COLUMNS = {
  { key = "name", label = L["Item"], width = 190, item = true, term = "name" },
  { key = "market", label = L["Market"], width = 86, format = "money", term = "market" },
  {
    key = "avg",
    width = 86,
    term = "avg",
    label = function()
      return L["%dd avg"]:format(avgDays())
    end,
    sortKey = function()
      return "avg" .. avgDays()
    end,
    text = function(s)
      return W.Money(s["avg" .. avgDays()], true)
    end,
  },
  { key = "change7", label = L["7d"], width = 62, format = "pct", term = "change7" },
  { key = "vol30", label = L["Volatility"], width = 70, format = "plainpct", term = "vol30" },
  { key = "qty", label = L["Supply"], width = 52, term = "qty" },
  { key = "sellRate", label = L["Sells/d"], width = 58, format = "rate", term = "sellRate" },
  {
    key = "signal",
    label = L["Signal"],
    width = 50,
    format = "signal",
    term = "signal",
    sortKey = "signalRank",
    ascendingFirst = true,
  },
  { key = "score", label = L["Score"], width = 50, term = "score" },
}
local ROWS = 17
local SIDEBAR_W = 170
local CAT_ROWS = 22
local CAT_H = 19
local QUALITIES = {
  { nil, L["Any quality"] },
  { 1, L["Common+"] },
  { 2, L["Uncommon+"] },
  { 3, L["Rare+"] },
  { 4, L["Epic+"] },
}

local function itemInfo(itemID)
  return ns.ItemCache.Get(itemID)
end

local function goldBox(parent, hint, onChange)
  local box = W.Input(parent)
  box:SetSize(58, 20)
  box:SetAutoFocus(false)
  box:SetNumeric(true)
  box.hint = W.Text(box, "GameFontDisableSmall")
  box.hint:SetPoint("LEFT", 6, 0)
  box.hint:SetPoint("RIGHT", -6, 0) -- clipped to the box (translations run longer)
  box.hint:SetJustifyH("LEFT")
  box.hint:SetWordWrap(false)
  box.hint:SetText(hint)
  box:SetScript("OnTextChanged", function(self)
    self.hint:SetShown(self:GetText() == "")
    onChange(tonumber(self:GetText()))
  end)
  box:SetScript("OnEnterPressed", box.ClearFocus)
  box:SetScript("OnEscapePressed", box.ClearFocus)
  return box
end

-- category sidebar: "All items", classes in AH order, the selected class's subclasses indented
function UI:CreateCategories(v)
  local side = CreateFrame("Frame", nil, v, "BackdropTemplate")
  W.Skin(side, W.COLORS.panel)
  side:SetPoint("TOPLEFT", 0, 0)
  side:SetPoint("BOTTOMLEFT", 0, 0)
  side:SetWidth(SIDEBAR_W)
  side.lines = {}
  for i = 1, CAT_ROWS do
    local b = CreateFrame("Button", nil, side)
    b:SetSize(SIDEBAR_W - 8, CAT_H)
    b:SetPoint("TOPLEFT", 4, -4 - (i - 1) * CAT_H)
    b.sel = b:CreateTexture(nil, "BACKGROUND")
    b.sel:SetAllPoints()
    b.sel:SetColorTexture(W.COLORS.accent[1], W.COLORS.accent[2], W.COLORS.accent[3], 0.2)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.06)
    b.text = W.Text(b, "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", 6, 0)
    b.text:SetPoint("RIGHT", -34, 0)
    b.text:SetWordWrap(false)
    b.count = W.Text(b, "GameFontDisableSmall", "RIGHT")
    b.count:SetPoint("RIGHT", -4, 0)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, button)
      local e = self.entry
      if not e then
        return
      end
      local q = UI.mq
      if e.newList then
        UI:PromptNewList()
        return
      end
      if e.header then
        return
      end
      if e.list and button == "RightButton" then
        UI:ListMenu(self, e.list)
        return
      end
      if e.guild and button == "RightButton" then
        W.Menu(self, {
          {
            text = L["Copy to my watchlists"],
            func = function()
              ns.AME.watch:CopyGuildList(e.guild)
              UI:WatchChanged()
            end,
          },
        })
        return
      end
      q.list, q.only = nil, nil
      if e.guild then
        local g = ns.AME.watch.db.guild[e.guild]
        q.classID, q.subClassID = nil, nil
        q.list, q.only = "g:" .. e.guild, g and g.items
      elseif e.list then
        q.classID, q.subClassID = nil, nil
        q.list, q.only = e.list, ns.AME.watch:Lists()[e.list].items
      elseif e.all then
        q.classID, q.subClassID = nil, nil
      elseif e.subClassID then
        q.classID, q.subClassID = e.classID, e.subClassID
      elseif q.classID == e.classID and not q.subClassID then
        q.classID = nil -- clicking the open class again closes it
      else
        q.classID, q.subClassID = e.classID, nil
      end
      UI.offset = 0
      UI:RenderCategories()
      UI:RefreshMarket(true)
    end)
    side.lines[i] = b
  end
  side:EnableMouseWheel(true)
  side:SetScript("OnMouseWheel", function(_, delta)
    UI.catOffset = math.max(0, (UI.catOffset or 0) - delta * 2)
    UI:RenderCategories()
  end)
  v.side = side
end

function UI:RenderCategories()
  local v = self.marketView
  local q = self.mq
  local entries = { { all = true, label = L["All items"], count = self.index and self.index.count or 0 } }
  local watch = ns.AME.watch
  if watch then
    for i, l in ipairs(watch:Lists()) do
      entries[#entries + 1] = {
        list = i,
        label = W.StarInline(12) .. " " .. l.name .. (l.shared and (" |cff33ccff%s|r"):format(L["shared"]) or ""),
        count = watch:Count(i),
      }
    end
    entries[#entries + 1] = { newList = true, label = "|cff999999+ " .. L["New list"] .. "|r", count = "" }
    local guild = watch:GuildLists()
    if #guild > 0 then
      entries[#entries + 1] = { header = true, label = "|cff999999" .. L["Guild watchlists"] .. "|r", count = "" }
      for _, g in ipairs(guild) do
        local n = 0
        for _ in pairs(g.items) do
          n = n + 1
        end
        entries[#entries + 1] = {
          guild = g.key,
          label = ("   %s |cff999999(%s)|r"):format(g.name, g.owner),
          count = n,
        }
      end
    end
  end
  for _, c in ipairs(self.categories or {}) do
    entries[#entries + 1] = { classID = c.classID, label = ns.ItemCache.ClassName(c.classID), count = c.count }
    if q.classID == c.classID then
      for _, s in ipairs(c.subs) do
        entries[#entries + 1] = {
          classID = c.classID,
          subClassID = s.subClassID,
          label = "   " .. ns.ItemCache.SubClassName(c.classID, s.subClassID),
          count = s.count,
        }
      end
    end
  end
  self.catOffset = math.min(self.catOffset or 0, math.max(0, #entries - CAT_ROWS))
  for i, b in ipairs(v.side.lines) do
    local e = entries[(self.catOffset or 0) + i]
    b.entry = e
    if e then
      b:Show()
      local selected
      if e.newList or e.header then
        selected = false
      elseif e.guild then
        selected = q.list == "g:" .. e.guild
      elseif e.list then
        selected = q.list == e.list
      elseif q.list then
        selected = false
      elseif e.all then
        selected = q.classID == nil
      elseif e.subClassID then
        selected = q.classID == e.classID and q.subClassID == e.subClassID
      else
        selected = q.classID == e.classID and q.subClassID == nil
      end
      b.sel:SetShown(selected)
      b.text:SetText(e.label)
      b.text:SetFontObject(e.subClassID and "GameFontHighlightSmall" or "GameFontNormalSmall")
      b.count:SetText(e.count)
    else
      b:Hide()
    end
  end
end

function UI:CreateMarketView(parent)
  local v = contentArea(parent)
  self.marketView = v
  self.mq = { sortKey = "score", ascending = false, minQuality = 1 } -- Common+: hide grey junk by default
  self:CreateCategories(v)

  local main = CreateFrame("Frame", nil, v)
  main:SetPoint("TOPLEFT", SIDEBAR_W + 10, 0)
  main:SetPoint("BOTTOMRIGHT", 0, 0)
  v.main = main

  -- toolbar: search, quality, price range, signals, reset
  local search = W.Input(main)
  search:SetSize(170, 20)
  search:SetPoint("TOPLEFT", 6, 0)
  search:SetAutoFocus(false)
  search.hint = W.Text(search, "GameFontDisableSmall")
  search.hint:SetPoint("LEFT", 6, 0)
  search.hint:SetPoint("RIGHT", -6, 0) -- clipped to the box (translations run longer)
  search.hint:SetJustifyH("LEFT")
  search.hint:SetWordWrap(false)
  search.hint:SetText(L["Search items..."])
  search:SetScript("OnTextChanged", function(self)
    self.hint:SetShown(self:GetText() == "")
    UI.mq.text = self:GetText()
    UI.offset = 0
    UI:RefreshMarket(true)
  end)
  search:SetScript("OnEnterPressed", search.ClearFocus)
  search:SetScript("OnEscapePressed", function(self)
    self:SetText("")
    self:ClearFocus()
  end)
  v.search = search

  local qualityOptions = {}
  for i, q in ipairs(QUALITIES) do
    local c = q[1] and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q[1]]
    qualityOptions[i] = { q[1], q[2], c and c.hex and c.hex:match("|c(%x+)") }
  end
  local quality = W.Dropdown(main, 104, qualityOptions, function(value)
    UI.mq.minQuality = value
    UI.offset = 0
    UI:RefreshMarket(true)
  end)
  quality:SetPoint("LEFT", search, "RIGHT", 8, 0)
  quality.defaultIndex = 2
  quality:SetIndex(2)
  v.quality = quality

  local minBox = goldBox(main, L["min g"], function(g)
    UI.mq.minPrice = g and g * 10000 or nil
    UI.offset = 0
    UI:RefreshMarket(true)
  end)
  minBox:SetPoint("LEFT", quality, "RIGHT", 10, 0)
  local maxBox = goldBox(main, L["max g"], function(g)
    UI.mq.maxPrice = g and g * 10000 or nil
    UI.offset = 0
    UI:RefreshMarket(true)
  end)
  maxBox:SetPoint("LEFT", minBox, "RIGHT", 6, 0)
  v.minBox, v.maxBox = minBox, maxBox

  local filters = { { nil, L["All"] }, { "buy", L["Buy"] }, { "hold", L["Hold"] }, { "sell", L["Sell"] } }
  v.filterButtons = {}
  for i, fdef in ipairs(filters) do
    local b = W.Button(main, fdef[2], 46, 20, function()
      UI.mq.signal = fdef[1]
      UI.offset = 0
      UI:RefreshMarket(true)
    end)
    b.key = fdef[1] or "all"
    if i == 1 then
      b:SetPoint("LEFT", maxBox, "RIGHT", 10, 0)
    else
      b:SetPoint("LEFT", v.filterButtons[i - 1], "RIGHT", 3, 0)
    end
    v.filterButtons[i] = b
  end
  local reset = W.Button(main, L["Reset"], 52, 20, function()
    UI:ResetMarketFilters()
  end)
  reset:SetPoint("LEFT", v.filterButtons[#filters], "RIGHT", 10, 0)

  -- the list (shared DataTable component)
  v.table = ns.DataTable.New(main, {
    columns = COLUMNS,
    rows = ROWS,
    top = -28,
    itemID = function(s)
      return s.itemID
    end,
    star = true,
    confidence = function(s)
      return ns.Analytics.Confidence(s, UI.index and UI.index.day)
    end,
    sort = { key = UI.mq.sortKey, ascending = UI.mq.ascending },
    onSort = function(key, ascending)
      UI.mq.sortKey, UI.mq.ascending = key, ascending
      UI:RefreshMarket(true)
    end,
    offset = {
      get = function()
        return UI.offset
      end,
      set = function(n)
        UI.offset = n
      end,
    },
    onClick = function(s)
      if IsShiftKeyDown() and ns.AME.ahOpen then
        ns.AME:SearchAuctionHouse(s.itemID)
      else
        UI:ShowItem(s.itemID)
      end
    end,
    tooltip = function(tip)
      if ns.AME.ahOpen then
        tip:AddLine(L["Shift-click to search the auction house"], 0.6, 0.6, 0.6)
      end
    end,
  })
  v.headers, v.rows, v.bar = v.table.headers, v.table.rows, v.table.bar

  v.status = W.Text(main, "GameFontDisableSmall", "LEFT")
  v.status:SetPoint("BOTTOMLEFT", 2, 0)

  main:EnableMouseWheel(true)
  main:SetScript("OnMouseWheel", function(_, delta)
    v.table:Scroll(delta)
  end)

  ns.ItemCache.OnNamesChanged(function()
    local q = UI.mq
    if not v:IsShown() then
      return
    end
    if (q.text and q.text ~= "") or q.minQuality or q.sortKey == "name" then
      UI:RefreshMarket(true)
    else
      UI:RenderMarket()
    end
  end)
  return v
end

function UI:ResetMarketFilters()
  local v = self.marketView
  self.mq = { sortKey = self.mq.sortKey, ascending = self.mq.ascending, minQuality = 1 }
  v.quality:SetIndex(v.quality.defaultIndex)
  v.search:SetText("")
  v.minBox:SetText("")
  v.maxBox:SetText("")
  self.offset = 0
  self:RenderCategories()
  self:RefreshMarket(true)
end

-- Rebuild the filtered, sorted list (only when the index, filters or sort change), then render.
function UI:RefreshMarket(force)
  local v = self.marketView
  if not (v and v:IsShown()) then
    return
  end
  local index, why = self:ViewIndex()
  if not index then
    self.list = nil
    local text = ns.AME:HistoryLoaded() and L["Building market index..."] or L["Loading history..."]
    if why == "empty" then
      text = L["No price history for the %s yet: scan there (any character on this account counts)."]:format(
        ns.HOUSE_LABEL[self:ViewHouse()] or self:ViewHouse()
      )
    end
    v.status:SetText(text)
    for _, row in ipairs(v.rows) do
      row:Hide()
    end
    if not ns.AME:HistoryLoaded() then
      ns.AME:LoadHistory()
      ns.AME:RebuildIndex()
    end
    return
  end
  if index ~= self.index then
    self.index = index
    self.categories = ns.MarketFilter.Categories(index, itemInfo)
    local ids = {}
    for id in pairs(index.items) do
      ids[#ids + 1] = id
    end
    ns.ItemCache.Warm(ids)
    self:RenderCategories()
    force = true
  end
  if force or not self.list then
    self.list, self.unnamed = ns.MarketFilter.Apply(index, self.mq, itemInfo)
  end
  self:RenderMarket()
end

-- Draw the visible rows from the cached list: cheap, so scrolling stays smooth.
function UI:RenderMarket()
  local v = self.marketView
  local list = self.list
  if not (v and list and v:IsShown()) then
    return
  end
  local q = self.mq
  for _, b in ipairs(v.filterButtons) do
    b:SetSelected(b.key == (q.signal or "all"))
  end
  v.quality:SetIndex(v.quality.index)
  local total = #list
  local t = v.table
  t.sort.key, t.sort.ascending = q.sortKey, q.ascending
  t:SetData(list)
  t:Render()
  self.offset = t:Offset()

  local cache = ns.ItemCache
  local status = L["%d items  -  showing %d-%d  -  index from %s"]:format(
    total,
    math.min(total, self.offset + 1),
    math.min(total, self.offset + ROWS),
    date("%b %d", self.index.day * DAY)
  )
  if cache.warmTotal and cache.warmDone and cache.warmDone < cache.warmTotal then
    status = status .. "  -  " .. L["loading item names %d/%d"]:format(cache.warmDone, cache.warmTotal)
  elseif (self.unnamed or 0) > 0 then
    status = status .. "  -  " .. L["%d items not searchable yet (names loading)"]:format(self.unnamed)
  end
  if q.list and q.only then
    local n = 0
    for _ in pairs(q.only) do
      n = n + 1
    end
    if n > total then
      status = status .. "  -  " .. L["%d watched items have no price history here yet"]:format(n - total)
    end
  end
  v.status:SetText(status)
end
