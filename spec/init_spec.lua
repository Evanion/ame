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
