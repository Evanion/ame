-- Market analytics over daily series. Pure: no WoW API calls.
--
-- Summarize(series) -> {
--   market, min, qty            latest day's values
--   avg3, avg7, avg14, avg30    mean market over the last 3 / 7 / 14 / 30 points
--   change1, change7, change30  fractional change of market vs 1 / 7 / 30 points earlier (0.1 = +10%)
--   vol30                       stdev of daily log returns over the last 30 points
--   z30                         z-score of today's market vs the last 30 points (mean reversion)
--   trend30                     least-squares slope per day / mean (drift: +0.01 = +1%/day)
--   supplyTrend30               same for quantity
--   sellRate                    estimated units sold per day (supply drain between full scans, last 7 points)
--   scans7                      scans feeding the last 7 points (see Analytics.Confidence)
--   days                        number of points
--   score, signal               opportunity score (higher = cheaper than usual on a stable item) and
--                               "buy" | "hold" | "sell" | "wait" (cheap but dumping) | "none" (not enough history)
--   phase                       price x supply reading (see Analytics.Phase)
-- }
-- Signals are deliberately conservative: they need >= MIN_DAYS of history and a big enough deviation relative to the
-- item's own volatility.
local _, ns = ...
local L = ns.L

local exp, floor, log, max, min, sqrt = math.exp, math.floor, math.log, math.max, math.min, math.sqrt

local Analytics = {}
ns.Analytics = Analytics

Analytics.MIN_DAYS = 7
Analytics.BUY_Z = -1.5
Analytics.SELL_Z = 1.5

local function round(x)
  return floor(x + 0.5)
end

-- mean of values[last-n+1 .. last]
function Analytics.SMA(values, n, last)
  last = last or #values
  if last < n or n <= 0 then
    return nil
  end
  local sum = 0
  for i = last - n + 1, last do
    sum = sum + values[i]
  end
  return sum / n
end

function Analytics.EMASeries(values, n)
  local alpha = 2 / (n + 1)
  local out = {}
  for i, v in ipairs(values) do
    out[i] = i == 1 and v or (alpha * v + (1 - alpha) * out[i - 1])
  end
  return out
end

function Analytics.Change(from, to)
  if not from or not to or from == 0 then
    return nil
  end
  return (to - from) / from
end

local function meanStd(values, first, last)
  local n = last - first + 1
  if n < 1 then
    return nil, nil
  end
  local sum = 0
  for i = first, last do
    sum = sum + values[i]
  end
  local mean = sum / n
  local sq = 0
  for i = first, last do
    sq = sq + (values[i] - mean) ^ 2
  end
  return mean, sqrt(sq / n)
end

-- first, last (optional, here and in ZScore / Trend): a range of values - the market index summarises ~30k items,
-- so no copies and no garbage
function Analytics.Volatility(values, first, last)
  first, last = first or 1, last or #values
  -- the standard deviation of the log returns, in two passes (no table of returns)
  local n, sum = 0, 0
  for i = first + 1, last do
    if values[i - 1] > 0 and values[i] > 0 then
      n, sum = n + 1, sum + log(values[i] / values[i - 1])
    end
  end
  if n < 1 then
    return nil
  end
  local mean, sq = sum / n, 0
  for i = first + 1, last do
    if values[i - 1] > 0 and values[i] > 0 then
      sq = sq + (log(values[i] / values[i - 1]) - mean) ^ 2
    end
  end
  return sqrt(sq / n)
end

function Analytics.ZScore(values, first, last)
  first, last = first or 1, last or #values
  local mean, std = meanStd(values, first, last)
  if not mean then
    return nil
  end
  if std == 0 then
    return 0
  end
  return (values[last] - mean) / std
end

-- least-squares slope per step, divided by the mean (relative drift per step)
function Analytics.Trend(values, first, last)
  first, last = first or 1, last or #values
  local n = last - first + 1
  if n < 2 then
    return nil
  end
  local sx, sy, sxx, sxy = 0, 0, 0, 0
  for i = 1, n do
    local y = values[first + i - 1]
    sx, sy, sxx, sxy = sx + i, sy + y, sxx + i * i, sxy + i * y
  end
  local denom = n * sxx - sx * sx
  local mean = sy / n
  if denom == 0 or mean == 0 then
    return 0
  end
  return ((n * sxy - sx * sy) / denom) / mean
