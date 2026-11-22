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

  it("counts only the places asked for, per character", function()
    local m = H.Map(holdings, "stored")
    assert.are.equal(26, m[2589].qty) -- bags and bank, not the AH or the mailbox
    assert.are.same({ ["PvP:Kke"] = 25, ["PvP:Alt"] = 1 }, m[2589].chars)
    assert.are.equal(66, H.Map(holdings, "listed")[2589].qty) -- the portfolio counts what's on sale too
    assert.are.equal(99, H.Map(holdings, { "mail" })[2589].qty)
  end)

  it("keeps to the characters asked for", function()
    local t = H.Totals(holdings, "stored", function(key)
      return key == "PvP:Alt"
    end)
    assert.are.same({ [2589] = 1 }, t)
  end)
end)
