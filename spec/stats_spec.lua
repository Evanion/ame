local addon = require("spec.helpers.addon")

describe("Stats", function()
  local Stats

  before_each(function()
    Stats = addon.load({ "Core/Init.lua", "Core/Stats.lua" }).Stats
  end)

  -- helper: feed listings {itemID, buyout, count} and return the finished snapshot
  local function scan(listings)
    local acc = Stats.NewAccumulator()
    for _, l in ipairs(listings) do
      acc:Add(l[1], l[2], l[3])
    end
    return acc:Finish()
  end

  local function row(snap, itemID)
    for i = 1, #snap.ids do
      if snap.ids[i] == itemID then
        return {
          min = snap.min[i],
          market = snap.market[i],
          median = snap.median[i],
          qty = snap.qty[i],
          auctions = snap.auctions[i],
        }
      end
    end
  end

  it("produces an empty columnar snapshot for no listings", function()
    local s = scan({})
    assert.are.same({}, s.ids)
    assert.are.equal(0, s.skipped)
  end)

  it("handles a single listing", function()
    local s = scan({ { 100, 500, 1 } })
    assert.are.same({ min = 500, market = 500, median = 500, qty = 1, auctions = 1 }, row(s, 100))
  end)

  it("uses unit price (buyout / count) for stacks", function()
    local s = scan({ { 7, 2000, 20 } })
    local r = row(s, 7)
    assert.are.equal(100, r.min)
    assert.are.equal(20, r.qty)
  end)

  it("sorts item ids ascending", function()
    local s = scan({ { 30, 1, 1 }, { 10, 1, 1 }, { 20, 1, 1 } })
    assert.are.same({ 10, 20, 30 }, s.ids)
  end)

  it("skips bid-only listings and counts them", function()
    local s = scan({ { 5, 0, 1 }, { 5, nil, 1 }, { 5, 300, 1 } })
    local r = row(s, 5)
    assert.are.equal(1, r.auctions)
    assert.are.equal(300, r.min)
    assert.are.equal(2, s.skipped)
  end)

  it("drops an item whose listings are all bid-only", function()
    local s = scan({ { 5, 0, 1 } })
    assert.is_nil(row(s, 5))
    assert.are.equal(1, s.skipped)
  end)

  it("treats a zero or missing count as 1", function()
    local s = scan({ { 5, 300, 0 }, { 5, 400, nil } })
    assert.are.equal(2, row(s, 5).qty)
  end)

  it("computes a quantity-weighted median", function()
    -- 1 unit @100, 5 units @200, 1 unit @900 -> 7 units, 4th unit is @200
    local s = scan({ { 1, 100, 1 }, { 1, 1000, 5 }, { 1, 900, 1 } })
    assert.are.equal(200, row(s, 1).median)
  end)

  it("market ignores a single cheap undercut outlier", function()
    -- one unit far below a deep market at ~1000; 100 units at 1000-1050
    local listings = { { 9, 10, 1 } }
    for i = 1, 10 do
      listings[#listings + 1] = { 9, (1000 + i * 5) * 10, 10 }
    end
    local r = row(scan(listings), 9)
    assert.are.equal(10, r.min) -- min still reports the undercut
    assert.is_true(r.market >= 1000 and r.market <= 1050, "market " .. r.market)
  end)

  it("market ignores expensive tail listings", function()
    -- 90 units @100, 10 units @100000 (wishful listings)
    local s = scan({ { 3, 9000, 90 }, { 3, 1000000, 10 } })
    assert.are.equal(100, row(s, 3).market)
  end)

  it("market stops growing past 30% of supply", function()
    -- evenly rising prices 100..199 (1 unit each): market covers at most the cheapest 30 units
    local listings = {}
    for p = 100, 199 do
      listings[#listings + 1] = { 4, p, 1 }
    end
    local r = row(scan(listings), 4)
    assert.is_true(r.market <= 115, "market " .. r.market)
    assert.is_true(r.market >= 100)
  end)

  it("keeps integer copper and handles values above 2^31", function()
    local big = 3 * 2 ^ 31 -- ~6.4M gold
    local s = scan({ { 8, big, 1 }, { 8, big + 2, 1 } })
    local r = row(s, 8)
    assert.are.equal(big, r.min)
    assert.are.equal(math.floor(r.market), r.market)
  end)

  it("aggregates many items independently", function()
    local s = scan({ { 1, 100, 1 }, { 2, 200, 2 }, { 1, 300, 1 } })
    assert.are.equal(2, row(s, 1).auctions)
    assert.are.equal(100, row(s, 2).min)
  end)
end)