end

-- scratch columns for Summarize, reused (no garbage per item); size: entries in use
local M, Q, size = {}, {}, 0

function Analytics.Summarize(series)
  local n = #series
  if n == 0 then
    return nil
  end
  local markets, qtys = M, Q
  for i = 1, n do
    local p = series[i]
    markets[i], qtys[i] = p.market, p.qty or 0
  end
  for i = n + 1, size do
    markets[i], qtys[i] = nil, nil
  end
  size = n
  local last = series[n]
  local s = {
    market = last.market,
    day = last.day,
    min = last.min,
    qty = last.qty,
    days = n,
    avg3 = round(Analytics.SMA(markets, min(3, n))),
    avg7 = round(Analytics.SMA(markets, min(7, n))),
    avg14 = round(Analytics.SMA(markets, min(14, n))),
    avg30 = round(Analytics.SMA(markets, min(30, n))),
    change1 = n > 1 and Analytics.Change(markets[n - 1], markets[n]) or nil,
    change7 = n > 7 and Analytics.Change(markets[n - 7], markets[n]) or nil,
    change30 = n > 30 and Analytics.Change(markets[n - 30], markets[n]) or nil,
  }
  -- data behind the numbers: scans feeding the last 7 points
  local scans7 = 0
  for k = math.max(1, n - 6), n do
    scans7 = scans7 + (series[k].scans or 1)
  end
  s.scans7 = scans7
  -- liquidity: units gone between consecutive full scans over the last 7 points, per day observed
  local drained, observed = 0, 0
  for k = math.max(1, n - 6), n do
    drained, observed = drained + (series[k].drain or 0), observed + (series[k].obs or 0)
  end
  if observed >= 120 then -- at least two hours of scan pairs
    s.sellRate = drained / (observed / 1440)
  end
  local from = max(1, n - 29) -- the last 30
  s.vol30 = Analytics.Volatility(markets, from, n)
  s.z30 = Analytics.ZScore(markets, from, n)
  s.trend30 = Analytics.Trend(markets, from, n)
  s.supplyTrend30 = Analytics.Trend(qtys, from, n)

  -- opportunity score: how far below its usual price an item is (negative z), damped for volatile items, nudged by
  -- a rising trend. Squashed to (-100, 100) so it sorts nicely in the screener.
  local z = s.z30 or 0
  local volPenalty = 1 / (1 + 10 * (s.vol30 or 0))
  -- the trend only nudges (capped), so an item far above its usual price never scores as a bargain
  local trendTerm = math.max(-0.25, math.min(0.25, 5 * (s.trend30 or 0)))
  s.phase = Analytics.Phase(series)
  local raw = -z * volPenalty + trendTerm + (Analytics.PHASE_SCORE[s.phase] or 0)
  s.score = round(100 * (2 / (1 + exp(-raw)) - 1))

  -- buy: unusually cheap for this item; sell: unusually expensive; hold: within its normal range (keep it if you
  -- own it, no edge to buy); none: too little history to judge
  s.signal = "none"
  if n >= Analytics.MIN_DAYS and s.z30 then
    if z <= Analytics.BUY_Z then
      s.signal = "buy"
    elseif z >= Analytics.SELL_Z then
      s.signal = "sell"
    else
      s.signal = "hold"
    end
    -- cheap but sellers are dumping: wait for the bottom instead of catching a falling knife
    if s.signal == "buy" and s.phase == "dumping" then
      s.signal = "wait"
    end
  end
  s.signalRank = Analytics.SIGNAL_RANK[s.signal]
  return s
end

-- sort order for signals: sell first (act on it), then buy, hold, wait, and no signal last
Analytics.SIGNAL_RANK = { sell = 1, buy = 2, hold = 3, wait = 4, vendor = 5, disenchant = 6, none = 7 }

-- What one listing nets: market price after the AH cut, minus the listing deposit - counted as lost (the risk you
-- take) unless the item's sell-through says how often it sells (SellThrough.Net).
local function listingNet(s, cut, deposit)
  if ns.SellThrough then
    return ns.SellThrough.Net(s, cut, deposit)
  end
  return s.market * (1 - (cut or 0)) - (deposit or 0)
end

