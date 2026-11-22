-- Recipes: the one recipe model (what a recipe makes, from the window, the catalog or the shipped data).
local addon = require("spec.helpers.addon")

describe("Recipes", function()
  local ns
  before_each(function()
    ns = addon.load({ "Core/Init.lua", "Core/Professions.lua", "Core/CraftingData.lua", "Core/Recipes.lua" })
    _G.AME_DB = {
      crafting = {
        catalog = {
          [129] = {
            at = 1,
            recipes = {
              [3275] = { out = 1251, min = 1, max = 3, r = { { 2589, 1, alt = { 2592 } } }, src = "Trainer" },
            },
          },
        },
        chars = {
          ["PvP:Kke"] = { professions = { [129] = { at = 1, learned = { [3275] = true } } } },
        },
      },
    }
    ns.CraftingData:Use({
      recipes = {
        [7001] = { 197, 4306, 1, 50, 75, 2589, 2 },
        [3275] = { 129, 1251, 1, 30, 70, 2589, 1 }, -- shipped too: its skill colours
        [7002] = { 333, 0, 0, 90, 110, 10940, 1 }, -- an enchant: no item, "made 0"
      },
      items = { [99001] = { 197, 50, 7001 } },
      cooldown = { [7001] = 86400 },
    })
  end)
  after_each(function()
    _G.AME_DB = nil
    _G.C_TradeSkillUI = nil
  end)

  it("takes a scanned recipe's product, yield and reagents, the shipped data's skill colours and cooldown", function()
    local r = ns.Recipes.Get(3275)
    assert.are.equal(1251, r.product)
    assert.are.equal(2, r.made) -- (1 + 3) / 2
    assert.are.equal(1, r.madeMin)
    assert.are.equal(3, r.madeMax)
    assert.are.equal(129, r.profession)
    assert.are.same({ 2592 }, r.reagents[1].alt)
    assert.are.equal("Trainer", r.src)
    assert.are.equal(30, r.yellow)
    assert.are.equal(70, r.grey)
    local d = ns.Recipes.Get(7001)
    assert.are.equal(4306, d.product)
    assert.are.equal(197, d.profession)
    assert.are.equal(86400, d.cooldown)
    assert.is_nil(ns.Recipes.Get(424242))
  end)

  it("makes an enchant one craft of nothing, not zero", function()
    local e = ns.Recipes.Get(7002)
    assert.is_nil(e.product)
    assert.are.equal(1, e.made)
  end)

  it("asks the open window for a recipe nobody recorded", function()
    _G.C_TradeSkillUI = {
      GetRecipeSchematic = function(id)
        if id == 5000 then
          return { outputItemID = 6000, quantityMin = 2, quantityMax = 2, reagentSlotSchematics = {} }
        end
      end,
    }
    local r = ns.Recipes.Get(5000)
    assert.are.equal(6000, r.product)
    assert.are.equal(2, r.made)
  end)

  it("knows a recorded recipe apart from a shipped one, and what makes an item", function()
    assert.are.equal(1251, ns.Recipes.Recorded(3275).product)
    assert.is_nil(ns.Recipes.Recorded(7001)) -- shipped only: not recorded
    local p = ns.Recipes.Producers(1251)
    assert.are.equal(1, #p)
    assert.are.equal(3275, p[1].recipe)
    assert.are.same({ "PvP:Kke" }, p[1].crafters)
  end)

  it("says how a recipe is learned: the recipe items that teach it (corrections applied), else a trainer", function()
    local how = ns.Recipes.Learnable(7001)
    assert.are.equal("item", how.via)
    assert.are.same({ { item = 99001, rank = 50 } }, how.items)
    ns.CraftingData.OVERRIDES.items[99001] = false -- the data was wrong: it teaches nothing
    finally(function()
      ns.CraftingData.OVERRIDES.items[99001] = nil
    end)
    local d = ns.CraftingData.data
    ns.CraftingData:Use({ recipes = d.recipes, items = d.items }) -- (worked out again when the data loads)
    how = ns.Recipes.Learnable(7001)
    assert.are.equal("trainer", how.via)
    assert.are.equal(1, how.learnAt) -- yellow at 50 or under: trained from the start
    assert.is_true(how.estimated)
  end)

  it("drops what it worked out when a profession is recorded again", function()
    local r = ns.Recipes.Get(3275)
    AME_DB.crafting.catalog[129] = { at = 2, recipes = { [3275] = { out = 1251, min = 5, max = 5, r = {} } } }
    assert.are_not.equal(r, ns.Recipes.Get(3275))
    assert.are.equal(5, ns.Recipes.Get(3275).made)
  end)
end)
