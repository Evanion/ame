-- Market statistics for a whole auction house: a price index, listed value, auctions, and listed value by category,
-- per day. Built alongside the market index (MarketIndex.Build feeds every item through Add), so it costs no extra pass
-- over history. Pure: item categories come from an injected classOf(itemID).
--
-- Price index: each day, the mean log price change of "steady" items (listed on most days of the window) between
-- consecutive days they were seen, chained into a level that starts at 100. A day counts only with at least
-- MIN_LISTED units listed, so a single item reposted every day doesn't make it "steady". Like a geometric
-- equal-weighted stock index: one-off listings and items seen once can't move it.
--
-- CPI (consumer price index): what players use up - consumables, trade goods, reagents, gems, ammo - weighted by
-- what's spent on each (sell rate x price), like a real CPI weights by household spending. Same steady-item rule and
-- chaining as the price index. Sell rates need full scans a few hours apart; without enough of them the weights fall
-- back to listed value (stats.cpiWeights says which).
--
-- Listed value: market price x units listed. Each price is capped at the outlier factor (Settings > Data) times the
-- item's 30-day average, so a fantasy listing (a grey at 99,999g, gold trading) can't dominate the total. Items with
-- too little history for an average can't be capped: the biggest contributors are kept (top) so they stay visible.
--
-- Totals only mean something on days with a full scan: a day of searches sees a few items. A day counts when it saw
-- at least COVERAGE of the most items seen on any day in the window.
local _, ns = ...

local exp, log, max, min, ceil = math.exp, math.log, math.max, math.min, math.ceil

local MarketStats = {}
ns.MarketStats = MarketStats

MarketStats.COVERAGE = 0.5 -- a day with at least this share of the busiest day's items had a full scan
MarketStats.STEADY_SHARE = 0.6 -- steady items: seen on at least this share of the days with data
MarketStats.STEADY_MIN = 3 -- ... and on at least this many days
MarketStats.MIN_BASKET = 5 -- fewer steady items changing on a day: the index stays flat that day
MarketStats.MIN_LISTED = 3 -- a day counts for the index, CPI and movers only with at least this many units listed:
-- one item reposted every day isn't a market price
MarketStats.MAX_GAP = 7 -- a price change spans at most this many days between full scans (longer gaps are left out)
MarketStats.MAX_MOVE = log(2) -- one item moves the index by at most a doubling / halving a day
MarketStats.TOP = 5 -- the largest items by value kept for the latest day
MarketStats.OTHER = -1 -- category of items whose class isn't known
-- item classes in the CPI basket: consumable, gem, reagent, projectile (ammo), trade goods
MarketStats.CPI_CLASSES = { [0] = true, [3] = true, [5] = true, [6] = true, [7] = true }
MarketStats.CPI_MIN_RATED = 20 -- CPI items with a sell rate needed to weight by spending (else by listed value)

-- from, to: the day range (inclusive); factor: outlier factor (nil / false = no cap); classOf(itemID) -> classID
function MarketStats.New(from, to, factor, classOf)
  return setmetatable({
    from = from,
    to = to,
    factor = (factor and factor > 1) and factor or nil,
    classOf = classOf,
    days = {}, -- [day] = { items, value, auctions, units, capped, cls = { [classID] = value }, top = { ... } }
    -- price changes, by the day they end on and how many days they span (only changes between two full-scan days
    -- count, which is known in Finish): [day][gap][n] = sum of log changes of items seen on n days / how many
    ret = {},
    cnt = {},
    seen = {}, -- [n] = items seen on n days
    -- CPI, per weighting (t: turnover, v: listed value): [w][day][gap][n] = { sum of weight x change, sum of weight,
    -- count }
    cpi = { t = {}, v = {} },
    cpiSeen = { t = {}, v = {} }, -- [w][n] = CPI items seen on n days
  }, { __index = MarketStats })
end

local EMPTY = {}

local function bump(t, k, v)
  t[k] = (t[k] or 0) + v
end

