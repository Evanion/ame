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

    it("handles an empty series", function()
      assert.is_nil(A.Summarize({}))
    end)
  end)
end)
