local addon = require("spec.helpers.addon")

describe("Backfill.FromAuctionator", function()
  local Backfill
  local DAY = 86400
  -- Auctionator counts days from its own epoch (Auctionator.Constants.SCAN_DAY_0)
  local DAY0 = 1000 * DAY

  before_each(function()
    Backfill = addon.load({ "Core/Init.lua", "Core/Backfill.lua" }).Backfill
  end)

  -- shape of Auctionator.Database.db (see Auctionator Source/Database/Mixin.lua):
  -- [dbKey] = { l = { [day] = lowest low }, h = { [day] = highest low }, a = { [day] = max available }, m = last }
  local db = {
    ["2589"] = { l = { ["5"] = 80 }, h = { ["5"] = 120, ["6"] = 100 }, a = { ["5"] = 40 }, m = 100 },
    ["g:19019:60"] = { l = {}, h = { ["5"] = 999 }, m = 999 }, -- gear key with item level: skipped in M1
    ["broken"] = { h = "nope" },
  }

  it("groups points by our UTC day and keeps only plain itemID keys", function()
    local days = Backfill.FromAuctionator(db, DAY0)
    assert.are.same(
      { [1005] = true, [1006] = true },
      (function()
        local s = {}
        for d in pairs(days) do
          s[d] = true
        end
        return s
      end)()
    )
    assert.are.equal(1, #days[1005])
    assert.are.equal(2589, days[1005][1][1])
  end)

  it("maps lowest/highest daily minimum to min and a midpoint market", function()
    local r = Backfill.FromAuctionator(db, DAY0)[1005][1]
    -- { id, min, market, median, qty, auctions, scans, high (Auctionator's highest minimum of the day) }
    assert.are.same({ 2589, 80, 100, 100, 40, 0, 1, 120 }, r)
  end)

  it("uses the high when there is no separate low, and qty 0 when unknown", function()
    local r = Backfill.FromAuctionator(db, DAY0)[1006][1]
    assert.are.same({ 2589, 100, 100, 100, 0, 0, 1, 100 }, r)
  end)

  it("returns nothing for missing or malformed input", function()
    assert.are.same({}, Backfill.FromAuctionator(nil, DAY0))
    assert.are.same({}, Backfill.FromAuctionator({}, nil))
  end)
end)
