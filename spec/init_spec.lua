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

  it("keys random-suffix variants apart from the plain item", function()
    local link = "|cff1eff00|Hitem:15211::::::1234:9876:60:::::|h[Raider Shortsword of Magic]|h|r"
    local key = ns.ItemIDFrom(link)
    assert.are.equal(15211 + 1234 * ns.SUFFIX_STEP, key)
    assert.are.same({ 15211, 1234 }, { ns.SplitKey(key) })
    assert.are.equal(15211, ns.BaseID(key))
    assert.is_true(ns.IsVariant(key))
    assert.is_false(ns.IsVariant(15211))
    assert.are.equal("item:15211::::::1234", ns.ItemString(key))
    assert.are.equal("item:15211", ns.ItemString(15211))
    assert.are.equal(key, ns.ItemIDFrom(ns.ItemString(key)))
    -- negative (scaled) suffixes, and the same bucket as the base item
    local neg = ns.ItemIDFrom("item:15211:0:0:0:0:0:-37:12345")
    assert.are.same({ 15211, -37 }, { ns.SplitKey(neg) })
    assert.are.equal(15211 % 32, neg % 32)
    assert.are.equal(15211 % 32, key % 32)
    -- a zero suffix is the plain item
    assert.are.equal(2589, ns.ItemIDFrom("item:2589:0:0:0:0:0:0:0"))
    assert.are.equal(2589, ns.ItemKey(2589, nil))
  end)

  it("reads WoW Forever links: the suffix is a bonus ID, mapped to the auction house's suffix once learned", function()
    -- real links from the game (Syndicator's saved data)
    local magic = "|cff1eff00|Hitem:15210::::::::1:1488:::1:12917::::::|h[Raider Shortsword of Magic]|h|r"
    local eagle = "|cff1eff00|Hitem:15210::::::::1:1488:::1:12718:1:28:5254:::::|h[Raider Shortsword of the Eagle]|h|r"
    local id, field, bonuses = ns.ParseItemString(magic)
    assert.are.same({ 15210, 0, "12917" }, { id, field, bonuses })
    assert.are.equal("12718", select(3, ns.ParseItemString(eagle)))
    assert.are.equal(15210, ns.ItemIDFrom(magic)) -- not learned yet: the plain item
    ns.suffixMap["15210:12917"] = 14324
    assert.are.equal(ns.ItemKey(15210, 14324), ns.ItemIDFrom(magic))
    ns.suffixMap["12718"] = 14301 -- learned on another item: any item's link with that bonus
    assert.are.equal(ns.ItemKey(15210, 14301), ns.ItemIDFrom(eagle))
    assert.are.equal(1478, ns.ItemIDFrom("|Hitem:1478::::::::39:1484:::::::::|h[Scroll of Protection II]|h"))
  end)

  it("numbers days the way history is stored (UTC)", function()
    assert.are.equal(0, ns.Today(86399))
    assert.are.equal(1, ns.Today(86400))
    assert.are.same({ "Alliance", "Horde", "Neutral" }, ns.HOUSE_ORDER)
  end)
end)
