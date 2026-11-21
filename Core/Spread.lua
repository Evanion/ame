-- How far each item's market price sits above its cheapest listing, so a summary scan doesn't drag the market down.
--
-- A summary scan (Auctionator's default Full Scan pages the browse list) only knows each item's lowest price, so it
-- used to record that as the market price too: the market line, signals and posting prices leaned to the single
-- cheapest copy, and candles lost their lower wicks. Scans that see every listing (replicate full scans, searches)
-- teach each item's spread: market / cheapest. A summary scan's market is then its cheapest x that spread (at most
-- MAX), and the cheapest stays what it was - the wick.
--
--   db = AME_DB.spread[shard] = { [itemKey] = spread x 100 (only when >= 102) }
local _, ns = ...

local Spread = {}
ns.Spread = Spread

Spread.MAX = 1.5 -- like the market price's own trim: listings past 1.5x aren't the market
Spread.KEEP = 1.02 -- closer than this to the cheapest: not kept (the market is the cheapest)
Spread.WEIGHT = 0.5 -- a new reading's share of the kept spread
Spread.SUMMARY_SHARE = 0.98 -- a scan where this share of items has market == cheapest is a summary scan
Spread.SUMMARY_MIN = 50 -- ... with at least this many items

-- Is a snapshot a summary (cheapest price only)? Own browse scans say so; scans from others are recognised by every
-- item's market being its cheapest.
function Spread.IsSummary(snap)
  local n = #snap.ids
  if n < Spread.SUMMARY_MIN then
    return false
  end
  local same = 0
  for i = 1, n do
    if snap.market[i] == snap.min[i] then
      same = same + 1
    end
  end
  return same >= n * Spread.SUMMARY_SHARE
end

-- learn from a snapshot that saw every listing
function Spread.Learn(db, snap)
  for i, id in ipairs(snap.ids) do
    local lo, m = snap.min[i], snap.market[i]
    if lo and m and lo > 0 and m >= lo then
      local r = math.min(m / lo, Spread.MAX)
      local old = db[id] and db[id] / 100 or 1
      local v = old + (r - old) * Spread.WEIGHT
      db[id] = v >= Spread.KEEP and math.floor(v * 100 + 0.5) or nil
    end
  end
end

-- a summary snapshot's market (and median) from its cheapest and the item's spread; returns how many it raised
function Spread.Apply(db, snap)
  local n = 0
  for i, id in ipairs(snap.ids) do
    local s = db[id]
    local lo = snap.min[i]
    if s and lo and lo > 0 then
      local m = math.floor(lo * math.min(s / 100, Spread.MAX) + 0.5)
      if m > snap.market[i] then
        snap.market[i] = m
        snap.median[i] = math.max(snap.median[i] or 0, m)
        n = n + 1
      end
    end
  end
  return n
end

-- in game: a shard's spreads (AME_DB.spread)
function Spread.For(shard)
  AME_DB.spread = AME_DB.spread or {}
  AME_DB.spread[shard] = AME_DB.spread[shard] or {}
  return AME_DB.spread[shard]
end

-- a snapshot on its way into the store: summary -> market from the spread; otherwise it teaches the spread
function Spread.Take(shard, snap, summary)
  if summary == nil then
    summary = Spread.IsSummary(snap)
  end
  local db = Spread.For(shard)
  if summary then
    return Spread.Apply(db, snap)
  end
  Spread.Learn(db, snap)
  return 0
end
