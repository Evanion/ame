-- Arbitrage tab: items to buy at one auction house and sell at another, after the selling house's cut.
local _, ns = ...

local W = ns.Widgets
local UI = ns.UI

local HOUSES = {
  { "Alliance", "Alliance AH" },
  { "Horde", "Horde AH" },
  { "Neutral", "Goblin AH" },
}
local HOUSE_NAME = { Alliance = "Alliance AH", Horde = "Horde AH", Neutral = "Goblin AH" }
local AGES = { { 1, "Seen today/yesterday" }, { 3, "Seen in 3 days" }, { 7, "Seen in 7 days" }, { false, "Any age" } }

local COLUMNS = {
  { key = "name", label = "Item", width = 214 },
  { key = "buy", label = "Buy at", width = 86, money = true, term = "arbBuy" },
  { key = "sell", label = "Sells for", width = 86, money = true, term = "arbSell" },
  { key = "fee", label = "AH cut", width = 76, money = true, term = "arbFee" },
  { key = "profit", label = "Profit", width = 86, money = true, term = "arbProfit" },
  { key = "margin", label = "Margin", width = 60, pct = true, term = "arbMargin" },
  { key = "supply", label = "Supply", width = 70, term = "arbSupply" },
  { key = "age", label = "Data", width = 56, term = "arbAge" },
}
local ROWS, ROW_H = 16, 22

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
    return "today"
  elseif days == 1 then
    return "1 day"
  end
  return days .. " days"
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
  buyLabel:SetText("Buy at")
  v.buy = W.Dropdown(v, 104, HOUSES, function(value)
    UI.arb.buy = value
    UI:RefreshArbitrage()
  end)
  v.buy.neutral = true
  v.buy:SetPoint("LEFT", buyLabel, "RIGHT", 6, 0)
  v.swap = W.Button(v, "Swap", 50, 20, function()
    UI.arb.buy, UI.arb.sell = UI.arb.sell, UI.arb.buy
    UI:RefreshArbitrage()
  end)
  v.swap:SetPoint("LEFT", v.buy, "RIGHT", 6, 0)
  local sellLabel = label("Sell at", v.swap)
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
    input.hint:SetText(hint)
    input:SetScript("OnTextChanged", function(self)
      self.hint:SetShown(self:GetText() == "")
      onChange(tonumber(self:GetText()))
    end)
    input:SetScript("OnEnterPressed", input.ClearFocus)
    return input
  end
  v.minProfit = goldInput("profit g", function(g)
    UI.arb.minProfit = g and g * 10000 or 1
    UI:RefreshArbitrage(true)
  end)
  v.minProfit:SetPoint("LEFT", v.sell, "RIGHT", 16, 0)
  v.minMargin = goldInput("margin %", function(p)
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

  -- header
  local x = 0
  v.headers = {}
  for _, col in ipairs(COLUMNS) do
    local h = CreateFrame("Button", nil, v)
    h:SetSize(col.width, 18)
    h:SetPoint("TOPLEFT", x, -32)
    h.text = W.Text(h, "GameFontNormalSmall", col.key == "name" and "LEFT" or "RIGHT")
    h.text:SetAllPoints()
    if col.term then
      ns.Help.Explain(h, col.term)
    end
    h:SetScript("OnClick", function()
      local a = UI.arb
      local key = col.key == "supply" and "sellQty" or col.key
      if key == "name" then
        return
      end
      if a.sortKey == key then
        a.ascending = not a.ascending
      else
        a.sortKey, a.ascending = key, false
      end
      UI:RefreshArbitrage(true)
    end)
    h.key = col.key == "supply" and "sellQty" or col.key
    x = x + col.width + 8
    v.headers[#v.headers + 1] = h
  end

  v.rows = {}
  for r = 1, ROWS do
    local row = CreateFrame("Button", nil, v)
    row:SetSize(x, ROW_H)
    row:SetPoint("TOPLEFT", 0, -52 - (r - 1) * ROW_H)
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
    UI.arbOffset = math.max(0, (UI.arbOffset or 0) - delta * 3)
    UI:RenderArbitrage()
  end)
  v.status = W.Text(v, "GameFontDisableSmall", "LEFT")
  v.status:SetPoint("BOTTOMLEFT", 0, 0)
  v.status:SetWidth(940)

  v:SetScript("OnShow", function()
    UI:RefreshArbitrage()
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
  self.arbRows = nil
  v.status:SetText("Loading market data...")
  self:RenderArbitrage()
  local token = {}
  self.arbToken = token
  AME:IndexFor(buyShard, function(buyIndex)
    AME:IndexFor(sellShard, function(sellIndex)
      if self.arbToken ~= token then
        return
      end
      self.arbMissing = (not buyIndex and HOUSE_NAME[a.buy]) or (not sellIndex and HOUSE_NAME[a.sell]) or nil
      local cut = ns.Settings:AuctionCut(a.sell)
      self.arbCut = cut
      self.arbRows = ns.Arbitrage.Find(buyIndex, sellIndex, {
        cut = cut,
        minProfit = a.minProfit,
        minMargin = a.minMargin,
        maxAge = a.maxAge or nil,
        today = math.floor(GetServerTime() / 86400),
        sortKey = a.sortKey,
        ascending = a.ascending,
      })
      self:RenderArbitrage()
    end)
  end)
end

function UI:RenderArbitrage()
  local v = self.arbView
  if not (v and v:IsShown()) then
    return
  end
  local a = self.arb
  for i, h in ipairs(v.headers) do
    local col = COLUMNS[i]
    local arrow = (a.sortKey == h.key) and (a.ascending and W.ARROW_UP or W.ARROW_DOWN) or ""
    h.text:SetText(col.label .. arrow)
  end
  local rows = self.arbRows or {}
  local total = #rows
  self.arbOffset = math.min(self.arbOffset or 0, math.max(0, total - ROWS))
  for r, row in ipairs(v.rows) do
    local e = rows[self.arbOffset + r]
    row.itemID = e and e.itemID
    row:SetShown(e ~= nil)
    if e then
      local name, _, quality, icon = W.ItemInfo(e.itemID)
      row.icon:SetTexture(icon or 134400)
      if not name then
        self:RenderWhenLoaded(e.itemID)
      end
      local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
      for c, col in ipairs(COLUMNS) do
        local val
        if col.key == "name" then
          val = (color and color.hex or "|cffffffff") .. (name or ("item:" .. e.itemID)) .. "|r"
        elseif col.key == "profit" then
          val = "|cff4dd973+|r" .. W.Money(e.profit, true)
        elseif col.money then
          val = W.Money(e[col.key], true)
        elseif col.pct then
          val = W.Percent(e.margin, 0)
        elseif col.key == "supply" then
          val = ("%s / %s"):format(tostring(e.buyQty or "-"), tostring(e.sellQty or "-"))
        elseif col.key == "age" then
          val = ageText(e.age)
        end
        row.cells[c]:SetText(val or "")
      end
    end
  end
  local status
  if not self.arbRows then
    status = "Loading market data..."
  elseif self.arbMissing then
    status = ("No price history for the %s yet: scan there (any character on this account counts) to compare."):format(
      self.arbMissing
    )
  else
    status = ("%d routes  -  buy at %s, sell at %s (%d%% cut, set in Settings)  -  deposits not included"):format(
      total,
      HOUSE_NAME[a.buy],
      HOUSE_NAME[a.sell],
      math.floor((self.arbCut or 0) * 100 + 0.5)
    )
  end
  if a.buy == a.sell then
    status = "Pick two different auction houses."
  end
  v.status:SetText(status)
end
