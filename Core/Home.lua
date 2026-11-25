-- Home: what to do now, and what's worth doing today (the redesign's first screen, docs/ux boards Home, HomeAH,
-- HomeFirstRun). Pure functions turn gathered facts into rows; Home.Gather reads them from the rest of AME.
--
--   Home.Gather() -> facts                          (game state; cached for a little while)
--   Home.State(facts, atAH) -> "first" | "ah" | "away"
--   Home.Kpis(facts) -> { kpi props, ... }          net worth, on the AH, profit 7 days, the market
--   Home.Todo(facts, atAH) -> rows                  alerts, cooldowns, requests, undercut auctions, bags to post
--   Home.Worth(facts, atAH) -> rows                 the best craft, buy, refine, carry and recipe to learn
--   Home.Steps(facts) -> rows                       the first run: scan, open your professions, visit your bank
-- A row is an action list row (Core/UI/Parts/Composites.lua): { key, pill, tone, title, sub, value, button, action,
-- off, primary, selected }. Its key says what the row is about ("alert:<itemID>", "craft:<recipeID>", ...).
local _, ns = ...
local L = ns.L

local Home = { CACHE = 30, errors = {} } -- errors: what the last gather caught (a piece that failed is left out)
ns.Home = Home

local DAY = 86400

local function g(copper)
  return ns.Widgets and ns.Widgets.Money(copper, true) or tostring(copper)
end

local function signed(copper)
  return ns.Widgets and ns.Widgets.SignedMoney(copper) or tostring(copper)
end

local function pct(x)
  return ("%+.1f%%"):format((x or 0) * 100)
end

-- ------------------------------------------------------------------------------------------------ state

-- the first run: no prices yet for this market (not even from your guild)
function Home.State(f, atAH)
  if not f.hasPrices then
    return "first"
  end
  return atAH and "ah" or "away"
end

-- ------------------------------------------------------------------------------------------------ kpis

function Home.Kpis(f)
  if not f.hasPrices then
    return {
      { label = L["Net worth"], note = L["after the first scan"] },
      { label = L["On the auction house"], note = L["after your first visit"] },
      { label = L["Profit, 7 days"], note = L["counted from today"] },
      { label = L["Market"], note = L["no prices yet"] },
    }
  end
  local out = {}
  local worth = (f.gold or 0) + (f.itemsValue or 0)
  local k = { label = L["Net worth"], copper = worth, note = L["gold and what you hold"] }
  if f.worthWeekAgo and f.worthWeekAgo > 0 then
    local change = worth / f.worthWeekAgo - 1
    k.delta, k.deltaTone, k.note = pct(change), change >= 0 and "good" or "bad", L["this week"]
  end
  out[1] = k
  local listed = f.listed or {}
  local ah = { label = L["On the auction house"], copper = listed.value or 0 }
  ah.note = L["%d auctions"]:format(listed.count or 0)
  if (f.undercut or 0) > 0 then
    ah.delta, ah.deltaTone = L["%d undercut"]:format(f.undercut), "bad"
  end
  out[2] = ah
  local led = f.ledger or {}
  out[3] = {
    label = L["Profit, 7 days"],
    copper = led.profit or 0,
    signed = true,
    note = L["%d sales · %d purchases"]:format(led.sales or 0, led.buys or 0),
  }
  if f.marketChange then
    out[4] = {
      label = L["Market"],
      value = ns.Widgets.Percent(f.marketChange), -- green / red
      note = (f.marketChange >= 0 and L["dearer this week"] or L["cheaper this week"]),
    }
  else
    if f.marketLevel then -- not a week of scans yet: the price index, the change when a week is in
      out[4] = { label = L["Market"], value = ("%.1f"):format(f.marketLevel), note = L["price index · the week's change after 7 days of scans"] }
    else
      out[4] = { label = L["Market"], note = L["builds as full scans come in"] }
    end
  end
  return out
