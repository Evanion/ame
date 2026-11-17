local addon = require("spec.helpers.addon")

describe("shard keys", function()
  local ns
  before_each(function()
    ns = addon.load({ "Core/Init.lua" })
  end)

  it("maps Forever's internal realm names to their ruleset", function()
    assert.are.equal("PvP", ns.MarketRealm("CAMWOWEU5Realm6PvP"))
    assert.are.equal("PvE", ns.MarketRealm("CAMWOWUS1Realm2PvE"))
    assert.are.equal("RPPvP", ns.MarketRealm("CAMWOWEU1Realm3RPPvP"))
    assert.are.equal("RP", ns.MarketRealm("CAMWOWEU1Realm4RP"))
    assert.are.equal("Forever", ns.MarketRealm("CAMWOWEU1Realm5"))
  end)

  it("keeps other realm names", function()
    assert.are.equal("Stormrage", ns.MarketRealm("Stormrage"))
    assert.are.equal("Stormrage|Horde", ns.ShardKey(ns.MarketRealm("Stormrage"), "Horde"))
  end)
end)

describe("shared helpers", function()
  local ns
  before_each(function()
    ns = addon.load({ "Core/Init.lua" })
  end)

  it("splits a shard key into market and auction house", function()
    assert.are.same({ "PvP", "Neutral" }, { ns.SplitShard("PvP|Neutral") })
    assert.are.same({ "Burning Blade", "Horde" }, { ns.SplitShard(ns.ShardKey("Burning Blade", "Horde")) })
    assert.is_nil(ns.SplitShard("not a shard"))
  end)

  it("reads item IDs from links and plain numbers only", function()
    assert.are.equal(2589, ns.ItemIDFrom("|cffffffff|Hitem:2589::::::::60:::::|h[Linen Cloth]|h|r"))
    assert.are.equal(2589, ns.ItemIDFrom(" 2589 "))
    assert.is_nil(ns.ItemIDFrom("Linen Cloth"))
    assert.is_nil(ns.ItemIDFrom(""))
    assert.is_nil(ns.ItemIDFrom(nil))
  end)

  it("numbers days the way history is stored (UTC)", function()
    assert.are.equal(0, ns.Today(86399))
    assert.are.equal(1, ns.Today(86400))
    assert.are.same({ "Alliance", "Horde", "Neutral" }, ns.HOUSE_ORDER)
  end)
end)
