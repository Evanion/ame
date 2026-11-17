local addon = require("spec.helpers.addon")

describe("Depth", function()
  local D
  before_each(function()
    D = addon.load({ "Core/Init.lua", "Core/Depth.lua" }).Depth
  end)

  local function book()
    return D.Book({ { 120, 5 }, { 100, 10 }, { 100, 5 }, { 150, 20 }, { 0, 3 } }, 1000)
  end

  it("builds price tiers cheapest first, merging equal prices and dropping junk rows", function()
    local b = book()
    assert.are.same({ 100, 120, 150 }, b.prices)
    assert.are.same({ 15, 5, 20 }, b.qtys)
    assert.are.equal(1000, b.t)
  end)

  it("round-trips through its compact storage form", function()
    local b = book()
    local back = D.Decode(D.Encode(b), 1000)
    assert.are.same(b, back)
  end)

  it("costs a purchase of N units from the cheapest up", function()
    local total, avg, last, got = D.Cost(book(), 18)
    assert.are.equal(15 * 100 + 3 * 120, total)
    assert.are.equal(total / 18, avg)
    assert.are.equal(120, last)
    assert.are.equal(18, got)
    local _, _, _, all = D.Cost(book(), 1000)
    assert.are.equal(40, all) -- only 40 listed
  end)

  it("finds how many units an arbitrage route stays profitable for", function()
    -- sells for 140 after the cut: the 100 and 120 tiers are worth buying, the 150 tier isn't
    local units, cost, profit = D.Route(book(), 140)
    assert.are.equal(20, units)
    assert.are.equal(15 * 100 + 5 * 120, cost)
    assert.are.equal(20 * 140 - cost, profit)
    assert.are.equal(0, (D.Route(book(), 90)))
  end)
end)
