-- Recipes: the one recipe model (what a recipe makes, from the window, the catalog or the shipped data).
local addon = require("spec.helpers.addon")

describe("Recipes", function()
  local ns
  before_each(function()
    ns = addon.load({ "Core/Init.lua", "Core/Professions.lua", "Core/CraftingData.lua", "Core/Recipes.lua" })
    _G.AME_DB = {
      crafting = {
        catalog = {
          [129] = { at = 1, recipes = { [3275] = { out = 1251, min = 1, max = 3, r = { { 2589, 1 } } } } },
        },
        chars = {
          ["PvP:Kke"] = { professions = { [129] = { at = 1, learned = { [3275] = true } } } },
        },
      },
    }
    ns.CraftingData:Use({
      recipes = { [7001] = { 197, 4306, 1, 50, 75, 2589, 2 } },
      items = {},
    })
  end)
  after_each(function()
    _G.AME_DB = nil
  end)

  it("takes a profession's recorded recipe first, else the shipped one", function()
    local r = ns.Recipes.Get(3275, 129)
    assert.are.equal(1251, r.product)
    assert.are.equal(2, r.made) -- (1 + 3) / 2
    assert.are.equal(129, r.profession)
    local d = ns.Recipes.Get(7001, nil)
    assert.are.equal(4306, d.product)
    assert.is_nil(ns.Recipes.Get(424242, nil))
  end)

  it("knows a recorded recipe without the shipped data, and what makes an item", function()
    local r = ns.Recipes.Recorded(3275)
    assert.are.equal(1251, r.product)
    assert.are.same({ { 2589, 1 } }, r.reagents)
    assert.is_nil(ns.Recipes.Recorded(7001)) -- shipped only: not recorded
    local p = ns.Recipes.Producers(1251)
    assert.are.equal(1, #p)
    assert.are.equal(3275, p[1].recipe)
    assert.are.same({ "PvP:Kke" }, p[1].crafters)
  end)
end)
