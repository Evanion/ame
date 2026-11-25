local addon = require("spec.helpers.addon")

describe("MarketFilter", function()
  local MF
  -- itemID -> { classID, subClassID, name, quality }
  local facts = {
    [1] = { classID = 7, subClassID = 5, name = "Linen Cloth", quality = 1 },
    [2] = { classID = 7, subClassID = 5, name = "Wool Cloth", quality = 1 },
    [3] = { classID = 7, subClassID = 7, name = "Copper Ore", quality = 1 },
    [4] = { classID = 2, subClassID = 0, name = "Arcanite Reaper", quality = 4 },
    [5] = { classID = 0, subClassID = 1 }, -- name not cached yet
  }
  local function info(id)
    return facts[id]
  end
  local index = {
    items = {
      [1] = { itemID = 1, market = 100, score = 5, signal = "buy" },
      [2] = { itemID = 2, market = 300, score = 9 },
      [3] = { itemID = 3, market = 50, score = 1, signal = "sell" },
      [4] = { itemID = 4, market = 5000000, score = 3 },
      [5] = { itemID = 5, market = 200, score = 7 },
    },
  }
  local function ids(list)
    local out = {}
    for i, s in ipairs(list) do
      out[i] = s.itemID
    end
    return out
  end

  before_each(function()
    MF = addon.load({ "Core/Init.lua", "Core/MarketFilter.lua" }).MarketFilter
  end)

  it("builds categories in auction house order with subclass counts", function()
    local cats = MF.Categories(index, info)
    local order = {}
    for i, c in ipairs(cats) do
      order[i] = c.classID
    end
    assert.are.same({ 2, 0, 7 }, order) -- Weapon, Consumable, Trade Goods
    local trade = cats[3]
    assert.are.equal(3, trade.count)
    assert.are.same({ 5, 7 }, { trade.subs[1].subClassID, trade.subs[2].subClassID })
    assert.are.equal(2, trade.subs[1].count)
  end)

  it("leaves hidden items out of the list and the category counts", function()
    local hide = { [2] = true }
    assert.are.same({ 5, 1, 4, 3 }, ids(MF.Apply(index, { hide = hide }, info)))
    assert.are.same({ 2 }, ids(MF.Apply(index, { only = hide }, info))) -- the Hidden list itself
    local trade
    for _, c in ipairs(MF.Categories(index, info, hide)) do
      if c.classID == 7 then
        trade = c
      end
    end
    assert.are.equal(2, trade.count)
  end)

  it("sorts by score by default and filters by category", function()
    assert.are.same({ 2, 5, 1, 4, 3 }, ids(MF.Apply(index, {}, info)))
    assert.are.same({ 2, 1, 3 }, ids(MF.Apply(index, { classID = 7 }, info)))
    assert.are.same({ 3 }, ids(MF.Apply(index, { classID = 7, subClassID = 7 }, info)))
  end)

  it("searches names case-insensitively and counts unnamed items", function()
    local list, unnamed = MF.Apply(index, { text = "CLOTH" }, info)
    assert.are.same({ 2, 1 }, ids(list))
    assert.are.equal(1, unnamed)
  end)

  it("filters by quality, price range and signal", function()
    assert.are.same({ 4 }, ids(MF.Apply(index, { minQuality = 3 }, info)))
    assert.are.same({ 2, 5, 1 }, ids(MF.Apply(index, { minPrice = 100, maxPrice = 300 }, info)))
    assert.are.same({ 3 }, ids(MF.Apply(index, { signal = "sell" }, info)))
  end)

  it("sorts by name A-Z by default, unnamed last", function()
    assert.are.same({ 4, 3, 1, 2, 5 }, ids(MF.Apply(index, { sortKey = "name" }, info)))
    assert.are.same({ 5, 2, 1, 3, 4 }, ids(MF.Apply(index, { sortKey = "name", ascending = true }, info)))
  end)

  it("sorts ascending on numeric columns", function()
    assert.are.same({ 3, 1, 5, 2, 4 }, ids(MF.Apply(index, { sortKey = "market", ascending = true }, info)))
  end)

  it("filters by required level and item level; items whose facts aren't loaded are left out", function()
    local gear = {
      [10] = { classID = 4, name = "Cap", quality = 2, minLevel = 20, level = 25 },
      [11] = { classID = 4, name = "Robe", quality = 2, minLevel = 35, level = 40 },
      [12] = { classID = 4, name = "Boots", quality = 2, minLevel = 0, level = 5 },
      [13] = { classID = 4 }, -- not loaded
    }
    local idx = { items = {} }
    for id in pairs(gear) do
      idx.items[id] = { itemID = id, score = id }
    end
    local function gearInfo(id)
      return gear[id]
    end
    assert.are.same({ 11, 10 }, ids(MF.Apply(idx, { minLevel = 20 }, gearInfo)))
    assert.are.same({ 10 }, ids(MF.Apply(idx, { minLevel = 20, maxLevel = 30 }, gearInfo)))
    assert.are.same({ 12 }, ids(MF.Apply(idx, { maxItemLevel = 10 }, gearInfo)))
    assert.are.same({ 11 }, ids(MF.Apply(idx, { minItemLevel = 30 }, gearInfo)))
  end)

  it("Usable by you leaves out what you can't use, and keeps what isn't known yet", function()
    local usable = { [1] = true, [2] = false } -- 3, 4, 5: not known yet
    local list = MF.Apply(index, {
      usable = function(id)
        return usable[id]
      end,
    }, info)
    assert.are.same({ 5, 1, 4, 3 }, ids(list))
  end)
end)

describe("MarketFilter.FindByName", function()
  it("ranks exact names, then names starting with the text, then the rest; shorter first", function()
    local MF = require("spec.helpers.addon").load({ "Core/Init.lua", "Core/MarketFilter.lua" }).MarketFilter
    local names = {
      [1] = "Swiftthistle",
      [2] = "Swiftness Potion",
      [3] = "Recipe: Swiftness Potion",
      [4] = "Swift",
      [5] = "Linen Cloth",
    }
    local index = { items = { [1] = {}, [2] = {}, [3] = {}, [4] = {}, [5] = {}, [6] = {} } }
    local hits = MF.FindByName(index, "SWIFT", function(id)
      return names[id] and { name = names[id], quality = 1 } or {}
    end, 3)
    local ids = {}
    for i, h in ipairs(hits) do
      ids[i] = h.itemID
    end
    assert.are.same({ 4, 1, 2 }, ids)
    assert.are.same({}, MF.FindByName(index, "", function() end))
  end)
end)
