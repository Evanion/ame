local addon = require("spec.helpers.addon")

describe("AHBrowse (the Shopping tab's search)", function()
  local B
  before_each(function()
    B = addon.load({ "Core/Init.lua", "Core/AHBrowse.lua" }).AHBrowse
  end)

  local FILTER = {
    PoorQuality = 1,
    CommonQuality = 2,
    UncommonQuality = 3,
    RareQuality = 4,
    EpicQuality = 5,
    LegendaryQuality = 6,
    UsableOnly = 10,
    ExactMatch = 11,
  }
  local CATS = {
    {
      name = "Weapons",
      filters = { { classID = 2 } },
      subCategories = {
        { name = "One-Handed Swords", filters = { { classID = 2, subClassID = 7 } } },
      },
    },
    { name = "Trade Goods", filters = { { classID = 7 } } },
  }

  it("builds the game's query: every quality by default, from the lowest asked for, and the flags", function()
    local q = B.Query("sword", {}, FILTER, { Price = 0 }, CATS)
    assert.are.equal("sword", q.searchString)
    assert.are.same({ 1, 2, 3, 4, 5, 6 }, q.filters)
    assert.are.same({}, q.itemClassFilters)
    q = B.Query(
      "",
      { quality = 3, usable = true, exact = true, category = "1.1", minLevel = 40, maxLevel = 50 },
      FILTER,
      {
        Price = 0,
      },
      CATS
    )
    assert.are.same({ 4, 5, 6, 10, 11 }, q.filters) -- rare and up
    assert.are.same({ { classID = 2, subClassID = 7 } }, q.itemClassFilters)
    assert.are.equal(40, q.minLevel)
    assert.are.equal(50, q.maxLevel)
  end)

  it("lists the categories two levels deep for the dropdown", function()
    assert.are.same(
      { { "1", "Weapons" }, { "1.1", "Weapons - One-Handed Swords" }, { "2", "Trade Goods" } },
      B.CategoryOptions(CATS)
    )
  end)

  it("turns results into rows with AME's view, filtering item level and price, cheapest first", function()
    local results = {
      { itemKey = { itemID = 10, itemLevel = 48, itemSuffix = 0 }, minPrice = 5000, totalQuantity = 2 },
      { itemKey = { itemID = 11, itemLevel = 30, itemSuffix = 0 }, minPrice = 900, totalQuantity = 1 },
      { itemKey = { itemID = 12, itemLevel = 50, itemSuffix = 0 }, minPrice = 9000, totalQuantity = 1 },
    }
    local index = { [10] = { market = 6250, signal = "buy" } }
    local rows = B.Rows(results, { minItemLevel = 40, maxPrice = 8000 }, index)
    assert.are.equal(1, #rows)
    assert.are.equal(10, rows[1].key)
    assert.is_true(math.abs(rows[1].vs + 0.2) < 1e-9)
    assert.are.equal("buy", rows[1].signal)
    assert.are.equal(3, #B.Rows(results, {}, nil))
    assert.are.equal(11, B.Rows(results, {}, nil)[1].key) -- cheapest first
  end)

  it("counts the filters set and labels a recent search", function()
    assert.are.equal(0, B.Count({}))
    assert.are.equal(3, B.Count({ minLevel = 40, quality = 3, exact = true }))
    local head, note = B.Label("", { category = "1.1", minLevel = 40, maxLevel = 50 }, CATS)
    assert.are.equal("One-Handed Swords", head)
    assert.are.equal("lvl 40-50", note)
  end)
end)

describe("AHSelling (the Selling tab's bags)", function()
  local S
  before_each(function()
    S = addon.load({ "Core/Init.lua", "Core/UI/Widgets.lua", "Core/UI/AHSelling.lua" }).AHSelling
  end)

  it("groups bag slots by item, and ranks them by what all of each is worth", function()
    local items = S.Group({
      { key = 2589, count = 20, loc = "a" },
      { key = 4306, count = 5, loc = "b" },
      { key = 2589, count = 20, loc = "c" },
    })
    assert.are.equal(2, #items)
    assert.are.equal(40, items[1].qty)
    assert.are.same({ "a", "c" }, items[1].locs)
    local market = { [2589] = { market = 100 }, [4306] = { market = 2000, signal = "sell" } }
    S.Rank(items, function(k)
      return market[k]
    end, function(k)
      return k == 2589 and 120 or nil
    end, 0.05)
    assert.are.equal(4306, items[1].key) -- 5 x 1900 beats 40 x 120
    assert.are.equal(9500, items[1].worth)
    assert.are.equal("vendor", items[2].where) -- a vendor pays 120, the AH nets 95
    assert.are.equal(4800, items[2].worth)
  end)
end)
