local addon = require("spec.helpers.addon")

describe("Spread", function()
  local S
  before_each(function()
    S = addon.load({ "Core/Init.lua", "Core/Spread.lua" }).Spread
  end)

  local function snap(rows)
    local s = { ids = {}, min = {}, market = {}, median = {} }
    for i, r in ipairs(rows) do
      s.ids[i], s.min[i], s.market[i], s.median[i] = r[1], r[2], r[3], r[3]
    end
    return s
  end

  it("learns each item's spread from scans that saw every listing, and forgets ones at the cheapest", function()
    local db = {}
    S.Learn(db, snap({ { 1, 100, 120 }, { 2, 100, 100 }, { 3, 100, 400 } }))
    assert.are.equal(110, db[1]) -- halfway to 1.2
    assert.is_nil(db[2])
    assert.are.equal(125, db[3]) -- 4x is capped at 1.5x
    S.Learn(db, snap({ { 1, 100, 120 } }))
    assert.are.equal(115, db[1])
  end)

  it("sets a summary scan's market from the spread, never below what it had", function()
    local db = { [1] = 115 }
    local s = snap({ { 1, 1000, 1000 }, { 2, 500, 500 } })
    assert.are.equal(1, S.Apply(db, s))
    assert.are.same({ 1150, 500 }, s.market)
    assert.are.same({ 1000, 500 }, s.min) -- the cheapest stays: the candle's wick
  end)

  it("recognises a summary scan: (nearly) every item's market is its cheapest", function()
    local rows = {}
    for i = 1, 60 do
      rows[i] = { i, 100, 100 }
    end
    assert.is_true(S.IsSummary(snap(rows)))
    rows[1] = { 1, 100, 130 }
    rows[2] = { 2, 100, 130 }
    assert.is_false(S.IsSummary(snap(rows)))
    assert.is_false(S.IsSummary(snap({ { 1, 100, 100 } }))) -- a search of one item isn't a scan
  end)
end)
