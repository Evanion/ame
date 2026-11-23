-- The Crafting tab's Tools section (Core/UI/CraftTools.lua): the tools a recipe needs, who of yours has one, and how
-- to get one - make it (yours, else the pattern), a vendor, the auction house - and where it's made.
local addon = require("spec.helpers.addon")

describe("Crafting tools", function()
  local ns, UI
  before_each(function()
    ns = addon.load({ "Core/Init.lua", "Core/UI/Widgets.lua" })
    ns.UI = {}
    addon.load({ "Core/UI/CraftTools.lua" }, ns)
    UI = ns.UI
  end)

  local SHAKER, SCHEMATIC, HAMMER = 15846, 16054, 5956
  local function env(over)
    local e = {
      market = function(id)
        return ({ [SHAKER] = 450000, [SCHEMATIC] = 125000 })[id]
      end,
      held = function()
        return nil
      end,
      recipesFor = function(id)
        return id == SHAKER and { 19567 } or {}
      end,
      producers = function()
        return {}
      end,
      recipe = function(id)
        return id == 19567 and { id = 19567, profession = 202, yellow = 270 } or nil
      end,
      taughtBy = function(spell)
        return spell == 19567 and { { item = SCHEMATIC, rank = 250 } } or {}
      end,
      vendorPrice = function(id)
        return id == HAMMER and 1800 or nil
      end,
      sources = function(id)
        return id == SCHEMATIC
            and { { kind = "vendor", npc = "Xizzer Fizzbolt", zone = "Winterspring", price = 150000 } }
          or nil
      end,
      profession = function(skillLine)
        return ({ [202] = "Engineering" })[skillLine]
      end,
      keyByName = function(name)
        return ({ ["Blacksmith Hammer"] = HAMMER })[name]
      end,
    }
    for k, v in pairs(over or {}) do
      e[k] = v
    end
    return e
  end

  it("says nothing for a recipe without tools or a place", function()
    assert.is_nil(UI.CraftTools({ id = 1 }, env()))
  end)

  it("a tool none of yours has and no recipe of yours makes: the pattern, its price and seller; the AH", function()
    local t = UI.CraftTools({ tools = { "Salt Shaker" }, toolIDs = { ["Salt Shaker"] = SHAKER } }, env())
    local tool = t.tools[1]
    assert.are.equal(SHAKER, tool.id)
    assert.is_nil(tool.held)
    local make, ah = tool.ways[1], tool.ways[2]
    assert.are.equal("make", make.kind)
    assert.are.equal("Engineering", make.profession)
    assert.are.equal(250, make.skill) -- what the schematic asks to learn it
    assert.are.equal(SCHEMATIC, make.patterns[1].item)
    assert.are.equal(125000, make.patterns[1].price)
    assert.are.equal("Xizzer Fizzbolt", make.patterns[1].source.npc)
    assert.are.same({ kind = "ah", price = 450000 }, ah)
    -- drawn: the tool a link, the pattern a link with its price, then where it's sold
    local blocks = UI.CraftToolBlocks(t)
    assert.are.equal("Tools", blocks[1].heading)
    local card = blocks[2].card
    assert.are.equal(SHAKER, card.item)
    assert.truthy(card.subtitle:find("none of yours has one", 1, true))
    assert.truthy(card.rows[1].label:find("Make it: Engineering 250", 1, true), card.rows[1].label)
    assert.are.equal(SCHEMATIC, card.rows[2].item)
    assert.are.equal(125000, card.rows[2].copper)
    assert.truthy(card.rows[3].label:find("Sold by Xizzer Fizzbolt, Winterspring", 1, true))
    assert.are.equal("On the auction house", card.rows[4].label)
  end)

  it("one of yours has it, or knows how to make it", function()
    local t = UI.CraftTools(
      { tools = { "Salt Shaker" }, toolIDs = { ["Salt Shaker"] = SHAKER } },
      env({
        held = function()
          return { total = 1, chars = { ["R:Tyken"] = 1 } }
        end,
        producers = function()
          return { { recipe = 19567, crafters = { "R:Zakzu" } } }
        end,
      })
    )
    local tool = t.tools[1]
    assert.are.same({ "Tyken" }, tool.held.chars)
    assert.are.same({ kind = "known", who = "Zakzu", profession = "Engineering" }, tool.ways[1])
    local card = UI.CraftToolBlocks(t)[2].card
    assert.truthy(card.subtitle:find("Tyken has one", 1, true))
    assert.truthy(card.rows[1].label:find("Make it: Zakzu knows it", 1, true))
  end)

  it("a vendor's tool (known by name), and where it's made", function()
    local t = UI.CraftTools({ tools = { "Blacksmith Hammer" }, at = { "Anvil" } }, env())
    local tool = t.tools[1]
    assert.are.equal(HAMMER, tool.id) -- looked up by its name
    assert.are.same({ { kind = "vendors", price = 1800 } }, tool.ways)
    local blocks = UI.CraftToolBlocks(t)
    assert.are.equal("Sold by vendors", blocks[2].card.rows[1].label)
    assert.are.equal("Requires Anvil", blocks[3].card.title)
  end)
end)