end

-- ------------------------------------------------------------------------------------------------ to do now

local function item(id, count)
  return { item = id, count = count }
end

-- what needs the auction house keeps its place away from it, with a greyed button naming where it works
local function ahRow(row, atAH, button, action)
  if atAH then
    row.button, row.action = button, action
  else
    row.button, row.off = L["At the AH"], true
  end
  return row
end

function Home.Todo(f, atAH)
  local now, rows = f.now or 0, {}
  local alerts, cooldowns, requests, ahRows = {}, {}, {}, {}
  for _, a in ipairs(f.alerts or {}) do
    alerts[#alerts + 1] = {
      key = "alert:" .. a.itemID,
      pill = L["ALERT"],
      tone = "warn",
      title = { item(a.itemID), " " .. (a.text or "") },
      sub = a.ago and L["%s ago"]:format(a.ago) or nil,
      button = L["Open"],
      action = "openItem",
    }
  end
  for _, c in ipairs(f.cooldowns or {}) do
    local sub = c.product and { { item = c.product }, " " } or {}
    if c.profit then
      sub[#sub + 1] = L["makes %s today"]:format(signed(c.profit))
    end
    cooldowns[#cooldowns + 1] = {
      key = "cooldown:" .. c.recipe .. ":" .. tostring(c.char),
      pill = L["COOLDOWN"],
      tone = "good",
      title = L["%s is ready on %s"]:format(c.name or "?", c.char or "?"),
      sub = #sub > 0 and sub or nil,
      button = L["Queue"],
      action = "queue",
    }
  end
  for _, r in ipairs(f.requests or {}) do
    requests[#requests + 1] = {
      key = "request:" .. r.id,
      pill = L["REQUEST"],
      tone = "link",
      title = { L["%s asks for %d "]:format(r.from, r.count), item(r.item) },
      sub = r.sub,
      button = L["Answer"],
      action = "openRequest",
    }
  end
  if (f.undercut or 0) > 0 then
    local first = f.undercutFirst
    ahRows[#ahRows + 1] = ahRow({
      key = "auctions",
      pill = L["AUCTIONS"],
      tone = "bad",
      title = L["%d of your auctions are undercut"]:format(f.undercut),
      sub = first and { item(first), f.undercut > 1 and L[" and %d more"]:format(f.undercut - 1) or "" } or nil,
    }, atAH, L["Review"], "goAuctions")
  end
  local bags = f.bags
  if bags and (bags.value or 0) > 0 then
    local sub = { L["%d items · "]:format(bags.count or 0) }
    if bags.first then
      sub[#sub + 1] = item(bags.first, bags.firstQty and ("×" .. bags.firstQty) or nil)
      sub[#sub + 1] = L[" first"]
    end
    ahRows[#ahRows + 1] = ahRow({
      key = "bags",
      pill = L["BAGS"],
      tone = "gold",
      title = L["%s in your bags is worth posting"]:format(g(bags.value)),
      sub = sub,
    }, atAH, L["Sell"], "goSell")
  end
  -- at the auction house what you came to do there leads; away from it, what you can act on anywhere comes first
  local order = atAH and { ahRows, alerts, cooldowns, requests } or { alerts, cooldowns, requests, ahRows }
  for _, list in ipairs(order) do
    for _, r in ipairs(list) do
      rows[#rows + 1] = r
    end
  end
  if rows[1] then
    rows[1].selected = true
    rows[1].primary = not rows[1].off or nil
  end
  local _ = now
  return rows
end

-- ------------------------------------------------------------------------------------------------ worth doing

function Home.Worth(f, atAH)
  local rows = {}
  local c = f.bestCraft
  if c then
    rows[#rows + 1] = {
      key = "craft:" .. c.recipe,
      pill = L["CRAFT"],
      title = { item(c.product or c.recipe) },
      sub = c.sub,
      value = L["%s each"]:format(signed(c.profit)),
      valueTone = "good",
      button = L["Queue"],
      action = "queue",
    }
  end
  local b = f.bestBuy
  if b then
    rows[#rows + 1] = {
      key = "buy:" .. b.item,
      pill = L["BUY"],
      title = { item(b.item) },
      sub = b.sub,
      value = L["%d%% under usual"]:format(math.floor(b.under * 100 + 0.5)),
      valueTone = "good",
      button = L["Open"],
      action = "openItem",
    }
  end
  local r = f.bestRefine
  if r then
    rows[#rows + 1] = {
      key = "refine:" .. r.item .. ":" .. r.recipe,
      pill = L["REFINE"],
      title = { item(r.item), L[" into "], item(r.product) },
      sub = L["You hold %d"]:format(r.qty or 0),
      value = signed(r.gain),
      valueTone = "good",
      button = L["Queue"],
      action = "queue",
    }
  end
  local a = f.bestCarry
  if a then
    rows[#rows + 1] = {
      key = "carry:" .. a.item,
      pill = L["CARRY"],
      title = { item(a.item), L[" to the %s"]:format(a.to) },
      sub = a.sub,
      value = signed(a.profit),
      valueTone = "good",
      button = L["Open"],
      action = "goArbitrage",
    }
  end
  local l = f.bestLearn
  if l then
    rows[#rows + 1] = {
      key = "learn:" .. l.item,
      pill = L["LEARN"],
      title = { item(l.item) },
      sub = l.sub,
      value = l.payback and (math.ceil(l.payback) <= 1 and L["1 day to pay back"] or L["%d days to pay back"]:format(math.ceil(l.payback))) or nil,
      valueTone = "good",
      button = L["Open"],
      action = "goLearn",
    }
  end
  local _ = atAH
  return rows
end

-- ------------------------------------------------------------------------------------------------ first run

function Home.Steps(f)
  local read, notYet = {}, {}
  for _, p in ipairs(f.professions or {}) do
    if p.read then
      read[#read + 1] = p.name
    else
      notYet[#notYet + 1] = p.name
    end
  end
  local profSub = { L["AME reads your recipes"] }
  if #read > 0 then
    profSub[#profSub + 1] = " · "
    profSub[#profSub + 1] = { text = L["%s read"]:format(table.concat(read, ", ")), tone = "good" }
  end
  if #notYet > 0 then
    profSub[#profSub + 1] = " · " .. L["%s not yet"]:format(table.concat(notYet, ", "))
  end
  local rows = {
    {
      key = "step:scan",
      pill = "1",
      tone = f.hasPrices and "good" or "warn",
      title = L["Scan the auction house"],
      sub = L["Press Full scan at any auction house · about a minute"],
      button = L["At the AH"],
      off = true,
    },
    {
      key = "step:professions",
      pill = "2",
      tone = #notYet == 0 and #read > 0 and "good" or nil,
      title = L["Open each of your professions once"],
      sub = profSub,
      button = L["Open"],
      action = "goCrafting",
    },
    {
      key = "step:bank",
      pill = "3",
      tone = f.bankSeen and "good" or nil,
      title = L["Visit your bank"],
      sub = L["So Portfolio counts what you hold there"],
      button = L["At a bank"],
      off = true,
    },
  }
  if (f.guildSharers or 0) > 0 then
    rows[#rows + 1] = {
      key = "step:guild",
      pill = L["GUILD"],
      tone = "good",
      title = L["%d guildmates share prices with AME"]:format(f.guildSharers),
      sub = L["Theirs arrive on their own and stand in for step 1"],
      button = L["Sharing"],
      action = "goSharing",
    }
  end
  rows[1].selected = true
  return rows
end

function Home.Know()
  return {
    {
      key = "know:ah",
      pill = L["AH"],
      title = L["AME's window opens at the auction house"],
      sub = L["\"Use the game's AH\" in the title bar swaps back"],
      button = L["Settings"],
      action = "goSettings",
    },
    {
      key = "know:craft",
      pill = L["CRAFT"],
      title = L["The same goes for your professions"],
      sub = L["Or keep the game's window, with AME beside it"],
      button = L["Settings"],
      action = "goSettings",
    },
    {
      key = "know:tips",
      pill = L["TIPS"],
      title = L["Tooltips show an item's price and what to do with it"],
      sub = L["Sell, Craft, DE or Vendor · hold Shift for more"],
    },
    {
      key = "know:guide",
      pill = L["GUIDE"],
      title = L["Every screen is explained in the Guide"],
      sub = L["Start with \"Your first scan\""],
      button = L["Guide"],
      action = "goGuide",
    },
  }
end

-- ------------------------------------------------------------------------------------------------ gather

-- the week's net worth: today's value is kept per day, and last week's read back
function Home.WeekAgo(log, today, value)
  log[today] = value
  for day in pairs(log) do
    if day < today - 40 then
      log[day] = nil
    end
  end
  for back = 7, 10 do
    if log[today - back] then
      return log[today - back]
    end
  end
  return nil
end

local function try(fn, ...)
  local ok, a, b = pcall(fn, ...)
  if ok then
    return a, b
  end
  Home.errors[#Home.errors + 1] = tostring(a)
  if ns.Dev and ns.Dev.Warn then
    ns.Dev.Warn("Home: " .. tostring(a))
  end
end

local function gatherMoney(f, holdings, keep)
  local gold = 0
  for key, h in pairs(holdings) do
    if keep(key) and type(h.money) == "number" then
      gold = gold + h.money
    end
  end
  f.gold = gold
end

local function gatherAlerts(f, now)
  local notices = ns.AME.notices
  if not notices then
    return
  end
  local out, seen = {}, {}
  for _, e in ipairs(notices:List()) do
    if e.kind == "alert" and e.itemID and not seen[e.itemID] and now - (e.at or 0) < DAY then
      seen[e.itemID] = true
      local mins = math.floor((now - e.at) / 60)
      out[#out + 1] = {
        itemID = e.itemID,
        text = e.text,
        ago = mins < 60 and L["%d min"]:format(math.max(1, mins)) or L["%d h"]:format(math.floor(mins / 60)),
      }
    end
  end
  f.alerts = out
end

local function gatherCooldowns(f, now, craft)
  local out = {}
  for key, c in pairs(ns.Professions and ns.Professions:Characters() or {}) do
    for _, p in pairs(c.professions or {}) do
      for recipeID, readyAt in pairs(p.cooldowns or {}) do
        if readyAt <= now then
          local r = ns.Recipes.Get(recipeID)
          local e = craft and r and craft:Evaluate(r, {})
          out[#out + 1] = {
            recipe = recipeID,
            char = tostring(key):match(":(.+)$") or key,
            name = ns.Crafters and ns.Crafters.RecipeName and ns.Crafters.RecipeName(recipeID) or tostring(recipeID),
            product = r and r.product,
            profit = e and e.profit,
          }
        end
      end
    end
  end
  table.sort(out, function(a, b)
    return (a.profit or 0) > (b.profit or 0)
  end)
  f.cooldowns = out
end

local function gatherBags(f, holdings, index, q)
  local me = ns.Trading.CharKey()
  local bags = holdings[me] and holdings[me].bags or {}
  local count, value, first, firstQty, best = 0, 0, nil, nil, 0
  for key, qty in pairs(bags) do
    local net, where = q:BestSale(key)
    local s = index.items[ns.BaseID and ns.BaseID(key) or key]
    if where == "ah" and net and net > 0 and s and s.signal ~= "vendor" then
      local worth = net * qty
      count, value = count + 1, value + worth
      if worth > best then
        best, first, firstQty = worth, key, qty
      end
    end
  end
  f.bags = { count = count, value = value, first = first, firstQty = firstQty }
end

local function gatherAuctions(f, holdings, index, keep)
  local filtered = {}
  for key, h in pairs(holdings) do
    if keep(key) then
      filtered[key] = h
    end
  end
  f.listed = ns.Portfolio.Listed(filtered, ns.Quote.Cut, index.items)
  local undercut, first = 0, nil
  for _, a in ipairs(ns.Trading:ActiveAuctions(filtered)) do
    local s = index.items[a.itemID]
    if s and s.min and a.unit and s.min < a.unit then
      undercut = undercut + 1
      first = first or a.itemID
    end
  end
  f.undercut, f.undercutFirst = undercut, first
end

local function gatherWorth(f, holdings, index, q, keep)
  local held = ns.Holdings.Of("owned", "market")
  local hide = ns.AME.watch and ns.AME.watch.Hidden and ns.AME.watch:Hidden() or nil
  local basis = ns.AME.ledger and ns.AME.ledger:CostBasis() or {}
  local _, totals = ns.Portfolio.Build(held, basis, index.items, hide, function(id)
    return q:Worth(id)
  end)
  f.itemsValue = totals and totals.value or 0
  AME_DB.worthLog = AME_DB.worthLog or {}
  f.worthWeekAgo = Home.WeekAgo(AME_DB.worthLog, ns.Today(f.now), (f.gold or 0) + f.itemsValue)
  local _ = holdings
  local __ = keep
end

-- the stack you hold that gains most from refining: { item, qty, recipe = recipeID, product, gain } or nil.
-- m: CraftModel.Build's model (held, uses, craft). SellOrRefine's options carry the recipe itself, not its id.
function Home.BestRefine(m)
  local best
  for id, n in pairs(m.held or {}) do
    local recipes = m.uses and m.uses[id]
    if recipes and n > 0 then
      local r = m.craft:SellOrRefine(id, n, recipes)
      local o = r and r.best
      if o and o.gain and o.gain > 0 and (not best or o.gain > best.gain) then
        local rec = type(o.recipe) == "table" and o.recipe or ns.Recipes.Get(o.recipe)
        if rec and rec.id then
          best = { item = id, qty = n, recipe = rec.id, product = rec.product, gain = o.gain }
        end
      end
    end
  end
  return best
end

local function gatherCrafting(f, index)
  local m = ns.CraftModel and ns.CraftModel.Build()
  if not m then
    return nil
  end
  local top = m.craft:TopEarners(m.entries, m.heldSet)
  for _, e in ipairs(top) do
    if e.eval and (e.eval.profit or 0) > 0 then
      local char = e.crafters and e.crafters[1]
      f.bestCraft = {
        recipe = e.recipe.id,
        product = e.recipe.product,
        profit = e.eval.profit,
        sub = char and L["%s · sells about %s"]:format(tostring(char):match(":(.+)$") or char, ns.Widgets.Rate(e.eval.sellRate)) or nil,
      }
      break
    end
  end
  f.bestRefine = Home.BestRefine(m)
  -- a recipe on the auction house one of your characters could learn
  if ns.CraftingData and ns.CraftingData.Teaches then
    local listings = {}
    for id, s in pairs(index.items) do
      if ns.CraftingData:Teaches(id) and s.min and (s.qty or 0) > 0 and (not index.day or not s.day or index.day - s.day <= 2) then
        listings[#listings + 1] = { item = id, price = s.min }
      end
    end
    local rows = m.craft:RecipesToBuy(listings, function(id)
      return ns.CraftingData:Teaches(id)
    end, ns.Recipes.Get, m.chars)
    for _, r in ipairs(rows or {}) do
      if r.ready and r.payback then
        local who = r.learners and r.learners[1]
        f.bestLearn = {
          item = r.item,
          payback = r.payback,
          sub = who and L["%s can learn it"]:format(tostring(who.char):match(":(.+)$") or who.char) or nil,
        }
        break
      end
    end
  end
  return m
end

local function gatherBuy(f, index)
  local watch = ns.AME.watch
  if not watch then
    return
  end
  local best
  for _, list in ipairs(watch:Lists() or {}) do
    for id in pairs(list.items or {}) do
      local s = index.items[id]
      local usual = s and (s.avg30 or s.avg7)
      if s and s.market and usual and usual > 0 then
        local under = 1 - s.market / usual
        if under >= 0.1 and (not best or under > best.under) then
          best = { item = id, under = under, sub = L["On your watchlist · %s sell a day"]:format(ns.Widgets.Rate(s.soldPerDay or s.sellRate)) }
        end
      end
    end
  end
  f.bestBuy = best
end

local function gatherCarry(f, index, AME)
  local realm = AME:MarketRealmName()
  local here = AME:CurrentHouse()
  local best
  for _, house in ipairs({ "Horde", "Alliance", "Neutral" }) do
    if house ~= here then
      local other = AME:CachedIndex(ns.ShardKey(realm, house))
      if other then
        local rows = ns.Arbitrage.Find(index, other, {
          cut = ns.Quote.Cut(house),
          today = ns.Today(GetServerTime()),
          minProfit = 1,
        })
        local r = rows and rows[1]
        if r and r.profit and (not best or r.profit > best.profit) then
          best = { item = r.itemID, profit = r.profit, to = ns.ShardLabel and ns.ShardLabel(ns.ShardKey(realm, house)) or house }
        end
      end
    end
  end
  f.bestCarry = best
end

local cache
function Home.Gather(force)
  local now = GetServerTime()
  if not force and cache and now - cache.at < Home.CACHE then
    return cache.facts
  end
  local AME = ns.AME
  local f = { now = now }
  Home.errors = {}
  local index = AME and AME.FactionIndex and AME:FactionIndex()
  f.hasPrices = index ~= nil or (AME and AME.HasData and AME:HasData(AME:FactionShard())) or false
  local holdings = ns.Trading and ns.Trading:Holdings() or {}
  local keep = ns.Holdings.Keep("market") or function()
    return true
  end
  try(gatherMoney, f, holdings, keep)
  try(gatherAlerts, f, now)
  f.professions = {}
  for _, c in pairs(ns.Professions and ns.Professions:Characters() or {}) do
    for _, p in pairs(c.professions or {}) do
      f.professions[#f.professions + 1] = { name = p.name or "?", read = p.learned and next(p.learned) ~= nil }
    end
  end
  f.bankSeen = false
  for key, h in pairs(holdings) do
    if keep(key) and h.bank then
      f.bankSeen = true
    end
  end
  if index then
    local q = ns.Quote.For(AME:FactionShard(), index, { fresh = false })
    try(gatherAuctions, f, holdings, index, keep)
    try(gatherBags, f, holdings, index, q)
    try(gatherWorth, f, holdings, index, q, keep)
    if ns.Trading.ResolveLedger then
      try(ns.Trading.ResolveLedger, ns.Trading)
    end
    f.ledger = AME.ledger and AME.ledger:Summary(now - 7 * DAY) or nil
    if ns.MarketStats and index.stats then
      local s = try(ns.MarketStats.Summary, index, 7)
      f.marketChange = s and s.levelChange
      f.marketLevel = s and s.level
    end
    local m = try(gatherCrafting, f, index)
    try(gatherCooldowns, f, now, m and m.craft)
    try(gatherBuy, f, index)
    try(gatherCarry, f, index, AME)
  end
  f.requests = ns.CraftRequests and ns.CraftRequests.Incoming and ns.CraftRequests.Incoming() or {}
  f.guildSharers = ns.SyncService and ns.SyncService.PeerCount and ns.SyncService:PeerCount() or 0
  cache = { at = now, facts = f }
  return f
end

function Home.Forget()
  cache = nil
end
