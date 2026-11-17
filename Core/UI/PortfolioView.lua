-- Portfolio tab: what you hold (all characters, bags + bank + auctions) valued at your faction's market, cost basis
-- and unrealized profit from your AH purchases, and the ledger of AH sales and purchases from auction mail.
local _, ns = ...

local W = ns.Widgets
local UI = ns.UI
local DAY = 86400

local ROWS, ROW_H = 13, 22

local POSITION_COLS = {
  { key = "name", label = "Item", width = 210 },
  { key = "qty", label = "Held", width = 50 },
  { key = "market", label = "Market", width = 84, money = true },
  { key = "value", label = "Value", width = 92, money = true },
  { key = "unitCost", label = "Avg cost", width = 84, money = true, term = "pfCost" },
  { key = "unrealized", label = "Unrealized", width = 92, term = "pfUnrealized" },
  { key = "signal", label = "Signal", width = 50, term = "signal" },
  { key = "sellRate", label = "Sells/d", width = 58, term = "sellRate" },
  { key = "daysToSell", label = "Days to sell", width = 74, term = "pfDays" },
}

local LEDGER_COLS = {
  { key = "when", label = "When", width = 96 },
  { key = "kind", label = "", width = 44 },
  { key = "name", label = "Item", width = 230 },
  { key = "qty", label = "Qty", width = 44 },
  { key = "amount", label = "Price", width = 92, money = true },
  { key = "cut", label = "AH cut", width = 76, money = true },
  { key = "profit", label = "Profit", width = 92, term = "pfProfit" },
  { key = "char", label = "Character", width = 150 },
}

local function signedMoney(v)
  if not v then
    return "|cff777777-|r"
  end
  if v < 0 then
    return "|cffff6159-|r" .. W.Money(-v, true)
  end
  return "|cff4dd973+|r" .. W.Money(v, true)
end

local function card(parent, label, x)
  local c = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  W.Skin(c, W.COLORS.panel)
  c:SetSize(184, 44)
  c:SetPoint("TOPLEFT", x, 0)
  c.label = W.Text(c, "GameFontDisableSmall")
  c.label:SetPoint("TOPLEFT", 8, -6)
  c.label:SetText(label)
  c.value = W.Text(c, "GameFontHighlight")
  c.value:SetPoint("BOTTOMLEFT", 8, 7)
  return c
end

local function table_(parent, cols, top)
  local t = { cols = cols, headers = {}, rows = {} }
  local x = 0
  for _, col in ipairs(cols) do
    local h = CreateFrame("Button", nil, parent)
    h:SetSize(col.width, 18)
    h:SetPoint("TOPLEFT", x, top)
    h.text = W.Text(h, "GameFontNormalSmall", (col.key == "name" or col.key == "char") and "LEFT" or "RIGHT")
    h.text:SetAllPoints()
    h.text:SetText(col.label)
    if col.term then
      ns.Help.Explain(h, col.term)
    end
    x = x + col.width + 8
    t.headers[#t.headers + 1] = h
  end
  for r = 1, ROWS do
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(x, ROW_H)
    row:SetPoint("TOPLEFT", 0, top - 20 - (r - 1) * ROW_H)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, r % 2 == 0 and 0.025 or 0)
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 1, 1, 0.06)
    row.cells = {}
    local cx = 0
    for c, col in ipairs(cols) do
      local left = col.key == "name" or col.key == "char"
      local fs = W.Text(row, "GameFontHighlightSmall", left and "LEFT" or "RIGHT")
      fs:SetSize(col.width, ROW_H)
      fs:SetPoint("LEFT", cx, 0)
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
        if self.chars then
          GameTooltip:AddLine(" ")
          for char, qty in pairs(self.chars) do
            GameTooltip:AddDoubleLine(char:gsub("^[^:]*:", ""), qty, 0.7, 0.7, 0.7, 1, 1, 1)
          end
        end
        GameTooltip:Show()
      end
    end)
    row:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
    t.rows[r] = row
  end
  return t
end

local function showTable(t, shown)
  for _, h in ipairs(t.headers) do
    h:SetShown(shown)
  end
  for _, row in ipairs(t.rows) do
    row:SetShown(shown and row.itemID ~= nil or (shown and row.hasData))
  end
