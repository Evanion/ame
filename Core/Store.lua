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
--   data.weeks = { [week] = { [bucket] = packed segment } }    week = floor(day / 7); days older than DAYS_KEEP,
--                                                              kept WEEKS_KEEP weeks
--   data.seen  = { [day] = { ["t:src"] = true } }               scans already merged into that day (dedupe)
--
-- Segments hold running SUMS (market, median, qty, auctions), the min, and the scan count per item, so merging a
-- scan is an incremental add: closed days never need their raw scans again, and late arrivals (sync) merge exactly.
-- Means are computed on read.
local _, ns = ...

local floor, max, min = math.floor, math.max, math.min
local sort = table.sort

local Codec = ns.Codec

local Store = {}
Store.__index = Store
ns.Store = Store

Store.DAY = 86400
Store.BUCKETS = 32
Store.RAW_KEEP = 48 * 3600
Store.DAYS_KEEP = 60 -- daily points; older ones fold into weeks (analysis uses 30 days)
Store.WEEKS_KEEP = 52 -- weekly points older than this are dropped
Store.CACHE_SIZE = 96

-- hours: bitmask of UTC hours already sampled for that item that day (0 in weekly segments)
-- high: the highest single market price seen in the period (the upper candle wick); 0 = unknown. Added later, so
-- older segments decode without it.
-- drain / obs (liquidity): units that disappeared between consecutive full scans of this house (sold, cancelled or
-- expired) and the minutes those scan pairs covered; their ratio is the sell rate. Also added later.
Store.SEGMENT_FIELDS = { "ids", "min", "market", "median", "qty", "auctions", "scans", "hours", "high", "drain", "obs" }
Store.DRAIN_WINDOW = 12 * 3600 -- pair a full scan with the previous one up to this much older
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
  data.books = data.books or {}
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
  return {
    ids = {},
    min = {},
    market = {},
    median = {},
    qty = {},
    auctions = {},
    scans = {},
    hours = {},
    high = {},
    drain = {},
    obs = {},
  }
end

-- Give the frame back between steps - only inside a background job: queries like Series also run from slash commands
-- on the main thread, where yielding is an error, possibly while another job has set the yield hook.
function Store:pause()
  if coroutine.running() then
    self.yield()
  end
end