-- VENDOR: the auction house pays less than a vendor: what a listing nets is below the vendor's price. Overrides the
-- price signal: whatever the trend, the vendor is the better deal. s gets vendorPrice / vendorNet.
function Analytics.VendorCheck(s, vendorPrice, cut, deposit)
  if not (s and s.market and vendorPrice and vendorPrice > 0) then
    return false
  end
  local net = listingNet(s, cut, deposit)
  if net >= vendorPrice then
    return false
  end
  s.signal, s.signalRank = "vendor", Analytics.SIGNAL_RANK.vendor
  s.vendorPrice, s.vendorNet = vendorPrice, net
  return true
end

-- DE (disenchant): the item's expected enchanting materials (Disenchant.Value, at what selling them nets) are worth
-- more than what listing the item nets and than what a vendor pays. Overrides the price signal (and VENDOR, when
-- disenchanting beats the vendor too). s gets deValue (and vendorNet: what listing nets).
function Analytics.DisenchantCheck(s, deValue, cut, deposit)
  if not (s and s.market and deValue and deValue > 0) then
    return false
  end
  local net = listingNet(s, cut, deposit)
  if deValue <= net or deValue <= (s.vendorPrice or 0) then
    return false
  end
  s.signal, s.signalRank = "disenchant", Analytics.SIGNAL_RANK.disenchant
  s.deValue, s.vendorNet = deValue, net
  return true
end

-- Market phase: the price trend read against the supply trend over the last week of data.
--                 supply shrinking      flat              growing
--   price up      shortage              demand            piling   (sellers piling in at high prices)
--   price flat    tightening            balanced          pressure (supply building up)
--   price down    withdrawing           weak              dumping
-- nil with too little data. Price moves count beyond +-5% a week, supply beyond +-10%.
Analytics.PRICE_MOVE = 0.05
Analytics.SUPPLY_MOVE = 0.10
Analytics.PHASES = {
  up = { down = "shortage", flat = "demand", up = "piling" },
  flat = { down = "tightening", flat = "balanced", up = "pressure" },
  down = { down = "withdrawing", flat = "weak", up = "dumping" },
}
-- nudges to the opportunity score (raw, before squashing)
Analytics.PHASE_SCORE = {
  withdrawing = 0.15,
  tightening = 0.1,
  shortage = 0.1,
  piling = -0.15,
  pressure = -0.1,
  dumping = -0.2,
}
Analytics.PHASE_LABEL = {
  shortage = L["Shortage"],
  demand = L["Steady demand"],
  piling = L["Sellers piling in"],
  tightening = L["Tightening"],
  balanced = L["Balanced"],
  pressure = L["Pressure building"],
  withdrawing = L["Sellers withdrawing"],
  weak = L["Weak demand"],
  dumping = L["Dumping"],
}

local function bitsIn(mask)
  local c = 0
  while mask and mask > 0 do
    c, mask = c + mask % 2, math.floor(mask / 2)
  end
  return c
end

-- The newest day just after midnight UTC holds only a few night-time scans: thinner supply and often lower prices
-- than the full days before it, which reads as "sellers withdrawing". Leave that day out while it has sampled fewer
-- than half the hours of the best earlier day in the window (a player who scans once a day keeps every day).
local function partialLastDay(series, n, from)
  local last = bitsIn(series[n].hours)
  if last == 0 then
    return false
  end
  local best = 0
  for k = from, n - 1 do
    best = math.max(best, bitsIn(series[k].hours))
  end
  return last * 2 < best
end

local P = {} -- scratch: Phase's supply column (at most 7)
function Analytics.Phase(series)
  local n = #series
  if n >= 2 and partialLastDay(series, n, math.max(1, n - 7)) then
    n = n - 1
  end
  if n < 4 then
    return nil
  end
  local from = math.max(1, n - 6)
  local qtys, count = P, n - from + 1
  for k = from, n do
    qtys[k - from + 1] = series[k].qty or 0
  end
  local price = Analytics.Change(series[from].market, series[n].market)
  local supply = (Analytics.Trend(qtys, 1, count) or 0) * count
  if not price then
    return nil
  end
  local function dir(x, band)
    return x > band and "up" or x < -band and "down" or "flat"
  end
  return Analytics.PHASES[dir(price, Analytics.PRICE_MOVE)][dir(supply, Analytics.SUPPLY_MOVE)]
