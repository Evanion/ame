-- MarketStats: price index, CPI, listed value (capped), full-scan days and the Overview summary, built through
-- MarketIndex.Build like the game does.
local addon = require("spec.helpers.addon")

describe("MarketStats", function()
  local ns, store
  local DAY = 86400
  local identity = {
    Compress = function(_, s)
      return s
    end,
    Decompress = function(_, s)
      return s
    end,
  }
  -- items below 50 are trade goods (in the CPI basket), the rest armor
  local function classOf(id)
    return id < 50 and 7 or 4
  end

  before_each(function()
    ns = addon.load({
      "Core/Init.lua",
      "Core/Codec.lua",
      "Core/Store.lua",
      "Core/Analytics.lua",
      "Core/MarketIndex.lua",
      "Core/MarketStats.lua",
    })
    store = ns.Store.New({}, {
      compressor = identity,
      now = function()
        return 2000 * DAY + 3600
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
      s.min[i], s.market[i], s.median[i], s.qty[i], s.auctions[i] = p, p, p, 10, 2
    end
    store:AddScan(s, day * DAY + 3600, "me")
  end

  -- 20 days: ten trade goods climbing 1% a day, a flat armor piece, and one listed at 1000x on the last day
  local function market()
    for d = 1981, 2000 do
      local items = { [50] = 1000000, [60] = d == 2000 and 20000000 or 20000 }
      for id = 1, 10 do
        items[id] = math.floor(10000 * 1.01 ^ (d - 1981) + 0.5)
      end
      scan(d, items)
    end
    return ns.MarketIndex.Build(store, 2000, 30, nil, 4, false, nil, classOf)
  end

  it("chains a price index over steady items, starting at 100", function()
    local st = market().stats
    assert.are.equal(20, #st.index)
    assert.are.equal(100, st.index[1].level)
    -- 10 of 12 items up 1% a day; on the last day item 60's outrageous price is dropped as an outlier (11 items)
    local L = math.log(1.01)
    local expected = 100 * math.exp(18 * (10 / 12) * L + (10 / 11) * L)
    assert.is_true(math.abs(st.index[#st.index].level - expected) < 0.05, st.index[#st.index].level)
    assert.are.equal(12, st.basket)
  end)

  it("keeps a CPI of what players use up (trade goods here), not the armor", function()
    local st = market().stats
    assert.are.equal("listed", st.cpiWeights) -- no sell rates without paired full scans: weighted by listed value
    assert.are.equal(10, st.cpiBasket)
    local level = st.cpi[#st.cpi].level
    assert.is_true(math.abs(level - 100 * 1.01 ^ 19) < 0.1, level)
  end)

  it("caps listed value at the outlier factor times the 30-day average, and shows what it capped", function()
    local st = market().stats
    local last = st.days[#st.days]
    assert.are.equal(2000, last.day)
    assert.are.equal(12, last.items)
    assert.are.equal(24, last.auctions)
    assert.are.equal(120, last.units)
    assert.are.equal(1, last.capped)
    assert.are.equal(80000 * 10, last.cls[4] - 1000000 * 10) -- item 60 at 4 x 20,000, not 20,000,000
    local capped
    for _, t in ipairs(last.top) do
      if t.id == 60 then
        capped = t
      end
    end
    assert.are.same({ id = 60, qty = 10, price = 80000, raw = 20000000, rawValue = 200000000, value = 800000 }, capped)
    assert.is_nil(st.days[1].top) -- only the newest day keeps its biggest items
  end)

  it("counts only full-scan days in the totals", function()
    for d = 1998, 1999 do
      local items = {}
      for id = 1, 12 do
        items[id] = 100
      end
      scan(d, items)
    end
    scan(2000, { [1] = 100 }) -- a search today
    local st = ns.MarketIndex.Build(store, 2000, 30, nil, 4, false, nil, classOf).stats
    assert.are.equal(2, #st.days)
    assert.are.equal(1999, st.day)
  end)

  it("summarises a period: changes, breadth, movers and categories by value", function()
    local index = market()
    local sum = ns.MarketStats.Summary(index, 7, classOf, nil, 4)
    assert.are.equal(2000, sum.day)
    assert.is_true(sum.levelChange > 0.05 and sum.levelChange < 0.08, sum.levelChange)
    assert.is_true(sum.valueChange > 0)
    assert.are.equal(0, sum.auctionsChange)
    assert.are.equal(10, sum.up)
    assert.are.equal(5, #sum.risers)
    assert.are.equal(0, #sum.fallers)
    assert.are.equal(4, sum.sectors[1].classID) -- armor: 10,000,000 + 800,000 capped
    assert.are.equal(7, sum.sectors[2].classID)
    assert.is_true(math.abs(sum.sectors[1].share + sum.sectors[2].share - 1) < 1e-9)
    assert.are.equal(#index.stats.days, #sum.series.days)
  end)

  it("leaves items with fewer than 3 units listed out of the index", function()
    local st = ns.MarketStats.New(1, 10, 4, classOf)
    for id = 1, 6 do
      local pts = {}
      for d = 1, 10 do
        -- item 6: one unit reposted every day, doubling in price
        pts[d] = { day = d, market = id == 6 and 2 ^ d or 100, qty = id == 6 and 1 or 10, auctions = 1 }
      end
      st:Add(id, pts, pts, { avg30 = 100, market = 100, qty = 10 })
    end
    local out = st:Finish()
    assert.are.equal(5, out.basket)
    assert.are.equal(100, out.index[#out.index].level)
    assert.are.equal(6, out.days[#out.days].items) -- still counted in the totals
  end)

  it("picks risers and fallers from one category on request", function()
    local index = market()
    assert.are.equal(0, #ns.MarketStats.Summary(index, 7, classOf, nil, 4, 4).risers) -- the armor didn't move
    assert.are.equal(5, #ns.MarketStats.Summary(index, 7, classOf, nil, 4, 7).risers)
  end)

  it("leaves gray items and white weapons and armour out of the risers and fallers", function()
    local index = market()
    local function risers(quality, classID)
      return #ns.MarketStats.Summary(index, 7, classOf, nil, 4, nil, function()
        return { quality = quality, classID = classID }
      end).risers
    end
    assert.are.equal(5, risers(1, 7)) -- white trade goods stay
    assert.are.equal(5, risers(nil, 2)) -- not known yet: stays
    assert.are.equal(5, risers(2, 2)) -- green gear stays
    assert.are.equal(0, risers(0, 7)) -- gray
    assert.are.equal(0, risers(1, 2)) -- a white weapon
    assert.are.equal(0, risers(1, 4)) -- white armour
  end)

  it("has nothing to summarise without statistics", function()
    assert.is_nil(ns.MarketStats.Summary({ items = {} }, 7))
  end)
end)
