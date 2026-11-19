-- CraftingData: the generated recipe data (AzerothMercantileExchange_Crafting/Recipes.lua) and how AME reads it.
local addon = require("spec.helpers.addon")

describe("CraftingData", function()
  local CD

  before_each(function()
    _G.AME_CraftingData = nil
    dofile("AzerothMercantileExchange_Crafting/Recipes.lua")
    CD = addon.load({ "Core/Init.lua", "Core/CraftingData.lua" }).CraftingData
    CD:Use(_G.AME_CraftingData)
  end)

  after_each(function()
    _G.AME_CraftingData = nil
  end)

  it("ships every profession's recipes, matching the game's own catalogs where we checked in game", function()
    local count = {}
    for id in pairs(_G.AME_CraftingData.recipes) do
      local r = CD:Recipe(id)
      count[r.profession] = (count[r.profession] or 0) + 1
    end
    -- seen in game on Forever 1.60.1 (/amedev recipes): Alchemy 196, Cooking 132, First Aid 32 (patches may add)
    assert.truthy(count[171] >= 196, count[171])
    assert.truthy(count[185] >= 132, count[185])
    assert.truthy(count[129] >= 32, count[129])
    for _, profession in ipairs({ 164, 165, 197, 202, 333 }) do -- the big crafting professions are all there
      assert.truthy((count[profession] or 0) > 200, profession)
    end
    assert.truthy(_G.AME_CraftingData.build:match("^1%.%d+%.%d+%.%d+$"))
  end)

  -- exact values on made-up rows (the shipped data may change with game patches; this runs before unattended releases)
  local SAMPLE = {
    build = "1.60.1.1",
    recipes = {
      [7837] = { 171, 6371, 2, 150, 170, 6359, 2, 3371, 1 },
      [7421] = { 333, 0, 1, 5, 25, 6218, 1, 10940, 1 }, -- an enchant: no product item
    },
    items = { [728] = { 185, 75, 2543 }, [9999] = { 165, 200, 1, 2 } },
  }

  it("decodes a recipe: product, yield, skill colors (green halfway) and reagents", function()
    CD:Use(SAMPLE)
    assert.are.same({
      profession = 171,
      product = 6371,
      made = 2,
      yellow = 150,
      green = 160,
      grey = 170,
      reagents = { { 6359, 2 }, { 3371, 1 } },
    }, CD:Recipe(7837))
    assert.is_nil(CD:Recipe(7421).product)
    assert.are.equal(15, CD:Recipe(7421).green)
    assert.is_nil(CD:Recipe(1))
  end)

  it("knows which recipes a recipe item teaches, and the skill it needs", function()
    CD:Use(SAMPLE)
    assert.are.same({ profession = 185, rank = 75, spells = { 2543 } }, CD:Teaches(728))
    assert.are.same({ 1, 2 }, CD:Teaches(9999).spells)
    assert.is_nil(CD:Teaches(2589))
  end)

  it("has what the game showed for known recipes and recipe items", function()
    local fireOil = CD:Recipe(7837)
    assert.are.equal(171, fireOil.profession) -- Alchemy
    assert.are.equal(6371, fireOil.product)
    local stew = CD:Teaches(728) -- Recipe: Westfall Stew
    assert.are.equal(185, stew.profession) -- Cooking
    assert.are.same({ 2543 }, stew.spells)
    assert.is_nil(CD:Teaches(2589)) -- Linen Cloth teaches nothing
  end)

  it("every recipe item teaches a shipped recipe of its profession", function()
    for item in pairs(_G.AME_CraftingData.items) do
      local t = CD:Teaches(item)
      for _, spell in ipairs(t.spells) do
        assert.is_not_nil(CD:Recipe(spell), ("item %d teaches %d"):format(item, spell))
      end
    end
  end)

  it("applies hand fixes over the generated rows", function()
    CD.OVERRIDES.recipes[7837] = { 171, 6371, 3, 150, 170 }
    CD.OVERRIDES.items[728] = false
    CD:Use(_G.AME_CraftingData) -- fresh cache
    assert.are.equal(3, CD:Recipe(7837).made)
    assert.is_nil(CD:Teaches(728))
    CD.OVERRIDES.recipes[7837], CD.OVERRIDES.items[728] = nil, nil
  end)
end)