end

-- Candles from the daily/weekly series, grouping periodDays days per candle. The store keeps daily aggregates, not
-- intraday prices, so a candle is: open = previous candle's close (the first candle opens at its first price),
-- close = last market price in the period,
-- high = highest price seen (the recorded daily high, else the highest market price; at least the open),
-- low = cheapest listing seen (the "min" price).
-- Returns { xs, open, high, low, close, period } with xs at the middle of each period (seconds).
-- unit: seconds per "day" step of the series (default a day; 3600 for hourly points built from scans)
function Analytics.Candles(series, periodDays, unit)
  local DAY = unit or 86400
  periodDays = math.max(1, math.floor(periodDays or 1))
  local out = { xs = {}, open = {}, high = {}, low = {}, close = {}, period = periodDays * DAY }
  local prevClose
  local i = 1
  while i <= #series do
    local group = math.floor(series[i].day / periodDays)
    local hi, lo, close, first = -math.huge, math.huge, nil, nil
    local j = i
    while j <= #series and math.floor(series[j].day / periodDays) == group do
      local p = series[j]
      local m = p.market or p.min
      if m then
        first = first or m
        close = m
        hi = math.max(hi, m, p.high or 0) -- the day's highest price seen, when recorded
        lo = math.min(lo, p.min or m, m)
      end
      j = j + 1
    end
    if close then
      local open = prevClose or first
      local n = #out.xs + 1
      out.xs[n] = (group * periodDays + periodDays / 2) * DAY
      out.open[n], out.close[n] = open, close
      out.high[n] = math.max(hi, open)
      out.low[n] = math.min(lo, open, close)
      prevClose = close
    end
    i = j
  end
  return out
end

-- Outlier days: a day whose market price is more than `factor` times above (or below) the median of the item's
-- neighbouring days (up to 7 either side) is treated as a bad print - typically one wildly overpriced listing in a
-- thin market. Needs at least 3 neighbours to judge. Returns the series without those days and how many were
-- dropped. factor nil/false/<= 1 disables.
Analytics.OUTLIER_NEIGHBOURS = 7

-- the median of a point's neighbours' markets (nil with fewer than 3), sorted in a reused buffer: the market index
-- cleans ~30k items, and a table per point kept the garbage collector stalling the game
local around = {}
local function neighbourMedian(series, i, k)
  local n = 0
  for j = max(1, i - k), min(#series, i + k) do
    local m = j ~= i and series[j].market
    if m then
      n = n + 1
      around[n] = m
    end
  end
  if n < 3 then
    return nil
  end
  for a = 2, n do -- insertion sort: at most 2k values
    local v, b = around[a], a - 1
    while b >= 1 and around[b] > v do
      around[b + 1] = around[b]
      b = b - 1
    end
    around[b + 1] = v
  end
  if n % 2 == 1 then
    return around[(n + 1) / 2]
  end
  return (around[n / 2] + around[n / 2 + 1]) / 2
end

-- the series without its outlier points: the series itself (not a copy) when none is dropped
function Analytics.Clean(series, factor)
  if not factor or factor <= 1 or #series < 4 then
    return series, 0
  end
  local out, dropped = nil, 0
  local k = Analytics.OUTLIER_NEIGHBOURS
  for i = 1, #series do
    local p = series[i]
    local m = p.market and neighbourMedian(series, i, k)
    if m and m > 0 and (p.market > m * factor or p.market < m / factor) then
      if not out then
        out = {}
        for j = 1, i - 1 do
          out[j] = series[j]
        end
      end
      dropped = dropped + 1
    elseif out then
      out[#out + 1] = p
    end
  end
  return out or series, dropped
end

-- How much to trust an item's numbers: "high" (6+ scans in its last week of data, seen within a day, a week of
-- history), "medium" (2+ scans, seen within 3 days), else "low". today: day number.
function Analytics.Confidence(s, today)
  if not s then
    return "low"
  end
  local age = today and s.day and (today - s.day) or 0
  if (s.scans7 or 0) >= 6 and age <= 1 and (s.days or 0) >= 7 then
    return "high"
  elseif (s.scans7 or 0) >= 2 and age <= 3 then
    return "medium"
  end
  return "low"
end
