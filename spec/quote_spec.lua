-- Quote: the one place an item's price and sales rate come from.
local addon = require("spec.helpers.addon")

describe("Quote", function()
  local Q
  before_each(function()
    Q = addon.load({ "Core/Init.lua" }).Quote
  end)

  it("counts what sells a day, never more than is listed", function()
    assert.are.equal(3, Q.UnitsPerDay({ sellRate = 40, qty = 3 }))
    assert.are.equal(12, Q.UnitsPerDay({ sellRate = 12, qty = 500 }))
    assert.is_nil(Q.UnitsPerDay({ qty = 10 }))
    assert.is_nil(Q.UnitsPerDay(nil))
  end)

  it("caps a price at the outlier factor times its 30-day average", function()
    assert.are.equal(400, Q.CapPrice({ market = 1000, avg30 = 100 }, 4))
    assert.are.equal(300, Q.CapPrice({ market = 300, avg30 = 100 }, 4))
    assert.are.equal(1000, Q.CapPrice({ market = 1000 }, 4)) -- no average: nothing to cap against
    assert.are.equal(1000, Q.CapPrice({ market = 1000, avg30 = 100 }, nil))
    assert.is_nil(Q.CapPrice({ market = 0 }, 4))
    assert.is_nil(Q.CapPrice(nil, 4))
  end)
end)

describe("Quote nets", function()
  local ns, Q, info
  before_each(function()
    ns = addon.load({ "Core/Init.lua", "Core/SellThrough.lua", "Core/Arbitrage.lua", "Core/Disenchant.lua" })
    Q = ns.Quote
    info = {}
    ns.ItemCache = {
      Get = function(id)
        return info[id] or {}
      end,
      Name = function(id)
        return "Item " .. id
      end,
    }
  end)
  local function quote(items)
    return setmetatable(
      { index = { items = items }, house = "Horde", cut = 0.05, hours = 24, factor = 4, fresh = {}, noFresh = true },
      Q
    )
  end

  it("nets a listing at the capped price after the cut and the deposit", function()
    assert.are.equal(95 - 3, Q.Net({ market = 100 }, 0.05, 3, 4))
    assert.are.equal(400 * 0.95, Q.Net({ market = 1000, avg30 = 100 }, 0.05, 0, 4)) -- a fantasy listing: capped
    -- with sell-through: the deposit lost only as often as listings fail
    assert.are.equal(0.5 * 95 - 0.5 * 10, Q.Net({ market = 100, sellThrough = 0.5, stWeight = 1 }, 0.05, 10, 4))
    assert.is_nil(Q.Net({}, 0.05, 0, 4))
  end)

  it("sells where it nets most, never a bind-on-pickup item, and values a unit at that", function()
    info[1] = { sellPrice = 10 } -- deposit 60% of 10 = 6 at 24 hours
    info[2] = { sellPrice = 200 }
    info[3] = { bind = 1 }
    local q = quote({ [1] = { market = 100 }, [2] = { market = 100 }, [3] = { market = 100 } })
    assert.are.equal(95 - 6, q:ListingNet(1))
    assert.are.same({ 89, "ah" }, { q:BestSale(1) })
    assert.are.same({ 200, "vendor" }, { q:BestSale(2) })
    assert.are.same({ nil, "unsellable" }, { q:BestSale(3) })
    assert.are.equal(89, q:Worth(1))
    assert.is_nil(q:BestSale(4)) -- no price, no vendor
    -- a pile of them: each at Worth, and how many kinds have no price
    assert.are.same({ 89 * 3 + 200 * 2, 2 }, { q:WorthOf({ [1] = 3, [2] = 2, [3] = 1, [4] = 7 }) })
  end)

  it("values a disenchant at what its materials sell for", function()
    info[50] = { classID = 4, quality = 2, level = 20 } -- green armor
    local outcomes = ns.Disenchant.Outcomes(20, 2, 4)
    local items = { [50] = { market = 1 } }
    for _, o in ipairs(outcomes) do
      items[o[1]] = { market = 1000 }
    end
    local de = quote(items):Disenchant(50)
    local want = 0
    for _, o in ipairs(outcomes) do
      want = want + 950 * o[2] * (o[3] + o[4]) / 2 -- after the cut (no vendor price: no deposit)
    end
    assert.near(want, de.value, 1e-6)
    assert.are.equal(950, de.outcomes[1].price)
    assert.is_nil(quote({}):Disenchant(50).value) -- a material without a price: no value
    assert.is_nil(quote(items):Disenchant(1)) -- not gear
  end)
end)

describe("Quote.PostNet", function()
  it("nets a post at its house's cut, less the deposit spread over the units", function()
    local ns = addon.load({ "Core/Init.lua" })
    ns.Settings = {
      AuctionCut = function(_, house)
        return house == "Neutral" and 0.15 or 0.05
      end,
    }
    ns.AME = {
      CurrentHouse = function()
        return "Horde"
      end,
    }
    assert.are.equal(1000 * 0.95 - 60 / 20, ns.Quote.PostNet("PvP|Horde", 1000, 60, 20))
    assert.are.equal(1000 * 0.85 - 60, ns.Quote.PostNet("PvP|Neutral", 1000, 60, nil))
    assert.are.equal(0.05, ns.Quote.Cut(nil)) -- the house you're at
  end)
end)
