-- Holdings: the one place your characters' items are added up.
local addon = require("spec.helpers.addon")

describe("Holdings", function()
  local H
  local holdings = {
    ["PvP:Kke"] = { bags = { [2589] = 20 }, bank = { [2589] = 5, [2592] = 3 }, auctions = { [2589] = 40 } },
    ["PvP:Alt"] = { bags = { [2589] = 1 }, mail = { [2589] = 99 } },
  }
  before_each(function()
    H = addon.load({ "Core/Init.lua" }).Holdings
  end)

  local guildBanks = { ["PvP:Guild"] = { tabs = { [1] = { [2589] = 7 }, [2] = { [2589] = 1 } } } }

  it("counts only the places asked for, per character and guild bank", function()
    local m = H.Map(holdings, "usable", nil, guildBanks)
    assert.are.equal(133, m[2589].qty) -- bags, bank, mailbox and guild banks, not the AH
    assert.are.same({ ["PvP:Kke"] = 25, ["PvP:Alt"] = 100 }, m[2589].chars)
    assert.are.same({ ["PvP:Guild"] = 8 }, m[2589].guilds)
    assert.are.equal(173, H.Map(holdings, "owned", nil, guildBanks)[2589].qty) -- what's on sale is owned too
    assert.are.equal(125, H.Map(holdings, "usable")[2589].qty) -- no guild banks given: none counted
    assert.are.equal(99, H.Map(holdings, { "mail" })[2589].qty)
  end)

  it("keeps to the characters asked for: one character has no guild bank", function()
    local t = H.Totals(holdings, "usable", H.Keep("PvP:Alt"), guildBanks)
    assert.are.same({ [2589] = 100 }, t)
    assert.is_nil(H.Keep("account"))
    assert.is_true(H.Keep(function()
      return true
    end)("x"))
  end)

  it("draws from a stock: what one use takes, the next can't", function()
    local r = H.Reserve({ [2589] = 5 })
    assert.are.equal(3, r:Take(2589, 3))
    assert.are.equal(2, r:Take(2589, 3))
    assert.are.equal(0, r:Left(2589))
    local f = H.Reserve(function(key)
      return key == 1 and 4 or 0
    end)
    assert.are.equal(4, f:Left(1))
    assert.are.equal(0, f:Take(2, 1))
  end)
end)
