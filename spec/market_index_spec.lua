local addon = require("spec.helpers.addon")

describe("MarketIndex", function()
  local ns, store, clock
  local DAY = 86400
  local identity = {
    Compress = function(_, s)
      return s
    end,
    Decompress = function(_, s)
      return s
    end,
  }

  before_each(function()
    ns = addon.load({
      "Core/Init.lua",
      "Core/Codec.lua",
      "Core/Store.lua",
      "Core/Analytics.lua",
      "Core/MarketIndex.lua",
    })
    clock = 2000 * DAY + 3600
    store = ns.Store.New({}, {
      compressor = identity,
      now = function()
        return clock
      end,
    })
  end)

  local function scan(day, items)
    local ids = {}
    for id in pairs(items) do
      ids[#ids + 1] = id
    end
    table.sort(ids)
    local s = { ids = ids, min = {}, market = {}, median = {}, qty = {}, auctions = {} }
    for i, id in ipairs(ids) do
      local p = items[id]
      s.min[i], s.market[i], s.median[i], s.qty[i], s.auctions[i] = p, p, p, 10, 1
    end
    store:AddScan(s, day * DAY + 3600, "me")
  end

  it("BucketSeries returns every item's daily series in a bucket", function()
    scan(1998, { [1] = 100, [1 + ns.Store.BUCKETS] = 7 })
    scan(1999, { [1] = 110 })
    scan(2000, { [1] = 120 })
    local series = store:BucketSeries(1, 1990, 2000)
    assert.are.equal(3, #series[1])
    assert.are.equal(120, series[1][3].market)
    assert.are.equal(1, #series[1 + ns.Store.BUCKETS])
  end)

  it("builds a summary per item across all buckets", function()
    for d = 1971, 2000 do
      scan(d, { [5] = 100, [6] = (d == 2000) and 60 or 100 + (d % 2) })
    end
    local index = ns.MarketIndex.Build(store, 2000, 30)
    assert.are.equal(100, index.items[5].market)
    assert.are.equal("buy", index.items[6].signal)
    assert.are.equal(2, index.count)
    assert.are.equal(2000, index.day)
  end)

  it("ranks items by opportunity score", function()
    for d = 1971, 2000 do
      scan(d, { [5] = 100 + (d % 2), [6] = (d == 2000) and 60 or 100 + (d % 2), [7] = (d == 2000) and 150 or 100 })
    end
    local index = ns.MarketIndex.Build(store, 2000, 30)
    local ranked = ns.MarketIndex.Rank(index, "score")
    assert.are.equal(6, ranked[1].itemID)
    assert.are.equal(7, ranked[#ranked].itemID)
  end)

  it("calls the checkpoint between buckets", function()
    scan(2000, { [1] = 1 })
    local calls = 0
    ns.MarketIndex.Build(store, 2000, 30, function()
      calls = calls + 1
    end)
    assert.are.equal(ns.Store.BUCKETS, calls)
  end)
end)
