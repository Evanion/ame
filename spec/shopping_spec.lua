local addon = require("spec.helpers.addon")

describe("Shopping lists", function()
  local ns, S, db

  before_each(function()
    ns = addon.load({ "Core/Init.lua", "Core/Codec.lua", "Core/Sync.lua", "Core/Shopping.lua" })
    db = {}
    S = ns.Shopping.New(db)
  end)

  it("makes named lists, rejecting blanks and duplicates, and renames them", function()
    assert.are.equal(1, (S:AddList("  Cindercloth Robe ")))
    assert.are.equal("Cindercloth Robe", S:Lists()[1].name)
    assert.is_nil((S:AddList("cindercloth robe")))
    assert.is_nil((S:AddList("  ")))
    assert.are.equal(2, (S:AddList("Runecloth Bag")))
    assert.is_false(S:RenameList(2, "Cindercloth Robe"))
    assert.is_true(S:RenameList(2, "Mooncloth Bag"))
    assert.is_true(S:RemoveList(1))
    assert.are.equal("Mooncloth Bag", S:Lists()[1].name)
  end)

  it("sets, adds up and removes items, with an optional top price", function()
    S:AddList("Robe")
    S:SetItem(1, 4339, 8, 20000) -- Bolt of Mageweave, up to 2g
    S:AddItem(1, 4339, 2)
    assert.are.same({ need = 10, max = 20000 }, S:Lists()[1].items[4339])
    S:SetItem(1, 4339, 10, false)
    assert.is_nil(S:Lists()[1].items[4339].max)
    S:SetItem(1, 4339, 0)
    assert.is_nil(S:Lists()[1].items[4339])
    assert.are.equal(0, S:Count(1))
  end)

  it("counts down from what your characters hold in bags and bank, and prices the rest", function()
    local items = { [4339] = { need = 10, max = 20000 }, [4337] = { need = 4 }, [8170] = { need = 2 } }
    local holdings = {
      ["PvP:Tyken"] = { bags = { [4339] = 3 }, bank = { [4337] = 4 }, auctions = { [4339] = 50 } },
      ["PvP:Alt"] = { bags = { [4339] = 1 } },
    }
    local market = { [4339] = { market = 15000 }, [4337] = { market = 900 } } -- 8170 has no price yet
    local rows, totals = ns.Shopping.Progress(items, holdings, market)
    assert.are.equal(4339, rows[1].itemID) -- still to buy, most expensive first
    assert.are.equal(4, rows[1].held) -- 3 + 1: what's listed on the AH doesn't count
    assert.are.equal(6, rows[1].missing)
    assert.are.equal(90000, rows[1].cost)
    assert.is_true(rows[1].cheap) -- 1g 50s is under the 2g top price
    assert.are.equal(1, rows[1].chars["PvP:Alt"])
    local silk = rows[#rows]
    assert.are.equal(4337, silk.itemID) -- covered: last
    assert.are.equal(0, silk.missing)
    assert.are.same({ missing = 2, cost = 90000, unpriced = 1, done = false, items = 3 }, totals)
    local _, all = ns.Shopping.Progress({ [4337] = { need = 4 } }, holdings, market)
    assert.is_true(all.done)
  end)

  it("shares lists with the guild over sync, and copies a guild member's list", function()
    S:AddList("Robe")
    S:SetItem(1, 4339, 10, 20000)
    S:SetItem(1, 4337, 4)
    S:SetShared(1, true)
    local shared = S:SharedLists()
    assert.are.equal(1, #shared)
    local msg = ns.Sync.EncodeShoppingList("PvP|Horde", "Robe", 1000, shared[1].entries)
    local m = ns.Sync.Decode(msg)
    assert.are.equal("shopping", m.type)
    assert.are.equal("Robe", m.name)
    assert.are.same({ { 4337, 4 }, { 4339, 10, 20000 } }, m.entries)
    -- a guildmate receives it; older versions don't replace newer
    local other = ns.Shopping.New({})
    assert.is_true(other:SetGuildList("Guildie", m.name, m.t, m.entries))
    assert.is_false(other:SetGuildList("Guildie", m.name, m.t - 1, {}))
    assert.are.equal(10, other:GuildLists()[1].items[4339].need)
    local i = other:CopyGuildList("Guildie/Robe")
    assert.are.equal("Robe (Guildie)", other:Lists()[i].name)
    assert.are.equal(20000, other:Lists()[i].items[4339].max)
    -- unsharing sends it empty: it disappears
    assert.is_true(other:SetGuildList("Guildie", "Robe", 2000, {}))
    assert.are.equal(0, #other:GuildLists())
  end)

  it("reads a recipe's reagents through the profession API", function()
    local api = {
      selected = function()
        return 3
      end,
      name = function()
        return "Cindercloth Robe"
      end,
      numReagents = function()
        return 2
      end,
      reagentLink = function(_, r)
        return r == 1 and "|cffffffff|Hitem:4339::::::::60:::::|h[Bolt of Mageweave]|h|r"
          or "|cffffffff|Hitem:4337::::::::60:::::|h[Thick Spider's Silk]|h|r"
      end,
      reagentCount = function(_, r)
        return r == 1 and 5 or 2
      end,
    }
    local recipe = ns.Shopping.Recipe(api)
    assert.are.equal("Cindercloth Robe", recipe.name)
    assert.are.same({ { 4339, 5 }, { 4337, 2 } }, recipe.reagents)
    api.selected = function()
      return 0
    end
    assert.is_nil(ns.Shopping.Recipe(api))
  end)
end)
