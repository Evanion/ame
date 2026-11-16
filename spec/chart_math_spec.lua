-- LibAMEChart-1.0 pure math (lib.Math). Loads LibStub + the library in plain Lua; no rendering.
describe("LibAMEChart-1.0 Math", function()
  local M

  before_each(function()
    _G.LibStub = nil
    dofile("Libs/Ace3/LibStub/LibStub.lua")
    dofile("LibAMEChart-1.0/LibAMEChart-1.0.lua")
    M = _G.LibStub("LibAMEChart-1.0").Math
  end)

  describe("NiceTicks", function()
    it("picks 1/2/5 x 10^k steps covering the range", function()
      local ticks, step = M.NiceTicks(0, 100, 5)
      assert.are.equal(20, step)
      assert.are.same({ 0, 20, 40, 60, 80, 100 }, ticks)
    end)

    it("works for awkward ranges", function()
      local ticks, step = M.NiceTicks(137, 912, 4)
      assert.are.equal(200, step)
      assert.are.same({ 200, 400, 600, 800 }, ticks)
    end)

    it("handles a flat range", function()
      local ticks = M.NiceTicks(50, 50, 4)
      assert.is_true(#ticks >= 1)
    end)
  end)

  describe("TimeTicks", function()
    local DAY = 86400

    it("uses daily ticks for a week", function()
      local ticks = M.TimeTicks(10 * DAY, 17 * DAY, 8)
      assert.are.equal(DAY, ticks[2].t - ticks[1].t)
      assert.are.equal("day", ticks[1].unit)
    end)

    it("uses weekly or coarser ticks for half a year", function()
      local ticks = M.TimeTicks(0, 180 * DAY, 6)
      assert.is_true(ticks[2].t - ticks[1].t >= 7 * DAY)
      assert.is_true(#ticks <= 8)
    end)

    it("uses hourly ticks within a day", function()
      local ticks = M.TimeTicks(DAY, DAY + 12 * 3600, 6)
      assert.are.equal("hour", ticks[1].unit)
    end)
  end)

  describe("Nearest", function()
    it("finds the closest x by binary search", function()
      local xs = { 0, 10, 20, 30 }
      assert.are.equal(1, M.Nearest(xs, -5))
      assert.are.equal(2, M.Nearest(xs, 14))
      assert.are.equal(3, M.Nearest(xs, 16))
      assert.are.equal(4, M.Nearest(xs, 99))
      assert.is_nil(M.Nearest({}, 1))
    end)
  end)

  describe("LTTB", function()
    it("returns all indices when under the threshold", function()
      assert.are.same({ 1, 2, 3 }, M.LTTB({ 1, 2, 3 }, { 5, 6, 7 }, 10))
    end)

    it("keeps first, last and the spike", function()
      local xs, ys = {}, {}
      for i = 1, 100 do
        xs[i], ys[i] = i, 10
      end
      ys[50] = 500
      local idx = M.LTTB(xs, ys, 10)
      assert.are.equal(10, #idx)
      assert.are.equal(1, idx[1])
      assert.are.equal(100, idx[#idx])
      local kept = false
      for _, i in ipairs(idx) do
        kept = kept or i == 50
      end
      assert.is_true(kept)
    end)
  end)

  describe("Zoom and Pan", function()
    it("zooms around an anchor and clamps to limits", function()
      local a, b = M.Zoom(0, 100, 50, 0.5, 0, 100)
      assert.are.same({ 25, 75 }, { a, b })
      a, b = M.Zoom(0, 100, 0, 0.5, 0, 100)
      assert.are.same({ 0, 50 }, { a, b })
      a, b = M.Zoom(25, 75, 50, 4, 0, 100) -- zooming out can't exceed the data
      assert.are.same({ 0, 100 }, { a, b })
    end)

    it("respects a minimum span", function()
      local a, b = M.Zoom(0, 10, 5, 0.01, 0, 100, 4)
      assert.are.equal(4, b - a)
    end)

    it("pans without leaving the limits", function()
      local a, b = M.Pan(20, 40, 10, 0, 100)
      assert.are.same({ 30, 50 }, { a, b })
      a, b = M.Pan(20, 40, 100, 0, 100)
      assert.are.same({ 80, 100 }, { a, b })
      a, b = M.Pan(20, 40, -100, 0, 100)
      assert.are.same({ 0, 20 }, { a, b })
    end)
  end)

  describe("Extent", function()
    it("finds y min/max of points within an x window, with padding", function()
      local lo, hi = M.Extent({ 0, 1, 2, 3 }, { 5, 50, 10, 99 }, 0.5, 2.5, 0)
      assert.are.same({ 10, 50 }, { lo, hi })
    end)

    it("pads flat data so it doesn't collapse", function()
      local lo, hi = M.Extent({ 0, 1 }, { 10, 10 }, 0, 1, 0.1)
      assert.is_true(lo < 10 and hi > 10)
    end)
  end)
end)
