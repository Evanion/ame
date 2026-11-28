-- Baganator plugins (Core/UI/Baganator.lua): what fits on a bag slot, and what counts as junk.
local addon = require("spec.helpers.addon")

describe("Baganator plugins", function()
  local Bag
  before_each(function()
    Bag = addon.load({ "Core/Init.lua", "Core/UI/Widgets.lua", "Core/UI/Baganator.lua" }).Baganator
  end)

  local function plain(s)
    return s and (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
  end

  it("writes a stack's worth in one rounded unit", function()
    assert.are.equal("8c", plain(Bag.SlotMoney(8)))
    assert.are.equal("45s", plain(Bag.SlotMoney(4520)))
    assert.are.equal("2.5g", plain(Bag.SlotMoney(25000)))
    assert.are.equal("3g", plain(Bag.SlotMoney(30000)))
    assert.are.equal("12g", plain(Bag.SlotMoney(123456)))
    assert.are.equal("1.2kg", plain(Bag.SlotMoney(12345678)))
    assert.are.equal("2kg", plain(Bag.SlotMoney(20000000)))
    assert.are.equal("45kg", plain(Bag.SlotMoney(456789012)))
    assert.is_nil(Bag.SlotMoney(0))
    assert.is_nil(Bag.SlotMoney(nil))
  end)

  it("tips as the Selling tab does: Arbitrate, vendor, DE, Sell, or nothing without a price", function()
    local signals = { [1] = "vendor", [2] = "vendor", [3] = "disenchant", [4] = "buy" }
    local where = { [4] = "ah", [5] = "vendor" }
    local api = {
      GetSignal = function(item)
        return signals[item]
      end,
      GetWorth = function(item)
        return where[item] and 100 or nil, where[item]
      end,
    }
    local instead = function(key)
      return key == 1 and { product = 99 } or nil
    end
    assert.are.equal("craft", Bag.Tip(api, 1, instead)) -- a recipe of yours makes it worth more
    assert.are.equal("vendor", Bag.Tip(api, 2, instead))
    assert.are.equal("disenchant", Bag.Tip(api, 3, instead))
    assert.are.equal("sell", Bag.Tip(api, 4, instead))
    assert.is_nil(Bag.Tip(api, 5, instead)) -- only a vendor's price, no signal: no tip (as the Selling tab)
    assert.is_nil(Bag.Tip(api, 6, instead)) -- never priced
    assert.are.equal("Arb", Bag.TIP_TEXT.craft[1])
  end)

  it(
    "the worth sort covers your bags, or the character bank: all its tabs or the one shown, no reagent bank",
    function()
      local ns = addon.load({ "Core/Init.lua", "Core/Trading.lua", "Core/UI/Widgets.lua", "Core/UI/Baganator.lua" })
      Bag = ns.Baganator
      assert.are.same({ 0, 1, 2, 3, 4 }, Bag.SortBags("backpack"))
      _G.Enum = { BagIndex = { CharacterBankTab_1 = 6, CharacterBankTab_2 = 7, CharacterBankTab_3 = 8 } }
      assert.are.same({ 6, 7, 8 }, Bag.SortBags("character_bank"))
      assert.are.same({ 7 }, Bag.SortBags("character_bank", 2))
      _G.Enum = { BagIndex = { Bank = -1, Reagentbank = -3, ReagentBag = 5 } }
      assert.are.same({ -1, 6, 7, 8, 9, 10, 11, 12 }, Bag.SortBags("character_bank", 2)) -- no tabs: the whole bank
      _G.Enum = nil
    end
  )

  describe("the worth sort's plan", function()
    -- apply the swaps to the cells, as the game would
    local function apply(cells, swaps)
      local out = {}
      for i = 1, #cells do
        out[i] = cells[i]
      end
      for _, sw in ipairs(swaps) do
        out[sw[1]], out[sw[2]] = out[sw[2]], out[sw[1]]
      end
      return out
    end
    local function keys(cells)
      local out = {}
      for i, c in ipairs(cells) do
        out[i] = c and c.key or "-"
      end
      return table.concat(out, " ")
    end
    local A, B, C = { key = "a", worth = 500 }, { key = "b", worth = 50 }, { key = "c", worth = 5 }

    it("puts the most valuable first, the empty slots last", function()
      local cells = { C, false, B, A, false }
      assert.are.equal("a b c - -", keys(apply(cells, Bag.SortPlan(cells))))
    end)

    it("reversed: the most valuable in the last slot", function()
      local cells = { A, false, B, C }
      assert.are.equal("- c b a", keys(apply(cells, Bag.SortPlan(cells, true))))
    end)

    it("never swaps two stacks of one item (the game would merge them), and does nothing when sorted", function()
      local A2 = { key = "a", worth = 200 }
      local cells = { B, A, A2, false }
      local swaps = Bag.SortPlan(cells)
      local now = { B, A, A2, false } -- the bags as each swap finds them
      for _, sw in ipairs(swaps) do
        local x, y = now[sw[1]], now[sw[2]]
        assert.is_false(x and y and x.key == y.key or false)
        now[sw[1]], now[sw[2]] = y, x
      end
      local sorted = apply(cells, swaps)
      assert.are.equal("a a b -", keys(sorted))
      assert.are.same({}, Bag.SortPlan(sorted))
    end)

    it("leaves unpriced items after the priced ones", function()
      local X = { key = "x", worth = 0 }
      local cells = { X, B, false, A }
      assert.are.equal("a b x -", keys(apply(cells, Bag.SortPlan(cells))))
    end)
  end)
end)
