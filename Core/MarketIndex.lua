-- Market index: a per-item 30-day summary for the whole shard, built in the background bucket by bucket. Tooltips and
-- the screener read this instead of decoding history on hover. Pure: store, day and checkpoint are passed in.
local _, ns = ...

local MarketIndex = {}
ns.MarketIndex = MarketIndex

-- returns { day =, days =, count =, items = { [itemID] = summary (see Analytics.Summarize) + itemID } }
-- outlierFactor: drop days priced more than this many times off the item's neighbouring days (nil = keep all)
-- cached: keep decompressed segments for the next build (Store:KeepTexts) - for the auction house you're at, where
-- the index is rebuilt after every scan
-- adjust (optional): fn(summary) applied to every item's summary (e.g. the VENDOR check, which needs vendor prices)
function MarketIndex.Build(store, today, days, checkpoint, outlierFactor, cached, adjust)
  local index = { day = today, days = days, count = 0, items = {}, outliers = 0 }
  if cached then
    store:KeepTexts(true)
  end
  for b = 0, ns.Store.BUCKETS - 1 do
    local from = today - days + 1
    local series = store:BucketSeries(b, from, today)
    for id, points in pairs(series) do
      local clean, dropped = ns.Analytics.Clean(points, outlierFactor)
      index.outliers = index.outliers + dropped
      local s = ns.Analytics.Summarize(clean)
      if s then
        s.outliers = dropped > 0 and dropped or nil
        s.itemID = id
        if adjust then
          adjust(s)
        end
        index.items[id] = s
        index.count = index.count + 1
      end
    end
    if checkpoint then
      checkpoint()
    end
  end
  return index
end

-- sorted list of summaries, best first for "score"; filter(summary) -> bool is optional
function MarketIndex.Rank(index, key, filter, ascending)
  local list = {}
  for _, s in pairs(index.items) do
    if s[key] ~= nil and (not filter or filter(s)) then
      list[#list + 1] = s
    end
  end
  table.sort(list, function(a, b)
    if a[key] == b[key] then
      return a.itemID < b.itemID
    end
    if ascending then
      return a[key] < b[key]
    end
    return a[key] > b[key]
  end)
  return list
end

-- Saving an index between sessions, so the screener and tooltips have (possibly stale) data right after login while
-- a fresh one is built at low priority. One columnar string: integers only, fractions scaled, nil as a sentinel.
-- Fields: { name, scale } - a value is stored as round(value * scale).
local NONE = -1099511627776 -- -(2^40): no value
local PHASE_KEYS = {
  "shortage",
  "demand",
  "piling",
  "tightening",
  "balanced",
  "pressure",
  "withdrawing",
  "weak",
  "dumping",
}
local PHASE_NUM = {}
for i, key in ipairs(PHASE_KEYS) do
  PHASE_NUM[key] = i
end
-- stored codes (stable across versions: saves from before VENDOR existed used 1-5)
local SIGNALS = { "sell", "buy", "hold", "wait", "none", "vendor" }
local SIGNAL_CODE = {}
for code, name in ipairs(SIGNALS) do
  SIGNAL_CODE[name] = code
end

-- bumped when saved indexes gain information (2: vendor prices, 3: what a listing nets for VENDOR items); older
-- saves are shown, then rebuilt once
MarketIndex.SAVE_VERSION = 3

MarketIndex.SAVED_FIELDS = {
  { "market", 1 },
  { "min", 1 },
  { "qty", 1 },
  { "day", 1 },
  { "days", 1 },
  { "avg3", 1 },
  { "avg7", 1 },
  { "avg14", 1 },
  { "avg30", 1 },
  { "change1", 1e4 },
  { "change7", 1e4 },
  { "change30", 1e4 },
  { "scans7", 1 },
  { "sellRate", 1e3 },
  { "vol30", 1e4 },
  { "z30", 1e3 },
  { "trend30", 1e6 },
  { "supplyTrend30", 1e6 },
  { "score", 1 },
  { "outliers", 1 },
  { "vendorPrice", 1 }, -- what a vendor pays (copper), when the client knew it at build time
  { "vendorNet", 1 }, -- VENDOR items: what a listing nets after the cut and deposit
}

local function columnNames()
  local names = { "ids", "signal", "phase" }
  for _, f in ipairs(MarketIndex.SAVED_FIELDS) do
    names[#names + 1] = f[1]
  end
  return names
end

-- index -> string (checkpoint, optional, is called between items in a background job)
function MarketIndex.Encode(index, checkpoint)
  local ids = {}
  for id in pairs(index.items) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  local cols = { ids = ids, signal = {}, phase = {} }
  for _, f in ipairs(MarketIndex.SAVED_FIELDS) do
    cols[f[1]] = {}
  end
  for i, id in ipairs(ids) do
    local s = index.items[id]
    cols.signal[i] = SIGNAL_CODE[s.signal or "none"] or SIGNAL_CODE.none
    cols.phase[i] = PHASE_NUM[s.phase] or 0
    for _, f in ipairs(MarketIndex.SAVED_FIELDS) do
      local v = s[f[1]]
      cols[f[1]][i] = v and math.floor(v * f[2] + 0.5) or NONE
    end
    if checkpoint and i % 500 == 0 then
      checkpoint()
    end
  end
  return ("%d|%d|%d|"):format(index.day, index.days, index.outliers or 0) .. ns.Codec.Encode(columnNames(), cols)
end

-- string -> index (as MarketIndex.Build makes it)
function MarketIndex.Decode(text, checkpoint)
  local day, days, outliers, body = text:match("^(%-?%d+)|(%d+)|(%d+)|(.*)$")
  local cols = ns.Codec.Decode(columnNames(), body, true) -- saves from older versions lack newer columns
  local index = { day = tonumber(day), days = tonumber(days), count = 0, items = {}, outliers = tonumber(outliers) }
  for i, id in ipairs(cols.ids) do
    local s = { itemID = id }
    s.signal = SIGNALS[cols.signal[i]] or "none"
    s.signalRank = ns.Analytics.SIGNAL_RANK[s.signal]
    s.phase = PHASE_KEYS[cols.phase[i]]
    for _, f in ipairs(MarketIndex.SAVED_FIELDS) do
      local col = cols[f[1]]
      local v = col and col[i]
      if v and v ~= NONE then
        s[f[1]] = f[2] == 1 and v or v / f[2]
      end
    end
    index.items[id] = s
    index.count = index.count + 1
    if checkpoint and i % 500 == 0 then
      checkpoint()
    end
  end
  return index
end
