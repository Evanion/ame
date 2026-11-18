-- Portfolio tab: what you hold (all characters, bags + bank + auctions) valued at your faction's market, cost basis
-- and unrealized profit from your AH purchases, and the ledger of AH sales and purchases from auction mail.
local _, ns = ...
local L = ns.L

local W = ns.Widgets
local UI = ns.UI
local DAY = 86400

local ROWS = 13

local function days(v)
  return v and (v < 1 and "<1" or ("%.0f"):format(v)) or W.NONE
end

local POSITION_COLS = {
  { key = "name", label = L["Item"], width = 210, item = true, ascendingFirst = true },
  { key = "qty", label = L["Held"], width = 50 },
  { key = "market", drop = 2, label = L["Market"], width = 84, format = "money" },
  { key = "value", label = L["Value"], width = 92, format = "money" },
  { key = "unitCost", drop = 1, label = L["Avg cost"], width = 84, format = "money", term = "pfCost" },
  {
    key = "unrealized",
    label = L["Unrealized"],
    width = 92,
    term = "pfUnrealized",
    text = function(e)
      return W.SignedMoney(e.unrealized)
    end,
  },
  {
    key = "signal",
    label = L["Signal"],
    width = 50,
    format = "signal",
    term = "signal",
    sortKey = "signalRank",
    ascendingFirst = true,
  },
  { key = "sellRate", drop = 3, label = L["Sells/d"], width = 58, format = "rate", term = "sellRate" },
  {
    key = "daysToSell",
    drop = 4,
    label = L["Days to sell"],
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
      return W.Dim(L["ended?"])
    end
    return left >= 3600 and ("%dh"):format(left / 3600) or ("%dm"):format(left / 60)
  end
  local bands = { [0] = "< 30m", [1] = "< 2h", [2] = "< 12h", [3] = "> 12h" }
  return a.timeLeftBand and bands[a.timeLeftBand] or W.NONE
end

local AUCTION_COLS = {
  { key = "name", label = L["Item"], width = 230, item = true, ascendingFirst = true },
  { key = "qty", label = L["Qty"], width = 50 },
  { key = "unit", label = L["Price each"], width = 92, format = "money" },
  { key = "total", label = L["Total"], width = 96, format = "money" },
  {
    key = "timeLeft",
    label = L["Time left"],
    width = 70,
    text = function(a)
      return timeLeft(a)
    end,
  },
  {
    key = "char",
    drop = 1,
    label = L["Character"],
    width = 150,
    align = "LEFT",
    ascendingFirst = true,
    text = function(a)
      return a.char or ""
    end,
  },
  {
    key = "house",
    drop = 2,
    label = L["Auction house"],
    width = 100,
    align = "LEFT",
    ascendingFirst = true,
    text = function(a)
      return ns.HOUSE_LABEL[a.house] or a.house or ""
    end,
  },
}

local function counterpartyCols(amountLabel, tradesLabel)
  return {
    { key = "name", label = L["Player"], width = 180, align = "LEFT", ascendingFirst = true },
    { key = "amount", label = amountLabel, width = 110, format = "money" },
    { key = "trades", label = tradesLabel, width = 70 },
    { key = "units", label = L["Items"], width = 60 },
    {
      key = "favourite",
      drop = 2,
      label = L["Mostly"],
      width = 230,
      align = "LEFT",
      ascendingFirst = true,
      text = function(c)
        return c.favourite or ""
      end,
    },
    {
      key = "last",
      drop = 1,
      label = L["Last"],
      width = 96,
      text = function(c)
        return c.last > 0 and date("%b %d %H:%M", c.last) or ""
      end,
    },
  }
end

local LEDGER_COLS = {
  {
    key = "when",
    label = L["When"],
    width = 96,
    align = "LEFT",
    sortKey = "t",
    text = function(e)
      return date("%b %d %H:%M", e.t)
    end,
  },
  {
    key = "kind",
    label = "",
    width = 44,
    text = function(e)
      if e.kind == "sale" or e.kind == "pending" then
        return W.Color("good", L["sold"])
      end
      return W.Color("hold", L["bought"])
    end,
  },
  {
    key = "name",
    label = L["Item"],
    width = 230,
    item = true,
    fallback = function(e)
      return e.name
    end,
  },
  {
    key = "qty",
    label = L["Qty"],
    width = 44,
    text = function(e)
      return e.qty and tostring(e.qty) or W.Dim("?")
    end,
  },
  {
    key = "amount",
    label = L["Price"],
    width = 92,
    text = function(e)
      if e.kind == "pending" then
        return W.Dim(L["awaiting mail"])
      end
      return W.Money(e.amount, true)
    end,
  },
  {
    key = "cut",
    drop = 1,
    label = L["AH cut"],
    width = 76,
    text = function(e)
      return e.cut and W.Money(e.cut, true) or ""
    end,
  },
  {
    key = "profit",
    label = L["Profit"],
    width = 92,
    term = "pfProfit",
    sortKey = false, -- computed per sale at render time
    text = function(e)
      return e.kind == "sale" and W.SignedMoney(UI.pfProfitOf and UI.pfProfitOf[e]) or ""
    end,
  },
  {
    key = "char",
    drop = 2,
    label = L["Character"],
    width = 150,
    align = "LEFT",
    text = function(e)
      return e.char or ""
    end,
  },
}

-- Layout (UI.Slots): header = KPI cards; toolbar = modes, account / this character, period, Export; the table of the
-- mode; status line.
local PERIODS = {
  { "today", L["Today"] },
  { 7, L["7 days"] },
  { 30, L["30 days"] },
  { "all", L["All time"] },
}
local SCOPES = {
  { "account", L["All characters"] },
  { "char", L["This character"] },
}

-- the start of the period (server time): today = since midnight (server day), else n days back, all = everything
function UI:PortfolioSince(now)
  local p = self.pfPeriod
  if p == "today" then
    return ns.Today(now) * DAY
  elseif p == "all" then
    return 0
  end
  return now - (p or 30) * DAY
end

function UI:CreatePortfolioView(parent, contentArea)
  local v = contentArea(parent)
  self.pfView = v
  self.pfMode, self.pfScope, self.pfPeriod = "positions", "account", 30
  local slots = UI.Slots(v, { header = 42, toolbar = 22, status = true })
  v.slots = slots
  v.cardRow = W.CardRow(slots.header, {
    { L["Holdings value"], term = "pfValue" },
    { L["Listed on the AH now"] }, -- its own tooltip: below
    { L["Unrealized profit"], term = "pfUnrealized" },
    { L["Realized profit"], term = "pfProfit" },
    { L["Sold / bought"], term = "pfFlow" },
  }, { width = UI.WIDTH - 20 })
  v.cardRow:SetPoint("TOPLEFT", 0, 0)
  v.cardRow:SetPoint("RIGHT", 0, 0)
  v.cards = v.cardRow.cards
  -- listed: per-character breakdown on hover
  W.Tooltip(v.cards[2], function(tip)
    local l = UI.pfListed
    W.TipText(
      tip,
      L["Listed on the auction house now"],
      L["Your active auctions on all characters, as of the last time each opened the auction house."]
    )
    if l and l.count > 0 then
      tip:AddLine(" ")
      W.TipPair(tip, L["Asking prices"], W.Money(l.value))
      W.TipPair(tip, L["You'd receive (after the cut)"], W.Money(l.net))
      W.TipPair(tip, L["At market price"], W.Money(l.market))
      tip:AddLine(" ")
      for char, c in pairs(l.chars) do
        W.TipPair(
          tip,
          ("%s (%s)"):format(char:gsub("^[^:]*:", ""), ns.HOUSE_LABEL[c.house] or c.house or "?"),
          ("%d  ·  %s"):format(c.count, W.Money(c.value, true))
        )
      end
    end
  end, "ANCHOR_BOTTOM")

  local bar = slots.toolbar
  v.modes = W.Segmented(bar, {
    { "positions", L["Positions"] },
    { "ledger", L["Ledger"] },
    { "auctions", L["Auctions"] },
    { "customers", L["Customers"] },
    { "suppliers", L["Suppliers"] },
  }, {
    minWidth = 70,
    onSelect = function(mode)
      UI.pfMode, UI.pfOffset = mode, 0
      UI:RefreshPortfolio()
    end,
  })
  v.modes:SetPoint("LEFT", 0, 0)
  v.ledgerButton, v.auctionsButton = v.modes.byKey.ledger, v.modes.byKey.auctions -- shortcuts (specs)
  v.export = W.Button(bar, L["Export"], 64, 20, function()
    UI:ExportPortfolio()
  end)
  v.export:SetPoint("RIGHT", 0, 0)
  v.period = W.Dropdown(bar, 96, PERIODS, function(value)
    UI.pfPeriod, UI.pfOffset = value, 0
    UI:RefreshPortfolio()
  end, { neutral = true, default = 30 })
  v.period:SetPoint("RIGHT", v.export, "LEFT", -6, 0)
  v.scope = W.Dropdown(bar, 120, SCOPES, function(value)
    UI.pfScope, UI.pfOffset = value, 0
    UI:RefreshPortfolio()
  end, { neutral = true })
  v.scope:SetPoint("RIGHT", v.period, "LEFT", -6, 0)

  local main = slots.main
  local function itemID(e)
    return e.itemID
  end
  local offset = {
    get = function()
      return UI.pfOffset
    end,
    set = function(n)
      UI.pfOffset = n
    end,
  }
  v.positions = ns.DataTable.New(main, {
    columns = POSITION_COLS,
    rows = ROWS,
    fill = true,
    top = 0,
    itemID = itemID,
    sort = { key = "value", ascending = false },
    offset = offset,
    tooltip = function(tip, e)
      if e.chars then
        tip:AddLine(" ")
        for char, qty in pairs(e.chars) do
          W.TipPair(tip, (char:gsub("^[^:]*:", "")), qty)
        end
      end
    end,
  })
  v.auctions = ns.DataTable.New(main, {
    columns = AUCTION_COLS,
    rows = ROWS,
    fill = true,
    top = 0,
    itemID = itemID,
    sort = { key = "total", ascending = false },
  })
  v.customers = ns.DataTable.New(main, {
    columns = counterpartyCols(L["Spent with you"], L["Purchases"]),
    rows = ROWS,
    fill = true,
    top = 0,
    sort = { key = "amount", ascending = false },
  })
  v.suppliers = ns.DataTable.New(main, {
    columns = counterpartyCols(L["You spent"], L["Purchases"]),
    rows = ROWS,
    fill = true,
    top = 0,
    sort = { key = "amount", ascending = false },
  })
  v.ledger = ns.DataTable.New(main, {
    columns = LEDGER_COLS,
    rows = ROWS,
    fill = true,
    top = 0,
    itemID = itemID,
    sort = { key = "t", ascending = false }, -- newest first
    offset = offset,
  })
  v.status = slots.status -- one for all five tables
  v:SetScript("OnShow", function()
    ns.Trading:ScanBags()
    UI:RefreshPortfolio()
  end)
  return v
end

-- the table on screen as text to copy
function UI:ExportPortfolio()
  local v = self.pfView
  local tbl = v[self.pfMode]
  local title = v.modes.byKey[self.pfMode].label:GetText() or ""
  return W.ExportBox(L["Export: %s"]:format(title), tbl:ExportText())
end

function UI:RefreshPortfolio()
  local v = self.pfView
  if not (v and v:IsShown()) then
    return
  end
  local AME = ns.AME
  local index = AME:FactionIndex()
  ns.Trading:ResolveLedger() -- entries recorded before their item was known: icons and average cost need the ID
  local basis = AME.ledger and AME.ledger:CostBasis() or {}
  -- scope: every character, or this one (holdings by "<market>:<name>", ledger entries by name)
  local holdings, char = ns.Trading:Holdings(), nil
  if self.pfScope == "char" then
    local key = ns.Trading.CharKey()
    holdings = { [key] = holdings[key] }
    char = UnitName("player")
  end
  self.pfRows, self.pfTotals = ns.Portfolio.Build(holdings, basis, index and index.items or {})
  self.pfListed = ns.Portfolio.Listed(holdings, function(house)
    return ns.Settings:AuctionCut(house)
  end, index and index.items or {})
  local now = GetServerTime()
  local since = self:PortfolioSince(now)
  local ledger = AME.ledger
  self.pfSummary = ledger and ledger:Summary(since, char) or {}
  self.pfLedger = ledger and ledger:Recent(since, nil, char) or {}
  self.pfAuctions = ns.Trading:ActiveAuctions(holdings)
  self.pfCustomers = ledger and ledger:Counterparties("sale", since, char) or {}
  self.pfSuppliers = ledger and ledger:Counterparties("buy", since, char) or {}
  -- does this client's auction mail name the other player at all?
  self.pfNamesSeen = false
  for _, e in ipairs(ledger and ledger.db.entries or {}) do
    if e.counterparty then
      self.pfNamesSeen = true
      break
    end
  end
  self.pfIndexMissing = index == nil
  self:RenderPortfolio()
end

function UI:RenderPortfolio()
  local v = self.pfView
  if not (v and v:IsShown() and self.pfRows) then
    return
  end
  local t, sum = self.pfTotals, self.pfSummary
  local l = self.pfListed
  local periodLabel
  for _, p in ipairs(PERIODS) do
    if p[1] == self.pfPeriod then
      periodLabel = p[2]
    end
  end
  v.period:SetValue(self.pfPeriod)
  v.scope:SetValue(self.pfScope)
  v.cards[1].value:SetText(W.Money(t.value, true))
  v.cards[2].value:SetText(
    l.count > 0 and W.Money(l.value, true) .. "  " .. W.Dim(L["%d auctions"]:format(l.count))
      or W.Color("none", L["none"])
  )
  v.cards[3].value:SetText(W.SignedMoney(t.unrealized))
  v.cards[4].label:SetText(L["Realized profit, %s"]:format(periodLabel or ""))
  v.cards[4].value:SetText(W.SignedMoney(sum.profit))
  v.cards[5].label:SetText(L["Sold / bought, %s"]:format(periodLabel or ""))
  v.cards[5].value:SetText(W.Money(sum.income or 0, true) .. " / " .. W.Money(sum.spent or 0, true))
  local mode = self.pfMode
  local ledgerMode, auctionsMode = mode == "ledger", mode == "auctions"
  local customersMode, suppliersMode = mode == "customers", mode == "suppliers"
  v.modes:Select(mode, true)

  local lists = {
    positions = { self.pfRows, v.positions },
    ledger = { self.pfLedger, v.ledger },
    auctions = { self.pfAuctions, v.auctions },
    customers = { self.pfCustomers, v.customers },
    suppliers = { self.pfSuppliers, v.suppliers },
  }
  local list, tbl = lists[mode][1], lists[mode][2]
  for name, pair in pairs(lists) do
    pair[2]:SetShown(name == mode)
  end
  if ledgerMode and ns.AME.ledger then
    self.pfProfitOf = ns.AME.ledger:Profits() -- one pass over the ledger, not one per sale
  end
  tbl:SetData(list)
  tbl:Render()

  local chars = 0
  for _ in pairs(self.pfScope == "char" and { 1 } or ns.Trading:Holdings()) do
    chars = chars + 1
  end
  local status, message
  if customersMode or suppliersMode then
    if not self.pfNamesSeen and #self.pfLedger > 0 then
      message =
        L["Your auction mail doesn't name the other player on this client (the auction house keeps them anonymous), so there's no one to list."]
    else
      status = customersMode and L["%d customers, by gold spent with you (from auction mail)."]:format(#list)
        or L["%d suppliers, by gold you spent with them (from auction mail)."]:format(#list)
    end
  elseif auctionsMode then
    status =
      L["%d active auctions on your characters, as of the last time each opened the auction house. Sales show up in the ledger right away and are settled when the auction mail arrives."]:format(
        #list
      )
  elseif ledgerMode then
    status =
      L["%d AH sales and purchases. AME records them from auction mail: open your mailbox to catch new ones."]:format(
        #list
      )
    if #list == 0 then
      message = L["No sales or purchases in this period yet. AME records them from auction mail."]
    end
  else
    if chars == 1 then
      status =
        L["%d positions on %d character. Bags update as you play; open your bank and the auction house to include bank items and active auctions."]:format(
          #list,
          chars
        )
    else
      status =
        L["%d positions on %d characters. Bags update as you play; open your bank and the auction house to include bank items and active auctions."]:format(
          #list,
          chars
        )
    end
    if self.pfIndexMissing then
      status = L["No market data for your faction's auction house yet - scan there to value your holdings."]
    end
  end
  tbl:SetMessage(message)
  v.status:SetText(status or "")
end
