local addon = require("spec.helpers.addon")

describe("Ingest", function()
  local ns, ingest, runner, api, got, clock, timers

  -- fake C_AuctionHouse: replicate rows are {itemID, buyout, count}
  local function fakeApi()
    local a = { rows = {}, commodities = {}, items = {}, full = {} }
    function a.GetNumReplicateItems()
      return #a.rows
    end
    function a.GetReplicateItemInfo(i) -- 0-based like the real API
      local r = a.rows[i + 1]
      -- name, texture, count, quality, usable, level, levelType, minBid, minIncrement, buyout, bid, highBidder,
      -- bidderFullName, owner, ownerFullName, saleStatus, itemID, hasAllInfo
      return nil, nil, r[3], 1, true, 1, "", 0, 0, r[2], 0, false, nil, nil, nil, 0, r[1], false
    end
    function a.HasFullCommoditySearchResults(itemID)
      return a.full[itemID] ~= false
    end
    function a.GetNumCommoditySearchResults(itemID)
      return #(a.commodities[itemID] or {})
    end
    function a.GetCommoditySearchResultInfo(itemID, i)
      local r = a.commodities[itemID][i]
      return { itemID = itemID, unitPrice = r[1], quantity = r[2] }
    end
    function a.HasFullItemSearchResults(key)
      return a.full[key.itemID] ~= false
    end
    function a.GetNumItemSearchResults(key)
      return #(a.items[key.itemID] or {})
    end
    function a.GetItemSearchResultInfo(key, i)
      local r = a.items[key.itemID][i]
      return { itemKey = key, buyoutAmount = r[1], quantity = r[2] }
    end
    return a
  end

  local function drain()
    local n = 0
    while runner:Busy() do
      runner:Tick()
      n = n + 1
      assert(n < 10000, "runner stuck")
    end
    return n
  end

  local function fireTimers()
    local pending = timers
    timers = {}
    for _, t in ipairs(pending) do
      t()
    end
  end

  local function row(snap, id)
    for i, v in ipairs(snap.ids) do
      if v == id then
        return { min = snap.min[i], market = snap.market[i], qty = snap.qty[i], auctions = snap.auctions[i] }
      end
    end
  end

  before_each(function()
    ns = addon.load({ "Core/Init.lua", "Core/Stats.lua", "Core/Jobs.lua", "Core/Ingest.lua" })
    clock = 0
    runner = ns.Jobs.New({
      budgetMs = 5,
      clock = function()
        clock = clock + 0.5 -- every clock read stands for some work, so long loops exceed the budget
        return clock
      end,
    })
    api = fakeApi()
    got = {}
    timers = {}
    ingest = ns.Ingest.New({
      api = api,
      jobs = runner,
      now = function()
        return 5000
      end,
      after = function(_, fn)
        timers[#timers + 1] = fn
      end,
      onSnapshot = function(snap, t, kind, info)
        got[#got + 1] = { snap = snap, t = t, kind = kind, info = info }
      end,
    })
  end)

  describe("full scans", function()
    it("reads the replicate list once per ReplicateItems request", function()
      api.rows = { { 10, 500, 5 }, { 10, 300, 1 }, { 20, 1000, 1 } }
      ingest:OnReplicateRequested()
      for _ = 1, 50 do -- the event storm
        ingest:OnReplicateUpdate()
      end
      drain()
      assert.are.equal(1, #got)
      assert.are.equal("full", got[1].kind)
      assert.are.equal(5000, got[1].t)
      assert.are.same({ 10, 20 }, got[1].snap.ids)
      assert.are.equal(100, row(got[1].snap, 10).min)
      assert.are.equal(3, got[1].info.rows)
    end)

    it("ignores replicate events without a request", function()
      api.rows = { { 10, 500, 5 } }
      ingest:OnReplicateUpdate()
      drain()
      assert.are.equal(0, #got)
    end)

    it("spreads a large read over several frames", function()
      for i = 1, 5000 do
        api.rows[i] = { 1000 + i % 300, 100 + i, 1 }
      end
      ingest:OnReplicateRequested()
      ingest:OnReplicateUpdate()
      local ticks = drain()
      assert.is_true(ticks > 1, "ticks " .. ticks)
      assert.are.equal(300, #got[1].snap.ids)
    end)

    it("discards a read interrupted by the AH closing", function()
      for i = 1, 5000 do
        api.rows[i] = { i, 100, 1 }
      end
      ingest:OnReplicateRequested()
      ingest:OnReplicateUpdate()
      runner:Tick()
      ingest:OnAuctionHouseClosed()
      drain()
      assert.are.equal(0, #got)
    end)

    it("can read again after a new request", function()
      api.rows = { { 10, 500, 5 } }
      ingest:OnReplicateRequested()
      ingest:OnReplicateUpdate()
      drain()
      ingest:OnReplicateRequested()
      ingest:OnReplicateUpdate()
      drain()
      assert.are.equal(2, #got)
    end)
  end)

  describe("search and sell-tab results", function()
    it("turns full commodity results into one partial snapshot after things settle", function()
      api.commodities[2589] = { { 100, 20 }, { 120, 5 } }
      ingest:OnCommodityResults(2589)
      ingest:OnCommodityResults(2589) -- results often update several times
      assert.are.equal(0, #got)
      fireTimers()
      drain()
      assert.are.equal(1, #got)
      assert.are.equal("partial", got[1].kind)
      local r = row(got[1].snap, 2589)
      assert.are.equal(100, r.min)
      assert.are.equal(25, r.qty)
    end)

    it("batches several items searched close together into one snapshot", function()
      api.commodities[1] = { { 10, 1 } }
      api.items[2] = { { 500, 1 } }
      ingest:OnCommodityResults(1)
      ingest:OnItemResults({ itemID = 2, itemLevel = 10 })
      fireTimers()
      drain()
      assert.are.equal(1, #got)
      assert.are.same({ 1, 2 }, got[1].snap.ids)
      assert.are.equal(500, row(got[1].snap, 2).min)
    end)

    it("skips results that aren't complete yet (only the cheapest page)", function()
      api.commodities[3] = { { 10, 1 } }
      api.full[3] = false
      ingest:OnCommodityResults(3)
      fireTimers()
      drain()
      assert.are.equal(0, #got)
    end)

    it("skips empty results", function()
      ingest:OnCommodityResults(4)
      fireTimers()
      drain()
      assert.are.equal(0, #got)
    end)
  end)
end)
