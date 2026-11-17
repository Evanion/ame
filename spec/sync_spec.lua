local addon = require("spec.helpers.addon")

describe("Sync (protocol core)", function()
  local Sync
  local H = 3600

  before_each(function()
    Sync = addon.load({ "Core/Init.lua", "Core/Codec.lua", "Core/Sync.lua" }).Sync
  end)

  local raw = {
    { t = 1000 * H, src = "Tyken Evanion", k = "full", s = "packedA" },
    { t = 1001 * H, src = "Tyken Evanion", k = "partial", s = "p" },
    { t = 1010 * H, src = "Guild Mate", k = "full", s = "packedB" },
  }

  it("inventory lists full scans only, newest first, capped", function()
    local inv = Sync.Inventory(raw, 10)
    assert.are.equal(2, #inv)
    assert.are.equal(1010 * H, inv[1].t)
    assert.are.equal("Guild Mate", inv[1].src)
    assert.are.equal(1, #Sync.Inventory(raw, 1))
  end)

  it("announce round-trips and is small", function()
    local msg = Sync.EncodeAnnounce("Realm|Horde", Sync.Inventory(raw, 10))
    assert.is_true(#msg < 120, #msg)
    local a = Sync.Decode(msg)
    assert.are.equal("announce", a.type)
    assert.are.equal("Realm|Horde", a.shard)
    assert.are.equal(2, #a.scans)
    assert.are.equal("Guild Mate", a.scans[1].src)
    assert.are.equal(1010 * H, a.scans[1].t)
  end)

  it("wants only scans it doesn't have, for its own shard, within the window", function()
    local announce = Sync.Decode(Sync.EncodeAnnounce("Realm|Horde", Sync.Inventory(raw, 10)))
    local mine = { { t = 1000 * H, src = "Tyken Evanion", k = "full" } }
    local want = Sync.Wanted(announce, "Realm|Horde", mine, 1012 * H, 48 * H)
    assert.are.equal(1, #want)
    assert.are.equal("Guild Mate", want[1].src)
    assert.are.same({}, Sync.Wanted(announce, "Realm|Alliance", mine, 1012 * H, 48 * H))
    assert.are.same({}, Sync.Wanted(announce, "Realm|Horde", mine, 1100 * H, 48 * H)) -- too old
  end)

  it("request and scan messages round-trip", function()
    local r = Sync.Decode(Sync.EncodeRequest("Realm|Horde", 1010 * H, "Guild Mate"))
    assert.are.same({ type = "request", shard = "Realm|Horde", t = 1010 * H, src = "Guild Mate" }, r)
    local s = Sync.Decode(Sync.EncodeScan("Realm|Horde", raw[3]))
    assert.are.equal("scan", s.type)
    assert.are.equal("packedB", s.packed)
    assert.are.equal("Guild Mate", s.src)
    assert.are.equal("full", s.kind)
  end)

  it("ignores garbage and other protocol versions", function()
    assert.is_nil(Sync.Decode("hello"))
    assert.is_nil(Sync.Decode("9|A|x"))
    assert.is_nil(Sync.Decode(""))
  end)

  describe("Plausible", function()
    local function snap(prices)
      local s = { ids = {}, market = {} }
      for i, p in ipairs(prices) do
        s.ids[i], s.market[i] = i, p
      end
      return s
    end
    local reference = { [1] = { market = 100 }, [2] = { market = 200 }, [3] = { market = 300 }, [4] = { market = 50 } }

    it("accepts a scan close to our own market data", function()
      assert.is_true(Sync.Plausible(snap({ 110, 190, 320, 55 }), reference))
    end)

    it("rejects a scan where most known items are wildly off (poisoning)", function()
      local ok, why = Sync.Plausible(snap({ 10000, 1, 30000, 55 }), reference)
      assert.is_false(ok)
      assert.truthy(why)
    end)

    it("accepts when we have nothing to compare against", function()
      assert.is_true(Sync.Plausible(snap({ 1, 2, 3 }), {}))
    end)
  end)

  describe("ParseBlocklist", function()
    it("reads 'AME block:' lines from the guild info, case-insensitively", function()
      local set = Sync.ParseBlocklist(
        "Welcome!\nRaids Wed/Sun\nAME block: Spam Bot, Price Fixer\nane block: nope\name BLOCK:  Third One  "
      )
      assert.are.same({ ["spam bot"] = "Spam Bot", ["price fixer"] = "Price Fixer", ["third one"] = "Third One" }, set)
    end)

    it("handles no guild info", function()
      assert.are.same({}, Sync.ParseBlocklist(nil))
      assert.are.same({}, Sync.ParseBlocklist("just a motd"))
    end)
  end)

  it("round-trips a shared watchlist, and an empty one (unshared)", function()
    local m = Sync.Decode(Sync.EncodeWatchlist("PvP|Horde", "Herbs|;", 1794800000, { 2449, 785, 3820 }))
    assert.are.equal("watchlist", m.type)
    assert.are.equal("PvP|Horde", m.shard)
    assert.are.equal("Herbs", m.name)
    assert.are.equal(1794800000, m.t)
    assert.are.same({ 2449, 785, 3820 }, m.ids)
    assert.are.same({}, Sync.Decode(Sync.EncodeWatchlist("PvP|Horde", "Herbs", 1, {})).ids)
  end)
end)
