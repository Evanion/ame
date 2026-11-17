local addon = require("spec.helpers.addon")

describe("Ledger", function()
  local Ledger, l
  before_each(function()
    Ledger = addon.load({ "Core/Init.lua", "Core/Ledger.lua" }).Ledger
    l = Ledger.New({})
  end)

  local function buy(t, qty, amount)
    return { t = t, kind = "buy", itemID = 10, name = "Silk", qty = qty, amount = amount }
  end
  local function sale(t, qty, amount, cut)
    return { t = t, kind = "sale", itemID = 10, name = "Silk", qty = qty, amount = amount, cut = cut }
  end

  it("records entries once per key, in time order", function()
    assert.is_true(l:Add(sale(200, 1, 100, 5), "a"))
    assert.is_false(l:Add(sale(200, 1, 100, 5), "a"))
    l:Add(buy(100, 10, 500), "b")
    assert.are.equal(100, l.db.entries[1].t)
    assert.are.equal(2, #l.db.entries)
  end)

  it("matches sales against purchases first-in-first-out for realized profit", function()
    l:Add(buy(100, 10, 500), "b1") -- 50 each
    l:Add(buy(110, 10, 1000), "b2") -- 100 each
    l:Add(sale(200, 15, 2250, 112), "s1") -- 150 each; cost 10*50 + 5*100 = 1000
    local s = l:Summary(0)
    assert.are.equal(2250 - 112, s.income)
    assert.are.equal(1500, s.spent)
    assert.are.equal(2250 - 112 - 1000, s.profit)
    local basis = l:CostBasis()[10]
    assert.are.equal(5, basis.units) -- 5 left from the second lot
    assert.are.equal(100, basis.unit)
  end)

  it("counts sales of items never bought on the AH fully as profit", function()
    l:Add(sale(200, 2, 300, 15), "s")
    assert.are.equal(285, l:Summary(0).profit)
  end)

  it("summarizes a period and lists recent entries newest first", function()
    l:Add(buy(100, 1, 50), "b")
    l:Add(sale(300, 1, 100, 5), "s")
    assert.are.equal(0, l:Summary(200).spent)
    assert.are.equal(95, l:Summary(200).income)
    local recent = l:Recent(0, 1)
    assert.are.equal(1, #recent)
    assert.are.equal("sale", recent[1].kind)
  end)

  it("forgets entries older than 90 days", function()
    l:Add(buy(100, 1, 50), "old")
    l:Add(buy(100 + 91 * 86400, 1, 50), "new")
    l:Prune(100 + 91 * 86400)
    assert.are.equal(1, #l.db.entries)
    assert.is_nil(l.db.keys.old)
  end)
end)

describe("Portfolio", function()
  local P
  before_each(function()
    P = addon.load({ "Core/Init.lua", "Core/Portfolio.lua" }).Portfolio
  end)

  local holdings = {
    ["PvP:Tyken"] = { bags = { [10] = 5, [20] = 1 }, bank = { [10] = 10 }, auctions = { [30] = 2 } },
    ["PvP:Alt"] = { bags = { [10] = 5 } },
  }
  local items = {
    [10] = { market = 120, signal = "hold", sellRate = 40 },
    [20] = { market = 5000, signal = "sell" },
    -- 30 has no market price: left out
  }

  it("adds up holdings across characters, bags, bank and auctions", function()
    local m = P.Merge(holdings)
    assert.are.equal(20, m[10].qty)
    assert.are.equal(15, m[10].chars["PvP:Tyken"])
    assert.are.equal(2, m[30].qty)
  end)

  it("totals what's listed on the AH across characters, after each house's cut and at market", function()
    local h = {
      a = { auctions = { [10] = 10 }, listed = { count = 2, value = 1500, house = "Horde" } },
      b = { auctions = { [20] = 1 }, listed = { count = 1, value = 6000, house = "Neutral" } },
      c = { bags = { [10] = 1 } },
    }
    local l = P.Listed(h, function(house)
      return house == "Neutral" and 0.15 or 0.05
    end, items)
    assert.are.equal(3, l.count)
    assert.are.equal(7500, l.value)
    assert.are.equal(1500 * 0.95 + 6000 * 0.85, l.net)
    assert.are.equal(10 * 120 + 5000, l.market)
    assert.is_nil(l.chars.c)
  end)

  it("values positions at market, with cost basis and unrealized profit where known", function()
    local rows, totals = P.Build(holdings, { [10] = { units = 8, unit = 100 } }, items)
    assert.are.equal(2, #rows)
    assert.are.equal(20, rows[1].itemID) -- 5000 beats 20 * 120 = 2400
    local silk = rows[2]
    assert.are.equal(2400, silk.value)
    assert.are.equal(800, silk.cost) -- 8 units bought at 100
    assert.are.equal(160, silk.unrealized) -- 8 * (120 - 100)
    assert.are.equal(0.5, silk.daysToSell) -- 20 held / 40 a day
    assert.are.equal("hold", silk.signal)
    assert.is_nil(rows[1].cost) -- looted: no cost known
    assert.are.equal(7400, totals.value)
    assert.are.equal(160, totals.unrealized)
  end)
end)
