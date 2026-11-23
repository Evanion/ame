-- Professions: reading an open profession window (fake C_TradeSkillUI, shaped like WoW Forever's as probed in game)
-- and saving catalogs per account and known recipes per character.
local addon = require("spec.helpers.addon")

describe("Professions", function()
  local P

  before_each(function()
    P = addon.load({ "Core/Init.lua", "Core/Professions.lua" }).Professions
  end)

  -- Alchemy at 215: Fire Oil learned (makes 2, on a cooldown here), Fermenter not learned yet
  local function alchemy(overrides)
    local schematics = {
      [7837] = {
        outputItemID = 6371,
        quantityMin = 2,
        quantityMax = 2,
        recipeType = 1,
        reagentSlotSchematics = {
          { reagentType = 1, quantityRequired = 2, reagents = { { itemID = 6359 } } },
          { reagentType = 1, quantityRequired = 1, reagents = { { itemID = 3371 }, { itemID = 3372 } } },
          { reagentType = 0, quantityRequired = 1, reagents = { { itemID = 9999 } } }, -- optional: left out
        },
      },
      [1263005] = {
        outputItemID = 279970,
        quantityMin = 1,
        quantityMax = 1,
        recipeType = 1,
        reagentSlotSchematics = {
          { reagentType = 1, quantityRequired = 1, reagents = { { itemID = 3372 } } },
        },
      },
    }
    local api = {
      IsTradeSkillReady = function()
        return true
      end,
      IsTradeSkillLinked = function()
        return false
      end,
      GetBaseProfessionInfo = function()
        return { professionID = 171, professionName = "Alchemy", skillLevel = 215, maxSkillLevel = 300 }
      end,
      GetAllRecipeIDs = function()
        return { 7837, 1263005 }
      end,
      GetRecipeInfo = function(id)
        return { recipeID = id, learned = id == 7837 }
      end,
      GetRecipeSchematic = function(id)
        return schematics[id]
      end,
      GetRecipeCooldown = function(id)
        return id == 7837 and 3600 or nil
      end,
    }
    for k, v in pairs(overrides or {}) do
      api[k] = v
    end
    return api
  end

  it("reads the whole catalog of an open profession, unlearned recipes included", function()
    local snap = P.Snapshot(alchemy(), 1000)
    assert.are.equal(171, snap.skillLine)
    assert.are.equal("Alchemy", snap.name)
    assert.are.equal(215, snap.skill)
    assert.are.equal(300, snap.max)
    assert.are.same({ [7837] = true }, snap.learned)
    assert.are.same({ [7837] = 4600 }, snap.cooldowns)
    assert.are.same({
      out = 6371,
      min = 2,
      max = 2,
      type = 1,
      r = { { 6359, 2 }, { 3371, 1, alt = { 3372 } } }, -- basic reagents only; alternatives kept
    }, snap.recipes[7837])
    assert.are.equal(279970, snap.recipes[1263005].out)
  end)

  it("keeps the game's own source text for recipes not learned yet (where to get them)", function()
    local snap = P.Snapshot(
      alchemy({
        GetRecipeSourceText = function(id)
          return "Vendor: Kulwia|nZone: Stonetalon (" .. id .. ")"
        end,
      }),
      1000
    )
    assert.are.equal("Vendor: Kulwia|nZone: Stonetalon (1263005)", snap.recipes[1263005].src)
    assert.is_nil(snap.recipes[7837].src) -- learned: no need
  end)

  it("keeps the tools a recipe needs (the game's tool requirements), by name", function()
    _G.Enum = _G.Enum or {}
    local had = _G.Enum.RecipeRequirementType
    _G.Enum.RecipeRequirementType = { SpellFocus = 0, Totem = 1, Area = 2 }
    finally(function()
      _G.Enum.RecipeRequirementType = had
    end)
    local snap = P.Snapshot(
      alchemy({
        GetRecipeRequirements = function(id)
          if id == 7837 then
            return { { name = "Salt Shaker", type = 1, met = true }, { name = "Anvil", type = 0, met = false } }
          end
          return {}
        end,
      }),
      1000
    )
    assert.are.same({ "Salt Shaker" }, snap.recipes[7837].tools) -- a tool; an anvil nearby isn't one you carry
    assert.is_nil(snap.recipes[1263005].tools)
  end)

  it("saves nothing from someone else's window, an unready one, or one with no profession", function()
    assert.is_nil(P.Snapshot(
      alchemy({
        IsTradeSkillLinked = function()
          return true
        end,
      }),
      0
    ))
    assert.is_nil(P.Snapshot(
      alchemy({
        IsTradeSkillReady = function()
          return false
        end,
      }),
      0
    ))
    assert.is_nil(P.Snapshot(
      alchemy({
        GetBaseProfessionInfo = function()
          return { professionID = 0, professionName = "" }
        end,
      }),
      0
    )) -- what the client reports with no window open
    assert.is_nil(P.Snapshot(
      alchemy({
        GetAllRecipeIDs = function()
          return {}
        end,
      }),
      0
    ))
    assert.is_nil(P.Snapshot(nil, 0))
  end)

  it("keeps one catalog per profession for the account and what each character knows", function()
    local db = {}
    P.Save(db, "PvP:Kke", P.Snapshot(alchemy(), 1000), 1000)
    local other = P.Snapshot(
      alchemy({
        GetRecipeInfo = function()
          return { learned = true }
        end,
        GetRecipeCooldown = function()
          return 0
        end,
      }),
      2000
    )
    P.Save(db, "PvP:Zakzu", other, 2000)
    assert.are.equal(2000, db.catalog[171].at) -- refreshed by whoever opened it last
    assert.are.same({ [7837] = true }, db.chars["PvP:Kke"].professions[171].learned)
    assert.are.same({ [7837] = true, [1263005] = true }, db.chars["PvP:Zakzu"].professions[171].learned)
    assert.are.equal(215, db.chars["PvP:Kke"].professions[171].skill)
  end)

  it("reads a character's professions from the spellbook, windows opened or not", function()
    local function getProfessions()
      return 3, nil, nil, 7 -- primary, (none), archaeology, cooking
    end
    local info = {
      [3] = { "Alchemy", nil, 215, 300, nil, nil, 171 },
      [7] = { "Cooking", nil, 120, 150, nil, nil, 185 },
    }
    local function getProfessionInfo(i)
      return unpack(info[i])
    end
    assert.are.same({
      { name = "Alchemy", skill = 215, max = 300, skillLine = 171 },
      { name = "Cooking", skill = 120, max = 150, skillLine = 185 },
    }, P.Spellbook(getProfessions, getProfessionInfo))
    assert.are.same({}, P.Spellbook(nil, nil))
  end)
end)
