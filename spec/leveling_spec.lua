-- Leveling guides and disenchant values, on a small made-up profession (prices in copper).
local addon = require("spec.helpers.addon")

describe("Leveling", function()
  local ns
  local CLOTH, BAND, KIT = 1, 2, 3
  local market

  before_each(function()
    ns = addon.load({ "Core/Init.lua", "Core/Crafting.lua", "Core/Leveling.lua", "Core/Disenchant.lua" })
    market = { [CLOTH] = { market = 100, avg30 = 100, sellRate = 1000 } }
  end)

  local function craft(over)
    local env = {
      market = function(id)
        return market[id]
      end,
      cut = 0.05,
    }
    for k, v in pairs(over or {}) do
      env[k] = v
    end
    return ns.Crafting.New(env)
  end

  -- a bandage (1 cloth, yellow 30, grey 60) known from the start; a heavy one (2 cloth) trained at 40
  local function recipes()
    return {
      {
        recipe = { id = 10, product = BAND, made = 1, reagents = { { CLOTH, 1 } } },
        yellow = 30,
        grey = 60,
        known = true,
      },
      {
        recipe = { id = 11, product = KIT, made = 1, reagents = { { CLOTH, 2 } } },
        yellow = 50,
        grey = 80,
        learnAt = 40,
      },
    }
  end

  it("uses the community skill-up chance: sure below yellow, falling to nothing at grey", function()
    local C = ns.Leveling.Chance
    assert.are.equal(1, C(10, 30, 60))
    assert.are.equal(1, C(30, 30, 60))
    assert.are.equal(0.5, C(45, 30, 60))
    assert.are.equal(0, C(60, 30, 60))
  end)

  it("switches recipes where the next one gets cheaper per skill point", function()
    local plan =
      ns.Leveling.Plan({ craft = craft(), recipes = recipes(), from = 1, to = 70, cap = 75, goal = "cheapest" })
    assert.is_true(plan.complete)
    assert.are.equal(2, #plan.steps)
    local a, b = plan.steps[1], plan.steps[2]
    assert.are.equal(10, a.entry.recipe.id)
    assert.are.same({ 1, 46 }, { a.from, a.to }) -- at 46 the bandage needs 2.14 crafts a point: 214 > 200
    assert.are.equal(11, b.entry.recipe.id)
    assert.are.same({ 46, 70 }, { b.from, b.to })
    assert.are.equal(100 * a.crafts + 200 * b.crafts, plan.cost)
    assert.are.equal(-plan.cost, plan.net) -- nothing to sell here
  end)

  it("adds a training step when the skill reaches its cap", function()
    local plan = ns.Leveling.Plan({ craft = craft(), recipes = recipes(), from = 70, to = 78, cap = 75 })
    local train
    for _, s in ipairs(plan.steps) do
      train = train or (s.train and s)
    end
    assert.are.equal("Journeyman", train.train)
    assert.are.equal(75, train.from)
  end)

  it("keeps an earlier step's results for a later step that needs them, and sells the rest the market takes", function()
    market[BAND] = { market = 150, avg30 = 150, sellRate = 2 } -- bandages sell, slowly
    local list = recipes()
    list[2].recipe.reagents = { { BAND, 1 } } -- the kit is made from a bandage
    local plan = ns.Leveling.Plan({ craft = craft(), recipes = list, from = 1, to = 70, cap = 75, goal = "recovery" })
    local a, b = plan.steps[1], plan.steps[2]
    assert.are.equal(11, b.entry.recipe.id)
    assert.is_true(a.results.keep > 0)
    assert.are.equal(math.min(a.crafts, b.crafts), a.results.keep)
    assert.is_true(a.results.sell <= 2 * ns.Leveling.HORIZON) -- 2 a day, 3 days
    assert.is_true(b.cost < 150 * b.crafts) -- the kept bandages were already paid for
  end)

  it("stops where no recipe can be used", function()
    local list = recipes()
    list[1].known, list[1].learnAt = false, 10
    local plan = ns.Leveling.Plan({ craft = craft(), recipes = list, from = 1, to = 70, cap = 75 })
    assert.are.equal(1, plan.stuck)
    assert.is_false(plan.complete)
  end)

  it("charges a recipe item's price when the path learns it", function()
    local list = recipes()
    list[2].itemPrice = 500
    local plan = ns.Leveling.Plan({ craft = craft(), recipes = list, from = 1, to = 70, cap = 75, goal = "cheapest" })
    local b = plan.steps[#plan.steps]
    assert.are.equal(500, b.learn)
  end)
end)

describe("Disenchant", function()
  local D

  before_each(function()
    D = addon.load({ "Core/Init.lua", "Core/Disenchant.lua" }).Disenchant
  end)

  it("expects mostly dust from green armor and mostly essence from green weapons", function()
    local armor = D.Expected(18, 2, 4) -- item level 18: Strange Dust 2-3, Greater Magic Essence 1-2, a shard
    assert.are.same({ { 10940, 0.75 * 2.5 }, { 10939, 0.20 * 1.5 }, { 10978, 0.05 } }, armor)
    local weapon = D.Expected(18, 2, 2)
    assert.are.equal(0.20 * 2.5, weapon[1][2])
    assert.are.equal(0.75 * 1.5, weapon[2][2])
  end)

  it("gives a shard for blues and Nexus Crystals for high epics, nothing for the rest", function()
    assert.are.same({ { 11084, 1 } }, D.Expected(30, 3, 4)) -- Large Glimmering Shard
    assert.are.same({ { 20725, 1 } }, D.Expected(58, 4, 2)) -- Nexus Crystal
    assert.is_nil(D.Expected(30, 2, 0)) -- a potion
    assert.is_nil(D.Expected(30, 1, 4)) -- white gear
  end)

  it("values a disenchant at its materials' prices", function()
    local price = function(id)
      return ({ [10940] = 100, [10939] = 1000, [10978] = 2000 })[id]
    end
    assert.are.equal(0.75 * 2.5 * 100 + 0.2 * 1.5 * 1000 + 0.05 * 2000, D.Value(18, 2, 4, price))
    assert.is_nil(D.Value(18, 2, 4, function()
      return nil
    end))
  end)
end)

describe("Leveling limits", function()
  local ns
  before_each(function()
    ns = require("spec.helpers.addon").load({ "Core/Init.lua", "Core/Crafting.lua", "Core/Leveling.lua" })
  end)
  local function craft()
    return ns.Crafting.New({
      market = function(id)
        return id == 1 and { market = 100, avg30 = 100 } or nil
      end,
      cut = 0,
    })
  end

  it("never plans a path on a recipe with a cooldown", function()
    local list = {
      {
        recipe = { id = 1, product = 5, reagents = { { 1, 1 } }, cooldown = 86400 },
        yellow = 30,
        grey = 60,
        known = true,
      },
    }
    local plan = ns.Leveling.Plan({ craft = craft(), recipes = list, from = 1, to = 10, cap = 75 })
    assert.are.equal(1, plan.stuck)
  end)

  it("charges a recipe item once, however many steps use the recipe", function()
    local list = {
      {
        recipe = { id = 1, product = 5, reagents = { { 1, 1 } } },
        yellow = 30,
        grey = 60,
        learnAt = 1,
        itemPrice = 500,
      },
      { recipe = { id = 2, product = 6, reagents = { { 1, 2 } } }, yellow = 20, grey = 25, known = true },
    }
    local plan = ns.Leveling.Plan({ craft = craft(), recipes = list, from = 1, to = 40, cap = 75, goal = "cheapest" })
    local charged = 0
    for _, st in ipairs(plan.steps) do
      charged = charged + (st.learn or 0)
    end
    assert.are.equal(500, charged)
  end)
end)
