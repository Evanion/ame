local addon = require("spec.helpers.addon")

describe("Pricing", function()
  local P
  before_each(function()
    P = addon.load({ "Core/Init.lua", "Core/Pricing.lua" }).Pricing
  end)

  local H = 3600
  local MONDAY_NOON = 4 * 86400 + 12 * H -- epoch day 4 was a Monday

  -- a scan of an item: lowest price and the ladder (units within 0/2/5/10/20% of it)
  local function obs(t, minPrice, ladder, qty)
    return { t = t, min = minPrice, ladder = ladder, qty = qty or ladder[#ladder] }
  end

  local function flat(demand, inflow, confidence)
    local p = P.Params(nil, nil, { sellRate = demand * 24 })
    p.inflow = inflow or 0
    if confidence then
      p.spread = confidence
    end
    return p
  end

  describe("ladder", function()
    it("counts the units within each band of the lowest price", function()
      local units, counts = { 100, 101, 104, 109, 119, 200 }, { 1, 2, 3, 4, 5, 6 }
      local order = { 1, 2, 3, 4, 5, 6 }
      assert.are.same({ 1, 3, 6, 10, 15 }, P.Ladder(units, counts, order))
    end)

    it("interpolates units below a price, and treats a ladder-less scan as all at the lowest", function()
      local o = obs(0, 100, { 10, 10, 20, 20, 30 }, 50)
      assert.are.equal(0, P.Below(o, 99))
      assert.are.equal(10, P.Below(o, 100))
      assert.are.equal(15, P.Below(o, 103.5)) -- halfway between the 2% and 5% edges
      assert.are.equal(50, P.Below(o, 1000))
      assert.are.equal(7, P.Below({ min = 100, qty = 7 }, 150))
    end)

    it("turns a ladder into an order book", function()
      local book = P.BookFromObs(obs(0, 100, { 10, 10, 20, 20, 30 }, 40))
      assert.are.same({ 100, 105, 120, 135 }, book.prices)
      assert.are.same({ 10, 10, 10, 10 }, book.qtys)
    end)
  end)

  describe("learning from scans", function()
    it("measures sales, undercutting supply and undercut size between two scans", function()
      local p = P.NewProfile()
      assert.is_false(P.Observe(p, obs(0, 100, { 10, 10, 20, 20, 30 })))
      -- before: 10 at 100, 10 at 104, 10 at 115. Two hours later 8 of the 100s sold and someone listed 4 at 95
      -- (5% under): 4 at 95, 2 at 100, 10 at 104, 10 at 115 - the 115s are past the 20% band of 95
      assert.is_true(P.Observe(p, obs(2 * H, 95, { 4, 4, 4, 16, 16 }, 26)))
      assert.are.equal(1, p.n)
      assert.near(2, p.inflow, 1e-9) -- 4 units / 2 h
      assert.near(0.05, p.cut, 1e-9)
      assert.near(4, p.demand, 1e-9) -- 8 sold / 2 h (cheap end: 20 below 105 before, 16 now, 4 of them new)
    end)

    it("ignores scans too close together or too far apart", function()
      local p = P.NewProfile()
      P.Observe(p, obs(0, 100, { 10, 10, 10, 10, 10 }))
      assert.is_false(P.Observe(p, obs(60, 100, { 5, 5, 5, 5, 5 })))
      assert.is_false(P.Observe(p, obs(60 + 72 * H, 100, { 5, 5, 5, 5, 5 })))
      assert.are.equal(0, p.n)
    end)

    it("learns which hours an item sells in", function()
      local p = P.NewProfile()
      P.Observe(p, obs(4 * 86400, 100, { 100, 100, 100, 100, 100 }))
      for day = 0, 13 do -- two weeks: 1 unit sold per hour in the morning, 10 per hour in the evening
        local base = (4 + day) * 86400 -- midnight
        P.Observe(p, { t = base + 6 * H, min = 100, qty = 1000, ladder = nil })
        P.Observe(p, { t = base + 8 * H, min = 100, qty = 998 })
        P.Observe(p, { t = base + 20 * H, min = 100, qty = 1000 })
        P.Observe(p, { t = base + 22 * H, min = 100, qty = 980 })
      end
      assert.truthy(p.hn > 20)
      assert.truthy((p.hd[22] or 1) > (p.hd[8] or 1)) -- evening sells faster than morning
    end)

    it("calibrates from your own listings", function()
      local p = P.NewProfile()
      for _ = 1, 10 do
        P.Learn(p, 0.8, false) -- the model was too optimistic
      end
      assert.truthy(p.calib < -1)
      assert.are.equal(10, p.no)
      local before = P.Params(p, nil, { sellRate = 24 })
      assert.truthy(before.calib < 0)
      P.Learn(p, nil, true) -- a listing without a recorded chance teaches nothing
      assert.are.equal(10, p.no)
    end)
  end)

  describe("blending with the category", function()
    it("leans on the category until the item has data of its own", function()
      local prior = { comp = 1, cut = 0.1, calib = 0.5, hd = {}, wd = {}, n = 10 }
      local fresh = P.Params(P.NewProfile(), prior, { sellRate = 24 })
      assert.near(1, fresh.inflow, 1e-9) -- comp 1 x demand 1/h
      assert.near(0.5, fresh.calib, 1e-9)
      local known = P.NewProfile()
      known.n, known.demand, known.inflow, known.cut = 100, 2, 0, 0.01
      local own = P.Params(known, prior, { sellRate = 24 })
      assert.truthy(own.inflow < 0.1)
      assert.truthy(own.demand > 1.9)
      assert.are.equal("high", own.confidence)
      assert.are.equal("low", P.Params(nil, nil, nil).confidence)
    end)

    it("summarizes a category from the items that have data", function()
      local a, b = P.NewProfile(), P.NewProfile()
      a.n, a.demand, a.inflow, a.cut = 5, 2, 1, 0.02
      b.n, b.demand, b.inflow, b.cut = 5, 1, 1, 0.04
      local prior = P.Prior({ a, b, P.NewProfile() })
      assert.near(0.75, prior.comp, 1e-9)
      assert.near(0.03, prior.cut, 1e-9)
      assert.are.equal(1, prior.hd[5])
    end)
  end)

  describe("the queue", function()
    it("sells slower, and less surely, when undercutters keep arriving", function()
      local calm, busy = flat(10, 0), flat(10, 8)
      assert.near(2, P.Hours(calm, 20, MONDAY_NOON), 1e-9)
      assert.near(10, P.Hours(busy, 20, MONDAY_NOON), 1e-9)
      assert.truthy(P.Chance(calm, 20, 4, MONDAY_NOON) > P.Chance(busy, 20, 4, MONDAY_NOON))
      assert.near(0.5, P.Chance(calm, 40, 4, MONDAY_NOON), 1e-9) -- exactly enough capacity: a coin flip
    end)

    it("counts listings at the same price as ahead of you", function()
      local book = { prices = { 100, 110 }, qtys = { 5, 7 } }
      assert.are.equal(0, P.Ahead(book, 99))
      assert.are.equal(5, P.Ahead(book, 100))
      assert.are.equal(12, P.Ahead(book, 200))
    end)
  end)

  describe("suggestions", function()
    local book = { prices = { 1000, 1050, 1100, 1300 }, qtys = { 10, 10, 30, 50 } }

    it("prices behind the cheap listings when they sell in time anyway, not 1c under the lowest", function()
      local fast = P.Suggest(book, flat(5, 0), { qty = 1, hours = 24, now = MONDAY_NOON, reference = 1100 })
      assert.truthy(fast.normal.price > 999)
      assert.truthy(fast.quick.price <= fast.normal.price)
      assert.truthy(fast.normal.price <= fast.patient.price)
      assert.is_false(fast.hold)
    end)

    it("goes lower when the item barely moves", function()
      local fast = P.Suggest(book, flat(5, 0), { hours = 24, now = MONDAY_NOON, reference = 1100 })
      local slow = P.Suggest(book, flat(0.2, 0), { hours = 24, now = MONDAY_NOON, reference = 1100 })
      assert.truthy(slow.normal.price < fast.normal.price)
    end)

    it("weighs the deposit lost on a listing that doesn't sell", function()
      local free = P.Suggest(book, flat(0.5, 0), { hours = 24, now = MONDAY_NOON, reference = 1100 })
      local costly =
        P.Suggest(book, flat(0.5, 0), { hours = 24, now = MONDAY_NOON, reference = 1100, deposit = 100000 })
      assert.truthy(costly.normal.chance >= free.normal.chance)
    end)

    it("never suggests below the vendor price, and says when to hold", function()
      local dead = P.Suggest(book, flat(0.01, 0), { hours = 2, now = MONDAY_NOON, vendor = 1200, reference = 1100 })
      assert.truthy(dead.quick.price > 1200)
      assert.is_true(dead.hold)
      -- the vendor pays more than anyone sensible would: the floor is the only answer, not an error
      local vendor = P.Suggest(book, flat(1, 0), { hours = 24, now = MONDAY_NOON, vendor = 5000, ceiling = 2000 })
      assert.are.equal(5001, vendor.normal.price)
    end)

    it("works from the usual price when nothing is listed", function()
      local s = P.Suggest({ prices = {}, qtys = {} }, flat(1, 0), { hours = 24, now = MONDAY_NOON, reference = 500 })
      assert.truthy(s.normal.price >= 450 and s.normal.price <= 750)
      assert.is_nil(P.Suggest({ prices = {}, qtys = {} }, flat(1, 0), {}))
    end)
  end)

  it("stores a profile compactly and reads it back", function()
    local p = P.NewProfile()
    P.Observe(p, obs(MONDAY_NOON, 100, { 10, 10, 20, 20, 30 }))
    P.Observe(p, obs(MONDAY_NOON + 2 * H, 95, { 4, 4, 6, 16, 26 }))
    P.Observe(p, obs(MONDAY_NOON + 4 * H, 95, { 2, 2, 4, 14, 24 }))
    P.Learn(p, 0.6, true)
    local s = P.Encode(p)
    assert.truthy(#s < 200)
    local q = P.Decode(s)
    assert.are.equal(p.n, q.n)
    assert.near(p.demand, q.demand, p.demand * 1e-3)
    assert.near(p.calib, q.calib, 1e-3)
    assert.are.same(p.last.ladder, q.last.ladder)
    assert.are.equal(p.hn, q.hn)
    assert.near(p.hd[15] or 1, q.hd[15], 1e-3)
    assert.are.equal(P.Encode(q), s)
    assert.are.equal(p.n, P.Samples(s))
    assert.are.equal(p.last.t, P.LastSeen(s))
    assert.is_nil(P.LastSeen(P.Encode(P.NewProfile())))
  end)
end)
