-- Main window: "Item" tab (chart + stats for one item) and "Market" tab (screener over the market index).
local _, ns = ...

local W = ns.Widgets
local DAY = 86400

local UI = {}
ns.UI = UI

local RANGES = { { "7D", 7 }, { "30D", 30 }, { "90D", 90 }, { "1Y", 365 }, { "All", nil } }

---------------------------------------------------------------------------------------------------------------------
-- window shell

function UI:Create()
  if self.frame then
    return self.frame
  end
  local f = CreateFrame("Frame", "AMEMainWindow", UIParent, "BackdropTemplate")
  self.frame = f
  f:SetSize(780, 500)
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

  local title = W.Text(f, "GameFontNormal")
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetText("|cff33ccffAzeroth|r Mercantile Exchange")
  self.shardText = W.Text(f, "GameFontDisableSmall")
  self.shardText:SetPoint("LEFT", title, "RIGHT", 10, 0)

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)

  self.tabs = {}
  local function tab(name, label, x)
    local b = W.Button(f, label, 70, 20, function()
      UI:ShowTab(name)
    end)
    b:SetPoint("TOPRIGHT", -(30 + x), -8)
    self.tabs[name] = b
  end
  tab("market", "Market", 0)
  tab("item", "Item", 76)

  self.views = {
    item = self:CreateItemView(f),
    market = self:CreateMarketView(f),
  }
  f:SetScript("OnShow", function()
    UI.shardText:SetText(ns.AME:CurrentShard())
  end)
  return f
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

