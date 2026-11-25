-- Portfolio, Sell and Auctions (the redesign's Portfolio tab, boards Portfolio, AHSell, SellCompact, AHSellTips,
-- AHAuctions): pure functions turn gathered facts into table rows, KPI cards and card lines; the Gather functions
-- read them from the rest of AME (Portfolio, Ledger, Trading, Posting, AHSelling, AHSearch), the way the old
-- Portfolio view and the auction house's Selling tab do. The screens are Core/UI/Screens/Portfolio.lua, Sell.lua and
-- Auctions.lua.
--
--   P.Gather(scope, range) -> facts          positions, totals, listed, ledger, customers, suppliers, auctions
--   P.Kpis(facts, rangeLabel, undercut) -> { kpi props, ... }
--   P.PositionRows / LedgerRows / CounterpartyRows (facts) -> table rows
--   P.Columns(view) -> table columns         P.Status(view, facts) -> the status line
--   P.Standing(auction, book) -> { kind = "lowest" | "only" | "undercut" | "unchecked", lowest, by, ahead, units }
--   P.AuctionRows(auctions, books, opts) -> rows, summary
--   P.SellEntries() -> entries               your bags at the auction house, ranked (AHSelling's rules)
--   P.BagRows(entries) / P.Ladder(advice, picked) / P.SaleRows(book, now)
--   P.Post(payload), P.Cancel(payload)       the game's posting and cancelling: call them from the button's click
local _, ns = ...
local L = ns.L

local P = { errors = {}, searched = {} }
ns.PortfolioPage = P

local DAY = 86400

local function W()
  return ns.Widgets
end

local function money(copper)
  return ns.Widgets and ns.Widgets.Money(copper, true) or tostring(copper)
end

local function count(n)
  return ns.Widgets and ns.Widgets.Count(n) or tostring(n)
end

local function now()
  return GetServerTime and GetServerTime() or os.time()
end

-- a piece of the gather that fails is left out, and named
local function try(name, fn, ...)
  local ok, err = ns.ShieldOk(fn, ...) -- its error goes to the game's handler (BugSack) too
  if not ok then
    P.errors[name] = err
  end
  return ok
end

-- ------------------------------------------------------------------------------------------------ toolbar

P.VIEWS = {
  { "positions", L["Positions"] },
  { "ledger", L["Ledger"] },
  { "auctions", L["Auctions"] },
  { "customers", L["Customers"] },
  { "suppliers", L["Suppliers"] },
}
P.SCOPES = { { "all", L["All characters"] }, { "char", L["This character"] } }
P.RANGES = { { "reset", L["Since reset"] }, { "7", L["7 days"] }, { "30", L["30 days"] }, { "all", L["All"] } }

-- Portfolio's views; Sell comes first while the auction house is open
function P.Views(atAH)
  local out = {}
  if atAH then
    out[1] = { "sell", L["Sell"] }
  end
  for _, v in ipairs(P.VIEWS) do
    out[#out + 1] = v
  end
  return out
end

function P.RangeLabel(range)
  for _, r in ipairs(P.RANGES) do
    if r[1] == range then
      return r[2]
    end
  end
  return ""
end

-- the start of a range (server time). reset: since the last daily reset (resetIn: seconds to the next one)
function P.Since(range, t, resetIn)
  if range == "all" then
    return 0
  elseif range == "reset" then
    if resetIn == nil and GetQuestResetTime then
      local ok, v = pcall(GetQuestResetTime)
      resetIn = ok and v or nil
    end
    if resetIn and resetIn > 0 and resetIn <= DAY then
      return t + resetIn - DAY
    end
    return math.floor(t / DAY) * DAY
  end
  return t - (tonumber(range) or 7) * DAY
end

-- ------------------------------------------------------------------------------------------------ positions

P.PLACES = { "bags", "bank", "mail", "auctions" }
P.PLACE = { bags = L["bags"], bank = L["bank"], mail = L["mail"], auctions = L["auction"] }

local function short(key)
  return (tostring(key):gsub("^[^:]*:", ""))
end

-- Where you hold an item, in a few words: "Tyken · bags", "Tyken · bags 10, Kke 8", "Kke · bank 4, mail 2".
--   h: a Holdings.Map entry ({ chars = { [charKey] = n }, guilds = { [guildKey] = n } }); holdings: AME_DB.holdings
function P.Where(key, h, holdings)
  local who = {}
  for char, n in pairs(h and h.chars or {}) do
    who[#who + 1] = { key = char, n = n }
  end
  for g, n in pairs(h and h.guilds or {}) do
    who[#who + 1] = { key = g, n = n, guild = true }
  end
  if #who == 0 then
    return ""
  end
  table.sort(who, function(a, b)
    if a.n ~= b.n then
      return a.n > b.n
    end
    return a.key < b.key
  end)
  local first = who[1]
  local places = {}
  if first.guild then
    places[1] = { L["guild bank"], first.n }
  else
    local mine = holdings and holdings[first.key] or {}
    for _, place in ipairs(P.PLACES) do
      local n = mine[place] and mine[place][key]
      if n and n > 0 then
        places[#places + 1] = { P.PLACE[place], n }
      end
    end
  end
  local alone = #who == 1 and #places == 1
  local bits = {}
  for i, p in ipairs(places) do
    bits[i] = alone and p[1] or (p[1] .. " " .. count(p[2]))
  end
  local text = short(first.key) .. (#bits > 0 and (" · " .. table.concat(bits, ", ")) or "")
  for i = 2, #who do
    text = text .. ", " .. short(who[i].key) .. " " .. count(who[i].n)
  end
  return text
end

local function days(v)
  if not v then
    return "—"
  end
  return v < 1 and "<1" or ("%.0f"):format(v)
end

function P.PositionRows(f)
  local out = {}
  for i, r in ipairs(f.positions or {}) do
    out[i] = {
      key = tostring(r.itemID),
      item = r.itemID,
      held = r.qty,
      where = { text = P.Where(r.itemID, f.held and f.held[r.itemID] or { chars = r.chars }, f.holdingsAll), color = "dim" },
      market = r.market,
      value = r.value,
      cost = r.unitCost,
      unrealized = r.unrealized,
      signal = r.signal,
      rate = r.soldPerDay,
      days = days(r.daysToSell),
    }
  end
  return out
end

-- ------------------------------------------------------------------------------------------------ ledger

local function when(t)
  return t and date("%b %d %H:%M", t) or ""
end

function P.LedgerRows(f)
  local out, profits = {}, f.profits or {}
  for i, e in ipairs(f.ledger or {}) do
    local sold = e.kind == "sale" or e.kind == "pending"
    out[i] = {
      key = "l" .. i,
      item = e.itemID,
      name = e.name,
      when = when(e.t),
      kind = sold and { text = L["sold"], color = "good" } or { text = L["bought"], color = "warn" },
      qty = e.qty and ns.Widgets.Count(e.qty) or { text = "?", color = "dim" },
      price = e.kind == "pending" and { text = L["awaiting mail"], color = "dim" } or ns.Widgets.Money(e.amount, true),
      cut = e.cut,
      profit = e.kind == "sale" and profits[e] or nil,
      char = e.char or "",
      faded = e.kind == "pending" or nil,
    }
  end
  return out
end

function P.CounterpartyRows(list)
  local out = {}
  for i, c in ipairs(list or {}) do
    out[i] = {
      key = "c" .. tostring(c.name),
      item = c.favouriteKey,
      name = c.favourite,
      player = c.name,
      amount = c.amount,
      trades = c.trades,
      units = c.units,
      last = c.last and c.last > 0 and when(c.last) or "",
    }
  end
  return out
end

-- ------------------------------------------------------------------------------------------------ columns

P.COLUMNS = {
  positions = {
    { key = "name", label = L["Item"], width = 220, item = true },
    { key = "held", label = L["Held"], width = 50, format = "count" },
    { key = "where", label = L["Where"], width = 170, align = "LEFT" },
    { key = "market", label = L["Market"], width = 80, format = "money" },
    { key = "value", label = L["Value"], width = 86, format = "money" },
    { key = "cost", label = L["Avg cost"], width = 80, format = "money", term = "pfCost" },
    { key = "unrealized", label = L["Unrealized"], width = 86, format = "signedMoney", term = "pfUnrealized" },
    { key = "signal", label = L["Signal"], width = 64, format = "signal", term = "signal" },
    { key = "rate", label = L["Sells/day"], width = 64, format = "rate", term = "sellRate" },
    { key = "days", label = L["Days to sell"], width = 76, term = "pfDays" },
  },
  ledger = {
    { key = "when", label = L["When"], width = 100, align = "LEFT" },
    { key = "kind", label = "", width = 54, align = "LEFT" },
    { key = "name", label = L["Item"], width = 240, item = true },
    { key = "qty", label = L["Qty"], width = 50 }, -- a dim "?" when unknown
    { key = "price", label = L["Price"], width = 92 }, -- money; a pending sale: "awaiting mail"
    { key = "cut", label = L["AH cut"], width = 80, format = "money" },
    { key = "profit", label = L["Profit"], width = 92, format = "signedMoney", term = "pfProfit" },
    { key = "char", label = L["Character"], width = 140, align = "LEFT" },
  },
  customers = {
    { key = "player", label = L["Player"], width = 180, align = "LEFT" },
    { key = "amount", label = L["Spent with you"], width = 110, format = "money" },
    { key = "trades", label = L["Purchases"], width = 80, format = "count" },
    { key = "units", label = L["Items"], width = 60, format = "count" },
    { key = "name", label = L["Mostly"], width = 240, item = true },
    { key = "last", label = L["Last"], width = 100 },
  },
  suppliers = {
    { key = "player", label = L["Player"], width = 180, align = "LEFT" },
    { key = "amount", label = L["You spent"], width = 110, format = "money" },
    { key = "trades", label = L["Purchases"], width = 80, format = "count" },
    { key = "units", label = L["Items"], width = 60, format = "count" },
    { key = "name", label = L["Mostly"], width = 240, item = true },
    { key = "last", label = L["Last"], width = 100 },
  },
  bags = {
    { key = "name", label = L["In your bags"], width = 170, item = true, count = "qty" },
    { key = "tip", label = L["Tip"], width = 52, align = "LEFT" },
    { key = "worth", label = L["Worth"], width = 70, format = "money" },
  },
  sale = {
    { key = "price", label = L["On sale now"], width = 90, format = "money", align = "LEFT" },
    { key = "qty", label = L["Qty"], width = 50, format = "count" },
    { key = "left", label = L["Time left"], width = 70 },
    { key = "mine", label = "", width = 44, align = "LEFT" },
  },
  auctions = {
    { key = "name", label = L["Item"], width = 220, item = true },
    { key = "qty", label = L["Qty"], width = 46, format = "count" },
    { key = "unit", label = L["Price each"], width = 86, format = "money" },
    { key = "lowest", label = L["Lowest now"], width = 86, format = "money" },
    { key = "standing", label = L["Standing"], width = 230, align = "LEFT" },
    { key = "left", label = L["Time left"], width = 70 },
    { key = "char", label = L["Character"], width = 90, align = "LEFT" },
    { key = "cancel", label = "", width = 60, button = { label = L["Cancel"], action = "cancelRow" } },
  },
}

P.SORT = {
  positions = { key = "value", ascending = false },
  customers = { key = "amount", ascending = false },
  suppliers = { key = "amount", ascending = false },
}

function P.Columns(view)
  return P.COLUMNS[view] or P.COLUMNS.positions
end

-- ------------------------------------------------------------------------------------------------ kpis

function P.Kpis(f, rangeLabel, undercut)
  local t, l, s = f.totals or {}, f.listed or { count = 0, value = 0 }, f.summary or {}
  local listed = { label = L["Listed on the AH now"] }
  if (l.count or 0) > 0 then
    listed.copper = l.value
    local d = L["%d auctions"]:format(l.count)
    if (undercut or 0) > 0 then
      d = d .. " · " .. L["%d undercut"]:format(undercut)
    end
    listed.delta, listed.deltaTone = d, (undercut or 0) > 0 and "bad" or "dim"
  else
    listed.value = L["none"]
  end
  local flow = money(s.income or 0) .. " / " .. money(s.spent or 0)
  return {
    { label = L["Holdings value"], copper = t.value or 0 },
    listed,
    { label = L["Unrealized profit"], copper = t.unrealized or 0, signed = true },
    { label = L["Realized profit · %s"]:format(rangeLabel or ""), copper = s.profit or 0, signed = true },
    { label = L["Sold / bought · %s"]:format(rangeLabel or ""), value = flow },
  }
end

-- ------------------------------------------------------------------------------------------------ status

function P.Status(view, f, rows)
  local n = #(rows or {})
  if f.indexMissing and view == "positions" then
    return L["No market data for your faction's auction house yet: scan there to value your holdings."]
  end
  if view == "ledger" then
    return n == 0 and L["No sales or purchases in this range yet. They're recorded from auction mail."]
      or L["%d sales and purchases, from auction mail: open your mailbox to catch new ones."]:format(n)
  elseif view == "customers" or view == "suppliers" then
    if not f.namesSeen and #(f.ledger or {}) > 0 then
      return L["Your auction mail doesn't name the other player on this client, so there's no one to list."]
    end
    return view == "customers" and L["%d customers, by gold spent with you"]:format(n)
      or L["%d suppliers, by gold you spent with them"]:format(n)
  end
  local chars = f.chars or 0
  local text = (chars == 1 and L["%d positions on %d character"] or L["%d positions on %d characters"]):format(n, chars)
  text = text .. " · " .. L["bank counted as of your last visit"] .. " · " .. L["soulbound items left out"]
  local t = f.totals or {}
  if (t.hidden or 0) > 0 then
    text = text .. " · " .. L["%d hidden, not counted"]:format(t.hidden)
  end
  return text
end

-- ------------------------------------------------------------------------------------------------ gather

function P.Gather(scope, range)
  P.errors = {}
  local AME = ns.AME or {}
  local f = { scope = scope, range = range, now = now() }
  local index = AME.FactionIndex and AME:FactionIndex()
  f.indexMissing = index == nil
  f.items = index and index.items or {}
  local hscope, char = "market", nil
  if scope == "char" and ns.Trading then
    hscope, char = ns.Trading.CharKey(), UnitName and UnitName("player")
  end
  f.char = char
  try("holdings", function()
    local all = (ns.Trading and ns.Trading:Holdings()) or (AME_DB and AME_DB.holdings) or {}
    local keep = ns.Holdings.Keep(hscope)
    local holdings, chars = {}, 0
    for key, h in pairs(all) do
      if not keep or keep(key) then
        holdings[key], chars = h, chars + 1
      end
    end
    f.holdings, f.holdingsAll, f.chars = holdings, all, chars
  end)
  f.holdings = f.holdings or {}
  try("positions", function()
    if ns.Trading and ns.Trading.ResolveLedger then
      ns.Trading:ResolveLedger()
    end
    local basis = AME.ledger and AME.ledger:CostBasis() or {}
    local q = index and ns.Quote.For(AME:FactionShard(), index, { fresh = false })
    f.held = ns.Holdings.Of("owned", hscope)
    f.positions, f.totals = ns.Portfolio.Build(f.held, basis, f.items, AME.watch and AME.watch:Hidden(), q and function(id)
      return q:Worth(id)
    end)
  end)
  try("listed", function()
    f.listed = ns.Portfolio.Listed(f.holdings, ns.Quote.Cut, f.items)
  end)
  try("ledger", function()
    local ledger = AME.ledger
    if not ledger then
      return
    end
    local since = P.Since(range, f.now)
    f.summary = ledger:Summary(since, char)
    f.ledger = ledger:Recent(since, nil, char)
    f.profits = ledger:Profits()
    f.customers = ledger:Counterparties("sale", since, char)
    f.suppliers = ledger:Counterparties("buy", since, char)
    local resolve = ns.Trading and ns.Trading.NameResolver and ns.Trading.NameResolver()
    for _, list in ipairs({ f.customers, f.suppliers }) do
      for _, c in ipairs(list) do
        c.favouriteKey = c.favourite and resolve and resolve(c.favourite) or nil
      end
    end
    for _, e in ipairs(ledger.db and ledger.db.entries or {}) do
      if e.counterparty then
        f.namesSeen = true
        break
      end
    end
  end)
  try("auctions", function()
    f.auctions = ns.Trading and ns.Trading:ActiveAuctions(f.holdings) or {}
    P.FillAuctionIDs(f.auctions, P.OwnedAuctions(), UnitName and UnitName("player"))
  end)
  f.positions, f.totals = f.positions or {}, f.totals or {}
  f.listed = f.listed or { count = 0, value = 0 }
  f.summary, f.ledger, f.auctions = f.summary or {}, f.ledger or {}, f.auctions or {}
  return f
end

-- ------------------------------------------------------------------------------------------------ auctions

-- this character's owned auctions as the game lists them now: { { auctionID, key, qty, unit } } (empty away from it)
function P.OwnedAuctions()
  local ah, out = C_AuctionHouse, {}
  if not (ah and ah.GetNumOwnedAuctions and ah.GetOwnedAuctionInfo) then
    return out
  end
  local ok, n = pcall(ah.GetNumOwnedAuctions)
  for i = 1, ok and n or 0 do
    local info = ah.GetOwnedAuctionInfo(i)
    local k = info and info.itemKey
    if k and info.auctionID and (info.status == nil or info.status == 0) then
      local key = ns.ItemKey(k.itemID, k.itemSuffix)
      if info.itemLink and ns.ItemCache and ns.ItemCache.Pair then
        key = ns.ItemCache.Pair(info.itemLink, k.itemID, k.itemSuffix)
      end
      out[#out + 1] = { auctionID = info.auctionID, key = key, qty = info.quantity or 1, unit = info.buyoutAmount or info.bidAmount }
    end
  end
  return out
end

-- Every character's auctions on this market, this character's with their game IDs: all the Auctions screen needs,
-- without Gather's positions and ledger (which cost far more and the screen doesn't show).
--   cancelling: { [auctionID] = true } left out (cancelled, the game's list not caught up yet)
function P.AuctionList(cancelling)
  local all = (ns.Trading and ns.Trading.Holdings and ns.Trading:Holdings()) or (AME_DB and AME_DB.holdings) or {}
  local keep = ns.Holdings and ns.Holdings.Keep and ns.Holdings.Keep("market")
  local holdings = {}
  for key, h in pairs(all) do
    if not keep or keep(key) then
      holdings[key] = h
    end
  end
  local list = ns.Trading and ns.Trading.ActiveAuctions and ns.Trading:ActiveAuctions(holdings) or {}
  P.FillAuctionIDs(list, P.OwnedAuctions(), UnitName and UnitName("player"))
  if not cancelling then
    return list
  end
  local out = {}
  for _, a in ipairs(list) do
    if not (a.auctionID and cancelling[a.auctionID]) then
      out[#out + 1] = a
    end
  end
  return out
end

-- The saved auction list (Trading:ScanAuctions) has no auction IDs: this character's auctions take theirs from the
-- game's owned list, matched by item, quantity and price, each ID used once.
function P.FillAuctionIDs(auctions, owned, me)
  local used = {}
  for _, a in ipairs(auctions or {}) do
    if not a.auctionID and a.char == me then
      for i, o in ipairs(owned or {}) do
        if not used[i] and o.key == a.itemID and o.qty == a.qty and o.unit == a.unit then
          a.auctionID, used[i] = o.auctionID, true
          break
        end
      end
    end
  end
  return auctions
end

-- what's on sale now against one of your auctions (book: AHSearch.results[key], rows cheapest first, yours marked).
-- Not searched yet: the last full scan's lowest (scanMin), as Home counts it - "scanUndercut" | "scanLowest".
function P.Standing(a, book, scanMin)
  if not (book and book.rows) then
    if scanMin and a.unit then
      if scanMin < a.unit then
        return { kind = "scanUndercut", lowest = scanMin, by = a.unit - scanMin }
      end
      return { kind = "scanLowest", lowest = scanMin }
    end
    return { kind = "unchecked" }
  end
  local lowest, other, ahead, units = nil, nil, 0, 0
  for _, r in ipairs(book.rows) do
    lowest = lowest and math.min(lowest, r.price) or r.price
    if not r.mine then
      other = other and math.min(other, r.price) or r.price
      if a.unit and r.price < a.unit then
        ahead, units = ahead + 1, units + (r.qty or 1)
      end
    end
  end
  if not other then
    return { kind = "only" }
  end
  if ahead == 0 then
    return { kind = "lowest", lowest = lowest }
  end
  return { kind = "undercut", lowest = lowest, by = a.unit - other, ahead = ahead, units = units }
end

function P.StandingText(st)
  if st.kind == "lowest" then
    return { text = L["lowest"], color = "good" }
  elseif st.kind == "only" then
    return { text = L["the only one"], color = "good" }
  elseif st.kind == "undercut" then
    return { text = L["undercut by %s · %d ahead"]:format(money(st.by), st.ahead), color = "bad" }
  elseif st.kind == "scanUndercut" then
    return { text = L["undercut by %s at the last scan"]:format(money(st.by)), color = "warn" }
  elseif st.kind == "scanLowest" then
    return { text = L["lowest at the last scan"], color = "dim" }
  end
  return { text = L["not checked"], color = "dim" }
end

P.BANDS = { [0] = L["< 30 min"], [1] = L["< 2 h"], [2] = L["< 12 h"], [3] = L["> 12 h"] }

function P.TimeLeft(a, t)
  if a.timeLeft then
    local left = a.timeLeft - (t - (a.seen or t))
    if left <= 0 then
      return { text = L["ended?"], color = "dim" }
    end
    return left >= 3600 and L["%d h"]:format(left / 3600) or L["%d min"]:format(math.max(1, left / 60))
  end
  return a.timeLeftBand and P.BANDS[a.timeLeftBand] or "—"
end

-- the last full scan's lowest price of an item, at the auction house you're looking at (what Home counts from)
function P.ScanMin()
  local AME = ns.AME
  local idx = AME and AME.FactionIndex and AME:FactionIndex()
  return function(id)
    local s = idx and idx.items and idx.items[id]
    return s and s.min or nil
  end
end

-- your auctions as rows. opts: { me (this character's name), atAH, undercutOnly, char (one character's), now,
-- scanMin (itemID -> the last full scan's lowest: the standing of an item not searched yet) }
-- -> rows, { count, asking, undercut, chars = { names }, checked (newest search) }
function P.AuctionRows(auctions, books, opts)
  opts = opts or {}
  local t = opts.now or now()
  local rows, sum = {}, { count = 0, asking = 0, undercut = 0, chars = {}, checked = nil }
  local seenChar = {}
  for i, a in ipairs(auctions or {}) do
    if a.char and not seenChar[a.char] then
      seenChar[a.char] = true
      sum.chars[#sum.chars + 1] = a.char
    end
    local book = books and books[a.itemID]
    if book and book.at and (not sum.checked or book.at > sum.checked) then
      sum.checked = book.at
    end
    local st = P.Standing(a, book, opts.scanMin and opts.scanMin(a.itemID))
    local under = st.kind == "undercut" or st.kind == "scanUndercut"
    sum.count, sum.asking = sum.count + 1, sum.asking + (a.total or 0)
    if under then
      sum.undercut = sum.undercut + 1
    end
    local mine = opts.me == nil or a.char == opts.me
    if (not opts.undercutOnly or under) and (not opts.char or a.char == opts.char) then
      rows[#rows + 1] = {
        key = a.auctionID and ("a" .. a.auctionID) or ("a" .. i .. ":" .. tostring(a.itemID)),
        item = a.itemID,
        qty = a.qty,
        unit = a.unit,
        lowest = st.lowest,
        standing = P.StandingText(st),
        left = P.TimeLeft(a, t),
        char = a.char or "",
        cancel = (mine and opts.atAH and a.auctionID) and L["Cancel"] or false,
        faded = not mine or nil,
        auctionID = a.auctionID,
        st = st,
        a = a,
      }
    end
  end
  table.sort(sum.chars)
  return rows, sum
end

-- your latest post of an item (AME_DB.listings, Posting:Record), at this unit price when given
function P.LastPost(key, unit)
  local list = AME_DB and AME_DB.listings or {}
  for i = #list, 1, -1 do
    local l = list[i]
    if l.itemID == key and (not unit or l.unit == unit) then
      return l
    end
  end
  return nil
end

-- the right panel's cards for one auction row
--   advice: Posting:Suggest for it (repost), hours: how long it'd take to sell at its price (Posting:ChanceAt)
function P.AuctionDetail(row, advice, hours, cut, t)
  local a, st = row.a or {}, row.st or {}
  local d = {}
  local post = P.LastPost(a.itemID, a.unit)
  local ago = post and ns.Widgets and ns.Widgets.Age(post.t, t or now())
  d.posted = ago and L["Posted %s ago at %s each"]:format(ago, money(a.unit)) or L["Asking %s each"]:format(money(a.unit))
  if st.kind == "undercut" then
    d.title = L["Undercut"]
    d.rows = {
      { label = L["Your price"], copper = a.unit },
      { label = L["Lowest now"], copper = st.lowest },
      { label = L["Ahead of you"], text = L["%d listings · %s units"]:format(st.ahead, count(st.units)) },
    }
  elseif st.lowest then
    -- a price to show (lowest, or the last scan's until it's searched): as money, as the table's Lowest now column;
    -- the standing's words ("undercut by 8s 9c at the last scan") are too long for the card's value
    d.title = st.kind == "scanUndercut" and L["Undercut"] or L["Standing"]
    d.rows = {
      { label = L["Your price"], copper = a.unit },
      { label = L["Lowest now"], copper = st.lowest },
    }
  else
    d.title = L["Standing"]
    d.rows = {
      { label = L["Your price"], copper = a.unit },
      { label = L["Lowest now"], text = P.StandingText(st).text, tone = P.StandingText(st).color },
    }
  end
  if st.kind ~= "unchecked" then
    d.note = hours and L["At your price it would take about %s to sell."]:format(ns.Widgets and ns.Widgets.Hours(hours) or hours)
      or L["At your price it may not sell within a week."]
  else
    d.note = L["Check prices searches what's on sale now."]
  end
  local n = advice and advice.normal
  if n and n.price then
    local qty = a.qty or 1
    d.repost = {
      {
        label = n.hours and L["Normal · sells in %s"]:format(ns.Widgets and ns.Widgets.Hours(n.hours) or n.hours) or L["Normal"],
        copper = n.price,
        big = true,
      },
      { label = L["New deposit"], copper = advice.deposit or 0 },
      { label = L["You net for %s, after the cut"]:format(count(qty)), copper = math.floor(n.price * qty * (1 - (cut or 0.05)) + 0.5) },
    }
  end
  return d
end

-- ------------------------------------------------------------------------------------------------ sell

P.TIP = {
  sell = { text = L["Sell"] },
  craft = { text = L["Craft"], color = "warn" },
  disenchant = { text = L["DE"], color = "disenchant" },
  vendor = { text = L["Vendor"], color = "vendor" },
}

-- an entry's tip: "sell" | "craft" | "disenchant" | "vendor" | nil (AHSelling.Tip; "auction" is Sell here)
function P.TipOf(e)
  local tip = ns.AHSelling and ns.AHSelling.Tip(e) or nil
  return tip == "auction" and "sell" or tip
end

-- Sell first, then Craft, DE, Vendor; the most worth first in each (AHSelling.TipOrder)
function P.SortBags(entries)
  for _, e in ipairs(entries) do
    e.tip = ns.AHSelling.TipOrder(e)
  end
  table.sort(entries, function(a, b)
    if a.tip ~= b.tip then
      return a.tip < b.tip
    end
    return tostring(a.key) < tostring(b.key)
  end)
  return entries
end

function P.BagRows(entries)
  local out = {}
  for i, e in ipairs(entries or {}) do
    local tip = P.TipOf(e)
    out[i] = {
      key = tostring(e.key),
      item = e.key,
      qty = e.qty,
      tip = P.TIP[tip] or "",
      worth = (e.worth or 0) > 0 and e.worth or nil,
      faded = tip == "vendor" or nil,
    }
  end
  return out
end

function P.Find(entries, key)
  for i, e in ipairs(entries or {}) do
    if tostring(e.key) == tostring(key) then
      return e, i
    end
  end
  return nil
end

-- the next row tipped Sell after key (not skipped), wrapping round; nil when there's none
function P.NextSell(entries, key, skipped)
  local _, at = P.Find(entries, key)
  at = at or 0
  local n = #(entries or {})
  for step = 1, n do
    local e = entries[(at + step - 1) % n + 1]
    if tostring(e.key) ~= tostring(key) and P.TipOf(e) == "sell" and not (skipped and skipped[tostring(e.key)]) then
      return e
    end
  end
  return nil
end

-- the first row to post: the first Sell row, else the first row
function P.FirstPick(entries, skipped)
  for _, e in ipairs(entries or {}) do
    if P.TipOf(e) == "sell" and not (skipped and skipped[tostring(e.key)]) then
      return e
    end
  end
  return entries and entries[1]
end

P.PICKS = { "quick", "normal", "patient", "market" }
P.PICK_LABEL = { quick = L["Quick"], normal = L["Normal"], patient = L["Patient"], market = L["Market"] }

-- the price ladder (priceladder props.picks) from Posting:Suggest's advice, and the pick key of each line.
-- Quick no cheaper than Normal is left out; Market stands apart (the item's market price as it is).
function P.Ladder(advice, picked, dense)
  local picks, keys = {}, {}
  for _, key in ipairs(P.PICKS) do
    local c = advice and advice[key]
    if not (key == "quick" and advice and advice.quickSame) and c and c.price then
      local whenText
      if key == "market" then
        whenText = L["the market price"]
      elseif c.hours then
        local h = ns.Widgets and ns.Widgets.Hours(c.hours) or tostring(c.hours)
        whenText = dense and h or L["sells in %s"]:format(h)
      else
        whenText = L["may not sell"]
      end
      picks[#picks + 1] = {
        label = P.PICK_LABEL[key],
        when = whenText,
        price = c.price,
        selected = picked == key or nil,
        apart = key == "market" or nil,
      }
      keys[#keys + 1] = key
    end
  end
  return picks, keys
end

-- what you net: the price times the units, less the cut
function P.Net(price, qty, cut)
  if not price then
    return nil
  end
  return math.floor(price * (qty or 1) * (1 - (cut or 0.05)) + 0.5)
end

-- what's on sale now for the item being posted (AHSearch book), as rows
function P.SaleRows(book, t)
  local out = {}
  for i, r in ipairs(book and book.rows or {}) do
    local left = ns.AHSearch and ns.AHSearch.TimeLeft and ns.AHSearch.TimeLeft(book, r, t or now())
    local text
    if left then
      text = left >= 3600 and L["%d h"]:format(left / 3600) or L["%d min"]:format(math.max(1, left / 60))
    else
      text = r.band and P.BANDS[r.band] or ""
    end
    out[i] = {
      key = "s" .. i,
      price = r.price,
      qty = r.qty,
      left = { text = text, color = "dim" },
      mine = r.mine and { text = L["yours"], color = "gold" } or "",
      row = r,
    }
  end
  return out
end

-- a listing clicked: just under it (yours: the same price)
function P.Under(row)
  if not row then
    return nil
  end
  return row.mine and row.price or math.max(1, row.price - 1)
end

-- in game: your bags at the auction house, valued and ranked as the Selling tab does (AHSelling's rules), each with
-- what a recipe of yours would make of it. Kept in P.bags for the post button.
function P.SellEntries()
  local S, AME = ns.AHSelling, ns.AME
  if not (S and AME) then
    return {}
  end
  local index = AME:FactionIndex()
  local items = index and index.items or {}
  local watch = AME.watch
  local shown = {}
  for _, e in ipairs(S.ScanBags()) do
    if not (watch and watch:IsHidden(e.key)) then
      shown[#shown + 1] = e
    end
  end
  local q = index and ns.Quote.For(AME:FactionShard(), index, { house = AME:CurrentHouse(), fresh = false })
  local list = S.Rank(shown, function(k)
    return items[k]
  end, function(k)
    if not q then
      return nil
    end
    return q:BestSale(k)
  end)
  for _, e in ipairs(list) do
    if e.signal == "vendor" and ns.CraftModel and ns.CraftModel.Instead then
      local ok, c = pcall(ns.CraftModel.Instead, e.key)
      e.craft = ok and c or nil
    end
  end
  P.bags, P.quote = P.SortBags(list), q
  return P.bags
end

-- the cut where you post (the auction house you're at)
function P.Cut()
  local AME = ns.AME
  return ns.Quote.Cut(AME and AME.CurrentHouse and AME:CurrentHouse() or "Horde")
end

-- AME's prices for the item, quantity and listing time
function P.Suggest(key, qty, duration)
  if not (ns.Posting and ns.AME) then
    return nil
  end
  local hours = ns.Posting.DurationHours(duration)
  local ok, advice = pcall(ns.Posting.Suggest, ns.Posting, ns.AME:CurrentShard(), key, qty or 1, hours)
  return ok and advice or nil
end

-- the deposit the game asks (AHSelling's Deposit, nil when it can't say)
function P.Deposit(e, qty, duration)
  if not (e and ns.AHSelling) then
    return nil
  end
  local ok, d = pcall(ns.AHSelling.Deposit, { entry = e, qty = qty, duration = duration })
  return ok and d or nil
end

-- the listing times: { { index, "12 h" }, ... }
function P.Durations()
  local out = {}
  for i = 1, 3 do
    out[i] = { tostring(i), L["%d h"]:format(ns.Posting and ns.Posting.DurationHours(i) or ({ 12, 24, 48 })[i]) }
  end
  return out
end

function P.DefaultDuration()
  local want = ns.Settings and ns.Settings:Get("listingHours")
  for i = 1, 3 do
    if ns.Posting and ns.Posting.DurationHours(i) == want then
      return i
    end
  end
  return 2
end

-- Post: the game's own posting, a stackable all at once, gear one at a time (as the Selling tab posts). Run it from
-- the button's click: the game wants a key press or click for each post.
--   payload = { key, price, qty, duration } -> ok, message
function P.Post(payload)
  local a = C_AuctionHouse
  local e = P.Find(P.bags, payload and payload.key)
  local price, qty = payload and payload.price, payload and payload.qty or 1
  if not (e and a and price and price > 0 and qty > 0 and e.locs and e.locs[1]) then
    return false, L["Nothing to post"]
  end
  local loc, ok, err = e.locs[1], nil, nil
  local n = e.commodity and math.min(qty, e.qty) or 1
  if e.commodity then
    ok, err = pcall(a.PostCommodity, loc, payload.duration or 2, n, price)
  else
    ok, err = pcall(a.PostItem, loc, payload.duration or 2, 1, nil, price)
  end
  if ok then
    return true, L["Posted %s at %s each"]:format(count(n), money(price))
  end
  return false, L["The game didn't take the post: %s"]:format(tostring(err))
end

-- Cancel one of your auctions (C_AuctionHouse.CancelAuction; AME's hook counts it). From the button's click.
function P.Cancel(payload)
  local a = C_AuctionHouse
  local id = payload and payload.auctionID
  if not (a and a.CancelAuction and id) then
    return false, L["Nothing to cancel"]
  end
  local ok, err = pcall(a.CancelAuction, id)
  if ok then
    return true, L["Cancelled: it comes back by mail"]
  end
  return false, tostring(err)
end

-- ------------------------------------------------------------------------------------------------ the tip cards

local function sellPrice(key)
  local info = ns.ItemCache and ns.ItemCache.Get and ns.ItemCache.Get(key)
  return info and info.sellPrice or 0
end

-- a row tipped Craft: what a recipe of yours makes of it, against selling it as it is
--   -> { sub, rows (keyvalue props), crafts, recipe, left }
function P.CraftCard(e)
  local c = e.craft or {}
  local r = c.recipe or {}
  local need = 1
  for _, g in ipairs(r.reagents or {}) do
    if g[1] == e.key or g[1] == (ns.BaseID and ns.BaseID(e.key)) then
      need = g[2] or 1
    end
  end
  local crafts = math.floor((e.qty or 0) / need)
  local used, left = crafts * need, (e.qty or 0) - crafts * need
  local raw, each = c.raw or 0, c.each or 0
  local out = { crafts = crafts, recipe = r.id, left = left }
  local recipeName = r.id and ns.Crafters and ns.Crafters.RecipeName and ns.Crafters.RecipeName(r.id)
  local s = e.summary
  out.sub = (s and s.market and L["market %s each"]:format(money(s.market)) or "")
    .. (c.crafter and recipeName and (" · " .. L["%s knows %s"]:format(c.crafter, recipeName)) or "")
  out.rows = {
    { item = e.key, count = e.qty, label = L["sold as it is"], copper = math.floor(raw * (e.qty or 0) + 0.5) },
    { item = c.product, count = crafts * (r.made or 1), label = L["sold"], copper = math.floor(each * used + 0.5) },
    { label = L["Crafting first nets"], copper = math.floor((each - raw) * used + 0.5), signed = true },
  }
  if left > 0 then
    out.rows[#out.rows + 1] = { label = L["%d left over"]:format(left), text = L["stays in your bags"], tone = "dim" }
  end
  return out
end

-- a row tipped DE: what disenchanting it gives on average, against selling it as it is and at a vendor
function P.DECard(e, q)
  local s = e.summary
  local spd = s and s.soldPerDay
  local out = {}
  if spd and spd > 0 and spd < 1 then
    out.sub = L["sells about once in %d days"]:format(math.floor(1 / spd + 0.5))
  elseif spd and spd >= 1 then
    out.sub = L["~%s sells/day"]:format(count(spd))
  else
    out.sub = L["hardly sells"]
  end
  local asIs = q and q.ListingNet and q:ListingNet(e.key)
  local de = q and q.Disenchant and q:Disenchant(e.key)
  out.rows = {
    { label = L["Sold as it is"], copper = asIs and math.floor(asIs + 0.5) or nil, text = not asIs and "—" or nil },
    { label = L["At a vendor"], copper = sellPrice(e.key) },
    { label = L["Disenchanted, on average"], copper = de and de.value and math.floor(de.value + 0.5) or nil, text = not (de and de.value) and "—" or nil },
  }
  for i, o in ipairs(de and de.outcomes or {}) do
    if i > 2 then
      break
    end
    out.rows[#out.rows + 1] = {
      item = o.item,
      count = o.min == o.max and tostring(o.min) or (o.min .. "–" .. o.max),
      label = i == 1 and L["most often"] or "",
      text = ("%d%%"):format(math.floor((o.chance or 0) * 100 + 0.5)),
      tone = "dim",
    }
  end
  return out
end

-- a row tipped Vendor: what a vendor pays against what the auction house would, after the cut and the deposit
function P.VendorCard(e, deposit, cut)
  local s = e.summary
  local qty = e.qty or 1
  local here = s and s.market and P.Net(s.market, qty, cut) or 0
  local vendor = sellPrice(e.key) * qty
  return {
    sub = (s and s.market and L["market %s each"]:format(money(s.market)) or "")
      .. (s and s.qty and (" · " .. L["%s on sale"]:format(count(s.qty))) or ""),
    rows = {
      { label = L["Sold here, after the cut"], copper = here },
      { label = L["Deposit lost if it does not sell"], copper = deposit or 0 },
      { label = L["At a vendor"], copper = vendor },
      { label = L["The vendor pays more by"], copper = vendor - here, signed = true },
    },
  }
end
