-- Portfolio tab: what you hold (all characters, bags + bank + auctions) valued at your faction's market, cost basis
-- and unrealized profit from your AH purchases, and the ledger of AH sales and purchases from auction mail.
local _, ns = ...

local W = ns.Widgets
local UI = ns.UI
local DAY = 86400

local ROWS = 13

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

local function days(v)
  return v and (v < 1 and "<1" or ("%.0f"):format(v)) or "|cff777777-|r"
end

local POSITION_COLS = {
  { key = "name", label = "Item", width = 210, item = true, sortKey = false },
  { key = "qty", label = "Held", width = 50 },
  { key = "market", label = "Market", width = 84, format = "money" },
  { key = "value", label = "Value", width = 92, format = "money" },
  { key = "unitCost", label = "Avg cost", width = 84, format = "money", term = "pfCost" },
  {
    key = "unrealized",
    label = "Unrealized",
    width = 92,
    term = "pfUnrealized",
    text = function(e)
      return signedMoney(e.unrealized)
    end,
  },
  { key = "signal", label = "Signal", width = 50, format = "signal", term = "signal", sortKey = false },
  { key = "sellRate", label = "Sells/d", width = 58, format = "rate", term = "sellRate" },
  {
    key = "daysToSell",
    label = "Days to sell",
    width = 74,
    term = "pfDays",
    text = function(e)
      return days(e.daysToSell)
    end,
  },
}

local function timeLeft(a)
  if a.timeLeft then
    local left = a.timeLeft - (GetServerTime() - (a.seen or GetServerTime()))
    if left <= 0 then
      return "|cff999999ended?|r"
    end
    return left >= 3600 and ("%dh"):format(left / 3600) or ("%dm"):format(left / 60)
  end
  local bands = { [0] = "< 30m", [1] = "< 2h", [2] = "< 12h", [3] = "> 12h" }
  return a.timeLeftBand and bands[a.timeLeftBand] or "|cff777777-|r"
end

local AUCTION_COLS = {
  { key = "name", label = "Item", width = 230, item = true, sortKey = false },
  { key = "qty", label = "Qty", width = 50 },
  { key = "unit", label = "Price each", width = 92, format = "money" },
  { key = "total", label = "Total", width = 96, format = "money" },
  {
    key = "timeLeft",
    label = "Time left",
    width = 70,
    text = function(a)
      return timeLeft(a)
    end,
  },
  {
    key = "char",
    label = "Character",
    width = 150,
    align = "LEFT",
    sortKey = false,
    text = function(a)
      return a.char or ""
    end,
  },
  {
    key = "house",
    label = "Auction house",
    width = 100,
    align = "LEFT",
    sortKey = false,
    text = function(a)
      return ns.HOUSE_LABEL[a.house] or a.house or ""
    end,
  },
}

local LEDGER_COLS = {
  {
    key = "when",
    label = "When",
    width = 96,
    align = "LEFT",
    text = function(e)
      return date("%b %d %H:%M", e.t)
    end,
  },
  {
    key = "kind",
    label = "",
    width = 44,
    text = function(e)
      return (e.kind == "sale" or e.kind == "pending") and "|cff4dd973sold|r" or "|cffffcc33bought|r"
    end,
  },
  {
    key = "name",
    label = "Item",
    width = 230,
    item = true,
    fallback = function(e)
      return e.name
    end,
  },
  {
    key = "qty",
    label = "Qty",
    width = 44,
    text = function(e)
      return e.qty and tostring(e.qty) or "|cff999999?|r"
    end,
  },
  {
    key = "amount",
    label = "Price",
    width = 92,
    text = function(e)
      if e.kind == "pending" then
        return "|cff999999awaiting mail|r"
      end
      return W.Money(e.amount, true)
    end,
  },
  {
    key = "cut",
    label = "AH cut",
    width = 76,
    text = function(e)
      return e.cut and W.Money(e.cut, true) or ""
    end,
  },
  {
    key = "profit",
    label = "Profit",
    width = 92,
    term = "pfProfit",
    text = function(e)
      return e.kind == "sale" and signedMoney(UI.pfProfitOf and UI.pfProfitOf[e]) or ""
    end,
  },
  {
    key = "char",
    label = "Character",
    width = 150,
    align = "LEFT",
    text = function(e)
      return e.char or ""
    end,
  },
}
for _, col in ipairs(LEDGER_COLS) do
  col.sortKey = false -- newest first
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
  v.auctionsButton = W.Button(v, "Auctions", 80, 20, function()
    UI.pfMode, UI.pfOffset = "auctions", 0
    UI:RefreshPortfolio()
  end)
  v.auctionsButton:SetPoint("LEFT", v.ledgerButton, "RIGHT", 4, 0)
  local function itemID(e)
    return e.itemID
  end
  v.positions = ns.DataTable.New(v, {
    columns = POSITION_COLS,
    rows = ROWS,
    top = -82,
    itemID = itemID,
    localSort = true,
    sort = { key = "value", ascending = false },
    offset = {
      get = function()
        return UI.pfOffset
      end,
      set = function(n)
        UI.pfOffset = n
      end,
    },
    tooltip = function(tip, e)
      if e.chars then
        tip:AddLine(" ")
        for char, qty in pairs(e.chars) do
          tip:AddDoubleLine(char:gsub("^[^:]*:", ""), qty, 0.7, 0.7, 0.7, 1, 1, 1)
        end
      end
    end,
  })
  v.auctions = ns.DataTable.New(v, {
    columns = AUCTION_COLS,
    rows = ROWS,
    top = -82,
    itemID = itemID,
    localSort = true,
    sort = { key = "total", ascending = false },
  })
  v.ledger = ns.DataTable.New(v, {
    columns = LEDGER_COLS,
    rows = ROWS,
    top = -82,
    itemID = itemID,
    offset = {
      get = function()
        return UI.pfOffset
      end,
      set = function(n)
        UI.pfOffset = n
      end,
    },
  })
  v.status = W.Text(v, "GameFontDisableSmall", "LEFT")
  v.status:SetPoint("BOTTOMLEFT", 0, 0)
  v.status:SetWidth(940)
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
  self.pfAuctions = ns.Trading:ActiveAuctions()
  self.pfIndexMissing = index == nil
  self:RenderPortfolio()
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
  local mode = self.pfMode
  local ledgerMode, auctionsMode = mode == "ledger", mode == "auctions"
  v.positionsButton:SetSelected(mode == "positions")
  v.ledgerButton:SetSelected(ledgerMode)
  v.auctionsButton:SetSelected(auctionsMode)

  local list = ledgerMode and self.pfLedger or auctionsMode and self.pfAuctions or self.pfRows
  local tbl = ledgerMode and v.ledger or auctionsMode and v.auctions or v.positions
  if ledgerMode and ns.AME.ledger then
    self.pfProfitOf = {}
    for _, e in ipairs(list) do
      if e.kind == "sale" then
        self.pfProfitOf[e] = ns.AME.ledger:Profit(e)
      end
    end
  end
  v.positions:SetShown(mode == "positions")
  v.ledger:SetShown(ledgerMode)
  v.auctions:SetShown(auctionsMode)
  tbl:SetData(list)
  tbl:Render()

  local h = ns.Trading:Holdings()
  local chars = 0
  for _ in pairs(h) do
    chars = chars + 1
  end
  local status
  if auctionsMode then
    status = (
      "%d active auctions on your characters, as of the last time each opened the auction house. Sales show up "
      .. "in the ledger right away and are settled when the auction mail arrives."
    ):format(#list)
  elseif ledgerMode then
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