local function contentArea(parent)
  local v = CreateFrame("Frame", nil, parent)
  v:SetPoint("TOPLEFT", 10, -36)
  v:SetPoint("BOTTOMRIGHT", -10, 10)
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
  local box = CreateFrame("EditBox", nil, v, "InputBoxTemplate")
  box:SetSize(180, 20)
  box:SetPoint("TOPRIGHT", -2, 0)
  box:SetAutoFocus(false)
  box:SetScript("OnEnterPressed", function(self)
    local id = ns.AME.ItemIDFrom(self:GetText())
    self:ClearFocus()
    if id then
      UI:ShowItem(id)
    end
  end)
  box.hint = W.Text(box, "GameFontDisableSmall")
  box.hint:SetPoint("LEFT", 2, 0)
  box.hint:SetText("Shift-click an item or type an ID")
  box:SetScript("OnTextChanged", function(self)
    self.hint:SetShown(self:GetText() == "")
  end)
  self.searchBox = box
  -- shift-clicking an item while the box has focus inserts its link
  hooksecurefunc("ChatEdit_InsertLink", function(link)
    if box:HasFocus() and link then
      box:SetText(link)
      local id = ns.AME.ItemIDFrom(link)
      if id then
        box:ClearFocus()
        UI:ShowItem(id)
      end
    end
  end)

  v.icon = v:CreateTexture(nil, "ARTWORK")
  v.icon:SetSize(32, 32)
  v.icon:SetPoint("TOPLEFT", 0, 0)
  v.name = W.Text(v, "GameFontNormalLarge")
  v.name:SetPoint("TOPLEFT", v.icon, "TOPRIGHT", 8, -2)
  v.sub = W.Text(v, "GameFontDisableSmall")
  v.sub:SetPoint("BOTTOMLEFT", v.icon, "BOTTOMRIGHT", 8, 2)

  -- stat cards
  v.cards = {}
  local labels = { "Market", "Lowest", "30d average", "7d change", "Volatility", "Supply", "Signal" }
  for i, label in ipairs(labels) do
    local c = statCard(v, label)
    c:SetSize((780 - 20 - 6 * 6) / 7, 40)
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
    local b = W.Button(v, r[1], 44, 18, function()
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
  v.legend = W.Text(v, "GameFontDisableSmall")
  v.legend:SetPoint("LEFT", v.rangeButtons[#RANGES], "RIGHT", 12, 0)
  v.legend:SetText(
    W.Swatch(0.2, 0.8, 1)
      .. " market   "
      .. W.Swatch(0.4, 0.87, 0.47)
      .. " lowest   "
      .. W.Swatch(1, 0.67, 0.2)
      .. " 7d average   "
      .. W.Swatch(0.53, 0.53, 0.67)
      .. " supply      wheel: zoom, drag: pan, double-click: reset"
  )

  -- chart
  local holder = CreateFrame("Frame", nil, v, "BackdropTemplate")
  W.Skin(holder, W.COLORS.panel)
  holder:SetPoint("TOPLEFT", v.rangeButtons[1], "BOTTOMLEFT", 0, -8)
  holder:SetPoint("BOTTOMRIGHT", 0, 0)
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
    local lines = { "|cffffffff" .. date("%a %b %d, %Y", x) .. "|r" }
    if rows.market and rows.market.x == x then
      lines[#lines + 1] = "Market  " .. W.Money(rows.market.y)
    end
    if rows.min and rows.min.x == x then
      lines[#lines + 1] = "Lowest  " .. W.Money(rows.min.y)
    end
    if rows.sma and rows.sma.x == x then
      lines[#lines + 1] = "7d avg  " .. W.Money(rows.sma.y)
    end
    if rows.qty and rows.qty.x == x then
      lines[#lines + 1] = "Supply  " .. rows.qty.y
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
  if days then
    local now = GetServerTime()
    self.chart:SetXRange(now - days * DAY, now + DAY)
  else
    self.chart:SetXRange(nil)
  end
end

function UI:ShowItem(itemID)
  self:Create()
  self.frame:Show()
  self:ShowTab("item")
  self.itemID = itemID
  local v = self.itemView

  local function header()
    local name, _, quality, icon = W.ItemInfo(itemID)
    v.icon:SetTexture(icon or 134400)
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    v.name:SetText((color and color.hex or "|cffffffff") .. (name or ("item:" .. itemID)) .. "|r")
  end
  header()
  W.OnItemLoaded(itemID, header)

  for _, c in ipairs(v.cards) do
    c.value:SetText("...")
  end
  v.sub:SetText("loading history...")
  self.chart:ClearSeries()
  self.chart:SetMessage("Loading history...")

  ns.AME:WithStore("chart-" .. itemID, nil, function(store)
    return { series = store:Series(itemID), latest = store:Latest(itemID) }
  end, function(ok, res)
    if self.itemID ~= itemID then
      return
    end
    if not ok then
      self.chart:SetMessage("Could not load history: " .. tostring(res))
      return
    end
    self:FillItem(itemID, res.series, res.latest)
  end)
end

function UI:FillItem(_, series, latest)
  local v = self.itemView
  if #series == 0 then
    self.chart:SetMessage("No history for this item yet. Run an Auctionator full scan, or search for it at the AH.")
    v.sub:SetText(ns.AME:CurrentShard())
    for _, c in ipairs(v.cards) do
      c.value:SetText("-")
    end
    return
  end
  self.chart:SetMessage(nil)
  local xs, market, low, qty, sma = {}, {}, {}, {}, {}
  for i, p in ipairs(series) do
    xs[i] = p.day * DAY + (p.res == "week" and 3.5 * DAY or DAY / 2)
    market[i], low[i], qty[i] = p.market, p.min, p.qty
  end
  for i = 1, #market do
    sma[i] = ns.Analytics.SMA(market, math.min(7, i), i)
  end
  local chart = self.chart
  chart:ClearSeries()
  chart:SetSeries("qty", { xs = xs, ys = qty, kind = "bars", axis = "volume", color = { 0.53, 0.53, 0.67, 1 } })
  chart:SetSeries("market", { xs = xs, ys = market, kind = "area", axis = "price", color = { 0.2, 0.8, 1, 1 } })
  chart:SetSeries("min", { xs = xs, ys = low, kind = "line", axis = "price", color = { 0.4, 0.87, 0.47, 0.9 } })
  chart:SetSeries("sma", {
    xs = xs,
    ys = sma,
    kind = "line",
    axis = "price",
    color = { 1, 0.67, 0.2, 0.9 },
    width = 1.5,
  })
  if self.rangeKey == "All" then
    self:SetRange(nil, "All")
  else
    self:SetRange(self.rangeDays or 30, self.rangeKey or "30D")
  end

  local s = ns.Analytics.Summarize(series)
  local cards = v.cards
  cards[1].value:SetText(W.Money(latest and latest.market or s.market))
  cards[2].value:SetText(W.Money(latest and latest.min or s.min))
  cards[3].value:SetText(W.Money(s.avg30))
  cards[4].value:SetText(W.Percent(s.change7))
  cards[5].value:SetText(s.vol30 and ("%.1f%%"):format(s.vol30 * 100) or "-")
  cards[6].value:SetText(
    tostring(latest and latest.qty or s.qty or 0) .. " " .. W.Percent(s.supplyTrend30 and s.supplyTrend30 * 7, 0)
  )
  cards[7].value:SetText(W.Signal(s.signal) .. ("  |cff999999%+d|r"):format(s.score or 0))
  v.sub:SetText(
    ("%s  ·  %d days of history%s"):format(
      ns.AME:CurrentShard(),
      #series,
      latest and ("  ·  last seen " .. date("%b %d %H:%M", latest.t)) or ""
    )
  )
end

---------------------------------------------------------------------------------------------------------------------
-- Market view (screener)

local COLUMNS = {
  { key = "name", label = "Item", width = 230 },
  { key = "market", label = "Market", width = 92, money = true },
  { key = "avg30", label = "30d avg", width = 92, money = true },
  { key = "change7", label = "7d", width = 62, pct = true },
  { key = "vol30", label = "Volatility", width = 70, pct = true, plain = true },
  { key = "qty", label = "Supply", width = 60 },
  { key = "signal", label = "Signal", width = 50 },
  { key = "score", label = "Score", width = 50 },
}
local ROWS = 16
local ROW_H = 22

function UI:CreateMarketView(parent)
  local v = contentArea(parent)
  self.marketView = v
  self.sortKey, self.sortAsc, self.filter = "score", false, "all"

  local filters = { { "all", "All" }, { "buy", "Buy signals" }, { "sell", "Sell signals" } }
  v.filterButtons = {}
  for i, fdef in ipairs(filters) do
    local b = W.Button(v, fdef[2], 84, 18, function()
      UI.filter = fdef[1]
      UI.offset = 0
      UI:RefreshMarket()
    end)
    b.key = fdef[1]
    if i == 1 then
      b:SetPoint("TOPLEFT", 0, 0)
    else
      b:SetPoint("LEFT", v.filterButtons[i - 1], "RIGHT", 4, 0)
    end
    v.filterButtons[i] = b
  end
  v.status = W.Text(v, "GameFontDisableSmall", "RIGHT")
  v.status:SetPoint("TOPRIGHT", 0, -3)

  -- header
  local x = 0
  v.headers = {}
  for _, col in ipairs(COLUMNS) do
    local h = CreateFrame("Button", nil, v)
    h:SetSize(col.width, 18)
    h:SetPoint("TOPLEFT", x, -26)
    h.text = W.Text(h, "GameFontNormalSmall", col.key == "name" and "LEFT" or "RIGHT")
    h.text:SetAllPoints()
    h.text:SetText(col.label)
    if col.key ~= "name" then
      h:SetScript("OnClick", function()
        if UI.sortKey == col.key then
          UI.sortAsc = not UI.sortAsc
        else
          UI.sortKey, UI.sortAsc = col.key, false
        end
        UI:RefreshMarket()
      end)
    end
    x = x + col.width + 8
    v.headers[#v.headers + 1] = h
  end

  -- rows
  v.rows = {}
  for r = 1, ROWS do
    local row = CreateFrame("Button", nil, v)
    row:SetSize(x, ROW_H)
    row:SetPoint("TOPLEFT", 0, -46 - (r - 1) * ROW_H)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, r % 2 == 0 and 0.025 or 0)
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 1, 1, 0.06)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", 0, 0)
    row.cells = {}
    local cx = 0
    for c, col in ipairs(COLUMNS) do
      local fs = W.Text(row, "GameFontHighlightSmall", col.key == "name" and "LEFT" or "RIGHT")
      fs:SetSize(col.key == "name" and col.width - 22 or col.width, ROW_H)
      fs:SetPoint("LEFT", col.key == "name" and cx + 22 or cx, 0)
      fs:SetWordWrap(false)
      row.cells[c] = fs
      cx = cx + col.width + 8
    end
    row:SetScript("OnClick", function(self)
      if self.itemID then
        UI:ShowItem(self.itemID)
      end
    end)
    row:SetScript("OnEnter", function(self)
      if self.itemID then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.itemID)
        GameTooltip:Show()
      end
    end)
    row:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
    v.rows[r] = row
  end
  v:EnableMouseWheel(true)
  v:SetScript("OnMouseWheel", function(_, delta)
    UI.offset = math.max(0, (UI.offset or 0) - delta * 3)
    UI:RefreshMarket()
  end)
  return v
end

function UI:RefreshMarket()
  local v = self.marketView
  if not (v and v:IsShown()) then
    return
  end
  for _, b in ipairs(v.filterButtons) do
    b:SetSelected(b.key == self.filter)
  end
  for i, h in ipairs(v.headers) do
    local col = COLUMNS[i]
    local arrow = (self.sortKey == col.key) and (self.sortAsc and W.ARROW_UP or W.ARROW_DOWN) or ""
    h.text:SetText(col.label .. arrow)
  end
  local index = ns.AME.index
  if not index then
    v.status:SetText(ns.AME:HistoryLoaded() and "Building market index..." or "Loading history...")
    for _, row in ipairs(v.rows) do
      row:Hide()
    end
    if not ns.AME:HistoryLoaded() then
      ns.AME:LoadHistory()
      ns.AME:RebuildIndex()
    end
    return
  end
  local filter
  if self.filter ~= "all" then
    filter = function(s)
      return s.signal == self.filter
    end
  end
  local list = ns.MarketIndex.Rank(index, self.sortKey, filter, self.sortAsc)
  local total = #list
  self.offset = math.min(self.offset or 0, math.max(0, total - ROWS))
  v.status:SetText(
    ("%d items  ·  showing %d–%d  ·  index from %s"):format(
      total,
      math.min(total, self.offset + 1),
      math.min(total, self.offset + ROWS),
      date("%b %d", index.day * DAY)
    )
  )
  for r, row in ipairs(v.rows) do
    local s = list[self.offset + r]
    if not s then
      row:Hide()
      row.itemID = nil
    else
      row:Show()
      row.itemID = s.itemID
      local name, _, quality, icon = W.ItemInfo(s.itemID)
      row.icon:SetTexture(icon or 134400)
      local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
      if not name then
        W.OnItemLoaded(s.itemID, function()
          if row.itemID == s.itemID then
            UI:RefreshMarket()
          end
        end)
      end
      for c, col in ipairs(COLUMNS) do
        local val
        if col.key == "name" then
          val = (color and color.hex or "|cffffffff") .. (name or ("item:" .. s.itemID)) .. "|r"
        elseif col.money then
          val = W.Money(s[col.key], true)
        elseif col.plain then
          val = s[col.key] and ("%.1f%%"):format(s[col.key] * 100) or "-"
        elseif col.pct then
          val = W.Percent(s[col.key])
        elseif col.key == "signal" then
          val = W.Signal(s.signal)
        else
          val = tostring(s[col.key] or "-")
        end
        row.cells[c]:SetText(val)
      end
    end
  end
end
