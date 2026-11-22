local addon = require("spec.helpers.addon")

describe("VendorPanel", function()
  local V
  before_each(function()
    V =
      addon.load({ "Core/Init.lua", "Core/Shopping.lua", "Core/UI/Widgets.lua", "Core/UI/VendorPanel.lua" }).VendorPanel
  end)

  it("sums what your lists still need, after what your characters hold", function()
    local lists = {
      { items = { [3371] = { need = 20 }, [2320] = { need = 10 } } },
      { items = { [3371] = { need = 5 } } },
    }
    local holdings = { ["R:Me"] = { bags = { [3371] = 2, [2320] = 10 } } }
    local needs = V.Needs(lists, holdings)
    assert.are.equal(25 - 2, needs[3371]) -- both lists together, less the 2 you hold (once)
    assert.is_nil(needs[2320]) -- enough
  end)

  it("lists only what the vendor sells and a list needs, rounded up to its stack", function()
    local offers = {
      { index = 1, key = 7005, price = 9, stack = 1, available = -1 },
      { index = 9, key = 3371, price = 18, stack = 5, available = -1 },
      { index = 4, key = 2320, price = 9, stack = 1, available = 3 },
    }
    local rows = V.Rows({ [3371] = 23, [2320] = 10 }, offers)
    assert.are.equal(2, #rows)
    assert.are.same({ 9, 25, 90 }, { rows[1].index, rows[1].buys, rows[1].cost }) -- 5 stacks of 5
    assert.are.same({ 4, 3, 27 }, { rows[2].index, rows[2].buys, rows[2].cost }) -- only 3 in stock
    assert.are.same({}, V.Rows({}, offers)) -- nothing needed: nothing to show
  end)

  it("buys in whole stacks, at most the game's largest purchase at a time", function()
    assert.are.same({ 25 }, V.Purchases(25, 5, 100))
    assert.are.same({ 20, 20, 5 }, V.Purchases(45, 5, 20))
    assert.are.same({ 200, 56 }, V.Purchases(256, 1, 200))
  end)
end)
