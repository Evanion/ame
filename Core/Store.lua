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
--   data.books = { [itemID] = { t =, s = Depth-encoded book } }  latest order book per item, kept RAW_KEEP
--   data.suffixed = { [itemID] = true }  items seen with random suffixes: their history is per variant (item key, see
--                                        ns.ItemKey), and data under the plain item ID (a mix of every suffix, from
--                                        before variants were tracked, or from older versions over sync) is dropped
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
  data.suffixed = data.suffixed or {}
  data.hours = data.hours or {}
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

-- self:pause as a plain function (for Codec's yield arguments)
function Store:pauser()
  if not self.pauseFn then
    self.pauseFn = function()
      self:pause()
    end
  end
  return self.pauseFn
end

function Store:decode(packed, fields)
  local hit = self.cache[packed]
  if hit then
    return hit
  end
  local cols = Codec.Decode(fields, self:unpack(packed), true, self:pauser())
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
    return Codec.Unpack(packed, self.compressor, self:pauser())
  end
  local text = texts.new[packed] or texts.old[packed] or Codec.Unpack(packed, self.compressor, self:pauser())
  texts.new[packed] = text
  return text
end

function Store:encode(cols, fields)
  return Codec.Pack(Codec.Encode(fields, cols), self.compressor, self:pauser())
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

-- Items whose variants show up for the first time: mark them suffixed and delete the history kept under their plain
-- item ID (a blend of every suffix's prices). Returns true when there were any.
function Store:markSuffixed(ids)
  local suffixed, fresh, any = self.data.suffixed, {}, false
  for _, id in ipairs(ids) do
    if ns.IsVariant(id) then
      local base = ns.BaseID(id)
      if not suffixed[base] then
        suffixed[base], fresh[base], any = true, true, true
      end
    end
  end
  if any then
    self:forget(fresh)
  end
  return any
end

-- remove items (set of ids) from every daily and weekly segment, and their order books
function Store:forget(set)
  local buckets = {}
  for id in pairs(set) do
    buckets[id % Store.BUCKETS] = true
    self.data.books[id] = nil
  end
  for _, tier in ipairs({ self.data.days, self.data.weeks }) do
    for _, segs in pairs(tier) do
      for b in pairs(buckets) do
        if segs[b] then
          local seg = self:decode(segs[b], Store.SEGMENT_FIELDS)
          local out, n = emptySegment(), 0
          for i, id in ipairs(seg.ids) do
            if not set[id] then
              n = n + 1
              for _, field in ipairs(Store.SEGMENT_FIELDS) do
                local col = seg[field]
                out[field][n] = col and col[i] or 0
              end
            end
          end
          if n < #seg.ids then
            segs[b] = n > 0 and self:encode(out, Store.SEGMENT_FIELDS) or nil
          end
          self:pause()
        end
      end
    end
  end
  self.data.rev = (self.data.rev or 0) + 1
end

-- data under a plain item ID that has variants: a mix of every suffix, not stored
function Store:Mixed(id)
  return self.data.suffixed[id] == true
end

-- kind: "full" (replicate scan, default) or "partial" (search / sell-tab results for a few items)
-- packed (optional): the snapshot already compressed (a scan received over sync), stored as is.
function Store:AddScan(snap, t, src, kind, packed)
  kind = kind or "full"
  local data = self.data
  local day = floor(t / Store.DAY)
  local ids = snap.ids
  local key = Store.ScanKey(t, src, kind, ids)
  local seen = data.seen[day]
  if seen and seen[key] then
    return false
  end

  -- raw tier (sorted by t)
  local raw = data.raw
  -- a full scan is compressed in pieces, pausing between them (Compress.CHUNK)
  if not packed then
    local text = Codec.EncodeSnapshot(snap)
    self:pause()
    packed = Codec.Pack(text, self.compressor, self:pauser())
    self:pause()
  end
  local entry = { t = t, src = src, k = kind, s = packed }
  local pos = #raw + 1
  while pos > 1 and raw[pos - 1].t > t do
    pos = pos - 1
  end
  table.insert(raw, pos, entry)
  self:markSuffixed(ids)
  local suffixed = self.data.suffixed
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
    local rows = suffixed[id] and {} or bucketRows(id) -- a mixed plain-ID row: not stored
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
    if before > 0 and not suffixed[id] then
      local rows = bucketRows(id)
      rows[#rows + 1] = { id, drainOnly = true, [10] = before, [11] = obs }
    end
  end
  data.days[day] = data.days[day] or {}
  self:mergeInto(data.days[day], byBucket)
  data.rev = (data.rev or 0) + 1 -- history changed: a saved market index of this shard is out of date
  data.seen[day] = seen or {}
  data.seen[day][key] = true

  if kind == "full" then
    self:AddHourFrom(snap, t, src, key)
  end
  self:Rollup()
  return true
end

-- A scan's dedupe key. It includes the content's shape, so several partial searches in the same second don't collide.
function Store.ScanKey(t, src, kind, ids)
  return ("%d:%s:%s:%d:%s:%s"):format(t, tostring(src), kind, #ids, tostring(ids[1]), tostring(ids[#ids]))
end

---------------------------------------------------------------------------------------------------------------------
-- Hourly points: data.hours = { [hour] = { t =, src =, key =, s = packed } }, hour = floor(t / 3600) (UTC). One per
-- hour (the newest full scan in it), kept HOURS_KEEP. Plain items only, in Codec.HOUR_FIELDS with prices rounded
-- (Codec.Round3): ~26 KB on a busy house, against ~240 KB for the full scan with its random-suffix variants. They
-- keep an hourly price line for a week after the full scans are pruned (RAW_KEEP), and are what sync sends to fill
-- the hours a player missed (docs/plans/sync-v2.md). key: the dedupe key of the scan it came from.

Store.HOUR = 3600
Store.HOURS_KEEP = 7 * Store.DAY

-- the hourly point of a full scan (replaces an older one of the same hour)
function Store:AddHourFrom(snap, t, src, key)
  local hours = self.data.hours
  local hour = floor(t / Store.HOUR)
  local have = hours[hour]
  if have and have.t >= t then
    return false
  end
  local suffixed = self.data.suffixed
  local cols = { ids = {}, min = {}, market = {}, qty = {}, auctions = {}, median = {} }
  local round3 = Codec.Round3
  local n = 0
  for i, id in ipairs(snap.ids) do
    if not ns.IsVariant(id) and not suffixed[id] then
      n = n + 1
      cols.ids[n], cols.min[n], cols.market[n] = id, round3(snap.min[i]), round3(snap.market[i])
      cols.qty[n], cols.auctions[n], cols.median[n] = snap.qty[i], snap.auctions[i], round3(snap.median[i])
    end
  end
  self:pause()
  local packed = Codec.Pack(Codec.Encode(Codec.HOUR_FIELDS, cols), self.compressor, self:pauser())
  hours[hour] = { t = t, src = src, key = key, s = packed }
  return true
end

-- an hourly point decoded (Codec.HOUR_FIELDS columns; median is nil in points made before it was added)
function Store:HourPoint(entry)
  return Codec.Decode(Codec.HOUR_FIELDS, Codec.Unpack(entry.s, self.compressor, self:pauser()), true, self:pauser())
end

-- An hourly point from sync (packed as stored, point = its decoded columns): kept for its hour when that hour has
-- none, and merged into its day like a scan (a price sample; no sell-rate pair: drain needs the scans either side).
-- key: the dedupe key of the scan it came from, so a point of a scan this day already has isn't counted twice.
function Store:AddHourPoint(t, src, key, packed, point)
  local data = self.data
  local hour = floor(t / Store.HOUR)
  if data.hours[hour] then
    return false
  end
  data.hours[hour] = { t = t, src = src, key = key, s = packed }
  local day = floor(t / Store.DAY)
  local seen = data.seen[day] or {}
  if key and key ~= "" and seen[key] then
    return true
  end
  local slot = 2 ^ floor((t % Store.DAY) / 3600)
  local byBucket = {}
  local median = point.median
  for i, id in ipairs(point.ids) do
    if not data.suffixed[id] and not ns.IsVariant(id) then
      local b = id % Store.BUCKETS
      byBucket[b] = byBucket[b] or {}
      local rows = byBucket[b]
      local m = point.market[i]
      rows[#rows + 1] =
        { id, point.min[i], m, median and median[i] or m, point.qty[i], point.auctions[i], 1, slot, m, 0, 0 }
    end
  end
  data.days[day] = data.days[day] or {}
  self:mergeInto(data.days[day], byBucket)
  data.rev = (data.rev or 0) + 1
  seen[key ~= "" and key or ("hour:" .. t .. ":" .. tostring(src))] = true
  data.seen[day] = seen
  self:Rollup()
  return true
end

-- A closed day as text, for sync: the scans merged into it (seen keys), then its packed segments.
--   "D1\n<key>\n<key>...\n\n<bucket36>=<packed>\n..."
function Store:ExportDay(day)
  local buckets = self.data.days[day]
  if not buckets then
    return nil
  end
  local keys, lines = {}, {}
  for key in pairs(self.data.seen[day] or {}) do
    keys[#keys + 1] = key
  end
  sort(keys)
  for b, packed in pairs(buckets) do
    lines[#lines + 1] = Codec.ToBase36(b) .. "=" .. packed
  end
  sort(lines)
  return "D1\n" .. table.concat(keys, "\n") .. "\n\n" .. table.concat(lines, "\n")
end

-- parse ExportDay's text: buckets { [b] = packed }, seen { [key] = true }, or nil when it doesn't parse
function Store.ParseDay(text)
  if type(text) ~= "string" or text:sub(1, 3) ~= "D1\n" then
    return nil
  end
  local head, body = text:sub(4):match("^(.-)\n\n(.*)$")
  if not head then
    return nil
  end
  local seen, buckets = {}, {}
  for key in head:gmatch("[^\n]+") do
    seen[key] = true
  end
  for b, packed in body:gmatch("(%w+)=([^\n]+)") do
    local n = Codec.FromBase36(b)
    if not n or n < 0 or n >= Store.BUCKETS then
      return nil
    end
    buckets[n] = packed
  end
  return buckets, seen
end

-- A whole day from sync, for a day this store has nothing of (so nothing is counted twice). Returns true if taken.
function Store:ImportWholeDay(day, buckets, seen)
  local data = self.data
  if data.days[day] or (data.seen[day] and next(data.seen[day])) then
    return false
  end
  data.days[day], data.seen[day] = buckets, seen
  data.rev = (data.rev or 0) + 1
  return true
end

-- a day's packed segments decoded into one snapshot-like table { ids, market } (mean market prices), to compare a
-- received day with our prices (Sync.Plausible)
function Store:DayPrices(buckets)
  local ids, market = {}, {}
  for _, packed in pairs(buckets) do
    local seg = self:decode(packed, Store.SEGMENT_FIELDS)
    for i, id in ipairs(seg.ids) do
      local n = seg.scans[i] or 0
      if n > 0 then
        ids[#ids + 1], market[#market + 1] = id, seg.market[i] / n
      end
    end
    self:pause()
  end
  return { ids = ids, market = market }
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
    if not (seg and find(seg.ids, r[1])) and not data.suffixed[r[1]] then
      byBucket[b] = byBucket[b] or {}
      local list = byBucket[b]
      list[#list + 1] = { r[1], r[2], r[3], r[4], r[5], r[6], r[7], 0, r[8] or 0 }
    end
  end
  self:mergeInto(tier, byBucket)
  data.rev = (data.rev or 0) + 1
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
      local ok, snap = (ns.Try or pcall)(function()
        return Codec.Decode(
          Codec.SNAPSHOT_FIELDS,
          Codec.Unpack(e.s, self.compressor, self:pauser()),
          nil,
          self:pauser()
        )
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
      local e = table.remove(raw, 1)
      -- a full scan from before hourly points existed: keep its hour before it goes
      local hour = floor(e.t / Store.HOUR)
      if (e.k or "full") == "full" and not data.hours[hour] and e.t >= now - Store.HOURS_KEEP then
        local ok, snap = (ns.Try or pcall)(function()
          return Codec.Decode(
            Codec.SNAPSHOT_FIELDS,
            Codec.Unpack(e.s, self.compressor, self:pauser()),
            nil,
            self:pauser()
          )
        end)
        if ok then
          self:AddHourFrom(snap, e.t, e.src, Store.ScanKey(e.t, e.src, "full", snap.ids))
        end
      end
    end
  end
  local hourCutoff = floor((now - Store.HOURS_KEEP) / Store.HOUR)
  for hour in pairs(data.hours) do
    if hour < hourCutoff then
      data.hours[hour] = nil
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

-- p (optional): a table to fill instead of a new one (BucketSeries with a pool); every field is set
local function point(seg, i, res, period, p)
  local scans = seg.scans[i]
  local high = seg.high and seg.high[i]
  local obs = seg.obs and seg.obs[i] or 0
  p = p or {}
  p.res = res
  p.min = seg.min[i]
  p.high = high and high > 0 and high or nil
  p.scans = scans
  p.drain = obs > 0 and seg.drain[i] or nil
  p.obs = obs > 0 and obs or nil
  for _, f in ipairs(SUMMED) do
    p[f] = round(seg[f][i] / scans)
  end
  if res == "week" then
    p.week, p.day, p.hours = period, period * 7, nil
  else
    p.week, p.day = nil, period
    local hours = seg.hours and seg.hours[i]
    p.hours = hours and hours > 0 and hours or nil -- bitmask of UTC hours sampled that day
  end
  return p
end

local function byDay(x, y)
  return x.day < y.day
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
-- pool (optional, Store.NewPool): the points and lists come from it, and go back with Store.Recycle once the
-- bucket is done - a rebuild of ~30k items x 30 days made a million tables, and collecting them stalled the game
function Store:BucketSeries(b, fromDay, toDay, pool)
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
            list = pool and Store.Take(pool.lists) or {}
            out[id] = list
          end
          list[#list + 1] = point(seg, i, res, period, pool and Store.Take(pool.points))
        end
      end
    end
  end
  add(self.data.weeks, "week")
  add(self.data.days, "day")
  for _, list in pairs(out) do
    sort(list, byDay)
  end
  return out
end

-- tables to reuse across BucketSeries calls: { points = { n, ... }, lists = { n, ... } }
function Store.NewPool()
  return { points = { n = 0 }, lists = { n = 0 } }
end

function Store.Take(stack)
  local n = stack.n
  if n == 0 then
    return nil
  end
  local t = stack[n]
  stack[n], stack.n = nil, n - 1
  return t
end

-- a bucket's series back into the pool (nothing may hold on to its points or lists after this)
function Store.Recycle(series, pool)
  local points, lists = pool.points, pool.lists
  for id, list in pairs(series) do
    for i = #list, 1, -1 do
      points.n = points.n + 1
      points[points.n] = list[i]
      list[i] = nil
    end
    lists.n = lists.n + 1
    lists[lists.n] = list
    series[id] = nil
  end
end

-- Size of a shard's stored history: days of daily points, and the bytes of their packed segments and hourly points.
function Store.Footprint(data)
  local days, bytes = 0, 0
  for _, buckets in pairs(data and data.days or {}) do
    days = days + 1
    for _, packed in pairs(buckets) do
      bytes = bytes + #packed
    end
  end
  for _, e in pairs(data and data.hours or {}) do
    bytes = bytes + #e.s
  end
  return days, bytes
end

-- What a market's history holds, for Settings, Data: { from = oldest day, to = newest day, days = daily points,
-- weeks = weekly points, hours = hourly points in the last week, hoursOf = hours in a week, full = full scans kept
-- in full, partial = searches kept in full, mine = of those, scanned by `me`, newest = newest full scan's time,
-- bytes }. Cheap: counts keys, decodes nothing.
function Store.Summary(data, now, me)
  local out = { days = 0, weeks = 0, hours = 0, hoursOf = Store.HOURS_KEEP / Store.HOUR, full = 0, partial = 0 }
  out.mine = 0
  if not data then
    out.bytes = 0
    return out
  end
  local function span(day)
    out.from = math.min(out.from or day, day)
    out.to = math.max(out.to or day, day)
  end
  for day in pairs(data.days or {}) do
    out.days = out.days + 1
    span(day)
  end
  for week in pairs(data.weeks or {}) do
    out.weeks = out.weeks + 1
    span(week * 7)
  end
  local since = floor(now / Store.HOUR) - out.hoursOf
  for hour in pairs(data.hours or {}) do
    if hour > since then
      out.hours = out.hours + 1
    end
  end
  for _, e in ipairs(data.raw or {}) do
    if (e.k or "full") == "full" then
      out.full = out.full + 1
      out.newest = math.max(out.newest or 0, e.t)
    else
      out.partial = out.partial + 1
    end
    if e.src == me then
      out.mine = out.mine + 1
    end
  end
  local _, bytes = Store.Footprint(data)
  for _, e in ipairs(data.raw or {}) do
    bytes = bytes + #(e.s or "")
  end
  out.bytes = bytes
  return out
end

-- Newest scan values for an item. Walks the raw scans newest first, decoding one per step outside the segment cache
-- (a decoded full scan is ~40k numbers: caching dozens pinned ~8 MB) and yielding between them.
function Store:Latest(itemID)
  local raw = self.data.raw
  for k = #raw, 1, -1 do
    local e = raw[k]
    local snap =
      Codec.Decode(Codec.SNAPSHOT_FIELDS, Codec.Unpack(e.s, self.compressor, self:pauser()), nil, self:pauser())
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
-- { { t, min, market, median, qty, auctions, kind, src }, ... }; before that, the hourly points (kind "hour", no
-- median; plain items only). Decodes one snapshot per scan (uncached, yields between scans), so it's meant for a
-- background job.
function Store:Intraday(itemID, fromT)
  local out = {}
  -- hourly points whose scan isn't among the raw ones any more (pruned, or a point that came by sync)
  local inRaw = {}
  for _, e in ipairs(self.data.raw) do
    inRaw[e.t] = true
  end
  local hours = {}
  for _, e in pairs(self.data.hours) do
    if not inRaw[e.t] and (not fromT or e.t >= fromT) and not ns.IsVariant(itemID) then
      hours[#hours + 1] = e
    end
  end
  table.sort(hours, function(a, b)
    return a.t < b.t
  end)
  for _, e in ipairs(hours) do
    local ok, p = pcall(self.HourPoint, self, e)
    local i = ok and find(p.ids, itemID)
    if i then
      out[#out + 1] = {
        t = e.t,
        min = p.min[i],
        market = p.market[i],
        qty = p.qty[i],
        auctions = p.auctions[i],
        kind = "hour",
        src = e.src,
      }
    end
    self:pause()
  end
  for _, e in ipairs(self.data.raw) do
    if not fromT or e.t >= fromT then
      -- not through the segment cache: a full scan decodes to ~40k numbers, dozens of them would pin lots of memory
      local snap =
        Codec.Decode(Codec.SNAPSHOT_FIELDS, Codec.Unpack(e.s, self.compressor, self:pauser()), nil, self:pauser())
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
  table.sort(out, function(a, b)
    return a.t < b.t
  end)
  return out
end
