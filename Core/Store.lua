-- Per-shard price history. Pure: no WoW API calls; clock and compressor are injected.
--
--   local store = ns.Store.New(data, { compressor = c, now = function() return serverTime end })
--   store:AddScan(snapshot, t, src)        -- snapshot from Stats (columnar); t = server time; src = scanner name
--   store:Latest(itemID)                   -- newest raw-scan stats (+ t, src) or nil
--   store:Series(itemID, fromDay, toDay)   -- daily/weekly points, oldest first
--
-- Persisted layout (data is the shard's SavedVariables table; everything below is plain strings/numbers):
--   data.raw   = { { t =, src =, s = packed snapshot }, ... }  sorted by t; kept RAW_KEEP seconds (Latest, sync)
--   data.days  = { [day] = { [bucket] = packed segment } }     day = floor(t / 86400) (UTC)
--   data.weeks = { [week] = { [bucket] = packed segment } }    week = floor(day / 7); days older than DAYS_KEEP
--   data.seen  = { [day] = { ["t:src"] = true } }               scans already merged into that day (dedupe)
--
-- Segments hold running SUMS (market, median, qty, auctions), the min, and the scan count per item, so merging a
-- scan is an incremental add: closed days never need their raw scans again, and late arrivals (sync) merge exactly.
-- Means are computed on read.
local _, ns = ...

local floor, min = math.floor, math.min
local sort = table.sort

local Codec = ns.Codec

local Store = {}
Store.__index = Store
ns.Store = Store

Store.DAY = 86400
Store.BUCKETS = 32
Store.RAW_KEEP = 48 * 3600
Store.DAYS_KEEP = 180
Store.CACHE_SIZE = 96

-- hours: bitmask of UTC hours already sampled for that item that day (0 in weekly segments)
Store.SEGMENT_FIELDS = { "ids", "min", "market", "median", "qty", "auctions", "scans", "hours" }
local SUMMED = { "market", "median", "qty", "auctions" }

local function round(x)
  return floor(x + 0.5)
end

function Store.New(data, opts)
  assert(opts and opts.compressor and opts.now, "Store.New(data, { compressor, now })")
  data.raw = data.raw or {}
  data.days = data.days or {}
  data.weeks = data.weeks or {}
  data.seen = data.seen or {}
  return setmetatable({
    data = data,
    compressor = opts.compressor,
    now = opts.now,
    -- called between buckets; pass coroutine.yield to time-slice a full scan across frames
    yield = opts.yield or function() end,
    cache = {}, -- packed string -> decoded segment
    cacheOrder = {},
  }, Store)
end

---------------------------------------------------------------------------------------------------------------------
-- segment helpers

local function emptySegment()
  return { ids = {}, min = {}, market = {}, median = {}, qty = {}, auctions = {}, scans = {}, hours = {} }
end

function Store:decode(packed, fields)
  local hit = self.cache[packed]
  if hit then
    return hit
  end
  local cols = Codec.Decode(fields, Codec.Unpack(packed, self.compressor))
  -- simple FIFO-bounded cache; segments are immutable values keyed by their packed string
  local order = self.cacheOrder
  order[#order + 1] = packed
  self.cache[packed] = cols
  if #order > Store.CACHE_SIZE then
    self.cache[table.remove(order, 1)] = nil
  end
  return cols
end

function Store:encode(cols, fields)
  return Codec.Pack(Codec.Encode(fields, cols), self.compressor)
end

-- binary search in a sorted id column
local function find(ids, id)
  local lo, hi = 1, #ids
  while lo <= hi do
    local mid = floor((lo + hi) / 2)
    local v = ids[mid]
    if v == id then
      return mid
    elseif v < id then
      lo = mid + 1
    else
      hi = mid - 1
    end
  end
end

-- is `slot` (a power of two) set in mask? (Lua 5.1 has no bit ops outside WoW; masks stay < 2^24)
local function hasSlot(mask, slot)
  return floor(mask / slot) % 2 == 1
end

-- Merge rows into a segment (both sorted by id). rows: list of
--   { id, min, market, median, qty, auctions, scans, slot }
-- where market..auctions are sums and slot is the sample's hour bit (2^hour) or 0 for "no slot check" (weekly
-- folds). A row whose hour slot is already taken only lowers min: one sample per item per hour feeds the means, so
-- repeated searches of the same item can't skew the day. Returns a new segment.
local function mergeRows(seg, rows)
  local out = emptySegment()
  local i, j, n = 1, 1, 0
  local sids = seg.ids
  while i <= #sids or j <= #rows do
    local a, r = sids[i], rows[j]
    n = n + 1
    if r and (not a or r[1] < a) then
      out.ids[n], out.min[n], out.market[n], out.median[n] = r[1], r[2], r[3], r[4]
      out.qty[n], out.auctions[n], out.scans[n], out.hours[n] = r[5], r[6], r[7], r[8]
      j = j + 1
    elseif not r or a < r[1] then
      out.ids[n], out.min[n], out.market[n], out.median[n] = a, seg.min[i], seg.market[i], seg.median[i]
      out.qty[n], out.auctions[n], out.scans[n], out.hours[n] = seg.qty[i], seg.auctions[i], seg.scans[i], seg.hours[i]
      i = i + 1
    elseif r[8] ~= 0 and hasSlot(seg.hours[i], r[8]) then -- same id, hour already sampled: only min
      out.ids[n], out.min[n], out.market[n], out.median[n] = a, min(seg.min[i], r[2]), seg.market[i], seg.median[i]
      out.qty[n], out.auctions[n], out.scans[n], out.hours[n] = seg.qty[i], seg.auctions[i], seg.scans[i], seg.hours[i]
      i, j = i + 1, j + 1
    else -- same id: add
      out.ids[n], out.min[n] = a, min(seg.min[i], r[2])
      out.market[n], out.median[n] = seg.market[i] + r[3], seg.median[i] + r[4]
      out.qty[n], out.auctions[n], out.scans[n] = seg.qty[i] + r[5], seg.auctions[i] + r[6], seg.scans[i] + r[7]
      out.hours[n] = seg.hours[i] + r[8]
      i, j = i + 1, j + 1
    end
  end
  return out
end

-- Merge per-bucket row lists into a tier table ({ [bucket] = packed }).
function Store:mergeInto(tier, rowsByBucket)
  for b, rows in pairs(rowsByBucket) do
    sort(rows, function(x, y)
      return x[1] < y[1]
    end)
    local seg = tier[b] and self:decode(tier[b], Store.SEGMENT_FIELDS) or emptySegment()
    tier[b] = self:encode(mergeRows(seg, rows), Store.SEGMENT_FIELDS)
    self.yield()
  end
end

---------------------------------------------------------------------------------------------------------------------
-- writes

-- kind: "full" (replicate scan, default) or "partial" (search / sell-tab results for a few items)
function Store:AddScan(snap, t, src, kind)
  kind = kind or "full"
  local data = self.data
  local day = floor(t / Store.DAY)
  local ids = snap.ids
  -- dedupe key includes the content's shape, so several partial searches in the same second don't collide
  local key = ("%d:%s:%s:%d:%s:%s"):format(t, tostring(src), kind, #ids, tostring(ids[1]), tostring(ids[#ids]))
  local seen = data.seen[day]
  if seen and seen[key] then
    return false
  end

  -- raw tier (sorted by t)
  local raw = data.raw
  local entry = { t = t, src = src, k = kind, s = Codec.Pack(Codec.EncodeSnapshot(snap), self.compressor) }
  local pos = #raw + 1
  while pos > 1 and raw[pos - 1].t > t do
    pos = pos - 1
  end
  table.insert(raw, pos, entry)

  -- merge into the day
  local slot = 2 ^ floor((t % Store.DAY) / 3600)
  local byBucket = {}
  for i, id in ipairs(ids) do
    local b = id % Store.BUCKETS
    local rows = byBucket[b]
    if not rows then
      rows = {}
      byBucket[b] = rows
    end
    rows[#rows + 1] = { id, snap.min[i], snap.market[i], snap.median[i], snap.qty[i], snap.auctions[i], 1, slot }
  end
  data.days[day] = data.days[day] or {}
  self:mergeInto(data.days[day], byBucket)
  data.seen[day] = seen or {}
  data.seen[day][key] = true

  self:Rollup()
  return true
end

-- Retention: prune raw scans, fold old days into weeks. Safe to call any time.
function Store:Rollup()
  local data = self.data
  local now = self.now()

  local cutoff = now - Store.RAW_KEEP
  local raw = data.raw
  local keep = 1
  while raw[keep] and raw[keep].t < cutoff do
    keep = keep + 1
  end
  if keep > 1 then
    for _ = 1, keep - 1 do
      table.remove(raw, 1)
    end
  end

  -- a week is compacted once its last day is older than DAYS_KEEP
  local today = floor(now / Store.DAY)
  local weeks = {}
  for day in pairs(data.days) do
    local week = floor(day / 7)
    if week * 7 + 6 < today - Store.DAYS_KEEP then
      weeks[week] = true
    end
  end
  for week in pairs(weeks) do
    local byBucket = {}
    for day = week * 7, week * 7 + 6 do
      local buckets = data.days[day]
      if buckets then
        for b, packed in pairs(buckets) do
          local seg = self:decode(packed, Store.SEGMENT_FIELDS)
          local rows = byBucket[b] or {}
          byBucket[b] = rows
          for i, id in ipairs(seg.ids) do
            rows[#rows + 1] = {
              id,
              seg.min[i],
              seg.market[i],
              seg.median[i],
              seg.qty[i],
              seg.auctions[i],
              seg.scans[i],
              0,
            }
          end
        end
        data.days[day] = nil
        data.seen[day] = nil
      end
    end
    -- rows may contain the same id several times (one per day); merge them one day at a time via mergeRows
    data.weeks[week] = data.weeks[week] or {}
    for b, rows in pairs(byBucket) do
      sort(rows, function(x, y)
        return x[1] < y[1]
      end)
      local seg = data.weeks[week][b] and self:decode(data.weeks[week][b], Store.SEGMENT_FIELDS) or emptySegment()
      local run, last = {}, nil
      for _, r in ipairs(rows) do
        if last and r[1] == last[1] then
          last[2] = min(last[2], r[2])
          for k = 3, 7 do
            last[k] = last[k] + r[k]
          end
        else
          last = { r[1], r[2], r[3], r[4], r[5], r[6], r[7], 0 }
          run[#run + 1] = last
        end
      end
      data.weeks[week][b] = self:encode(mergeRows(seg, run), Store.SEGMENT_FIELDS)
    end
  end
end

---------------------------------------------------------------------------------------------------------------------
-- reads

local function point(seg, i, res, period)
  local scans = seg.scans[i]
  local p = {
    res = res,
    min = seg.min[i],
    scans = scans,
  }
  for _, f in ipairs(SUMMED) do
    p[f] = round(seg[f][i] / scans)
  end
  if res == "week" then
    p.week, p.day = period, period * 7
  else
    p.day = period
  end
  return p
end

function Store:Series(itemID, fromDay, toDay)
  fromDay, toDay = fromDay or -math.huge, toDay or math.huge
  local b = itemID % Store.BUCKETS
  local out = {}
  for week, buckets in pairs(self.data.weeks) do
    local first = week * 7
    if buckets[b] and first + 6 >= fromDay and first <= toDay then
      local seg = self:decode(buckets[b], Store.SEGMENT_FIELDS)
      local i = find(seg.ids, itemID)
      if i then
        out[#out + 1] = point(seg, i, "week", week)
      end
    end
  end
  for day, buckets in pairs(self.data.days) do
    if buckets[b] and day >= fromDay and day <= toDay then
      local seg = self:decode(buckets[b], Store.SEGMENT_FIELDS)
      local i = find(seg.ids, itemID)
      if i then
        out[#out + 1] = point(seg, i, "day", day)
      end
    end
  end
  sort(out, function(x, y)
    return x.day < y.day
  end)
  return out
end

function Store:Latest(itemID)
  local raw = self.data.raw
  for k = #raw, 1, -1 do
    local e = raw[k]
    local snap = self:decode(e.s, Codec.SNAPSHOT_FIELDS)
    local i = find(snap.ids, itemID)
    if i then
      return {
        t = e.t,
        src = e.src,
        min = snap.min[i],
        market = snap.market[i],
        median = snap.median[i],
        qty = snap.qty[i],
        auctions = snap.auctions[i],
      }
    end
  end
end