end

function UI:CreatePortfolioView(parent, contentArea)
  local v = contentArea(parent)
  self.pfView = v
  self.pfMode = "positions"
  v.cards = {
    card(v, "Holdings value", 0),
    card(v, "Listed on the AH now", 192),
    card(v, "Unrealized profit", 384),
    card(v, "Realized profit, 7 days", 576),
    card(v, "30 days: sold / bought", 768),
  }
  for i, term in ipairs({ "pfValue", false, "pfUnrealized", "pfProfit", "pfFlow" }) do
    v.cards[i]:EnableMouse(true)
    if term then
      ns.Help.Explain(v.cards[i], term)
    end
  end
  -- listed: per-character breakdown on hover
  v.cards[2]:SetScript("OnEnter", function(self)
    local l = UI.pfListed
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Listed on the auction house now", 1, 1, 1)
    GameTooltip:AddLine(
      "Your active auctions on all characters, as of the last time each opened the auction house.",
      nil,
      nil,
      nil,
      true
    )
    if l and l.count > 0 then
      GameTooltip:AddLine(" ")
      GameTooltip:AddDoubleLine("Asking prices", W.Money(l.value), 0.8, 0.8, 0.8, 1, 1, 1)
      GameTooltip:AddDoubleLine("You'd receive (after the cut)", W.Money(l.net), 0.8, 0.8, 0.8, 1, 1, 1)
      GameTooltip:AddDoubleLine("At market price", W.Money(l.market), 0.8, 0.8, 0.8, 1, 1, 1)
      GameTooltip:AddLine(" ")
      for char, c in pairs(l.chars) do
        GameTooltip:AddDoubleLine(
          ("%s (%s)"):format(char:gsub("^[^:]*:", ""), ns.HOUSE_LABEL[c.house] or c.house or "?"),
          ("%d  ·  %s"):format(c.count, W.Money(c.value, true)),
          0.7,
          0.7,
          0.7,
          1,
          1,
          1
        )
      end
    end
    GameTooltip:Show()
  end)
  v.cards[2]:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  v.positionsButton = W.Button(v, "Positions", 80, 20, function()
    UI.pfMode, UI.pfOffset = "positions", 0
    UI:RefreshPortfolio()
  end)
  v.positionsButton:SetPoint("TOPLEFT", 0, -54)
  v.ledgerButton = W.Button(v, "Ledger", 80, 20, function()
    UI.pfMode, UI.pfOffset = "ledger", 0
    UI:RefreshPortfolio()
  end)
  v.ledgerButton:SetPoint("LEFT", v.positionsButton, "RIGHT", 4, 0)
  v.positions = table_(v, POSITION_COLS, -82)
  v.ledger = table_(v, LEDGER_COLS, -82)
  v.status = W.Text(v, "GameFontDisableSmall", "LEFT")
  v.status:SetPoint("BOTTOMLEFT", 0, 0)
  v.status:SetWidth(940)
  v:EnableMouseWheel(true)
  v:SetScript("OnMouseWheel", function(_, delta)
    UI.pfOffset = math.max(0, (UI.pfOffset or 0) - delta * 3)
    UI:RenderPortfolio()
  end)
  v:SetScript("OnShow", function()
    ns.Trading:ScanBags()
    UI:RefreshPortfolio()
  end)
  return v
end

function UI:RefreshPortfolio()
  local v = self.pfView
  if not (v and v:IsShown()) then
    return
  end
  local AME = ns.AME
  local index = AME:FactionIndex()
  local basis = AME.ledger and AME.ledger:CostBasis() or {}
  self.pfRows, self.pfTotals = ns.Portfolio.Build(ns.Trading:Holdings(), basis, index and index.items or {})
  self.pfListed = ns.Portfolio.Listed(ns.Trading:Holdings(), function(house)
    return ns.Settings:AuctionCut(house)
  end, index and index.items or {})
  local now = GetServerTime()
  self.pfWeek = AME.ledger and AME.ledger:Summary(now - 7 * DAY) or {}
  self.pfMonth = AME.ledger and AME.ledger:Summary(now - 30 * DAY) or {}
  self.pfLedger = AME.ledger and AME.ledger:Recent(now - 90 * DAY) or {}
  self.pfIndexMissing = index == nil
  self:RenderPortfolio()
