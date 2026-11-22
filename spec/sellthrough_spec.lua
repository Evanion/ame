local addon = require("spec.helpers.addon")

describe("SellThrough", function()
  local ST

  setup(function()
    ST = addon.load({ "Core/Init.lua", "Core/Codec.lua", "Core/SellThrough.lua" }).SellThrough
  end)

  local DAY = 86400

  it("counts units per outcome and fades old ones", function()
    local r = ST.New()
    assert.is_true(ST.Add(r, "sold", 5, 1000))
    assert.is_true(ST.Add(r, "expired", 20, 1000))
    assert.is_true(ST.Add(r, "cancelled", 10, 1000))
    assert.is_false(ST.Add(r, "bogus", 1, 1000))
    assert.is_false(ST.Add(r, "sold", 0, 1000))
    assert.are.same({ s = 5, e = 20, c = 10, n = 3, t = 1000 }, r)
    ST.Decay(r, 1000 + ST.HALF_LIFE)
    assert.are.equal(2.5, r.s)
    assert.are.equal(1.5, r.n)
    assert.are.same(r, ST.Decode(ST.Encode(r)))
  end)

  it("combines yours with guildmates', fading each by its age", function()
    local own = { s = 2, e = 8, c = 0, n = 2, t = 0 }
    local peer = { t = 0, r = { s = 0, e = 10, c = 0, n = 2, t = 0 } }
    local tot = ST.Combine(own, { peer }, ST.HALF_LIFE)
    assert.are.equal(1, tot.s)
    assert.are.equal(9, tot.e)
    assert.are.equal(2, tot.n)
    assert.are.equal(1, tot.peers)
    local p, w = ST.Rate(tot)
    assert.are.equal(0.1, p)
    assert.are.equal(2 / (2 + ST.WEIGHT), w)
    assert.is_nil(ST.Combine(nil, {}, 0))
    assert.is_nil(ST.Combine({ s = 0, e = 0, c = 0, n = 0, t = 0 }, nil, 0))
  end)

  it("Raptor Hide: never sells, so it's worth the vendor price and only listing loses the deposit", function()
    -- 1.9k listed, ~5k a day leaving the AH (expired and reposted), market 2s41, vendor 2s08
    local s = { market = 241, sellRate = 5000, qty = 1900 }
    local tot = { s = 0, e = 200, c = 0, n = 30, peers = 3 }
    assert.is_true(ST.Apply(s, tot, 208))
    local w = 30 / 33
    assert.are.equal(0, s.sellThrough)
    assert.are.equal(5000, s.churnRate)
    assert.are.equal(5000 * (1 - w), s.sellRate) -- what's left of the scans' guess
    assert.are.equal(w * 208 + (1 - w) * 241, s.value)
    assert.are.equal(3, s.stPeers)
    -- a listing nets about the lost deposit (125c of 24 h): far below the vendor
    local net = ST.Net(s, 0.05, 125)
    assert.truthy(net < 0, net)
  end)

  it("a fast seller keeps its deposit: listing nets the market price after the cut", function()
    local s = { market = 1000 }
    ST.Apply(s, { s = 1000, e = 0, c = 0, n = 1000, peers = 0 }, 100)
    assert.near(950, ST.Net(s, 0.05, 300), 2)
    -- no outcomes: the cautious view (deposit lost)
    assert.are.equal(650, ST.Net({ market = 1000 }, 0.05, 300))
  end)

  it("shares items compactly and clamps junk it receives", function()
    local text = ST.EncodeItems({
      { 2589, { s = 1.25, e = 3, c = 0, n = 2 }, -0.5, 4, 0.75, 3 },
      { 15211 + 14324 * 1000000, { s = 0, e = 1e9, c = 0, n = 1e9 }, 9, 1e9, -9, 0 },
    })
    local items = ST.DecodeItems(text, 500)
    local a = items[2589]
    assert.are.same({ s = 1.3, e = 3, c = 0, n = 2, t = 500 }, a.r) -- tenths
    assert.are.equal(-0.5, a.calib)
    assert.are.equal(4, a.no)
    assert.are.equal(0.75, a.speed)
    local junk = items[15211 + 14324 * 1000000]
    assert.are.equal(ST.MAX_UNITS, junk.r.e)
    assert.are.equal(ST.MAX_OUTCOMES, junk.r.n)
    assert.are.equal(2, junk.calib)
    assert.are.equal(-2, junk.speed)
    assert.are.same({}, ST.DecodeItems("x:y;1:2", 0))
  end)

  it("merges guildmates' posting outcomes into a profile, weighted by how many each had", function()
    local p = { calib = 1, no = 1, speed = 0, sn = 0, n = 7 }
    local q = ST.MergeProfile(p, { { calib = -1, no = 3, speed = 1, sn = 2 } })
    assert.are.equal(-0.5, q.calib)
    assert.are.equal(4, q.no)
    assert.are.equal(1, q.speed)
    assert.are.equal(2, q.sn)
    assert.are.equal(7, q.n)
    assert.are.equal(1, p.calib) -- yours unchanged
    assert.are.equal(p, ST.MergeProfile(p, {}))
  end)

  it("fades a whole day's outcomes only slightly", function()
    local r = ST.New(1)
    ST.Add(r, "sold", 10, 1)
    ST.Decay(r, 1 + DAY)
    assert.truthy(r.s > 9.6 and r.s < 10)
  end)

  it("estimates what sells of items nobody listed from the market's own sell-through", function()
    assert.are.equal(ST.DEFAULT_SHARE, ST.Prior({})) -- nothing to go on yet
    -- many outcomes, a fifth sold: the share moves most of the way there
    local through = { [1] = { s = 20, e = 80, c = 0, n = 200 } }
    local share = ST.Prior(through)
    assert.truthy(share > 0.2 and share < 0.22, share)
    local s = { sellRate = 300 }
    ST.Estimate(s, share)
    assert.are.equal(300, s.churnRate)
    assert.are.equal(300 * share, s.sellRate)
    assert.are.equal(share, s.stPrior)
    -- an item with a few outcomes of its own leans on that share for the rest
    local own = { sellRate = 100 }
    ST.Apply(own, { s = 1, e = 0, c = 0, n = 1 }, nil, 0.5)
    local w = 1 / (1 + ST.WEIGHT)
    assert.are.equal(100 * (w * 1 + (1 - w) * 0.5), own.sellRate)
  end)
end)
