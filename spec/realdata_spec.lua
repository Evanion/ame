-- The analytics, VENDOR and posting-price models over real auction house data (spec/fixtures/market.lua, made with
-- scripts/fixture-from-sv.lua from a real client's saved data: 120 items of one house, market data only).
local addon = require("spec.helpers.addon")

describe("real market data", function()
  local ns, fixture
  before_each(function()
    ns = addon.load({
      "Core/Init.lua",
      "Core/Codec.lua",
      "Core/Analytics.lua",
      "Core/Arbitrage.lua",
      "Core/Pricing.lua",
      "Core/MarketStats.lua",
    })
    fixture = dofile("spec/fixtures/market.lua")
  end)

  -- fixture points -> the series Analytics expects (as Store:Series returns them)
  local function series(item)
    local out = {}
    for i, p in ipairs(item.points) do
      out[i] = {
        res = "day",
        day = p[1],
        min = p[2],
        market = p[3],
        median = p[4],
        qty = p[5],
        scans = p[6],
        high = p[7] > 0 and p[7] or nil,
        drain = p[8],
        obs = p[9],
      }
    end
    return out
  end

  local function summary(item)
    local clean = ns.Analytics.Clean(series(item), 4) -- the default outlier factor
    return ns.Analytics.Summarize(clean)
  end

  local function finite(x)
    return x == nil or (x == x and x ~= math.huge and x ~= -math.huge)
  end

  it("has a useful mix: every price signal, many days of history", function()
    local signals, longest, n = {}, 0, 0
    for _, item in pairs(fixture.items) do
      signals[item.signal] = true
      longest = math.max(longest, #item.points)
      n = n + 1
    end
    assert.are.equal(120, n)
    for _, s in ipairs({ "buy", "sell", "hold", "wait", "none" }) do
      assert.is_true(signals[s], "no item with " .. s)
    end
    assert.truthy(longest >= 10)
  end)

  it("summarizes every item to sane numbers", function()
    for id, item in pairs(fixture.items) do
      local s = summary(item)
      assert.is_not_nil(s, id)
      for _, key in ipairs({ "market", "min", "avg7", "avg30", "change7", "vol30", "z30", "trend30", "sellRate" }) do
        assert.is_true(finite(s[key]), ("%d %s = %s"):format(id, key, tostring(s[key])))
      end
      assert.truthy(s.market > 0, id)
      assert.truthy(s.score >= -100 and s.score <= 100, id)
      assert.is_not_nil(ns.Analytics.SIGNAL_RANK[s.signal], id)
    end
  end)

  it("reproduces the signal the game computed for every item (a regression check on the analytics)", function()
    local differ = {}
    for id, item in pairs(fixture.items) do
      local s = summary(item)
      local expected = item.signal == "vendor" and s.signal or item.signal -- VENDOR is applied on top
      if s.signal ~= expected then
        differ[#differ + 1] = ("%d: %s, game said %s"):format(id, s.signal, item.signal)
      end
    end
    table.sort(differ)
    assert.are.same({}, differ)
  end)

  it("says VENDOR exactly when the AH nets less than the vendor (items with known vendor prices)", function()
    local checked = 0
    for id, item in pairs(fixture.items) do
      if item.vendor then
        local s = summary(item)
        local deposit = ns.Arbitrage.Deposit(item.vendor, "Horde", 24)
        local vendor = ns.Analytics.VendorCheck(s, item.vendor, 0.05, deposit)
        assert.are.equal(s.market * 0.95 - deposit < item.vendor, vendor, id)
        checked = checked + 1
      end
    end
    if checked == 0 then
      -- vendor prices are saved with the market index from 0.2.0-beta.3: regenerate the fixture after a logout
      pending("no vendor prices in the fixture yet")
    end
  end)

  it("gives sane posting prices for every item, from young profiles and category priors", function()
    local profiles = {}
    for _, item in pairs(fixture.items) do
      if item.profile then
        profiles[#profiles + 1] = ns.Pricing.Decode(item.profile)
      end
    end
    local prior = ns.Pricing.Prior(profiles)
    local now = fixture.day * 86400 + 12 * 3600
    for id, item in pairs(fixture.items) do
      local s = summary(item)
      local p = item.profile and ns.Pricing.Decode(item.profile) or ns.Pricing.NewProfile()
      local params = ns.Pricing.Params(p, prior, s)
      local last = item.points[#item.points]
      local book = ns.Pricing.BookFromObs(p.last or { min = last[2], qty = last[5] })
      local advice = ns.Pricing.Suggest(book, params, {
        qty = 1,
        hours = 24,
        now = now,
        cut = 0.05,
        deposit = ns.Arbitrage.Deposit(item.vendor or 0, "Horde", 24),
        vendor = item.vendor,
        reference = s.avg7 or s.market,
      })
      if advice then
        local q, n, pa = advice.quick, advice.normal, advice.patient
        assert.truthy(q.price <= n.price and n.price <= pa.price, id)
        for _, c in ipairs({ q, n, pa }) do
          assert.truthy(c.price >= 1 and c.price == math.floor(c.price), id)
          assert.truthy(c.chance >= 0.01 and c.chance <= 0.99, id)
          assert.is_true(c.hours == nil or (finite(c.hours) and c.hours >= 0), id)
          assert.truthy(not item.vendor or c.price > item.vendor, id)
        end
      end
    end
  end)

  it("gives a sane market index and CPI over real history (only full-scan days, steady items)", function()
    local first, last = math.huge, -math.huge
    for _, item in pairs(fixture.items) do
      for _, p in ipairs(item.points) do
        first, last = math.min(first, p[1]), math.max(last, p[1])
      end
    end
    local st = ns.MarketStats.New(math.max(first, last - 29), last, 4, function()
      return 7 -- all trade goods: the whole fixture is in the CPI basket
    end)
    for id, item in pairs(fixture.items) do
      local pts = series(item)
      local clean = ns.Analytics.Clean(pts, 4)
      local s = ns.Analytics.Summarize(clean)
      st:Add(id, pts, clean, s)
    end
    local out = st:Finish()
    assert.truthy(#out.days >= 5)
    assert.truthy(out.basket >= 50, out.basket)
    assert.are.equal("turnover", out.cpiWeights) -- the fixture has sell rates
    assert.are.equal(out.days[1].day, out.index[1].day) -- the index starts on the first full-scan day
    for _, list in ipairs({ out.index, out.cpi }) do
      assert.truthy(#list >= 4)
      for _, p in ipairs(list) do
        assert.truthy(finite(p.level) and p.level > 50 and p.level < 200, p.level)
      end
    end
  end)
end)