function Store:decode(packed, fields)
  local hit = self.cache[packed]
  if hit then
    return hit
  end
  local cols = Codec.Decode(fields, self:unpack(packed), true)
  -- simple FIFO-bounded cache; segments are immutable values keyed by their packed string
  local order = self.cacheOrder
  order[#order + 1] = packed
  self.cache[packed] = cols
  if #order > Store.CACHE_SIZE then
    self.cache[table.remove(order, 1)] = nil
  end
  return cols
end

-- Decompressing is most of a market index build (~2.5 s of ~4 s for 30 days of one house), and closed days never
-- change. KeepTexts(true) keeps the decompressed text of every segment the next build reads (~8 MB per house) and
-- hands it to the build after that; KeepTexts(false) frees it. Keyed by the packed string, so it can't go stale: a
-- changed segment is a different string.
function Store:KeepTexts(on)
  self.texts = on and { old = self.texts and self.texts.new or {}, new = {} } or nil
end

function Store:unpack(packed)
  local texts = self.texts
  if not texts then
    return Codec.Unpack(packed, self.compressor)
  end
  local text = texts.new[packed] or texts.old[packed] or Codec.Unpack(packed, self.compressor)
  texts.new[packed] = text
  return text
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
--   { id, min, market, median, qty, auctions, scans, slot, high, drain, obs }
-- or a drain-only row { id, drainOnly = true, [10] = drain, [11] = obs } for an item that vanished from the AH:
-- it only adds liquidity to a row the segment already has.
-- where market..auctions are sums and slot is the sample's hour bit (2^hour) or 0 for "no slot check" (weekly
-- folds). A row whose hour slot is already taken only lowers min: one sample per item per hour feeds the means, so
-- repeated searches of the same item can't skew the day. Returns a new segment.
local function mergeRows(seg, rows)
  local out = emptySegment()
  local i, j, n = 1, 1, 0
  local sids = seg.ids
  local sh, sd, so = seg.high or {}, seg.drain or {}, seg.obs or {}
  local function copySeg(k)
    out.ids[n], out.min[n], out.market[n], out.median[n] = sids[k], seg.min[k], seg.market[k], seg.median[k]
    out.qty[n], out.auctions[n], out.scans[n], out.hours[n] = seg.qty[k], seg.auctions[k], seg.scans[k], seg.hours[k]
    out.high[n], out.drain[n], out.obs[n] = sh[k] or 0, sd[k] or 0, so[k] or 0
  end
  while i <= #sids or j <= #rows do
    local a, r = sids[i], rows[j]
    n = n + 1
    if r and (not a or r[1] < a) then
      if r.drainOnly then -- nothing to add liquidity to
        n = n - 1
      else
        out.ids[n], out.min[n], out.market[n], out.median[n] = r[1], r[2], r[3], r[4]
        out.qty[n], out.auctions[n], out.scans[n], out.hours[n] = r[5], r[6], r[7], r[8]
        out.high[n], out.drain[n], out.obs[n] = r[9] or 0, r[10] or 0, r[11] or 0
      end
      j = j + 1
    elseif not r or a < r[1] then
      copySeg(i)
      i = i + 1
    elseif r.drainOnly then
      copySeg(i)
      out.drain[n], out.obs[n] = out.drain[n] + (r[10] or 0), out.obs[n] + (r[11] or 0)
      i, j = i + 1, j + 1
    elseif r[8] ~= 0 and hasSlot(seg.hours[i], r[8]) then -- same id, hour already sampled: only min
      out.ids[n], out.min[n], out.market[n], out.median[n] = a, min(seg.min[i], r[2]), seg.market[i], seg.median[i]
      out.qty[n], out.auctions[n], out.scans[n], out.hours[n] = seg.qty[i], seg.auctions[i], seg.scans[i], seg.hours[i]
      out.high[n] = max(sh[i] or 0, r[9] or 0)
      out.drain[n], out.obs[n] = (sd[i] or 0) + (r[10] or 0), (so[i] or 0) + (r[11] or 0)
      i, j = i + 1, j + 1
    else -- same id: add
      out.ids[n], out.min[n] = a, min(seg.min[i], r[2])
      out.market[n], out.median[n] = seg.market[i] + r[3], seg.median[i] + r[4]
      out.qty[n], out.auctions[n], out.scans[n] = seg.qty[i] + r[5], seg.auctions[i] + r[6], seg.scans[i] + r[7]
      out.hours[n] = seg.hours[i] + r[8]
      out.high[n] = max(sh[i] or 0, r[9] or 0)
      out.drain[n], out.obs[n] = (sd[i] or 0) + (r[10] or 0), (so[i] or 0) + (r[11] or 0)
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
    self:pause()
  end
end

---------------------------------------------------------------------------------------------------------------------
-- writes

