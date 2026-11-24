-- The Item page (boards Main, ItemAH, ItemCompact, ItemAHCompact): one item's chart, what you hold of it, the other
-- auction houses, what crafting does with it, its market price and numbers, what to post it at, the verdict in
-- words and, at the auction house, what is on sale now. Pure functions turn gathered facts into widget props;
-- ItemPage.Gather reads them from the rest of AME (the item's history loads in the background: ItemPage.Get).
--
--   ItemPage.Get(shard, key, onReady) -> entry | nil   the item's history ({ series, latest, mixed, intraday })
--   ItemPage.Gather(app, key) -> facts                  everything the screen shows (each piece guarded)
--   ItemPage.Summarize(series, latest, opts) -> sum     the cleaned series, its summary, the market now, its change
--   ItemPage.Subtitle(f, compact), PriceCard(sum), StatRows(sum), PostLadder(advice), Verdict(sum, ctx),
--   ItemPage.Position(held, basis, market), Houses(list), CraftRows(c), Listings(book, qty, now), Actions(f, atAH)
--   ItemPage.ChartData(entry, sum, range, now, extra) -> the chart widget's source (kind "item")
local _, ns = ...
local L = ns.L

local ItemPage = { cache = {}, errors = {} }
ns.ItemPage = ItemPage

local DAY = 86400
local floor, abs = math.floor, math.abs

local function W()
  return ns.Widgets
end

local function money(c)
  return W() and W().Money(c, true) or tostring(c)
end

local function count(n)
  return W() and W().Count(n) or tostring(n)
end

local function pctRound(x)
  return floor(abs(x) * 100 + 0.5)
end

-- ------------------------------------------------------------------------------------------------ ranges

-- 2D plots every recent scan, 7D the hourly points before them too; the others plot daily history
ItemPage.RANGES = {
  { "2D", 2 },
  { "7D", 7 },
  { "30D", 30 },
  { "90D", 90 },
  { "1Y", 365 },
  { "All", nil },
}
ItemPage.INTRADAY = { ["2D"] = true, ["7D"] = true }
ItemPage.RECENT_DAYS = 2 -- an item with a scan this recent opens on 2D, else on 7D

-- the range buttons: the narrow window has no 1Y (All covers it)
function ItemPage.RangeOptions(compact)
  local out = {}
  for _, r in ipairs(ItemPage.RANGES) do
    if not (compact and r[1] == "1Y") then
      out[#out + 1] = { r[1], r[1] == "All" and L["All"] or r[1] }
    end
  end
  return out
end

function ItemPage.RangeDays(key)
  for _, r in ipairs(ItemPage.RANGES) do
    if r[1] == key then
      return r[2]
    end
  end
  return 7
end

-- the range an item opens on until you pick one: 2D with a recent scan, else 7D; the narrow window has no 1Y
function ItemPage.Range(picked, latest, now, compact)
  local key = picked
  if not key then
    key = latest and latest.t and now - latest.t <= ItemPage.RECENT_DAYS * DAY and "2D" or "7D"
  end
  if compact and key == "1Y" then
    key = "All"
  end
  return key
end

-- ------------------------------------------------------------------------------------------------ loading

local function cacheKey(shard, key)
  return tostring(shard) .. "|" .. tostring(key)
end

-- The item's history at one auction house: daily series, the newest scan, whether its suffixes are priced apart,
-- and the last week scan by scan (2D and 7D plot those). Loaded in the background the first time; onReady() runs
-- when it arrives. Returns the entry once loaded (it stays until ItemPage.Forget).
function ItemPage.Get(shard, key, onReady)
  if not (shard and key) then
    return nil
  end
  local k = cacheKey(shard, key)
  local e = ItemPage.cache[k]
  if e and e.loaded then
    return e
  end
  if e and e.loading then
    e.waiting = onReady or e.waiting
    return nil
  end
  e = { loading = true, waiting = onReady }
  ItemPage.cache[k] = e
  local AME = ns.AME
  if not (AME and AME.WithStore) then
    e.loading, e.loaded, e.series = false, true, {}
    return e
  end
  local now = GetServerTime()
  AME:WithStore("item-page-" .. tostring(key), shard, function(store)
    return {
      series = store:Series(key),
      latest = store:Latest(key),
      mixed = store:Mixed(key),
      intraday = store.Intraday and store:Intraday(key, now - 7 * DAY) or nil,
    }
  end, function(ok, res)
    e.loading, e.loaded = false, true
    if ok and type(res) == "table" then
      e.series, e.latest, e.mixed, e.intraday = res.series or {}, res.latest, res.mixed, res.intraday
    else
      e.series, e.error = {}, tostring(res)
    end
    e.at = GetServerTime()
    local fn = e.waiting
    e.waiting = nil
    if fn then
      fn()
    end
  end)
  return nil
end

-- new listings for the item were stored (a search): load it again next time it's drawn
function ItemPage.Forget(key)
  for k in pairs(ItemPage.cache) do
    if key == nil or k:match("|(.+)$") == tostring(key) then
      local e = ItemPage.cache[k]
      if not (e and e.loading) then
        ItemPage.cache[k] = nil
      end
    end
  end
end

-- ------------------------------------------------------------------------------------------------ summary

-- opts: { factor (outlier factor), avgDays, today }
-- -> { s, series, dropped, latest, market, avg, change, level, scans } or nil (no history)
function ItemPage.Summarize(series, latest, opts)
  opts = opts or {}
  if not series or #series == 0 then
    return nil
  end
  local A = ns.Analytics
  local clean, dropped = A.Clean(series, opts.factor)
  local s = A.Summarize(clean)
  if not s then
    return nil
  end
  -- the latest raw scan can itself be a bad print (one overpriced listing): the cleaned series' then
  local factor = opts.factor
  if latest and factor and factor > 1 and s.avg30 and s.avg30 > 0 and latest.market then
    if latest.market > s.avg30 * factor or latest.market < s.avg30 / factor then
      latest, dropped = nil, dropped + 1
    end
  end
  local days = opts.avgDays or 7
  local avg = s["avg" .. days] or s.avg30
  local market = latest and latest.market or s.market
  local change = market and avg and avg > 0 and market / avg - 1 or nil
  return {
    s = s,
    series = clean,
    dropped = dropped,
    latest = latest,
    market = market,
    avg = avg,
    avgDays = days,
    change = change,
    level = A.Confidence(s, opts.today),
    scans = s.scans7 or 0,
  }
end

-- "▲ 56% above" in the gain / loss colour; "right at it" dim
function ItemPage.ChangeText(change)
  if not change then
    return nil, "dim"
  end
  local p = pctRound(change)
  if p == 0 then
    return L["right at it"], "dim"
  end
  if change > 0 then
    return "▲ " .. L["%d%% above"]:format(p), "good"
  end
  return "▼ " .. L["%d%% below"]:format(p), "bad"
end

-- the Market price card: { now, vs = { text, tone }, note, signal, phase }
function ItemPage.PriceCard(sum, indexed)
  if not sum then
    return { now = nil, vsLabel = L["vs 7-day average"], vs = "—", vsTone = "dim", note = L["No history at this auction house yet."] }
  end
  local text, tone = ItemPage.ChangeText(sum.change)
  local word = ({ high = L["high"], medium = L["medium"], low = L["low"] })[sum.level] or ""
  local pips = W() and W().Confidence(sum.level) or ""
  local signal = indexed and indexed.signal or sum.s.signal
  return {
    now = sum.market,
    vsLabel = L["vs %d-day average"]:format(sum.avgDays),
    vs = text or "—",
    vsTone = tone,
    note = L["Confidence %s %s"]:format(pips, word) .. " · " .. L["%d scans this week"]:format(sum.scans),
    signal = signal ~= "none" and signal or nil,
    phase = sum.s.phase and ns.Analytics.PHASE_LABEL and ns.Analytics.PHASE_LABEL[sum.s.phase] and ns.Analytics.PHASE_LABEL[sum.s.phase]:lower() or nil,
  }
end

-- the numbers card: keyvalue props, in the board's order
function ItemPage.StatRows(sum)
  local s = sum and sum.s or {}
  local latest = sum and sum.latest
  local rows = {
    { label = L["Lowest listing"], copper = latest and latest.min or s.min },
    { label = L["%d-day average"]:format(sum and sum.avgDays or 7), copper = sum and sum.avg },
    { label = L["Volatility"], text = s.vol30 and ("%.1f%%"):format(s.vol30 * 100) or "—" },
  }
  local supply = count((latest and latest.qty) or s.qty or 0)
  local tone
  local trend = s.supplyTrend30 and s.supplyTrend30 * 7
  if trend and abs(trend) >= 0.005 then
    -- rising supply is bad for sellers (red), falling good (green)
    tone = trend > 0 and "bad" or "good"
    supply = supply .. " " .. (trend > 0 and "▲" or "▼") .. L["%d%%/wk"]:format(pctRound(trend))
  end
  if not sum then
    supply = "—"
  end
  rows[#rows + 1] = { label = L["Supply"], text = supply, tone = tone }
  local sold = s.soldPerDay or (s.sellRate and s.sellRate) or nil
  rows[#rows + 1] = { label = L["Sells/day"], text = sold and ("~" .. count(sold)) or "—" }
  return rows
end

-- ------------------------------------------------------------------------------------------------ subtitle, status

-- "Herb · Horde AH · 10 days of history · ▮▮▮ 12 scans this week · last seen 16:20 (2 h ago)"
-- f: { category, house, days, level, scans, latest, now }; compact: the short form
function ItemPage.Subtitle(f, compact)
  local parts = {}
  if f.category and not compact then
    parts[#parts + 1] = f.category
  end
  parts[#parts + 1] = f.house
  if not f.days or f.days == 0 then
    parts[#parts + 1] = f.loading and L["loading history..."] or L["no history yet"]
    return table.concat(parts, " · ")
  end
  if not compact then
    parts[#parts + 1] = L["%d days of history"]:format(f.days)
  end
  local pips = W() and W().Confidence(f.level) or ""
  parts[#parts + 1] = pips .. " " .. L["%d scans this week"]:format(f.scans or 0)
  local latest = f.latest
  if latest and latest.t and W() then
    local ago = W().Ago(latest.t, f.now)
    parts[#parts + 1] = compact and L["seen %s"]:format(ago)
      or L["last seen %s (%s)"]:format(date and date("%H:%M", latest.t) or "", ago)
  end
  return table.concat(parts, " · ")
end

-- Where the prices come from: the newest full scan of the market and who ran it, and the searches since.
-- raw: the shard's history entries ({ k = "full" | ..., t, src }); me: your name
function ItemPage.PriceSource(raw, latest, now, me, compact)
  local full, searches = nil, 0
  for _, e in ipairs(raw or {}) do
    if e.k == "full" and (not full or e.t > full.t) then
      full = e
    end
  end
  for _, e in ipairs(raw or {}) do
    if e.k ~= "full" and full and e.t > full.t then
      searches = searches + 1
    end
  end
  local ago = function(t)
    return W() and W().Ago(t, now) or tostring(t)
  end
  local out
  if full then
    local mine = not full.src or full.src == me
    if compact then
      out = L["Full scan %s"]:format(ago(full.t))
    else
      out = mine and L["Prices from your full scan %s"]:format(ago(full.t))
        or L["Prices from %s's full scan %s"]:format(full.src, ago(full.t))
    end
    if searches > 0 then
      out = out .. (compact and " · " or " ")
        .. (compact and L["%d searches since"] or L["and %d searches since"]):format(searches)
    end
  elseif latest and latest.t then
    out = L["searched %s"]:format(ago(latest.t))
  end
  return out or ""
end

-- ------------------------------------------------------------------------------------------------ posting

-- What it would post at (the Sell view's ladder): Quick, Normal, Patient by how fast they sell; Normal picked.
-- advice: Posting:Suggest's answer (or nil); qty: how many; hours: listing time; cut: the AH's share
-- -> { head = { label, text }, picks = { pick, ... }, net = { label, copper }, notes = { text, ... } } (empty picks
-- without advice)
function ItemPage.PostLadder(advice, qty, hours, cut, net)
  qty, hours = qty or 1, hours or 24
  local out = {
    head = { label = L["Post %s at (%d h listing)"]:format(count(qty), hours) },
    picks = {},
    notes = {},
  }
  if not (advice and advice.normal) then
    out.head.text = L["not enough data yet"]
    out.notes[1] = L["Search for it at the auction house, or run a full scan."]
    return out
  end
  local n = advice.normal
  out.head.text = L["%d ahead"]:format(n.ahead or 0)
  local H = W() and W().Hours or tostring
  if not advice.quickSame and advice.quick then
    out.picks[#out.picks + 1] = { label = L["Quick"], when = H(advice.quick.hours), price = advice.quick.price }
  end
  out.picks[#out.picks + 1] =
    { label = L["Normal"], when = L["sells in %s"]:format(H(n.hours)), price = n.price, selected = true }
  if advice.patient then
    out.picks[#out.picks + 1] = { label = L["Patient"], when = H(advice.patient.hours), price = advice.patient.price }
  end
  out.net = {
    label = L["You net for %s, after the cut"]:format(count(qty)),
    copper = net or floor(n.price * qty * (1 - (cut or 0.05)) - (advice.deposit or 0)),
  }
  if advice.hold then
    out.notes[#out.notes + 1] = L["unlikely to sell soon: consider holding"]
  elseif advice.cheap then
    out.notes[#out.notes + 1] = L["well below its usual price"]
  end
  return out
end

-- ------------------------------------------------------------------------------------------------ verdict

local HEADLINE = {
  buy = L["Cheaper than usual"],
  sell = L["Dearer than usual"],
  hold = L["A normal price"],
  wait = L["Cheap, but still falling"],
  vendor = L["A vendor pays more"],
}
local ACTION = {
  buy = L["a good time to buy"],
  sell = L["a good time to sell what you hold"],
  hold = L["no edge: buy only what you need"],
  wait = L["wait for it to settle"],
  vendor = L["vendor it instead"],
}

-- The verdict in words, as the tooltip and the Selling page say it: a headline ("Dearer than usual, and selling
-- fast.") and one line on why ("56% over its 7-day average while supply grows: a good time to sell what you hold.").
-- ctx: { signal (the index's call), vendorPrice, vendorNet } -> signal, headline, line
function ItemPage.Verdict(sum, ctx)
  ctx = ctx or {}
  if not sum then
    return "none", L["No call yet"], L["No history at this auction house yet."]
  end
  local s = sum.s
  local signal = ctx.signal or s.signal or "none"
  local head = HEADLINE[signal] or L["No call yet"]
  local sold = s.soldPerDay or s.sellRate
  if HEADLINE[signal] and sold then
    if sold >= 20 then
      head = L["%s, and selling fast"]:format(head)
    elseif sold < 1 then
      head = L["%s, and slow to sell"]:format(head)
    end
  end
  head = head .. "."
  if signal == "vendor" and ctx.vendorPrice then
    local line = L["Posting nets ~%s after cut and deposit; a vendor pays %s."]:format(
      money(ctx.vendorNet or 0),
      money(ctx.vendorPrice)
    )
    return signal, head, line
  end
  local parts
  local d = sum.change
  if d and abs(d) >= 0.03 then
    parts = (d > 0 and L["%d%% over its %d-day average"] or L["%d%% under its %d-day average"]):format(
      pctRound(d),
      sum.avgDays
    )
  elseif d then
    parts = L["right at its %d-day average"]:format(sum.avgDays)
  end
  local trend = s.supplyTrend30 and s.supplyTrend30 * 7
  if parts and trend and abs(trend) >= 0.05 then
    parts = parts .. " " .. (trend > 0 and L["while supply grows"] or L["while supply shrinks"])
  end
  local line
  if signal == "none" then
    line = L["Needs %d days of history (has %d)."]:format(ns.Analytics.MIN_DAYS or 5, s.days or 0)
  elseif parts and ACTION[signal] then
    line = parts .. ": " .. ACTION[signal] .. "."
  elseif ACTION[signal] then
    line = ACTION[signal]:gsub("^%l", string.upper) .. "."
  else
    line = (parts or "") .. "."
  end
  -- capitalise the start
  line = line:gsub("^%l", string.upper)
  if sum.level == "low" then
    line = line .. " " .. L["Few recent scans: scan again."]
  end
  return signal, head, line
end

-- ------------------------------------------------------------------------------------------------ cards

-- Your position: what you hold, where, what it cost and what it is up or down.
-- held: Trading.Held; basis: Ledger:CostBasis()[key]; market: copper -> keyvalue props
function ItemPage.Position(held, basis, market)
  local n = held and held.total or 0
  if n == 0 then
    return { { label = L["You hold"], text = L["none"], tone = "dim" } }
  end
  local rows = { { label = L["You hold"], text = count(n) } }
  local where = {}
  if (held.bags or 0) > 0 then
    where[#where + 1] = L["bags %s"]:format(count(held.bags))
  end
  if (held.bank or 0) > 0 then
    where[#where + 1] = L["bank %s"]:format(count(held.bank))
  end
  if (held.auctions or 0) > 0 then
    where[#where + 1] = L["AH %s"]:format(count(held.auctions))
  end
  if (held.guildBank or 0) > 0 then
    where[#where + 1] = L["guild bank %s"]:format(count(held.guildBank))
  end
  local names = {}
  for _, c in ipairs(held.chars or {}) do
    names[#names + 1] = c.name
  end
  rows[#rows + 1] = { label = table.concat(where, " · "), text = table.concat(names, ", "), tone = "dim" }
  if basis and basis.unit then
    rows[#rows + 1] = { label = L["Average cost"], copper = floor(basis.unit + 0.5) }
    if market then
      rows[#rows + 1] = {
        label = L["Unrealized"],
        copper = floor((market - basis.unit) * math.min(basis.units or n, n) + 0.5),
        signed = true,
      }
    end
  end
  return rows
end

-- Other auction houses: every house of this market, its market price and how its net compares with yours.
-- list: { { house, label, market, net, mine, age } } (own first) -> rows, note
function ItemPage.Houses(list, own, labels)
  local mine
  for _, h in ipairs(list) do
    if h.mine then
      mine = h.net
    end
  end
  local rows, seen, goblinAge = {}, {}, nil
  for _, h in ipairs(list) do
    seen[h.house] = true
    local row = { label = h.label, copper = h.market }
    if h.mine then
      row.note, row.noteTone = L["here"], "dim"
    elseif mine and mine > 0 and h.net then
      local d = h.net / mine - 1
      row.note = ("%+d%% "):format(floor(d * 100 + (d >= 0 and 0.5 or -0.5))) .. L["net"]
      row.noteTone = d > 0 and "good" or d < 0 and "bad" or "dim"
    end
    if h.house == "Neutral" and not h.mine then
      goblinAge = h.age
    end
    rows[#rows + 1] = row
  end
  for _, house in ipairs({ own, "Neutral", own == "Horde" and "Alliance" or "Horde" }) do
    if not seen[house] then
      rows[#rows + 1] = { label = labels[house] or house, text = L["no data"], tone = "dim" }
    end
  end
  local note = L["After each cut"]
  if goblinAge then
    note = note .. " · " .. L["goblin data %s"]:format(goblinAge)
  end
  return rows, note
end

-- Crafting: what makes it and what it goes into. c: { usedIn = key?, makers = { { name, profit } }, more = n }
function ItemPage.CraftRows(c)
  local rows = {}
  if c.usedIn then
    rows[#rows + 1] = { label = L["Used in"], valueItem = c.usedIn }
  end
  local maker = c.makers and c.makers[1]
  if maker then
    rows[#rows + 1] = {
      label = L["%s makes it"]:format(maker.name),
      copper = maker.profit,
      signed = maker.profit ~= nil,
      text = maker.profit == nil and L["no price yet"] or nil,
      tone = maker.profit == nil and "dim" or nil,
    }
  end
  if (c.more or 0) > 0 then
    local label
    if maker then
      label = c.more == 1 and L["and 1 more recipe"] or L["and %d more recipes"]:format(c.more)
    else
      label = c.more == 1 and L["1 recipe makes it"] or L["%d recipes make it"]:format(c.more)
    end
    rows[#rows + 1] = {
      label = label,
      text = L["Show"],
      action = "showRecipes",
    }
  end
  if #rows == 0 then
    rows[1] = { label = L["No recipe of yours uses or makes it"], text = "" }
  end
  return rows
end

-- ------------------------------------------------------------------------------------------------ listings

-- Pure: buying qty climbs the listings, cheapest first: how many each gives, what it all costs, how many there are
function ItemPage.Fill(rows, qty)
  local shop = ns.AHShopping
  if shop and shop.Fill then
    return shop.Fill(rows, qty)
  end
  local taken, cost, left = {}, 0, qty or 0
  for i, r in ipairs(rows or {}) do
    if left <= 0 then
      break
    end
    local n = math.min(left, r.qty)
    taken[i], cost, left = n, cost + n * r.price, left - n
  end
  return taken, cost, (qty or 0) - left
end

local function timeLeft(seconds, band)
  local shop = ns.AHShopping
  if shop and shop.TimeLeftText then
    return shop.TimeLeftText(seconds, band)
  end
  if seconds then
    return seconds >= 3600 and L["%d h"]:format(floor(seconds / 3600)) or L["%d min"]:format(math.max(1, floor(seconds / 60)))
  end
  return ""
end

-- What's on sale now (AHSearch.results[key]), cheapest first, with the rows an order of qty takes from picked
-- ("40 of 85": the last one partly). -> rows { key, each, qty, left, selected, mine }, cost, covered, total units
function ItemPage.Listings(book, qty, now)
  local rows, units = {}, 0
  if not book then
    return rows, 0, 0, 0
  end
  local taken, cost, covered = ItemPage.Fill(book.rows, book.commodity and qty or 0)
  for i, r in ipairs(book.rows or {}) do
    local seconds, band
    if ns.AHSearch and ns.AHSearch.TimeLeft then
      seconds, band = ns.AHSearch.TimeLeft(book, r, now)
    end
    local t = taken[i]
    rows[i] = {
      key = "listing" .. i,
      each = r.price,
      qty = (t and t < r.qty) and L["%s of %s"]:format(count(t), count(r.qty)) or count(r.qty),
      left = timeLeft(seconds, band),
      selected = t ~= nil and t > 0 or nil,
      mine = r.mine or nil,
    }
    units = units + (r.qty or 0)
  end
  return rows, cost, covered, units
end

-- "3,234 on sale · just now"
function ItemPage.OnSale(book, units, now)
  if not book then
    return L["searching..."]
  end
  if #(book.rows or {}) == 0 then
    return L["none listed"]
  end
  local ago = book.at and now and (now - book.at < 60 and L["just now"] or (W() and W().Ago(book.at, now))) or ""
  return L["%s on sale"]:format(count(units)) .. (ago ~= "" and (" · " .. ago) or "")
end

-- ------------------------------------------------------------------------------------------------ actions

-- The action bar: everything you can do with the item without leaving the page. Search the AH and Sell need the
-- auction house (greyed away from it); Who can make it when anyone's recipe makes it.
-- f: { held (bags count), lists (watchlists it's on), alert, hidden, whoCan } -> button props (with ids)
function ItemPage.Actions(f, atAH)
  local off = atAH and "normal" or "disabled"
  local out = {
    { id = "search", label = atAH and L["Search again"] or L["Search the AH"], action = "searchAH", variant = off },
  }
  local n = f.sellable or 0
  out[#out + 1] = {
    id = "sell",
    label = n > 0 and L["Sell %s"]:format(count(n)) or L["Sell"],
    action = "sell",
    variant = (atAH and n > 0) and "normal" or "disabled",
  }
  out[#out + 1] = { id = "list", label = L["Add to a shopping list"] .. " ▾", menu = "lists" }
  local watching = f.watchLists and #f.watchLists > 0
  out[#out + 1] = {
    id = "watch",
    label = watching and ("★ " .. L["Watching"] .. " · " .. table.concat(f.watchLists, ", ") .. " ▾") or (L["Watch"] .. " ▾"),
    menu = "watch",
  }
  local alert = f.alert
  local alertText
  if alert and alert.below then
    alertText = L["Alert: below %s"]:format(money(alert.below))
  elseif alert and alert.above then
    alertText = L["Alert: above %s"]:format(money(alert.above))
  elseif alert and alert.signal then
    alertText = L["Alert: on a signal"]
  else
    alertText = L["Set an alert"]
  end
  out[#out + 1] = { id = "alert", label = alertText .. " ▾", menu = "alert" }
  out[#out + 1] = {
    id = "who",
    label = L["Who can make it"],
    action = "whoCan",
    variant = f.whoCan and "normal" or "disabled",
    right = true,
  }
  out[#out + 1] = { id = "hide", label = f.hidden and L["Unhide"] or L["Hide from lists"], action = "toggleHidden", right = true }
  return out
end

-- the alert menu's choices: below the lowest listing, below the average, a signal alert, and clearing it
function ItemPage.AlertChoices(sum, alert)
  local out = {}
  local s = sum and sum.s or {}
  local low = sum and ((sum.latest and sum.latest.min) or s.min)
  if low then
    out[#out + 1] = { key = "below:" .. floor(low), label = L["Below %s (the lowest listing)"]:format(money(low)) }
  end
  if sum and sum.avg then
    local under = floor(sum.avg * 0.9)
    out[#out + 1] = { key = "below:" .. under, label = L["Below %s (10%% under its average)"]:format(money(under)) }
    local over = floor(sum.avg * 1.2)
    out[#out + 1] = { key = "above:" .. over, label = L["Above %s (20%% over its average)"]:format(money(over)) }
  end
  out[#out + 1] = { key = "signal", label = L["On a buy or sell signal"], checked = alert and alert.signal or false }
  if alert then
    out[#out + 1] = { key = "clear", label = L["Clear the alert"] }
  end
  return out
end

-- ------------------------------------------------------------------------------------------------ chart data

-- A rolling average over `hours` (a week) at each of xs: every hour before counts once (its last value, carried for
-- up to CARRY hours when an hour has none, else that day's daily price, byDay[day]). The scan-by-scan ranges'
-- 7-day average: a 7-point average of scans isn't one.
ItemPage.ROLL_HOURS, ItemPage.CARRY_HOURS = 168, 6
function ItemPage.RollingAverage(xs, values, byDay, hours)
  hours = hours or ItemPage.ROLL_HOURS
  local hourly = {}
  for i, x in ipairs(xs) do
    if values[i] then
      hourly[floor(x / 3600)] = values[i]
    end
  end
  local out = {}
  if #xs == 0 then
    return out
  end
  local first, last = floor(xs[1] / 3600) - hours + 1, floor(xs[#xs] / 3600)
  local sum, n, vals, seen, seenAt = {}, {}, {}, nil, nil
  local s, c = 0, 0
  for h = first, last do
    local v = hourly[h]
    if v then
      seen, seenAt = v, h
    elseif seen and h - seenAt <= ItemPage.CARRY_HOURS then
      v = seen
    else
      v = byDay[floor(h / 24)]
    end
    vals[h] = v
    if v then
      s, c = s + v, c + 1
    end
    local drop = vals[h - hours]
    if drop then
      s, c = s - drop, c - 1
    end
    sum[h], n[h] = s, c
  end
  for i, x in ipairs(xs) do
    local h = floor(x / 3600)
    if values[i] and n[h] and n[h] > 0 then
      out[i] = sum[h] / n[h]
    end
  end
  return out
end

-- The chart widget's source for an item: the points of the range picked (scan by scan on 2D and 7D, the days
-- before the first scan filled with daily points), the 7-day average at each, your trades, the vendor price.
-- entry: ItemPage.Get's; sum: ItemPage.Summarize's (its cleaned series); range: "2D" ... "All"; now: server time;
-- extra: { vendor, trades = { { x, y, kind } }, message }
function ItemPage.ChartData(entry, sum, range, now, extra)
  extra = extra or {}
  local data = { now = now, vendor = extra.vendor, trades = extra.trades, points = {} }
  if not entry then
    data.message = L["Loading history..."]
    return data
  end
  if not sum then
    data.message = extra.message
      or (entry.mixed and L['Each suffix of this item ("of the Monkey", "of Magic"...) has its own prices. Shift-click one, or search its full name.']
        or L["No history for this item yet. Search for it at the auction house, or run a full scan."])
    return data
  end
  local days = ItemPage.RangeDays(range)
  local daily = sum.series
  local intraday = ItemPage.INTRADAY[range] and entry.intraday and #entry.intraday > 0
  local from = days and (now - days * DAY) or nil
  local pts, xs, market = {}, {}, {}
  if intraday then
    local scans = {}
    for _, p in ipairs(entry.intraday) do
      if p.t >= from then
        scans[#scans + 1] = p
      end
    end
    if #scans == 0 then
      intraday = false
    else
      -- over 7D the days before the first scan get their daily points, so the chart spans the whole range
      if days > 2 then
        local first = scans[1].t
        for _, p in ipairs(daily) do
          local t = p.day and p.res ~= "week" and p.day * DAY + DAY / 2
          if t and t >= from and (p.day + 1) * DAY <= first then
            pts[#pts + 1] = { t = t, market = p.market, min = p.min, qty = p.qty }
            data.daily = true
          end
        end
      end
      for _, p in ipairs(scans) do
        pts[#pts + 1] = p
      end
    end
  end
  if not intraday then
    pts = daily
    if range == "2D" then
      data.message = L["No scans of this item in the last 2 days. Daily history is on the other ranges."]
    end
  end
  for i, p in ipairs(pts) do
    xs[i] = p.t or (p.day * DAY + (p.res == "week" and 3.5 * DAY or DAY / 2))
    market[i] = p.market
  end
  local avg
  if intraday then
    local byDay = {}
    for _, p in ipairs(daily) do
      if p.day and p.res ~= "week" then
        byDay[p.day] = p.market
      end
    end
    avg = ItemPage.RollingAverage(xs, market, byDay)
  else
    avg = {}
    for i = 1, #market do
      avg[i] = ns.Analytics.SMA(market, math.min(7, i), i)
    end
  end
  for i, p in ipairs(pts) do
    data.points[i] = { x = xs[i], market = p.market, min = p.min, high = p.high, qty = p.qty, avg = avg[i] }
  end
  data.intraday = intraday or false
  data.id = tostring(entry) .. ":" .. tostring(range) .. ":" .. #data.points
  if from then
    data.from, data.to = from, now + (intraday and 3600 or DAY)
  end
  return data
end

-- your own trades in it, as dots: what you paid / got per unit and when (ledger entries)
function ItemPage.Trades(entries, key, name)
  local out = {}
  for _, e in ipairs(entries or {}) do
    local mine = e.itemID == key or (name and e.name == name)
    if mine and (e.kind == "buy" or e.kind == "sale") and (e.qty or 0) > 0 and e.amount then
      out[#out + 1] = { x = e.t, y = e.amount / e.qty, kind = e.kind }
    end
  end
  return out
end

-- ------------------------------------------------------------------------------------------------ gather

local function try(fn, ...)
  local ok, a, b = pcall(fn, ...)
  if ok then
    return a, b
  end
  ItemPage.errors[#ItemPage.errors + 1] = tostring(a)
  if ns.Dev and ns.Dev.Warn then
    ns.Dev.Warn("Item page: " .. tostring(a))
  end
end

-- every house of this market with a price for it (as the tooltip's Shift details list them)
local function gatherHouses(key, own)
  local AME = ns.AME
  local realm = AME:MarketRealmName()
  local out = {}
  local today = ns.Today and ns.Today(GetServerTime()) or floor(GetServerTime() / DAY)
  for _, house in ipairs({ own, "Neutral", own == "Horde" and "Alliance" or "Horde" }) do
    local shard = ns.ShardKey(realm, house)
    local index = AME.CachedIndex and AME:CachedIndex(shard)
    local s = index and index.items[key]
    if s and s.market then
      local q = ns.Quote.For(shard, index, { house = house, fresh = false })
      local age = s.day and (today - s.day)
      out[#out + 1] = {
        house = house,
        label = ns.HOUSE_LABEL[house] or house,
        market = s.market,
        net = q:ListingNet(key),
        mine = house == own,
        age = age and (age <= 0 and L["from today"] or age == 1 and L["1 day old"] or L["%d days old"]:format(age)),
      }
    end
  end
  return out
end

-- recipe spell -> reagents, from the shipped data, reversed: item -> recipes it goes into (built once)
local usedBy, usedByData
local function usedIn(key)
  local out = {}
  local data = ns.CraftingData and ns.CraftingData.data
  if data and data.recipes then
    if usedByData ~= data then
      usedBy, usedByData = {}, data
      for spell in pairs(data.recipes) do
        local r = ns.CraftingData:Recipe(spell)
        for _, g in ipairs(r and r.product and r.reagents or {}) do
          usedBy[g[1]] = usedBy[g[1]] or {}
          table.insert(usedBy[g[1]], r.product)
        end
      end
    end
    for _, p in ipairs(usedBy[key] or {}) do
      out[#out + 1] = p
    end
  end
  return out
end

local function gatherCraft(key)
  local c = { makers = {}, more = 0 }
  local uses = usedIn(key)
  table.sort(uses)
  c.usedIn = uses[1]
  local craft = ns.CraftModel and ns.CraftModel.Craft and ns.CraftModel.Craft()
  local producers = ns.Recipes and ns.Recipes.Producers(key) or {}
  for _, p in ipairs(producers) do
    local who = p.crafters and p.crafters[1]
    if who then
      local r = ns.Recipes.Get(p.recipe)
      local e = craft and r and craft:Evaluate(r, {})
      c.makers[#c.makers + 1] = { name = who:match("[^:]+$") or who, profit = e and e.profit, recipe = p.recipe }
    end
  end
  local all = ns.Crafters and ns.Crafters.RecipesFor and ns.Crafters.RecipesFor(key) or {}
  c.recipes = #all
  c.more = math.max(0, #all - (c.makers[1] and 1 or 0))
  c.whoCan = #all > 0
  return c
end

-- Everything the screen shows for one item at the viewed auction house. onReady: redraw when the history loads.
function ItemPage.Gather(app, key, onReady)
  ItemPage.errors = {}
  local AME = ns.AME or {}
  local now = GetServerTime()
  local house = app:House()
  local shard = AME.MarketRealmName and app:Shard() or nil
  local f = { key = key, now = now, house = ns.HOUSE_LABEL and ns.HOUSE_LABEL[house] or house, shard = shard }
  if not key then
    return f
  end
  local info = ns.ItemCache and ns.ItemCache.Get(key) or {}
  f.vendor = info.sellPrice
  f.category = info.subClassID and ns.ItemCache.SubClassName and try(ns.ItemCache.SubClassName, info.classID, info.subClassID)
  f.entry = try(ItemPage.Get, shard, key, onReady)
  f.loading = f.entry == nil
  local settings = ns.Settings
  local avgDays = settings and settings:Get("tooltipAvgDays") or 7
  f.avgDays = avgDays
  if f.entry then
    f.sum = try(ItemPage.Summarize, f.entry.series, f.entry.latest, {
      factor = settings and settings:Get("outlierFactor"),
      avgDays = avgDays,
      today = floor(now / DAY),
    })
  end
  local index = AME.CachedIndex and shard and AME:CachedIndex(shard)
  f.indexed = index and index.items and index.items[key]
  -- held: what you have; you can sell what's in your bags
  f.held = ns.Trading and ns.Trading.Held and AME_DB and try(ns.Trading.Held, key) or nil
  f.sellable = f.held and f.held.bags or 0
  local ledger = AME.ledger
  if ledger and ledger.CostBasis then
    local basis = try(ledger.CostBasis, ledger)
    f.basis = basis and basis[key]
  end
  if AME.MarketRealmName and ns.Quote then
    f.houses = try(gatherHouses, key, house) or {}
  else
    f.houses = {}
  end
  f.craft = try(gatherCraft, key) or { makers = {}, more = 0 }
  f.whoCan = f.craft.whoCan
  -- posting: what you hold (or one), your usual listing time
  local hours = settings and settings:Get("listingHours") or 24
  f.postQty = (f.held and f.held.total and f.held.total > 0) and f.held.total or 1
  f.hours = hours
  if ns.Posting and ns.Posting.Suggest and shard then
    f.advice = try(ns.Posting.Suggest, ns.Posting, shard, key, f.postQty, hours)
    if f.advice and f.advice.normal and ns.Quote and ns.Quote.PostNet then
      -- what one nets after the cut and its share of the deposit, times how many
      local each = try(ns.Quote.PostNet, shard, f.advice.normal.price, f.advice.deposit, f.advice.qty)
      f.net = each and floor(each * f.postQty + 0.5) or nil
    end
    f.cut = ns.Quote and ns.Quote.Cut and ns.Quote.ShardHouse and try(ns.Quote.Cut, ns.Quote.ShardHouse(shard)) or nil
  end
  -- watching, alerts, hidden
  local watch = AME.watch
  if watch then
    f.watchLists = {}
    for i, l in ipairs(watch:Lists() or {}) do
      if watch:Has(i, key) then
        f.watchLists[#f.watchLists + 1] = l.name
      end
    end
    f.alert = watch:Alert(key)
    f.hidden = watch:IsHidden(key)
  end
  f.trades = AME.ledger and AME.ledger.db and ItemPage.Trades(AME.ledger.db.entries, key, ns.ItemCache.Name(key)) or nil
  f.raw = AME.HistoryLoaded and AME:HistoryLoaded() and AME.history and AME.history.shards[shard]
    and AME.history.shards[shard].raw
  -- at the auction house: what's on sale now
  f.book = ns.AHSearch and ns.AHSearch.results and ns.AHSearch.results[key]
  return f
end
