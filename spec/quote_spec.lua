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