-- kind: "full" (replicate scan, default) or "partial" (search / sell-tab results for a few items)
-- packed (optional): the snapshot already compressed (a scan received over sync), stored as is.
function Store:AddScan(snap, t, src, kind, packed)
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
  -- compressing a full scan takes ~100 ms in one go (inside LibDeflate); yield around it so nothing else piles on
  if not packed then
    local text = Codec.EncodeSnapshot(snap)
    self:pause()
    packed = Codec.Pack(text, self.compressor)
    self:pause()
  end
  local entry = { t = t, src = src, k = kind, s = packed }
  local pos = #raw + 1
  while pos > 1 and raw[pos - 1].t > t do
    pos = pos - 1
  end
  table.insert(raw, pos, entry)
  local prevQty, obs = nil, 0
  if kind == "full" then
    prevQty, obs = self:previousFull(pos)
    self:pause()
    -- the next full scan pairs with this one: remember its quantities instead of decompressing it again
    local qty = {}
    for i, id in ipairs(ids) do
      qty[id] = snap.qty[i]
    end
    self.lastFull = { t = t, qty = qty }
  end

  -- merge into the day
  local slot = 2 ^ floor((t % Store.DAY) / 3600)
  local byBucket = {}
  local function bucketRows(id)
    local b = id % Store.BUCKETS
    local rows = byBucket[b]
    if not rows then
      rows = {}
      byBucket[b] = rows
    end
    return rows
  end
  for i, id in ipairs(ids) do
    local rows = bucketRows(id)
    local before = prevQty and prevQty[id]
    local drain = before and max(0, before - snap.qty[i]) or 0
    rows[#rows + 1] = {
      id,
      snap.min[i],
      snap.market[i],
      snap.median[i],
      snap.qty[i],
      snap.auctions[i],
      1,
      slot,
      snap.market[i],
      drain,
      before and obs or 0,
    }
    if prevQty then
      prevQty[id] = nil
    end
  end
  -- items that were listed in the previous scan and are gone now: all of it drained
  for id, before in pairs(prevQty or {}) do
    if before > 0 then
      local rows = bucketRows(id)
      rows[#rows + 1] = { id, drainOnly = true, [10] = before, [11] = obs }
    end
  end
  data.days[day] = data.days[day] or {}
  self:mergeInto(data.days[day], byBucket)
  data.seen[day] = seen or {}
  data.seen[day][key] = true

  self:Rollup()
  return true
end

-- Backfill: add day points for items that day doesn't have yet (own data always wins). rows: list of
-- { id, min, market, median, qty, auctions, scans } with market..auctions as sums. key dedupes the import per day.
function Store:ImportDay(day, rows, key)
  local data = self.data
  data.seen[day] = data.seen[day] or {}
  if data.seen[day][key] then
    return false
  end
  data.days[day] = data.days[day] or {}
  local tier = data.days[day]
  local byBucket = {}
  for _, r in ipairs(rows) do
    local b = r[1] % Store.BUCKETS
    local seg = tier[b] and self:decode(tier[b], Store.SEGMENT_FIELDS)
    if not (seg and find(seg.ids, r[1])) then
      byBucket[b] = byBucket[b] or {}
      local list = byBucket[b]
      list[#list + 1] = { r[1], r[2], r[3], r[4], r[5], r[6], r[7], 0, r[8] or 0 }
    end
  end
  self:mergeInto(tier, byBucket)
  data.seen[day][key] = true
  return true
end

-- The full scan before raw[pos] (same house, within DRAIN_WINDOW), as { [itemID] = qty } plus the minutes between
-- them - but only when raw[pos] is the newest full scan: a late one (e.g. relayed by sync) would count an interval
-- twice.
function Store:previousFull(pos)
  local raw = self.data.raw
  local entry = raw[pos]
  for k = pos + 1, #raw do
    if (raw[k].k or "full") == "full" then
      return nil, 0
    end
  end
  for k = pos - 1, 1, -1 do
    local e = raw[k]
    if entry.t - e.t > Store.DRAIN_WINDOW then
      return nil, 0
    end
    if (e.k or "full") == "full" and e.t < entry.t then
      if self.lastFull and self.lastFull.t == e.t then
        return self.lastFull.qty, floor((entry.t - e.t) / 60)
      end
      local ok, snap = pcall(function()
        return Codec.Decode(Codec.SNAPSHOT_FIELDS, Codec.Unpack(e.s, self.compressor))
      end)
      if not ok then
        return nil, 0
      end
      local qty = {}
      for i, id in ipairs(snap.ids) do
        qty[id] = snap.qty[i]
      end
      return qty, floor((entry.t - e.t) / 60)
    end
  end
  return nil, 0
end

-- Order books from searches (latest per item, kept RAW_KEEP): books = { [itemID] = Depth book }
function Store:SetBooks(books)
  for itemID, book in pairs(books or {}) do
    self.data.books[itemID] = { t = book.t, s = ns.Depth.Encode(book) }
  end
end

-- the item's latest order book if newer than maxAge seconds (nil otherwise)
function Store:Book(itemID, maxAge)
  local b = self.data.books[itemID]
  if not b or (maxAge and self.now() - b.t > maxAge) then
    return nil
  end
  return ns.Depth.Decode(b.s, b.t)
end

-- Retention: prune raw scans, fold old days into weeks, drop old weeks. Safe to call any time; yields per folded
-- day (the first run after a retention change can fold months).
function Store:Rollup()
  local data = self.data
  local now = self.now()

  local cutoff = now - Store.RAW_KEEP
  for itemID, b in pairs(data.books or {}) do
    if b.t < cutoff then
      data.books[itemID] = nil
    end
  end
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
              seg.high and seg.high[i] or 0,
              seg.drain and seg.drain[i] or 0,
              seg.obs and seg.obs[i] or 0,
            }
          end
        end
        data.days[day] = nil
        data.seen[day] = nil
        self:pause()
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
          last[9] = max(last[9], r[9])
          last[10], last[11] = last[10] + r[10], last[11] + r[11]
        else
          last = { r[1], r[2], r[3], r[4], r[5], r[6], r[7], 0, r[9], r[10], r[11] }
          run[#run + 1] = last
        end
      end
      data.weeks[week][b] = self:encode(mergeRows(seg, run), Store.SEGMENT_FIELDS)
    end
  end

  local oldest = floor(today / 7) - Store.WEEKS_KEEP
  for week in pairs(data.weeks) do
    if week < oldest then
      data.weeks[week] = nil
    end
  end
end

---------------------------------------------------------------------------------------------------------------------
-- reads

local function point(seg, i, res, period)
  local scans = seg.scans[i]
  local high = seg.high and seg.high[i]
  local obs = seg.obs and seg.obs[i] or 0
  local p = {
    res = res,
    min = seg.min[i],
    high = high and high > 0 and high or nil,
    scans = scans,
    drain = obs > 0 and seg.drain[i] or nil,
    obs = obs > 0 and obs or nil,
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
      self:pause()
      local i = find(seg.ids, itemID)
      if i then
        out[#out + 1] = point(seg, i, "week", week)
      end
    end
  end
  for day, buckets in pairs(self.data.days) do
    if buckets[b] and day >= fromDay and day <= toDay then
      local seg = self:decode(buckets[b], Store.SEGMENT_FIELDS)
      self:pause()
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

-- Every item's points in one bucket over a day range: { [itemID] = { points oldest first } }. Used to build the
-- market index bucket by bucket, so memory stays bounded.
function Store:BucketSeries(b, fromDay, toDay)
  local out = {}
  local function add(tier, res)
    for period, buckets in pairs(tier) do
      local first = res == "week" and period * 7 or period
      local last = res == "week" and first + 6 or period
      if buckets[b] and last >= fromDay and first <= toDay then
        local seg = self:decode(buckets[b], Store.SEGMENT_FIELDS)
        self:pause()
        for i, id in ipairs(seg.ids) do
          local list = out[id]
          if not list then
            list = {}
            out[id] = list
          end
          list[#list + 1] = point(seg, i, res, period)
        end
      end
    end
  end
  add(self.data.weeks, "week")
  add(self.data.days, "day")
  for _, list in pairs(out) do
    sort(list, function(x, y)
      return x.day < y.day
    end)
  end
  return out
end

-- Newest scan values for an item. Walks the raw scans newest first, decoding one per step outside the segment cache
-- (a decoded full scan is ~40k numbers: caching dozens pinned ~8 MB) and yielding between them.
function Store:Latest(itemID)
  local raw = self.data.raw
  for k = #raw, 1, -1 do
    local e = raw[k]
    local snap = Codec.Decode(Codec.SNAPSHOT_FIELDS, Codec.Unpack(e.s, self.compressor))
    self:pause()
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

-- Every recent scan (full and partial, kept in full for RAW_KEEP) that saw the item, oldest first:
-- { { t, min, market, median, qty, auctions, kind, src }, ... }. Decodes one snapshot per scan (uncached, yields
-- between scans), so it's meant for a background job.
function Store:Intraday(itemID, fromT)
  local out = {}
  for _, e in ipairs(self.data.raw) do
    if not fromT or e.t >= fromT then
      -- not through the segment cache: a full scan decodes to ~40k numbers, dozens of them would pin lots of memory
      local snap = Codec.Decode(Codec.SNAPSHOT_FIELDS, Codec.Unpack(e.s, self.compressor))
      local i = find(snap.ids, itemID)
      if i then
        out[#out + 1] = {
          t = e.t,
          min = snap.min[i],
          market = snap.market[i],
          median = snap.median[i],
          qty = snap.qty[i],
          auctions = snap.auctions[i],
          kind = e.k or "full",
          src = e.src,
        }
      end
      self:pause()
    end
  end
  return out
end
