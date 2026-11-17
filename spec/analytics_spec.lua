local addon = require("spec.helpers.addon")

describe("Analytics", function()
  local A

  before_each(function()
    A = addon.load({ "Core/Init.lua", "Core/Analytics.lua" }).Analytics
  end)

  local function near(expected, actual, tol)
    assert.is_true(math.abs(expected - actual) <= (tol or 1e-6), ("expected %s, got %s"):format(expected, actual))
  end

  it("SMA averages the last n values", function()
    assert.are.equal(3, A.SMA({ 1, 2, 3, 4, 5 }, 3, 4)) -- values 2,3,4 ending at index 4
    assert.is_nil(A.SMA({ 1, 2 }, 3, 2))
  end)

  it("EMA series seeds with the first value", function()
    local e = A.EMASeries({ 10, 10, 20 }, 3) -- alpha = 0.5
    assert.are.same({ 10, 10, 15 }, e)
  end)

  it("percent change between two values", function()
    near(0.25, A.Change(100, 125))
    assert.is_nil(A.Change(0, 10))
    assert.is_nil(A.Change(nil, 10))
  end)

  it("volatility is the stdev of daily log returns", function()
    assert.are.equal(0, A.Volatility({ 100, 100, 100 }))
    local v = A.Volatility({ 100, 110, 100, 110 })
    -- returns +9.5%, -9.5%, +9.5% -> population stdev ~0.0899
    assert.is_true(v > 0.085 and v < 0.095, tostring(v))
    assert.is_nil(A.Volatility({ 100 }))
  end)

  it("z-score of the last value against the window", function()
    near(0, A.ZScore({ 10, 10, 10, 10 }))
    assert.is_true(A.ZScore({ 10, 10, 10, 5 }) < -1)
    assert.is_true(A.ZScore({ 10, 10, 10, 20 }) > 1)
  end)

  it("slope of a least-squares line, normalized by the mean", function()
    near(0, A.Trend({ 5, 5, 5, 5 }))
    assert.is_true(A.Trend({ 1, 2, 3, 4 }) > 0)
    assert.is_true(A.Trend({ 4, 3, 2, 1 }) < 0)
  end)

  describe("Summarize", function()
    local function series(markets, qtys)
      local s = {}
      for i, m in ipairs(markets) do
        s[i] = { day = 100 + i, market = m, min = m, qty = qtys and qtys[i] or 10, scans = 1 }
      end
      return s
    end

    it("summarizes an item's series for tooltips and the screener", function()
      local markets = {}
      for i = 1, 30 do
        markets[i] = 100
      end
      markets[30] = 80 -- dropped today
      local s = A.Summarize(series(markets))
      assert.are.equal(80, s.market)
      assert.are.equal(99, s.avg30) -- round((29*100 + 80) / 30)
      near(-0.2, s.change7)
      assert.is_true(s.z30 < -2)
      assert.are.equal(30, s.days)
    end)

    it("flags a dip with stable history as an opportunity, and a spike as overpriced", function()
      local stable, dip, spike = {}, {}, {}
      for i = 1, 30 do
        stable[i] = 100 + (i % 2)
        dip[i] = 100 + (i % 2)
        spike[i] = 100 + (i % 2)
      end
      dip[30], spike[30] = 75, 140
      local sDip = A.Summarize(series(dip))
      local sStable = A.Summarize(series(stable))
      local sSpike = A.Summarize(series(spike))
      assert.is_true(sDip.score > sStable.score)
      assert.is_true(sStable.score > sSpike.score)
      assert.are.equal("buy", sDip.signal)
      assert.are.equal("sell", sSpike.signal)
    end)

    it("does not signal on thin history", function()
      local s = A.Summarize(series({ 100, 50 }))
      assert.are.equal("none", s.signal)
    end)

    it("says hold when the price is within its normal range", function()
      local s = A.Summarize(series({ 100, 102, 99, 101, 100, 98, 101, 100, 99, 101 }))
      assert.are.equal("hold", s.signal)
    end)

    it("handles an empty series", function()
      assert.is_nil(A.Summarize({}))
    end)
  end)
end)

