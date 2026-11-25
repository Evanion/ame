-- Home: what to do now, and what's worth doing today (the redesign's first screen, docs/ux boards Home, HomeAH,
-- HomeFirstRun). Pure functions turn gathered facts into rows; Home.Gather reads them from the rest of AME.
--
--   Home.Gather() -> facts                          (game state; kept until what it's built from changes)
--   Home.Stamp(holdings, keep) -> text              what the facts are built from, as one value (Gather's key)
--   Home.State(facts, atAH) -> "first" | "ah" | "away"
--   Home.Kpis(facts) -> { kpi props, ... }          net worth, on the AH, profit 7 days, the market
--   Home.Todo(facts, atAH) -> rows                  alerts, cooldowns, requests, undercut auctions, bags to post
--   Home.Worth(facts, atAH) -> rows                 the best craft, buy, refine, carry and recipe to learn
--   Home.Steps(facts) -> rows                       the first run: scan, open your professions, visit your bank
-- A row is an action list row (Core/UI/Parts/Composites.lua): { key, pill, tone, title, sub, value, button, action,
-- off, primary, selected }. Its key says what the row is about ("alert:<itemID>", "craft:<recipeID>", ...).
local _, ns = ...
local L = ns.L

local Home = { errors = {} } -- errors: what the last gather caught (a piece that failed is left out)
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

-- Prices are stale when the newest full scan (yours or a guildmate's, by sync) is older than this: Home then asks for a
-- fresh scan before it recommends anything (board HomeStale)
Home.STALE = 3 * 3600

function Home.Stale(f)
  return f.hasPrices and f.scanAge ~= nil and f.scanAge > Home.STALE or false
end

-- "9 h", "2 days": how old the newest full scan is
function Home.Age(seconds)
  local h = math.floor((seconds or 0) / 3600)
  if h < 48 then
    return L["%d h"]:format(math.max(1, h))
  end
  return L["%d days"]:format(math.floor(h / 24))
end

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
  elseif f.marketLevel then -- not a week of scans yet: the price index, the change when a week is in
    out[4] = { label = L["Market"], value = ("%.1f"):format(f.marketLevel), note = L["price index · the week's change after 7 days of scans"] }
  else
    out[4] = { label = L["Market"], note = L["builds as full scans come in"] }
  end
  if Home.Stale(f) then -- how old the prices are, where the market's figure is (board HomeStale)
    out[4].note = L["prices %s old"]:format(Home.Age(f.scanAge))
    out[4].delta, out[4].deltaTone = L["old"], "warn"
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

-- how long ago an alert fired, as of the facts' time (f.now): "12 min ago", "3 h ago"
function Home.Ago(a, now)
  local ago = a.ago
  if a.at and now then
    local mins = math.floor((now - a.at) / 60)
    ago = mins < 60 and L["%d min"]:format(math.max(1, mins)) or L["%d h"]:format(math.floor(mins / 60))
  end
  return ago and L["%s ago"]:format(ago) or nil
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
      sub = Home.Ago(a, now),
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

-- up to three of each kind (Home.PER_KIND), the best first: f.crafts, f.buys, f.refines, f.carries, f.learns (or the
-- single f.bestCraft ... where only one was gathered)
Home.PER_KIND = 3

local function kind(f, many, one)
  local out = {}
  for i, v in ipairs(f[many] or { f[one] }) do
    if i > Home.PER_KIND then
      break
    end
    out[i] = v
  end
  return out
end

function Home.Worth(f, atAH)
  local rows = {}
  for _, c in ipairs(kind(f, "crafts", "bestCraft")) do
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
  for _, b in ipairs(kind(f, "buys", "bestBuy")) do
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
  for _, r in ipairs(kind(f, "refines", "bestRefine")) do
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
  for _, a in ipairs(kind(f, "carries", "bestCarry")) do
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
  for _, l in ipairs(kind(f, "learns", "bestLearn")) do
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

-- ------------------------------------------------------------------------------------------------ the strip

-- Your gold, a point a day over the last `days` (30): every kept character's last figure on or before each day. A
-- character's first figure stands for the days before it (AME hadn't seen them yet), its gold now for today.
-- -> { xs, ys } (x: the day's server time), or nil before two days are in
function Home.GoldLine(holdings, keep, today, days)
  days = days or 30
  local chars, first = {}, nil
  for key, h in pairs(holdings or {}) do
    if keep(key) then
      local log = {}
      for day, copper in pairs(h.goldDays or {}) do
        log[day] = copper
      end
      if type(h.money) == "number" then
        log[today] = h.money
      end
      local earliest
      for day in pairs(log) do
        earliest = math.min(earliest or day, day)
      end
      if earliest then
        chars[#chars + 1] = { log = log, earliest = earliest }
        first = math.min(first or earliest, earliest)
      end
    end
  end
  if not first then
    return nil
  end
  local from = math.max(first, today - days + 1)
  if from >= today then
    return nil
  end
  local xs, ys = {}, {}
  for day = from, today do
    local sum = 0
    for _, c in ipairs(chars) do
      local back = day
      while back > c.earliest and c.log[back] == nil do
        back = back - 1
      end
      sum = sum + (c.log[back] or c.log[c.earliest])
    end
    xs[#xs + 1], ys[#ys + 1] = day * DAY, sum
  end
  return { xs = xs, ys = ys }
end

Home.MAIL_SOON = 3 -- days: a mailbox whose first mail runs out sooner is marked (what's left in it is lost)
Home.MAIL_ROWS = 3

-- Waiting in your mail: one row per kept character with gold or items there, the first to run out first.
-- -> rows (keyvalue props), the total gold in all of them; rows is empty when nothing waits.
function Home.Mail(holdings, keep, now)
  local found = {}
  for key, h in pairs(holdings or {}) do
    local box = h.inbox
    if keep(key) and box and ((box.money or 0) > 0 or (box.items or 0) > 0) then
      found[#found + 1] = { name = tostring(key):match(":(.+)$") or tostring(key), box = box }
    end
  end
  table.sort(found, function(a, b)
    local x, y = a.box.firstOut or math.huge, b.box.firstOut or math.huge
    if x ~= y then
      return x < y
    end
    return a.name < b.name
  end)
  local rows, total = {}, 0
  for i, c in ipairs(found) do
    local box = c.box
    total = total + (box.money or 0)
    if i <= Home.MAIL_ROWS then
      local what = {}
      if (box.sales or 0) > 0 then
        what[#what + 1] = box.sales == 1 and L["1 sale"] or L["%d sales"]:format(box.sales)
      end
      if (box.items or 0) > 0 then
        what[#what + 1] = box.items == 1 and L["1 item"] or L["%d items"]:format(box.items)
      end
      local row = { label = c.name .. (#what > 0 and (" · " .. table.concat(what, ", ")) or ""), copper = box.money or 0 }
      if box.firstOut then
        local left = (box.firstOut - now) / DAY
        if left < 0 then
          row.note = L["some may have run out"]
        elseif left < 1 then
          row.note = L["first runs out today"]
        else
          local d = math.floor(left)
          row.note = d == 1 and L["first runs out in 1 day"] or L["first runs out in %d days"]:format(d)
        end
        row.noteTone = left < Home.MAIL_SOON and "bad" or nil
      end
      rows[#rows + 1] = row
    end
  end
  return rows, total
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

-- a piece of the gather: one that fails is left out, its error going to the game's handler (BugSack). The profiler
-- (/amedev on) sets Home.Timed to time each piece by its label.
local function try(label, fn, ...)
  if Home.Timed then
    return Home.Timed(label, ns.Shield, fn, ...)
  end
  return ns.Shield(fn, ...)
end

local function gatherMoney(f, holdings, keep)
  local gold = 0
  for key, h in pairs(holdings) do
    if keep(key) and type(h.money) == "number" then
      gold = gold + h.money
    end
  end
  f.gold = gold
  f.myGold = _G.GetMoney and _G.GetMoney() or nil
  -- the strip: neither needs prices
  f.goldLine = Home.GoldLine(holdings, keep, ns.Today(f.now))
  f.mail, f.mailTotal = Home.Mail(holdings, keep, f.now)
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
      out[#out + 1] = { itemID = e.itemID, text = e.text, at = e.at }
      Home.Until(f, e.at + DAY) -- it leaves the list then
    end
  end
  f.alerts = out
end

local function gatherCooldowns(f, now, craft)
  local out = {}
  for key, c in pairs(ns.Professions and ns.Professions:Characters() or {}) do
    for _, p in pairs(c.professions or {}) do
      for recipeID, readyAt in pairs(p.cooldowns or {}) do
        Home.Until(f, readyAt > now and readyAt or nil) -- it joins the list then
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
  -- items you've hidden (kept for your own use, like a mana drink) aren't suggested for posting, as on Sell
  local watch = ns.AME and ns.AME.watch
  for key, qty in pairs(bags) do
    local net, where = q:BestSale(key)
    local s = index.items[ns.BaseID and ns.BaseID(key) or key]
    local hidden = watch and watch.IsHidden and watch:IsHidden(key)
    if where == "ah" and net and net > 0 and s and s.signal ~= "vendor" and not hidden then
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

-- the stacks you hold that gain from refining, the most first: { { item, qty, recipe = recipeID, product, gain } }.
-- m: CraftModel.Build's model (held, uses, craft). SellOrRefine's options carry the recipe itself, not its id.
function Home.Refines(m)
  local out = {}
  for id, n in pairs(m.held or {}) do
    local recipes = m.uses and m.uses[id]
    if recipes and n > 0 then
      local r = m.craft:SellOrRefine(id, n, recipes)
      local o = r and r.best
      if o and o.gain and o.gain > 0 then
        local rec = type(o.recipe) == "table" and o.recipe or ns.Recipes.Get(o.recipe)
        if rec and rec.id then
          out[#out + 1] = { item = id, qty = n, recipe = rec.id, product = rec.product, gain = o.gain }
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.gain ~= b.gain then
      return a.gain > b.gain
    end
    return tostring(a.item) < tostring(b.item)
  end)
  return out
end

-- the one that gains most, or nil
function Home.BestRefine(m)
  return Home.Refines(m)[1]
end

-- what this character's gold covers (a purchase is paid from the one you're on): Worth doing today only suggests a
-- buy, a carry or a recipe you can pay for
local function affordable(f, copper)
  return copper == nil or f.myGold == nil or copper <= f.myGold
end

-- the first `n` of a list, keeping f.best<Kind> as its first for the rest of AME
local function top(list, n)
  local out = {}
  for i = 1, math.min(n or Home.PER_KIND, #list) do
    out[i] = list[i]
  end
  return out
end

-- the costly part of Worth doing's crafting rows: the model (Core/CraftModel), its top earners and refines, and the
-- recipes for sale your characters could learn. It hangs on the market index, your recipes and what you hold to
-- craft with (Home.Piece keys it on those); not on gold, which only filters the recipes to buy (applyCrafting).
local function gatherCrafting(index)
  local m = ns.CraftModel and ns.CraftModel.Build()
  if not m then
    return nil
  end
  local crafts = {}
  for _, e in ipairs(m.craft:TopEarners(m.entries, m.heldSet)) do
    if e.eval and (e.eval.profit or 0) > 0 then
      local char = e.crafters and e.crafters[1]
      crafts[#crafts + 1] = {
        recipe = e.recipe.id,
        product = e.recipe.product,
        profit = e.eval.profit,
        sub = char and L["%s · sells about %s"]:format(tostring(char):match(":(.+)$") or char, ns.Widgets.Rate(e.eval.sellRate)) or nil,
      }
      if #crafts >= Home.PER_KIND then
        break
      end
    end
  end
  local out = { m = m, crafts = crafts, refines = top(Home.Refines(m)) }
  -- recipes on the auction house your characters could learn
  if ns.CraftingData and ns.CraftingData.Teaches then
    local listings = {}
    for id, s in pairs(index.items) do
      if ns.CraftingData:Teaches(id) and s.min and (s.qty or 0) > 0 and (not index.day or not s.day or index.day - s.day <= 2) then
        listings[#listings + 1] = { item = id, price = s.min }
      end
    end
    out.toBuy = m.craft:RecipesToBuy(listings, function(id)
      return ns.CraftingData:Teaches(id)
    end, ns.Recipes.Get, m.chars) or {}
  end
  return out
end

-- the crafting rows into the facts, the recipes to buy filtered to what this character's gold covers
local function applyCrafting(f, c)
  f.crafts, f.bestCraft = c.crafts, c.crafts[1]
  f.refines = c.refines
  f.bestRefine = f.refines[1]
  if c.toBuy then
    local learns = {}
    for _, r in ipairs(c.toBuy) do
      if r.ready and r.payback and affordable(f, r.price) then
        local who = r.learners and r.learners[1]
        learns[#learns + 1] = {
          item = r.item,
          payback = r.payback,
          sub = who and L["%s can learn it"]:format(tostring(who.char):match(":(.+)$") or who.char) or nil,
        }
        if #learns >= Home.PER_KIND then
          break
        end
      end
    end
    f.learns, f.bestLearn = learns, learns[1]
  end
end

local function gatherBuy(f, index)
  local watch = ns.AME.watch
  if not watch then
    return
  end
  local buys, seen = {}, {}
  for _, list in ipairs(watch:Lists() or {}) do
    for id in pairs(list.items or {}) do
      local s = index.items[id]
      local usual = s and (s.avg30 or s.avg7)
      if not seen[id] and s and s.market and usual and usual > 0 then
        seen[id] = true
        local under = 1 - s.market / usual
        if under >= 0.1 and affordable(f, s.market) then
          buys[#buys + 1] = { item = id, under = under, sub = L["On your watchlist · %s sell a day"]:format(ns.Widgets.Rate(s.soldPerDay or s.sellRate)) }
        end
      end
    end
  end
  table.sort(buys, function(a, b)
    if a.under ~= b.under then
      return a.under > b.under
    end
    return tostring(a.item) < tostring(b.item)
  end)
  f.buys = top(buys)
  f.bestBuy = f.buys[1]
end

-- the routes to carry to this realm's other auction houses, best first per house: they hang on the two markets'
-- indexes and the day (Home.Piece keys them on those); gold only filters them (applyCarry)
local function gatherCarry(index, AME)
  local realm = AME:MarketRealmName()
  local here = AME:CurrentHouse()
  local out = {}
  for _, house in ipairs({ "Horde", "Alliance", "Neutral" }) do
    if house ~= here then
      local other = AME:CachedIndex(ns.ShardKey(realm, house))
      if other then
        out[#out + 1] = {
          to = ns.ShardLabel and ns.ShardLabel(ns.ShardKey(realm, house)) or house,
          rows = ns.Arbitrage.Find(index, other, {
            cut = ns.Quote.Cut(house),
            today = ns.Today(GetServerTime()),
            minProfit = 1,
          }) or {},
        }
      end
    end
  end
  return out
end

-- the inputs gatherCarry hangs on, as one value
local function carryKey(index, AME)
  local realm = AME:MarketRealmName()
  local here = AME:CurrentHouse()
  local out = { tostring(index), tostring(realm), tostring(here), ns.Today(GetServerTime()) }
  for _, house in ipairs({ "Horde", "Alliance", "Neutral" }) do
    if house ~= here then
      out[#out + 1] = tostring(AME:CachedIndex(ns.ShardKey(realm, house)))
    end
  end
  return table.concat(out, "|")
end

-- the best routes whose first item your gold covers
local function applyCarry(f, houses)
  local routes = {}
  for _, h in ipairs(houses) do
    local n = 0
    for _, r in ipairs(h.rows) do
      if r.profit and affordable(f, r.buy) then
        routes[#routes + 1] = { item = r.itemID, profit = r.profit, to = h.to }
        n = n + 1
        if n >= Home.PER_KIND then
          break
        end
      end
    end
  end
  table.sort(routes, function(a, b)
    return a.profit > b.profit
  end)
  f.carries = top(routes)
  f.bestCarry = f.carries[1]
end

-- The costly pieces of the gather, each kept until what it hangs on changes, so a change of gold, bags or mail
-- reruns only the pieces that read them. Home.Piece(name, key, fn, ...) -> fn's result, run (as a gather piece:
-- timed, errors to BugSack) only when key differs from the last run's. A piece that failed runs again next time.
local pieces = {}
Home.runs = {} -- name -> how many times a piece has run (specs)
function Home.Piece(name, key, fn, ...)
  local p = pieces[name]
  if p and p.key == key then
    return p.value
  end
  Home.runs[name] = (Home.runs[name] or 0) + 1
  local ok, value = ns.ShieldOk(function(...)
    if Home.Timed then
      return Home.Timed(name, fn, ...)
    end
    return fn(...)
  end, ...)
  if ok then
    pieces[name] = { key = key, value = value }
    return value
  end
  pieces[name] = nil
end

-- what a character's places hold, as identities (Trading replaces a place's table when it changes)
local function heldKey(holdings, keep, places)
  local out = {}
  for key, h in pairs(holdings or {}) do
    if not keep or keep(key) then
      out[#out + 1] = key
      for _, place in ipairs(places) do
        out[#out + 1] = tostring(h[place])
      end
    end
  end
  return table.concat(out, "|")
end

-- the guild banks' tabs, as identities
local function guildKey()
  local out = {}
  for gkey, bank in pairs(AME_DB and AME_DB.guildBanks or {}) do
    out[#out + 1] = gkey
    for tab, items in pairs(bank.tabs or {}) do
      out[#out + 1] = tostring(tab) .. "=" .. tostring(items)
    end
  end
  return table.concat(out, "|")
end

-- the ledger's length and newest entry
local function ledgerKey()
  local entries = AME_DB and AME_DB.ledger and AME_DB.ledger.entries or {}
  local last = entries[#entries]
  return #entries .. ":" .. tostring(last and last.t)
end

-- f.until: the soonest a fact changes with the clock alone (a cooldown ready, an alert a day old, a new day)
function Home.Until(f, at)
  if at then
    f["until"] = math.min(f["until"] or at, at)
  end
end

-- What Home's facts are built from, as one value: the market index (a new one after every scan), your recipes, the
-- notifications, the ledger, the items you've hidden, and each kept character's bags, gold, mail, auctions and bank
-- (Trading replaces those tables when they change). Guild requests and sync call Home.Forget themselves.
function Home.Stamp(holdings, keep)
  local AME = ns.AME or {}
  local out = { tostring(AME.FactionIndex and AME:FactionIndex()) }
  local function add(v)
    out[#out + 1] = tostring(v)
  end
  add(ns.Recipes and ns.Recipes.Stamp and ns.Recipes.Stamp())
  local notices = AME.notices and AME.notices.db and AME.notices.db.list or {}
  add(#notices .. ":" .. tostring(notices[#notices] and notices[#notices].at))
  local ledger = AME.ledger and AME.ledger.db and AME.ledger.db.entries or {}
  add(#ledger .. ":" .. tostring(ledger[#ledger] and ledger[#ledger].t))
  add(AME.watch and AME.watch.HiddenCount and AME.watch:HiddenCount())
  for key, h in pairs(holdings or {}) do
    if keep(key) then
      add(key)
      add(h.bags)
      add(h.money)
      add(h.mail)
      add(h.inbox)
      add(h.auctions)
      add(h.bank)
    end
  end
  return table.concat(out, "|")
end

local function sources()
  local holdings = ns.Trading and ns.Trading:Holdings() or {}
  local keep = ns.Holdings.Keep("market") or function()
    return true
  end
  return holdings, keep
end

-- the stamp as it is now (the Home screen's Stamp: drawn again only when it changes)
function Home.Current()
  return Home.Stamp(sources())
end

local cache
function Home.Gather(force)
  local now = GetServerTime()
  local AME = ns.AME
  local holdings, keep = sources()
  local stamp = Home.Stamp(holdings, keep)
  if not force and cache and cache.stamp == stamp and now < (cache.facts["until"] or math.huge) then
    local f = cache.facts
    f.now = now -- what the clock alone changes: how old the scan is, how long ago an alert fired
    if f.scanAt then
      f.scanAge = now - f.scanAt
    end
    return f
  end
  local f = { now = now }
  Home.Until(f, (ns.Today(now) + 1) * DAY) -- a new day: the gold line, mail's days left
  Home.errors = {}
  local index = AME and AME.FactionIndex and AME:FactionIndex()
  f.hasPrices = index ~= nil or (AME and AME.HasData and AME:HasData(AME:FactionShard())) or false
  try("gatherMoney", gatherMoney, f, holdings, keep)
  try("gatherAlerts", gatherAlerts, f, now)
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
    try("gatherAuctions", gatherAuctions, f, holdings, index, keep)
    try("gatherBags", gatherBags, f, holdings, index, q)
    try("gatherWorth", gatherWorth, f, holdings, index, q, keep)
    -- names in the ledger to item IDs: they resolve against what you hold and the market's items, so it runs again
    -- when the ledger, the index or what your characters hold changes
    if ns.Trading.ResolveLedger then
      Home.Piece("resolveLedger", ledgerKey() .. "|" .. tostring(index) .. "|" .. heldKey(holdings, nil, { "bags", "bank", "auctions" }), ns.Trading.ResolveLedger, ns.Trading)
    end
    f.ledger = AME.ledger and AME.ledger:Summary(now - 7 * DAY) or nil
    if ns.MarketStats and index.stats then
      local s = Home.Piece("marketStats", tostring(index) .. "|" .. tostring(index.stats), function()
        return { s = ns.MarketStats.Summary(index, 7) }
      end)
      s = s and s.s
      f.marketChange = s and s.levelChange
      f.marketLevel = s and s.level
    end
    -- the newest full scan of this market, yours or a guildmate's (sync stores theirs beside yours)
    local data = AME.history and AME.history.shards and AME.history.shards[AME:FactionShard()]
    local newest
    for _, e in ipairs(data and data.raw or {}) do
      if (e.k or "full") == "full" and e.t then
        newest = math.max(newest or 0, e.t)
      end
    end
    if newest then
      f.scanAt, f.scanAge = newest, now - newest
    end
    local craftKey = table.concat({
      tostring(index),
      ns.Recipes and ns.Recipes.Stamp and ns.Recipes.Stamp() or "",
      tostring(ns.CraftingData and ns.CraftingData.data),
      heldKey(holdings, keep, ns.Holdings.PLACES.usable),
      guildKey(),
    }, "|")
    local c = Home.Piece("gatherCrafting", craftKey, gatherCrafting, index)
    local m = c and c.m
    if c then
      try("applyCrafting", applyCrafting, f, c)
    end
    try("gatherCooldowns", gatherCooldowns, f, now, m and m.craft)
    try("gatherBuy", gatherBuy, f, index)
    local houses = Home.Piece("gatherCarry", carryKey(index, AME), gatherCarry, index, AME)
    if houses then
      try("applyCarry", applyCarry, f, houses)
    end
  end
  f.requests = ns.CraftRequests and ns.CraftRequests.Incoming and ns.CraftRequests.Incoming() or {}
  f.guildSharers = ns.SyncService and ns.SyncService.PeerCount and ns.SyncService:PeerCount() or 0
  cache = { stamp = stamp, facts = f }
  return f
end

function Home.Forget()
  cache = nil
  pieces = {}
end

-- who you share with changed (the guild line): gathered again next time
if ns.Events and ns.Events.On then
  ns.Events.On("SyncChanged", function()
    Home.Forget()
  end)
end
