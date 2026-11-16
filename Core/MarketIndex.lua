-- Market index: a per-item 30-day summary for the whole shard, built in the background bucket by bucket. Tooltips and
-- the screener read this instead of decoding history on hover. Pure: store, day and checkpoint are passed in.
local _, ns = ...

local MarketIndex = {}
ns.MarketIndex = MarketIndex

-- returns { day =, days =, count =, items = { [itemID] = summary (see Analytics.Summarize) + itemID } }
-- outlierFactor: drop days priced more than this many times off the item's neighbouring days (nil = keep all)
function MarketIndex.Build(store, today, days, checkpoint, outlierFactor)
  local index = { day = today, days = days, count = 0, items = {}, outliers = 0 }
  for b = 0, ns.Store.BUCKETS - 1 do
    local series = store:BucketSeries(b, today - days + 1, today)
    for id, points in pairs(series) do
      local clean, dropped = ns.Analytics.Clean(points, outlierFactor)
      index.outliers = index.outliers + dropped
      local s = ns.Analytics.Summarize(clean)
      if s then
        s.outliers = dropped > 0 and dropped or nil
        s.itemID = id
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
