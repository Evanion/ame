local addon = require("spec.helpers.addon")

describe("CraftQueue", function()
  local Q
  before_each(function()
    Q = addon.load({ "Core/Init.lua", "Core/CraftQueue.lua" }).CraftQueue
  end)

  local GAUNTLET, BAR, ORE, CLOTH, VIAL, COIF = 7919, 3860, 3858, 4338, 3371, 7931
  local recipes = {
    [100] = { id = 100, product = GAUNTLET, made = 1, reagents = { { BAR, 6 }, { CLOTH, 4 } } },
    [200] = { id = 200, product = BAR, made = 1, reagents = { { ORE, 1 } } },
    [300] = { id = 300, product = COIF, made = 1, reagents = { { BAR, 2 }, { VIAL, 1 } } },
  }
  local prices = { [ORE] = 10500, [BAR] = 11800, [CLOTH] = 4500, [GAUNTLET] = 120000, [COIF] = 50000 }

  local function env(overrides)
    local craft = {}
    function craft:Price(id)
      return prices[id]
    end
    function craft:CraftCost(r)
      local c = 0
      for _, g in ipairs(r.reagents) do
        local p = prices[g[1]]
        if not p then
          return nil
        end
        c = c + p * g[2]
      end
      return c
    end
    function craft:Evaluate(r)
      local c = self:CraftCost(r)
      return { profit = c and prices[r.product] * 0.95 - c }
    end
    local e = {
      me = "M:Me",
      craft = craft,
      recipe = function(id)
        return recipes[id]
      end,
      producers = function(item)
        if item == BAR then
          return { { recipe = 200, crafters = { "M:Bankalt" } } }
        elseif item == GAUNTLET then
          return { { recipe = 100, crafters = { "M:Me" } } }
        end
      end,
      held = function(item)
        local h = {
          [ORE] = { chars = { { name = "Bankalt", bags = 3, bank = 0 } } },
          [BAR] = { chars = { { name = "Me", me = true, bags = 0, bank = 4 } } },
          [CLOTH] = { chars = { { name = "Me", me = true, bags = 20, bank = 0 } } },
        }
        return h[item] or { chars = {} }
      end,
      vendorBuy = function(item)
        return item == VIAL and 4 or nil
      end,
    }
    for k, v in pairs(overrides or {}) do
      e[k] = v
    end
    return e
  end

  local function source(m, kind)
    for _, s in ipairs(m.sources) do
      if s.kind == kind then
        return s
      end
    end
  end

  local function material(plan, item)
    for _, m in ipairs(plan.materials) do
      if m.item == item then
        return m
      end
    end
  end

  it("makes the parts first, from your stock first, and buys only what's left", function()
    local q = Q.New({})
    q:Add(100, 2)
    local plan = Q.Plan(q.db, env())
    -- smelting bars comes first, on the alt who knows it
    assert.are.equal(2, #plan.steps)
    assert.are.equal(200, plan.steps[1].recipe)
    assert.are.equal(8, plan.steps[1].count) -- 12 bars needed, 4 in your bank
    assert.are.equal("M:Bankalt", plan.steps[1].crafter)
    assert.is_false(plan.steps[1].mine)
    assert.are.equal(100, plan.steps[2].recipe)
    assert.is_true(plan.steps[2].mine)
    local bar = material(plan, BAR)
    assert.are.equal(12, bar.need)
    assert.are.equal(4, source(bar, "bank").qty)
    assert.are.equal(8, source(bar, "made").qty)
    assert.are.equal("make", bar.choice)
    assert.are.equal(1300, bar.saves) -- 1s 18s bought vs 1s 05s of ore a bar
    local ore = material(plan, ORE)
    assert.are.equal(8, ore.need)
    assert.are.same({ kind = "alt", qty = 3, char = "Bankalt" }, source(ore, "alt"))
    assert.are.equal(5, source(ore, "ah").qty)
    assert.are.equal(52500, plan.toBuy)
    assert.are.equal(8, source(material(plan, CLOTH), "carried").qty)
    assert.are.equal(2 * (114000 - 88800), plan.profit)
    -- in words: buy the ore, fetch from the alt and the bank, then craft in order
    assert.are.same(
      { "buy", "bank", "alt", "craft", "craft" },
      (function()
        local kinds = {}
        for _, t in ipairs(plan.todo) do
          kinds[#kinds + 1] = t.kind
        end
        return kinds
      end)()
    )
  end)

  it("buys a part only when that's picked; one you can make is made first, even when buying is cheaper", function()
    local q = Q.New({})
    q:Add(100, 2)
    q:SetChoice(BAR, "buy")
    local plan = Q.Plan(q.db, env())
    assert.are.equal(1, #plan.steps)
    assert.are.equal(8, source(material(plan, BAR), "ah").qty)
    assert.is_nil(material(plan, ORE))
    -- not picked: bought bars cost less than the ore for them, but you can smelt them, so the smelting is queued
    -- first; what making costs over buying shows as its saves
    q:SetChoice(BAR, nil)
    prices[BAR] = 10000
    finally(function()
      prices[BAR] = 11800
    end)
    plan = Q.Plan(q.db, env())
    assert.are.equal(2, #plan.steps)
    assert.is_true(plan.steps[1].part)
    assert.are.equal("make", material(plan, BAR).choice)
    assert.is_true(material(plan, BAR).saves < 0)
  end)

  it("takes vendor reagents from a vendor, and shares a part's crafts between the items that need it", function()
    local q = Q.New({})
    q:Add(100, 2)
    q:Add(300, 1)
    local plan = Q.Plan(q.db, env())
    assert.are.same({ kind = "vendor", qty = 1, cost = 4 }, source(material(plan, VIAL), "vendor"))
    local bar = material(plan, BAR)
    assert.are.equal(14, bar.need)
    assert.are.equal(10, source(bar, "made").qty)
    assert.are.equal(10, plan.steps[1].count) -- one smelting step for both
    assert.are.equal(3, #plan.steps)
  end)

  it("keeps the queue: adds merge, crafts count off, removing and clearing", function()
    local q = Q.New({})
    q:Add(100, 2)
    q:Add(100, 1)
    assert.are.equal(3, q.db.items[1].count)
    q:Crafted(100, 2)
    assert.are.equal(1, q.db.items[1].count)
    q:Crafted(100)
    assert.is_true(q:Empty())
    q:Add(300, 1)
    assert.is_true(q:Remove(300))
    assert.is_false(q:Remove(300))
  end)

  it("picks the next step you can craft here", function()
    local q = Q.New({})
    q:Add(100, 2)
    local plan = Q.Plan(q.db, env())
    local next = Q.Next(plan, function()
      return true
    end)
    assert.are.equal(100, next.recipe) -- the bars are Bankalt's to smelt
  end)
end)

describe("ProfessionBar.CraftsFromBags", function()
  it("counts the crafts the reagents in your bags make", function()
    local ns =
      require("spec.helpers.addon").load({ "Core/Init.lua", "Core/UI/Widgets.lua", "Core/UI/ProfessionBar.lua" })
    local PB = ns.ProfessionBar
    local stew = { reagents = { { 1, 2 }, { 2, 1 }, { 3, 1 } } } -- 2 eyes, a crab meat, a spice each
    assert.are.equal(20, PB.CraftsFromBags(stew, { [1] = 40, [2] = 20, [3] = 20 }))
    assert.are.equal(5, PB.CraftsFromBags(stew, { [1] = 40, [2] = 5, [3] = 20 }))
    assert.are.equal(0, PB.CraftsFromBags(stew, { [1] = 40 }))
  end)
end)
