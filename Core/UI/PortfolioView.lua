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
  { key = "market", label = L["Market"], width = 84, format = "money" },
  { key = "value", label = L["Value"], width = 92, format = "money" },
  { key = "unitCost", label = L["Avg cost"], width = 84, format = "money", term = "pfCost" },
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
  { key = "sellRate", label = L["Sells/d"], width = 58, format = "rate", term = "sellRate" },
  {
    key = "daysToSell",
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
    label = L["Character"],
    width = 150,
    align = "LEFT",
    text = function(e)
      return e.char or ""
    end,
  },
}

function UI:CreatePortfolioView(parent, contentArea)
  local v = contentArea(parent)
  self.pfView = v
  self.pfMode = "positions"
  v.cardRow = W.CardRow(v, {
    { L["Holdings value"], term = "pfValue" },
    { L["Listed on the AH now"] }, -- its own tooltip: below
    { L["Unrealized profit"], term = "pfUnrealized" },
    { L["Realized profit, 7 days"], term = "pfProfit" },
    { L["30 days: sold / bought"], term = "pfFlow" },
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
  v.modes = W.Segmented(v, {
    { "positions", L["Positions"] },
    { "ledger", L["Ledger"] },
    { "auctions", L["Auctions"] },
    { "customers", L["Customers"] },
    { "suppliers", L["Suppliers"] },
  }, {
    minWidth = 80,
    onSelect = function(mode)
      UI.pfMode, UI.pfOffset = mode, 0
      UI:RefreshPortfolio()
    end,
  })
  v.modes:SetPoint("TOPLEFT", v.cardRow, "BOTTOMLEFT", 0, -10)
  v.ledgerButton, v.auctionsButton = v.modes.byKey.ledger, v.modes.byKey.auctions -- shortcuts (specs)
  local function itemID(e)
    return e.itemID
  end
  v.positions = ns.DataTable.New(v, {
    columns = POSITION_COLS,
    rows = ROWS,
    top = -80,
    itemID = itemID,
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
          W.TipPair(tip, (char:gsub("^[^:]*:", "")), qty)
        end
      end
    end,
  })
  v.auctions = ns.DataTable.New(v, {
    columns = AUCTION_COLS,
    rows = ROWS,
    top = -80,
    itemID = itemID,
    sort = { key = "total", ascending = false },
  })
  v.customers = ns.DataTable.New(v, {
    columns = counterpartyCols(L["Spent with you"], L["Purchases"]),
    rows = ROWS,
    top = -80,
    sort = { key = "amount", ascending = false },
  })
  v.suppliers = ns.DataTable.New(v, {
    columns = counterpartyCols(L["You spent"], L["Purchases"]),
    rows = ROWS,
    top = -80,
    sort = { key = "amount", ascending = false },
  })
  v.ledger = ns.DataTable.New(v, {
    columns = LEDGER_COLS,
    rows = ROWS,
    top = -80,
    itemID = itemID,
    sort = { key = "t", ascending = false }, -- newest first
    offset = {
      get = function()
        return UI.pfOffset
      end,
      set = function(n)
        UI.pfOffset = n
      end,
    },
  })
  v.status = W.StatusLine(v) -- one for all five tables
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
  ns.Trading:ResolveLedger() -- entries recorded before their item was known: icons and average cost need the ID
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
  self.pfCustomers = AME.ledger and AME.ledger:Counterparties("sale", now - 90 * DAY) or {}
  self.pfSuppliers = AME.ledger and AME.ledger:Counterparties("buy", now - 90 * DAY) or {}
  -- does this client's auction mail name the other player at all?
  self.pfNamesSeen = false
  for _, e in ipairs(AME.ledger and AME.ledger.db.entries or {}) do
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
  local t, w, m = self.pfTotals, self.pfWeek, self.pfMonth
  local l = self.pfListed
  v.cards[1].value:SetText(W.Money(t.value, true))
  v.cards[2].value:SetText(
    l.count > 0 and W.Money(l.value, true) .. "  " .. W.Dim(L["%d auctions"]:format(l.count))
      or W.Color("none", L["none"])
  )
  v.cards[3].value:SetText(W.SignedMoney(t.unrealized))
  v.cards[4].value:SetText(W.SignedMoney(w.profit))
  v.cards[5].value:SetText(W.Money(m.income or 0, true) .. " / " .. W.Money(m.spent or 0, true))
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

  local h = ns.Trading:Holdings()
  local chars = 0
  for _ in pairs(h) do
    chars = chars + 1
  end
  local status, message
  if customersMode or suppliersMode then
    if not self.pfNamesSeen and #self.pfLedger > 0 then
      message =
        L["Your auction mail doesn't name the other player on this client (the auction house keeps them anonymous), so there's no one to list."]
    else
      status = customersMode
          and L["%d customers in the last 90 days, by gold spent with you (from auction mail)."]:format(#list)
        or L["%d suppliers in the last 90 days, by gold you spent with them (from auction mail)."]:format(#list)
    end
  elseif auctionsMode then
    status =
      L["%d active auctions on your characters, as of the last time each opened the auction house. Sales show up in the ledger right away and are settled when the auction mail arrives."]:format(
        #list
      )
  elseif ledgerMode then
    status =
      L["%d AH sales and purchases in the last 90 days. AME records them from auction mail: open your mailbox to catch new ones."]:format(
        #list
      )
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
