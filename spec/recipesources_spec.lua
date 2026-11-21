local addon = require("spec.helpers.addon")

describe("RecipeSources", function()
  local RS
  before_each(function()
    RS = addon.load({ "Core/Init.lua", "Core/Codec.lua", "Core/RecipeSources.lua" }).RecipeSources
  end)

  local function money(c)
    return c .. "c"
  end

  it("keeps each vendor and drop once, vendors first, the newest sighting's price", function()
    local db = {}
    assert.is_true(RS.Add(db, 7978, { kind = "drop", npc = "Venture Co. Enforcer", zone = "Stonetalon", t = 1 }))
    assert.is_true(RS.Add(db, 7978, { kind = "vendor", npc = "Kulwia", zone = "Stonetalon", price = 120, t = 2 }))
    assert.is_false(RS.Add(db, 7978, { kind = "vendor", npc = "Kulwia", zone = "Stonetalon", price = 150, t = 3 }))
    assert.are.equal(2, #db[7978])
    assert.are.equal("vendor", db[7978][1].kind)
    assert.are.equal(150, db[7978][1].price)
    assert.are.same(
      { "Sold by Kulwia, Stonetalon  ·  150c", "Drops from Venture Co. Enforcer, Stonetalon" },
      RS.Lines(db[7978], nil, money)
    )
  end)

  it("falls back to the game's own source text, on one line without colour codes", function()
    local text = "|cFFFFD200Vendor: |rKulwia|n|cFFFFD200Zone: |rStonetalon Mountains"
    assert.are.same({ "Vendor: Kulwia  ·  Zone: Stonetalon Mountains" }, RS.Lines(nil, text, money))
    assert.are.same({}, RS.Lines(nil, nil, money))
  end)

  it("round-trips sources over sync, names cleaned of the separators", function()
    local db = {}
    RS.Add(db, 7978, { kind = "vendor", npc = "Kul;wia", zone = "Stone|talon", price = 12000, t = 5 })
    RS.Add(db, 7979, { kind = "drop", npc = "Ogre", t = 5 })
    local back = RS.Decode(RS.Encode(db), 9, "Guild Mate")
    table.sort(back, function(a, b)
      return a.item < b.item
    end)
    assert.are.same({
      item = 7978,
      src = { kind = "vendor", npc = "Kulwia", zone = "Stonetalon", price = 12000, t = 9, by = "Guild Mate" },
    }, back[1])
    assert.are.same({ item = 7979, src = { kind = "drop", npc = "Ogre", t = 9, by = "Guild Mate" } }, back[2])
  end)
end)
