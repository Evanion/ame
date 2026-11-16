local addon = require("spec.helpers.addon")

describe("Watch", function()
  local Watch, w, db

  before_each(function()
    Watch = addon.load({ "Core/Init.lua", "Core/Watch.lua" }).Watch
    db = {}
    w = Watch.New(db)
  end)

  describe("lists", function()
    it("starts with one default list", function()
      assert.are.equal(1, #w:Lists())
      assert.are.equal("Watchlist", w:Lists()[1].name)
    end)

    it("adds named lists, rejecting blanks and duplicates", function()
      assert.are.equal(2, (w:AddList("  Enchanting  ")))
      assert.are.equal("Enchanting", w:Lists()[2].name)
      assert.is_nil((w:AddList("enchanting")))
      assert.is_nil((w:AddList("   ")))
    end)

    it("toggles items and knows what is watched", function()
      assert.is_true(w:Toggle(1, 2589))
      assert.is_true(w:Has(1, 2589))
      assert.is_true(w:Watched(2589))
      assert.are.equal(1, w:Count(1))
      assert.is_false(w:Toggle(1, 2589))
      assert.is_false(w:Watched(2589))
      assert.are.equal(0, w:Count(1))
    end)

    it("never removes the last list", function()
      assert.is_false(w:RemoveList(1))
      w:AddList("Herbs")
      assert.is_true(w:RemoveList(1))
      assert.are.equal("Herbs", w:Lists()[1].name)
    end)

    it("keeps state in the saved table", function()
      w:Toggle(1, 10)
      local again = Watch.New(db)
      assert.is_true(again:Has(1, 10))
    end)
  end)

  describe("alerts", function()
    it("fires a below alert once, re-arming after the price recovers past the threshold", function()
      w:SetAlert(10, { below = 1000 })
      assert.are.equal(0, #w:Check({ [10] = { market = 1200, signal = "none" } }))
      local fired = w:Check({ [10] = { market = 950, signal = "none" } })
      assert.are.equal(1, #fired)
      assert.are.equal("below", fired[1].kind)
      assert.are.equal(950, fired[1].market)
      assert.are.equal(0, #w:Check({ [10] = { market = 900, signal = "none" } })) -- still below: no repeat
      assert.are.equal(0, #w:Check({ [10] = { market = 1010, signal = "none" } })) -- within hysteresis
      assert.are.equal(0, #w:Check({ [10] = { market = 1030, signal = "none" } })) -- re-armed
      assert.are.equal(1, #w:Check({ [10] = { market = 990, signal = "none" } }))
    end)

    it("fires above alerts", function()
      w:SetAlert(10, { above = 5000 })
      local fired = w:Check({ [10] = { market = 5100, signal = "none" } })
      assert.are.equal("above", fired[1].kind)
    end)

    it("fires on new buy/sell signals", function()
      w:SetAlert(10, { signal = true })
      assert.are.equal("buy", w:Check({ [10] = { market = 1, signal = "buy" } })[1].kind)
      assert.are.equal(0, #w:Check({ [10] = { market = 1, signal = "buy" } }))
      assert.are.equal("sell", w:Check({ [10] = { market = 1, signal = "sell" } })[1].kind)
      w:Check({ [10] = { market = 1, signal = "none" } })
      assert.are.equal(1, #w:Check({ [10] = { market = 1, signal = "sell" } }))
    end)

    it("removes an alert when every condition is cleared, and ignores unknown items", function()
      w:SetAlert(10, { below = 100, signal = true })
      w:SetAlert(10, { below = false, signal = false })
      assert.is_nil(w:Alert(10))
      w:SetAlert(11, { below = 100 })
      assert.are.equal(0, #w:Check({}))
    end)

    it("counts items with alerts as watched", function()
      w:SetAlert(77, { above = 10 })
      assert.is_true(w:Watched(77))
    end)
  end)
end)
