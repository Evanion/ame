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

  it("counts grey items and VENDOR items as junk, nothing else", function()
    local signals = { [1] = "vendor", [2] = "sell" }
    local api = {
      GetSignal = function(item)
        return signals[item]
      end,
    }
    assert.is_true(Bag.IsJunk(api, 0, 3))
    assert.is_true(Bag.IsJunk(api, 1, 1))
    assert.is_false(Bag.IsJunk(api, 1, 2))
    assert.is_false(Bag.IsJunk(api, 2, 3)) -- AME knows nothing about it: not junk
  end)
end)