describe("Analytics.Candles", function()
  local A
  before_each(function()
    A = require("spec.helpers.addon").load({ "Core/Init.lua", "Core/Analytics.lua" }).Analytics
  end)

  local series = {
    { day = 100, market = 100, min = 90 },
    { day = 101, market = 120, min = 110 },
    { day = 102, market = 110, min = 80 },
    { day = 103, market = 130, min = 125 },
  }

  it("makes daily candles: open = previous close, wick down to the cheapest listing", function()
    local c = A.Candles(series, 1)
    assert.are.equal(4, #c.xs)
    assert.are.equal(100.5 * 86400, c.xs[1])
    assert.are.same({ 100, 100, 120, 110 }, c.open)
    assert.are.same({ 100, 120, 110, 130 }, c.close)
    assert.are.same({ 100, 120, 120, 130 }, c.high)
    assert.are.same({ 90, 100, 80, 110 }, c.low)
  end)

  it("groups several days per candle", function()
    local c = A.Candles(series, 2) -- days 100-101, 102-103
    assert.are.equal(2, #c.xs)
    assert.are.equal(2 * 86400, c.period)
    assert.are.same({ 100, 120 }, c.open)
    assert.are.same({ 120, 130 }, c.close)
    assert.are.same({ 120, 130 }, c.high)
    assert.are.same({ 90, 80 }, c.low)
  end)

  it("handles an empty series", function()
    assert.are.equal(0, #A.Candles({}, 3).xs)
  end)
end)

describe("Analytics.Clean", function()
  local A
  before_each(function()
    A = require("spec.helpers.addon").load({ "Core/Init.lua", "Core/Analytics.lua" }).Analytics
  end)

  local function series(prices)
    local out = {}
    for i, m in ipairs(prices) do
      out[i] = { day = 100 + i, market = m, min = m }
    end
    return out
  end

  it("drops a day priced wildly above its neighbours (one 1000% markup listing)", function()
    local clean, dropped = A.Clean(series({ 100, 105, 98, 1100, 102, 99, 101 }), 4)
    assert.are.equal(1, dropped)
    for _, p in ipairs(clean) do
      assert.is_true(p.market < 200)
    end
  end)

  it("drops absurdly cheap prints too", function()
    local _, dropped = A.Clean(series({ 1000, 1010, 1, 990, 1005 }), 4)
    assert.are.equal(1, dropped)
  end)

  it("keeps real trends and big-but-plausible moves", function()
    local _, dropped = A.Clean(series({ 100, 120, 150, 190, 240, 300, 380, 470 }), 4)
    assert.are.equal(0, dropped)
    local _, dropped2 = A.Clean(series({ 100, 100, 100, 250, 100, 100 }), 4)
    assert.are.equal(0, dropped2)
  end)

  it("does nothing when disabled or with too little history", function()
    local s = series({ 100, 5000, 100, 100 })
    assert.are.equal(0, select(2, A.Clean(s, false)))
    assert.are.equal(0, select(2, A.Clean(series({ 100, 5000, 100 }), 4)))
  end)
end)

describe("Analytics score vs signal", function()
  local A
  before_each(function()
    A = require("spec.helpers.addon").load({ "Core/Init.lua", "Core/Analytics.lua" }).Analytics
  end)

  it("never scores an item that spiked far above its usual price as a bargain", function()
    local series = {}
    for i = 1, 20 do
      series[i] = { day = i, market = 40 + (i % 3), qty = 100 }
    end
    for i = 21, 26 do -- a steep climb to ~1s (like Crocolisk Meat at 1s 3c vs a 42c average)
      series[i] = { day = i, market = 40 + (i - 20) * 11, qty = 100 }
    end
    local s = A.Summarize(series)
    assert.are.equal("sell", s.signal)
    assert.is_true(s.score < 0, "score " .. s.score)
  end)

  it("keeps short averages for tooltips", function()
    local s = A.Summarize({ { day = 1, market = 10 }, { day = 2, market = 20 }, { day = 3, market = 30 } })
    assert.are.equal(20, s.avg3)
    assert.are.equal(20, s.avg14)
  end)
end)

describe("Analytics.Candles upper wick", function()
  it("reaches the day's recorded high above the body", function()
    local A = require("spec.helpers.addon").load({ "Core/Init.lua", "Core/Analytics.lua" }).Analytics
    local c = A.Candles({
      { day = 1, market = 100, min = 90 },
      { day = 2, market = 150, min = 140, high = 200 },
    }, 1)
    assert.are.equal(150, c.close[2])
    assert.are.equal(200, c.high[2]) -- above max(open, close): a visible upper wick
    assert.are.equal(100, c.high[1]) -- no recorded high: the wick stays at the body
  end)
end)

describe("Analytics sell rate", function()
  it("turns drained units over observed minutes into units per day", function()
    local A = require("spec.helpers.addon").load({ "Core/Init.lua", "Core/Analytics.lua" }).Analytics
    local s = A.Summarize({
      { day = 1, market = 10, drain = 30, obs = 360 },
      { day = 2, market = 10, drain = 90, obs = 720 },
    })
    assert.are.equal(160, s.sellRate) -- 120 units over 18 observed hours = 160 per day
  end)
end)

describe("Analytics.Confidence", function()
  it("rates how much to trust an item's numbers from scan count, freshness and history", function()
    local A = require("spec.helpers.addon").load({ "Core/Init.lua", "Core/Analytics.lua" }).Analytics
    local series = {}
    for d = 1, 8 do
      series[d] = { day = d, market = 100, scans = 2 }
    end
    local s = A.Summarize(series)
    assert.are.equal(14, s.scans7)
    assert.are.equal("high", A.Confidence(s, 8))
    assert.are.equal("medium", A.Confidence(s, 11)) -- 3 days old
    assert.are.equal("low", A.Confidence(s, 20)) -- stale
    assert.are.equal("low", A.Confidence(A.Summarize({ { day = 1, market = 100, scans = 1 } }), 1))
    assert.are.equal("medium", A.Confidence(A.Summarize({ { day = 1, market = 100, scans = 3 } }), 1))
  end)
end)

describe("Analytics market phase", function()
  local A
  before_each(function()
    A = require("spec.helpers.addon").load({ "Core/Init.lua", "Core/Analytics.lua" }).Analytics
  end)

  -- 7 days moving price and supply linearly by the given fractions
  local function week(priceMove, supplyMove)
    local s = {}
    for k = 1, 7 do
      local f = (k - 1) / 6
      s[k] = { day = k, market = math.floor(1000 * (1 + priceMove * f)), qty = math.floor(1000 * (1 + supplyMove * f)) }
    end
    return s
  end

  it("reads the week's price move against supply", function()
    local cases = {
      { 0.2, -0.3, "shortage" },
      { 0.2, 0, "demand" },
      { 0.2, 0.3, "piling" },
      { 0, -0.3, "tightening" },
      { 0, 0, "balanced" },
      { 0, 0.3, "pressure" },
      { -0.2, -0.3, "withdrawing" },
      { -0.2, 0, "weak" },
      { -0.2, 0.3, "dumping" },
    }
    for _, c in ipairs(cases) do
      assert.are.equal(c[3], A.Phase(week(c[1], c[2])), ("price %+.0f%% supply %+.0f%%"):format(c[1] * 100, c[2] * 100))
    end
    assert.is_nil(A.Phase(week(0.2, 0.3)[1] and { { day = 1, market = 1 } }))
  end)

  it("turns a buy into wait while sellers are dumping", function()
    local series = {}
    for d = 1, 20 do
      series[d] = { day = d, market = 1000, qty = 100 }
    end
    for d = 21, 27 do -- price crashing while supply floods in
      series[d] = { day = d, market = 1000 - (d - 20) * 60, qty = 100 + (d - 20) * 40 }
    end
    local s = A.Summarize(series)
    assert.are.equal("dumping", s.phase)
    assert.are.equal("wait", s.signal)
  end)

  it("nudges the score up when sellers withdraw and down when they pile in", function()
    local base = A.Summarize(week(0, 0))
    local withdrawing = A.Summarize(week(-0.2, -0.3))
    local dumping = A.Summarize(week(-0.2, 0.3))
    assert.is_true(withdrawing.score > dumping.score)
    assert.are.equal("balanced", base.phase)
  end)
end)

describe("Analytics signal order", function()
  it("sorts sell first, then buy, hold, wait, and no signal last", function()
    local A = require("spec.helpers.addon").load({ "Core/Init.lua", "Core/Analytics.lua" }).Analytics
    local order = { "sell", "buy", "hold", "wait", "none" }
    for i = 2, #order do
      assert.is_true(A.SIGNAL_RANK[order[i - 1]] < A.SIGNAL_RANK[order[i]], order[i - 1] .. " before " .. order[i])
    end
  end)
end)