local function keepTop(top, entry)
  local n = #top
  if n >= MarketStats.TOP and top[n].value >= entry.value then
    return
  end
  local i = n + 1
  while i > 1 and top[i - 1].value < entry.value do
    i = i - 1
  end
  table.insert(top, i, entry)
  if #top > MarketStats.TOP then
    top[#top] = nil
  end
end

local function usable(p, from, to)
  return p.res ~= "week"
    and p.market
    and p.market > 0
    and (p.qty or 0) >= MarketStats.MIN_LISTED
    and p.day >= from
    and p.day <= to
end

-- t[a][b], created on first use
local function slot(t, a, b)
  local ta = t[a]
  if not ta then
    ta = {}
    t[a] = ta
  end
  local tb = ta[b]
  if not tb then
    tb = {}
    ta[b] = tb
  end
  return tb
end

-- Units a day an item really sells, for turnover and CPI weights: Quote.UnitsPerDay, its sell rate but never more
-- than is listed. The sell rate counts every listing that leaves between full scans - expired and cancelled ones
-- too - and a short observation scales up to a day, so for gear (single listings that mostly expire) it can be far
-- above what sells.
local function soldPerDay(s)
  return ns.Quote.UnitsPerDay(s) or 0
end

-- One item: raw = its points in the window (oldest first, as Store:BucketSeries gives them), clean = the same with
-- outlier days dropped (Analytics.Clean), s = its summary (Analytics.Summarize; avg30 sets the cap).
function MarketStats:Add(id, raw, clean, s)
  local cap = self.factor and s and s.avg30 and s.avg30 > 0 and self.factor * s.avg30 or nil
  local cls = (self.classOf and self.classOf(id)) or MarketStats.OTHER
  local from, to = self.from, self.to
  for _, p in ipairs(raw) do
    local d = p.day
    if p.res ~= "week" and p.market and d >= from and d <= to then
      local day = self.days[d]
      if not day then
        day = { items = 0, value = 0, auctions = 0, units = 0, capped = 0, cls = {}, top = {} }
        self.days[d] = day
      end
      local price, qty = p.market, p.qty or 0
      local capped = cap and price > cap
      if capped then
        price = cap
        day.capped = day.capped + 1
      end
      local value = price * qty
      day.items = day.items + 1
      day.value = day.value + value
      day.auctions = day.auctions + (p.auctions or 0)
      day.units = day.units + qty
      bump(day.cls, cls, value)
      local top = day.top
      if value > 0 and (#top < MarketStats.TOP or top[#top].value < value) then -- a table only for what makes it
        keepTop(top, { id = id, qty = qty, price = price, raw = capped and p.market or nil, value = value })
      end
    end
  end
  -- price changes between consecutive days seen, filed under how many days the item was seen (steady or not is
  -- decided in Finish, once the number of full-scan days is known)
  local n, prev = 0, nil
  for _, p in ipairs(clean) do
    if usable(p, from, to) then
      n = n + 1
    end
  end
  if n == 0 then
    return
  end
  bump(self.seen, n, 1)
  -- CPI weights: spending per day (sell rate x capped price), and listed value (capped price x units listed)
  local weights
  if MarketStats.CPI_CLASSES[cls] and s and s.market then
    local price = cap and min(s.market, cap) or s.market
    weights = { v = price * (s.qty or 0) }
    local rate = soldPerDay(s)
    if rate > 0 then
      weights.t = price * rate
    end
    for w, weight in pairs(weights) do
      if weight > 0 then
        bump(self.cpiSeen[w], n, 1)
      else
        weights[w] = nil
      end
    end
  end
  for _, p in ipairs(clean) do
    if usable(p, from, to) then
      if prev and p.day - prev.day <= MarketStats.MAX_GAP then
        local r = max(-MarketStats.MAX_MOVE, min(MarketStats.MAX_MOVE, log(p.market / prev.market)))
        local gap = p.day - prev.day
        bump(slot(self.ret, p.day, gap), n, r)
        bump(slot(self.cnt, p.day, gap), n, 1)
        for w, weight in pairs(weights or EMPTY) do
          local byDay = slot(self.cpi[w], p.day, gap)
          local acc = byDay[n]
          if not acc then
            acc = { 0, 0, 0 }
            byDay[n] = acc
          end
          acc[1], acc[2], acc[3] = acc[1] + weight * r, acc[2] + weight, acc[3] + 1
        end
      end
      prev = p
    end
  end
end

-- -> stats = {
--   from, to, steadyMin (days an item needs to count as steady), basket (steady items),
--   days = { { day, items, value, auctions, units, capped, cls = { [classID] = value } }, ... } full-scan days, oldest
--     first; the newest also has top = { { id, qty, price, raw (uncapped price, when capped), value }, ... }
--   index = { { day, level }, ... } oldest first (level 100 on the first full-scan day)
--   cpi = { { day, level }, ... } the same for the CPI; cpiBasket (its steady items),
--   cpiWeights ("turnover" | "listed")
--   day = the newest full-scan day (nil: none)
-- }
function MarketStats:Finish()
  local busiest = 0
  for _, day in pairs(self.days) do
    busiest = max(busiest, day.items)
  end
  local covered, scanned = {}, {}
  for d = self.from, self.to do
    local day = self.days[d]
    if day and day.items >= MarketStats.COVERAGE * busiest then
      day.day = d
      covered[d] = true
      scanned[#scanned + 1] = day
    end
  end
  local steadyMin = max(MarketStats.STEADY_MIN, ceil(MarketStats.STEADY_SHARE * #scanned))
  local out = { from = self.from, to = self.to, steadyMin = steadyMin, basket = 0, days = scanned, index = {} }
  for n, count in pairs(self.seen) do
    if n >= steadyMin then
      out.basket = out.basket + count
    end
  end
  -- CPI: weight by spending when enough basket items have a sell rate
  local function steadyCount(seen)
    local c = 0
    for n, count in pairs(seen) do
      if n >= steadyMin then
        c = c + count
      end
    end
    return c
  end
  local w = steadyCount(self.cpiSeen.t) >= MarketStats.CPI_MIN_RATED and "t" or "v"
  out.cpiWeights, out.cpiBasket, out.cpi = w == "t" and "turnover" or "listed", steadyCount(self.cpiSeen[w]), {}
  local cpiLevel, cpiStarted = 100, false
  local level, started = 100, false
  -- both indexes move only on full-scan days, by changes from an earlier full-scan day: prices from a day of
  -- searches (or another data source) aren't comparable
  for d = self.from, self.to do
    local sum, count, ws, wt, wc = 0, 0, 0, 0, 0
    if covered[d] then
      for gap, byN in pairs(self.ret[d] or {}) do
        if covered[d - gap] then
          for n, r in pairs(byN) do
            if n >= steadyMin then
              sum, count = sum + r, count + self.cnt[d][gap][n]
            end
          end
        end
      end
      for gap, byN in pairs(self.cpi[w][d] or {}) do
        if covered[d - gap] then
          for n, acc in pairs(byN) do
            if n >= steadyMin then
              ws, wt, wc = ws + acc[1], wt + acc[2], wc + acc[3]
            end
          end
        end
      end
    end
    if started and count >= MarketStats.MIN_BASKET then
      level = level * exp(sum / count)
      out.index[#out.index + 1] = { day = d, level = level }
    elseif not started and covered[d] then
      started = true
      out.index[1] = { day = d, level = level }
    end
    if cpiStarted and wc >= MarketStats.MIN_BASKET and wt > 0 then
      cpiLevel = cpiLevel * exp(ws / wt)
      out.cpi[#out.cpi + 1] = { day = d, level = cpiLevel }
    elseif not cpiStarted and covered[d] then
      cpiStarted = true
      out.cpi[1] = { day = d, level = cpiLevel }
    end
  end
  for i, day in ipairs(out.days) do
    if i < #out.days then
      day.top = nil -- only the newest day's biggest items are shown
    end
  end
  local last = out.days[#out.days]
  out.day = last and last.day or nil
  return out
end

-- the newest entry of list (sorted by .day) with day <= d
local function atOrBefore(list, d)
  local found
  for _, e in ipairs(list) do
    if e.day <= d then
      found = e
    else
      break
    end
  end
  return found
end
MarketStats.AtOrBefore = atOrBefore

local function change(a, b)
  return (a and b and a > 0) and (b / a - 1) or nil
end

local CHANGE_KEY = { [1] = "change1", [7] = "change7", [30] = "change30" }

-- What the Overview shows, over a period (1 / 7 / 30 days):
-- index = { stats = ..., items = { [id] = summary } } (MarketIndex); classOf(itemID) -> classID; hide (optional set);
-- moverClass (optional): risers and fallers from this category only
-- -> {
--   day, level, levelChange, value, valueChange, auctions, auctionsChange, items, units, capped, basket,
--   turnover (copper per day), up, down, buy, sell, risers = { s, ... }, fallers = { s, ... },
--   sectors = { { classID, value, share, change, turnover }, ... } by value, top = { ... } (see Finish),
--   series = { days = {...}, level = {...}, value = {...}, auctions = {...} } for the chart
-- } or nil when the index has no stats (or no full-scan day)
function MarketStats.Summary(index, period, classOf, hide, factor, moverClass)
  local st = index and index.stats
  local last = st and st.days[#st.days]
  if not last then
    return nil
  end
  period = period or 7
  local prev = atOrBefore(st.days, last.day - period)
  local lvl = st.index[#st.index]
  local lvlPrev = lvl and atOrBefore(st.index, lvl.day - period)
  local cpi = st.cpi and st.cpi[#st.cpi]
  local cpiPrev = cpi and atOrBefore(st.cpi, cpi.day - period)
  local out = {
    day = last.day,
    level = lvl and lvl.level,
    levelChange = lvlPrev and change(lvlPrev.level, lvl.level),
    cpi = cpi and cpi.level,
    cpiChange = cpiPrev and change(cpiPrev.level, cpi.level),
    cpiBasket = st.cpiBasket,
    cpiWeights = st.cpiWeights,
    value = last.value,
    valueChange = prev and change(prev.value, last.value),
    auctions = last.auctions,
    auctionsChange = prev and change(prev.auctions, last.auctions),
    items = last.items,
    units = last.units,
    capped = last.capped,
    basket = st.basket,
    top = last.top or {},
    turnover = 0,
    up = 0,
    down = 0,
    buy = 0,
    sell = 0,
  }
  factor = (factor and factor > 1) and factor or nil
  local key = CHANGE_KEY[period] or "change7"
  local movers, turnoverBy = {}, {}
  for id, s in pairs(index.items or {}) do
    if not (hide and hide[id]) then
      if s.signal == "buy" then
        out.buy = out.buy + 1
      elseif s.signal == "sell" then
        out.sell = out.sell + 1
      end
      if s.sellRate and s.market then
        local t = soldPerDay(s) * ns.Quote.CapPrice(s, factor)
        out.turnover = out.turnover + t
        bump(turnoverBy, (classOf and classOf(id)) or MarketStats.OTHER, t)
      end
      local c = s[key]
      if c and (s.days or 0) >= st.steadyMin and (s.qty or 0) >= MarketStats.MIN_LISTED then
        if c > 0.0005 then
          out.up = out.up + 1
        elseif c < -0.0005 then
          out.down = out.down + 1
        end
        if not moverClass or ((classOf and classOf(id)) or MarketStats.OTHER) == moverClass then
          movers[#movers + 1] = s
        end
      end
    end
  end
  table.sort(movers, function(a, b)
    if a[key] == b[key] then
      return a.itemID < b.itemID
    end
    return a[key] > b[key]
  end)
  out.risers, out.fallers = {}, {}
  for i = 1, min(5, #movers) do
    if movers[i][key] > 0 then
      out.risers[#out.risers + 1] = movers[i]
    end
    local f = movers[#movers - i + 1]
    if f[key] < 0 then
      out.fallers[#out.fallers + 1] = f
    end
  end
  out.sectors = {}
  for classID, value in pairs(last.cls) do
    out.sectors[#out.sectors + 1] = {
      classID = classID,
      value = value,
      share = last.value > 0 and value / last.value or 0,
      change = prev and change(prev.cls[classID], value),
      turnover = turnoverBy[classID],
    }
  end
  table.sort(out.sectors, function(a, b)
    if a.value == b.value then
      return a.classID < b.classID
    end
    return a.value > b.value
  end)
  local series = { days = {}, value = {}, auctions = {}, levelDays = {}, level = {}, cpiDays = {}, cpi = {} }
  for i, p in ipairs(st.cpi or {}) do
    series.cpiDays[i], series.cpi[i] = p.day, p.level
  end
  for i, d in ipairs(st.days) do
    series.days[i], series.value[i], series.auctions[i] = d.day, d.value, d.auctions
  end
  for i, p in ipairs(st.index) do
    series.levelDays[i], series.level[i] = p.day, p.level
  end
  out.series = series
  return out
end
