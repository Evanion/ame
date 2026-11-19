local addon = require("spec.helpers.addon")

describe("Arbitrage", function()
  local A
  before_each(function()
    A = addon.load({ "Core/Init.lua", "Core/Arbitrage.lua" }).Arbitrage
  end)

  local horde = {
    items = {
      [1] = { min = 100, market = 110, qty = 50, day = 10 }, -- cheap here
      [2] = { min = 1000, market = 1000, qty = 5, day = 10 },
      [3] = { min = 500, market = 520, qty = 9, day = 4 }, -- stale
      [4] = { min = 70, market = 80, qty = 3, day = 10 }, -- not on the goblin AH
    },
  }
  local goblin = {
    items = {
      [1] = { min = 180, market = 200, qty = 4, day = 10 },
      [2] = { min = 900, market = 950, qty = 2, day = 9 },
      [3] = { min = 850, market = 900, qty = 2, day = 10 },
    },
  }

  local function ids(rows)
    local out = {}
    for i, r in ipairs(rows) do
      out[i] = r.itemID
    end
    return out
  end

  it("buys at the cheapest listing and sells at market minus the selling house's cut", function()
    local rows = A.Find(horde, goblin, { cut = 0.15, today = 10 })
    assert.are.same({ 3, 1 }, ids(rows)) -- item 2 loses money; item 4 isn't sold there
    local r = rows[2]
    assert.are.equal(100, r.buy)
    assert.are.equal(200, r.sell)
    assert.are.equal(30, r.fee)
    assert.are.equal(70, r.profit) -- 200 - 15% - 100
    assert.are.equal(0.7, r.margin)
    assert.are.equal(50, r.buyQty)
    assert.are.equal(4, r.sellQty)
  end)

  it("leaves hidden items out", function()
    assert.are.same({ 3 }, ids(A.Find(horde, goblin, { cut = 0.15, today = 10, hide = { [1] = true } })))
  end)

  it("the fee can turn a price gap into a loss", function()
    local small = { items = { [9] = { min = 100, market = 100, day = 1 } } }
    local big = { items = { [9] = { min = 110, market = 110, day = 1 } } }
    assert.are.equal(1, #A.Find(small, big, { cut = 0.05 })) -- 110 - 5.5 - 100 = 4.5
    assert.are.equal(0, #A.Find(small, big, { cut = 0.15 })) -- 110 - 16.5 - 100 < 0
  end)

  it("filters by profit, margin and data age, and sorts", function()
    assert.are.same({ 3 }, ids(A.Find(horde, goblin, { cut = 0.15, minProfit = 100 })))
    assert.are.same({ 1 }, ids(A.Find(horde, goblin, { cut = 0.15, minMargin = 0.6 })))
    assert.are.same({ 1 }, ids(A.Find(horde, goblin, { cut = 0.15, today = 10, maxAge = 3 })))
    local byMargin = A.Find(horde, goblin, { cut = 0.15, sortKey = "margin" })
    assert.are.same({ 1, 3 }, ids(byMargin))
  end)

  it("leaves out gold transfers (junk listed for thousands at the other house) and counts them", function()
    local buy = { items = { [1] = { min = 200, market = 250 }, [2] = { min = 1000, market = 1100 } } }
    local sell = { items = { [1] = { market = 30000000 }, [2] = { market = 3000 } } } -- 3000g for a 2s hatchet
    local rows, transfers = A.Find(buy, sell, { cut = 0.15 })
    assert.are.equal(1, #rows)
    assert.are.equal(2, rows[1].itemID)
    assert.are.equal(1, transfers)
    rows = A.Find(buy, sell, { cut = 0.15, maxMargin = false }) -- no limit
    assert.are.equal(2, #rows)
  end)

  it("copes with missing indexes", function()
    assert.are.equal(0, #A.Find(nil, goblin, {}))
    assert.are.equal(0, #A.Find(horde, nil, {}))
  end)

  it("computes listing deposits from vendor price, duration and house", function()
    assert.are.equal(600, A.Deposit(1000, "Horde", 24)) -- 60%
    assert.are.equal(3000, A.Deposit(1000, "Neutral", 24)) -- 5x at the goblin AH
    assert.are.equal(250, A.Deposit(1000, "Neutral", 2))
    assert.are.equal(100, A.Deposit(10, "Horde", 2)) -- 1 silver minimum
    assert.are.equal(1, A.Deposit(10, "Horde", 2, 1)) -- 1 copper minimum after Nov 17
    assert.is_nil(A.Deposit(nil, "Horde", 24))
  end)
end)
