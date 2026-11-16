-- Per-item statistics for one auction house scan. Pure: no WoW API calls.
--
-- Usage:
--   local acc = ns.Stats.NewAccumulator()
--   acc:Add(itemID, buyoutPrice, count)   -- once per listing
--   local snap = acc:Finish()
--   -- snap = { ids = {...sorted}, min = {...}, market = {...}, median = {...}, qty = {...}, auctions = {...},
--   --          skipped = <bid-only listings> }   (columnar, parallel arrays, integer copper)
--
-- market: quantity-weighted mean of the cheapest supply. Always the cheapest 15% of units; continue up to 30% while
-- each unit price is within 1.2x of the previous one. Then listings outside [0.5x, 1.5x] of that mean are dropped
-- (a lone undercut or a wishful tail) and the mean is recomputed.
local _, ns = ...

local floor = math.floor
local sort = table.sort

local Stats = {}
ns.Stats = Stats

Stats.MARKET_MIN_SHARE = 0.15
Stats.MARKET_MAX_SHARE = 0.30
Stats.MARKET_STEP = 1.2
Stats.MARKET_TRIM_LOW = 0.5
Stats.MARKET_TRIM_HIGH = 1.5

local function round(x)
  return floor(x + 0.5)
end

local Accumulator = {}
Accumulator.__index = Accumulator

function Stats.NewAccumulator()
  return setmetatable({ items = {}, skipped = 0 }, Accumulator)
end

function Accumulator:Add(itemID, buyout, count)
  if not buyout or buyout <= 0 then
    self.skipped = self.skipped + 1
    return
  end
  if not count or count <= 0 then
    count = 1
  end
  local e = self.items[itemID]
  if not e then
    e = { units = {}, counts = {}, n = 0 }
    self.items[itemID] = e
  end
  local n = e.n + 1
  e.n = n
  e.units[n] = buyout / count
  e.counts[n] = count
end

-- weighted mean of entries order[from..to] (by index into units/counts), optionally filtered to [lo, hi]
local function weightedMean(units, counts, order, last, lo, hi)
  local sum, qty = 0, 0
  for k = 1, last do
    local j = order[k]
    local u = units[j]
    if not lo or (u >= lo and u <= hi) then
      sum = sum + u * counts[j]
      qty = qty + counts[j]
    end
  end
  if qty == 0 then
    return nil
  end
  return sum / qty
end

local function summarize(e)
  local units, counts, n = e.units, e.counts, e.n
  local order = {}
  local total = 0
  for j = 1, n do
    order[j] = j
    total = total + counts[j]
  end
  sort(order, function(a, b)
    return units[a] < units[b]
  end)

  -- median and market window in one walk
  local half = total / 2
  local minShare, maxShare = total * Stats.MARKET_MIN_SHARE, total * Stats.MARKET_MAX_SHARE
  local median
  local last = 0 -- market window = order[1..last]
  local cum = 0
  local prev
  for k = 1, n do
    local j = order[k]
    local u = units[j]
    if last == k - 1 then
      if cum < minShare or (cum < maxShare and prev and u <= prev * Stats.MARKET_STEP) then
        last = k
      end
    end
    cum = cum + counts[j]
    if not median and cum >= half then
      median = u
    end
    prev = u
  end

  local mean = weightedMean(units, counts, order, last)
  local trimmed = weightedMean(units, counts, order, last, mean * Stats.MARKET_TRIM_LOW, mean * Stats.MARKET_TRIM_HIGH)

  return round(units[order[1]]), round(trimmed or mean), round(median), total, n
end

function Accumulator:Finish()
  local ids = {}
  for id in pairs(self.items) do
    ids[#ids + 1] = id
  end
  sort(ids)
  local snap = { ids = ids, min = {}, market = {}, median = {}, qty = {}, auctions = {}, skipped = self.skipped }
  for i, id in ipairs(ids) do
    snap.min[i], snap.market[i], snap.median[i], snap.qty[i], snap.auctions[i] = summarize(self.items[id])
  end
  return snap
end