end

local function cellValue(col, e)
  local val = e[col.key]
  if col.key == "unrealized" or col.key == "profit" then
    return signedMoney(val)
  elseif col.money then
    return W.Money(val, true)
  elseif col.key == "signal" then
    return W.Signal(val)
  elseif col.key == "sellRate" then
    return W.Rate(val)
  elseif col.key == "daysToSell" then
    return val and (val < 1 and "<1" or ("%.0f"):format(val)) or "|cff777777-|r"
  end
  return val ~= nil and tostring(val) or "|cff777777-|r"
end

function UI:RenderPortfolio()
  local v = self.pfView
  if not (v and v:IsShown() and self.pfRows) then
    return
  end
  local t, w, m = self.pfTotals, self.pfWeek, self.pfMonth
  local l = self.pfListed
  v.cards[1].value:SetText(W.Money(t.value, true))
  v.cards[2].value:SetText(
    l.count > 0 and ("%s  |cff999999%d auctions|r"):format(W.Money(l.value, true), l.count) or "|cff777777none|r"
  )
  v.cards[3].value:SetText(signedMoney(t.unrealized))
  v.cards[4].value:SetText(signedMoney(w.profit))
  v.cards[5].value:SetText(W.Money(m.income or 0, true) .. " / " .. W.Money(m.spent or 0, true))
  local ledgerMode = self.pfMode == "ledger"
  v.positionsButton:SetSelected(not ledgerMode)
  v.ledgerButton:SetSelected(ledgerMode)
  showTable(v.positions, not ledgerMode)
  showTable(v.ledger, ledgerMode)

  local list = ledgerMode and self.pfLedger or self.pfRows
  local tbl = ledgerMode and v.ledger or v.positions
  self.pfOffset = math.min(self.pfOffset or 0, math.max(0, #list - ROWS))
  local profitOf = {}
  if ledgerMode and ns.AME.ledger then
    for _, e in ipairs(list) do
      if e.kind == "sale" then
        profitOf[e] = ns.AME.ledger:Profit(e)
      end
    end
  end
  for r, row in ipairs(tbl.rows) do
    local e = list[self.pfOffset + r]
    row.itemID, row.chars, row.hasData = e and e.itemID, e and e.chars, e ~= nil
    row:SetShown(e ~= nil)
    if e then
      local name, _, quality = W.ItemInfo(e.itemID or 0)
      if e.itemID and not name then
        self:RenderWhenLoaded(e.itemID)
      end
      local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
      local itemText = (color and color.hex or "|cffffffff")
        .. (name or e.name or ("item:" .. tostring(e.itemID)))
        .. "|r"
      for c, col in ipairs(tbl.cols) do
        local val
        if col.key == "name" then
          val = itemText
        elseif col.key == "when" then
          val = date("%b %d %H:%M", e.t)
        elseif col.key == "kind" then
          val = e.kind == "sale" and "|cff4dd973sold|r" or "|cffffcc33bought|r"
        elseif col.key == "profit" then
          val = e.kind == "sale" and signedMoney(profitOf[e]) or ""
        elseif col.key == "cut" then
          val = e.cut and W.Money(e.cut, true) or ""
        elseif col.key == "char" then
          val = e.char or ""
        else
          val = cellValue(col, e)
        end
        row.cells[c]:SetText(val)
      end
    end
  end

  local h = ns.Trading:Holdings()
  local chars = 0
  for _ in pairs(h) do
    chars = chars + 1
  end
  local status
  if ledgerMode then
    status = (
      "%d AH sales and purchases in the last 90 days. AME records them from auction mail: open your "
      .. "mailbox to catch new ones."
    ):format(#list)
  else
    status = (
      "%d positions on %d character%s. Bags update as you play; open your bank and the auction house to "
      .. "include bank items and active auctions."
    ):format(#list, chars, chars == 1 and "" or "s")
    if self.pfIndexMissing then
      status = "No market data for your faction's auction house yet - scan there to value your holdings."
    end
  end
  v.status:SetText(status)
end
