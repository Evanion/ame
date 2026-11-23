-- Crafting math: input costs (buy, vendor, held, crafted), recipe profit and gold a day, sell or refine, and
-- recipes worth buying - on a small made-up market (prices in copper).
local addon = require("spec.helpers.addon")

describe("Crafting", function()
  local C

  -- items
  local ORE, BAR, SAGE, BLOOM, VIAL, ELIXIR, HELM, ENCHANT_DUST = 10, 11, 20, 21, 22, 30, 40, 50
  local market = {
    [ORE] = { market = 11000, avg30 = 11000, sellRate = 200 },
    [BAR] = { market = 14000, avg30 = 14000, sellRate = 90 },
    [SAGE] = { market = 20000, avg30 = 20000, sellRate = 40 },
    [BLOOM] = { market = 21000, avg30 = 21000, sellRate = 30 },
    [ELIXIR] = { market = 135000, avg30 = 135000, sellRate = 28 },
  }
  local SMELT = { id = 1, product = BAR, made = 1, reagents = { { ORE, 1 } } }
  local MONGOOSE = { id = 2, product = ELIXIR, made = 1, reagents = { { SAGE, 2 }, { BLOOM, 2 }, { VIAL, 1 } } }

  local function env(over)
    local e = {
      market = function(id)
        return market[id]
      end,
      vendorBuy = function(id)
        return id == VIAL and 400 or nil
      end,
      vendorSell = function(id)
        return id == HELM and 50000 or nil
      end,
      cut = 0.05,
      producers = function(id)
        return id == BAR and { SMELT } or {}
      end,
      factor = 4,
    }
    for k, v in pairs(over or {}) do
      e[k] = v
    end
    return e
  end

  before_each(function()
    C = addon.load({ "Core/Init.lua", "Core/Crafting.lua" }).Crafting
  end)

  it("values an input at the cheapest way to get it: buy, vendor, what you'd net selling yours, or craft", function()
    local c = C.New(env())
    assert.are.same({ 21000, "buy" }, { c:InputCost(BLOOM) })
    assert.are.same({ 400, "vendor" }, { c:InputCost(VIAL) })
    -- one you hold costs what selling it would net (buying pays no cut, selling does)
    assert.are.same({ 19000, "held" }, { c:InputCost(SAGE, true) })
    -- a bar is cheaper to smelt from bought ore than to buy
    local cost, source, via = c:InputCost(BAR)
    assert.are.equal(11000, cost)
    assert.are.equal("craft", source)
    assert.are.equal(SMELT, via)
    assert.is_nil(c:InputCost(999)) -- no price, no vendor, no recipe
  end)

  it("works out profit per craft and the gold a day the market absorbs", function()
    local c = C.New(env())
    local e = c:Evaluate(MONGOOSE)
    assert.are.equal(2 * 20000 + 2 * 21000 + 400, e.cost)
    assert.are.equal(135000 * 0.95, e.revenue)
    assert.are.equal(135000 * 0.95 - 82400, e.profit)
    assert.are.equal(e.profit * 28, e.perDay) -- 28 sell a day
    assert.are.equal("vendor", e.reagents[3].source)
    -- with the sage in your bags, it costs what you'd have netted selling it
    assert.are.equal(2 * 19000 + 2 * 21000 + 400, c:Evaluate(MONGOOSE, { [SAGE] = true }).cost)
  end)

  it("says why a recipe has no profit: can't be sold, no price, an enchant", function()
    local c = C.New(env({
      sellable = function(id)
        return id ~= ELIXIR
      end,
    }))
    assert.are.equal("unsellable", c:Evaluate(MONGOOSE).why)
    assert.are.equal("unpriced", C.New(env()):Evaluate({ product = 999, reagents = { { ORE, 1 } } }).why)
    assert.are.equal("enchant", C.New(env()):Evaluate({ reagents = { { ENCHANT_DUST, 1 } } }).why)
  end)

  it("caps a fantasy-priced product at the outlier factor", function()
    market[99] = { market = 10000000, avg30 = 100000, sellRate = 1 }
    local c = C.New(env())
    assert.are.equal(400000, c:Price(99))
    market[99] = nil
  end)

  it("ranks recipes by gold a day, losers and unpriced last", function()
    local loser = { id = 3, product = ORE, made = 1, reagents = { { BAR, 1 } } } -- a bar back into ore
    local unpriced = { id = 4, product = 999, made = 1, reagents = { { ORE, 1 } } }
    local list = C.New(env())
      :TopEarners({ { recipe = unpriced }, { recipe = loser }, { recipe = SMELT }, { recipe = MONGOOSE } })
    assert.are.same({ 2, 1, 3, 4 }, {
      list[1].recipe.id,
      list[2].recipe.id,
      list[3].recipe.id,
      list[4].recipe.id,
    })
  end)

  it("compares selling a stack raw with refining it first", function()
    local c = C.New(env())
    local r = c:SellOrRefine(ORE, 120, { SMELT })
    assert.are.equal(120 * 11000 * 0.95, r.raw)
    assert.are.equal(SMELT, r.best.recipe)
    assert.are.equal(120 * 14000 * 0.95, r.best.net)
    assert.are.equal(120 / 90, r.best.days) -- the bar market takes 90 a day
    -- bars selling for less than the ore: sell it raw
    market[BAR].market = 9000
    assert.is_nil(c:SellOrRefine(ORE, 120, { SMELT }).best)
    market[BAR].market = 14000
  end)

  it("charges a refine for the other reagents, and its parts add up to what it nets", function()
    local c = C.New(env())
    -- 7 sage: 3 elixirs, each needing 2 bloom (bought) and a vial (vendor); 1 sage left, sold raw
    local o = c:SellOrRefine(SAGE, 7, { MONGOOSE }).options[1]
    assert.are.equal(3, o.crafts)
    assert.are.same({ n = 3, copper = 3 * 135000 * 0.95 }, o.sold)
    assert.are.same({ item = BLOOM, n = 6, each = 21000, copper = 6 * 21000, source = "buy" }, o.others[1])
    assert.are.same({ item = VIAL, n = 3, each = 400, copper = 3 * 400, source = "vendor" }, o.others[2])
    assert.are.same({ n = 1, copper = 20000 * 0.95 }, o.left)
    assert.are.equal(o.sold.copper - o.others[1].copper - o.others[2].copper + o.left.copper, o.net)
  end)

  it("recommends recipes on the AH your characters could learn, by payback", function()
    local c = C.New(env())
    local teaches = function(item)
      return ({
        [900] = { profession = 171, rank = 280, spells = { 2 } },
        [901] = { profession = 164, rank = 1, spells = { 1 } },
      })[item]
    end
    local recipe = function(spell)
      return ({ [1] = SMELT, [2] = MONGOOSE })[spell]
    end
    local chars = {
      ["PvP:Kke"] = { professions = { [171] = { skill = 300, learned = {} } } },
      ["PvP:Alt"] = { professions = { [171] = { skill = 250, learned = {} } } },
    }
    local list = c:RecipesToBuy({ { item = 900, price = 120000 }, { item = 901, price = 500 } }, teaches, recipe, chars)
    assert.are.equal(1, #list) -- nobody has Blacksmithing for item 901
    local e = list[1]
    assert.are.equal(900, e.item)
    assert.is_true(e.ready)
    assert.are.equal("PvP:Kke", e.learners[1].char)
    assert.is_false(e.learners[2].ready) -- 250 < 280
    assert.are.equal(120000 / e.eval.perDay, e.payback)
    -- a recipe one of your characters already knows isn't recommended
    chars["PvP:Alt"].professions[171].learned[2] = true
    assert.are.equal(0, #c:RecipesToBuy({ { item = 900, price = 120000 } }, teaches, recipe, chars))
    -- nor one the game says a character knows, though its recorded profession hasn't caught up
    chars["PvP:Alt"].professions[171].learned[2] = nil
    local function knows(key, spell)
      return key == "PvP:Alt" and spell == 2
    end
    assert.are.equal(0, #c:RecipesToBuy({ { item = 900, price = 120000 } }, teaches, recipe, chars, knows))
  end)
end)

describe("Crafting sales and cooldowns", function()
  local C
  local market = {
    [1] = { market = 100, avg30 = 100, sellRate = 50, qty = 50 },
    [2] = { market = 1000, avg30 = 1000, sellRate = 40, qty = 3 }, -- gear: a high rate from expiring listings
  }
  before_each(function()
    C = require("spec.helpers.addon").load({ "Core/Init.lua", "Core/Crafting.lua" }).Crafting
  end)
  local function new()
    return C.New({
      market = function(id)
        return market[id]
      end,
      cut = 0,
    })
  end

  it("never counts more sold a day than is listed", function()
    assert.are.equal(3, new():SalesPerDay(2))
    assert.are.equal(50, new():SalesPerDay(1))
  end)

  it("counts what the whole market takes a day, and how often a cooldown lets you craft it", function()
    local transmute = { product = 2, made = 1, reagents = { { 1, 1 } }, cooldown = 2 * 86400 }
    local e = new():Evaluate(transmute)
    assert.are.equal(900 * 3, e.perDay) -- the market's three a day: the cooldown limits you, not the market
    assert.are.equal(0.5, e.canPerDay) -- one craft every two days
  end)
end)
