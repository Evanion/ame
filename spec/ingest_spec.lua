local addon = require("spec.helpers.addon")

describe("Ingest", function()
  local ns, ingest, runner, api, got, clock, timers

  -- fake C_AuctionHouse: replicate rows are {itemID, buyout, count}
  local function fakeApi()
    local a = { rows = {}, commodities = {}, items = {}, full = {}, browse = {}, browseFull = false }
    function a.HasFullBrowseResults()
      return a.browseFull
    end
    function a.GetBrowseResults()
      local out = {}
      for i, r in ipairs(a.browse) do
        local key = { itemID = r[1], itemLevel = r[4] or 0, itemSuffix = r[5] or 0 }
        out[i] = { itemKey = key, minPrice = r[2], totalQuantity = r[3] }
      end
      return out
    end
    function a.GetNumReplicateItems()
      return #a.rows
    end
    function a.GetReplicateItemInfo(i) -- 0-based like the real API
      local r = a.rows[i + 1]
      -- name, texture, count, quality, usable, level, levelType, minBid, minIncrement, buyout, bid, highBidder,
      -- bidderFullName, owner, ownerFullName, saleStatus, itemID, hasAllInfo
      return nil, nil, r[3], 1, true, 1, "", 0, 0, r[2], 0, false, nil, nil, nil, 0, r[1], false
    end
    function a.GetReplicateItemLink(i) -- rows can carry a link as r[4]
      return a.rows[i + 1][4]
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
      return { itemKey = key, buyoutAmount = r[1], quantity = r[2], itemLink = r[3] }
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

  describe("random-suffix variants", function()
    local magic = "|cff1eff00|Hitem:15211::::::1234::60:::::|h[Raider Shortsword of Magic]|h|r"
    local monkey = "|cff1eff00|Hitem:15211::::::567::60:::::|h[Raider Shortsword of the Monkey]|h|r"

    it("records each suffix of a full scan under its own key, from the row's link", function()
      api.rows = { { 15211, 3500, 1, magic }, { 15211, 900, 1, monkey }, { 15211, 3700, 1, magic }, { 10, 50, 1 } }
      ingest:OnReplicateRequested()
      ingest:OnReplicateUpdate()
      drain()
      local snap = got[1].snap
      assert.are.equal(3, #snap.ids)
      assert.is_nil(row(snap, 15211))
      assert.are.equal(2, row(snap, ns.ItemKey(15211, 1234)).qty)
      assert.are.equal(900, row(snap, ns.ItemKey(15211, 567)).min)
      assert.are.equal(1, row(snap, 10).qty)
    end)

    it("keys browse rows by their itemKey's suffix", function()
      api.browse = { { 15211, 3500, 2, 0, 1234 }, { 15211, 900, 1, 0, 567 } }
      api.browseFull = true
      ingest:OnBrowseQuery({ searchString = "" })
      ingest:OnBrowseResults()
      drain()
      local snap = got[1].snap
      assert.are.equal(3500, row(snap, ns.ItemKey(15211, 1234)).min)
      assert.are.equal(900, row(snap, ns.ItemKey(15211, 567)).min)
    end)

    it("keys item search rows by their links, and the search by its itemKey", function()
      api.items[15211] = { { 3500, 1, magic }, { 3600, 2 } }
      ingest:OnItemResults({ itemID = 15211, itemLevel = 0, itemSuffix = 1234 })
      fireTimers()
      drain()
      local snap = got[1].snap
      assert.are.same({ ns.ItemKey(15211, 1234) }, snap.ids)
      assert.are.equal(3, row(snap, ns.ItemKey(15211, 1234)).qty)
    end)

    it("hands the links to learn, which names the variants", function()
      local learned = {}
      ingest.learn = function(link)
        learned[#learned + 1] = link
        return ns.ItemIDFrom(link)
      end
      api.rows = { { 15211, 3500, 1, magic } }
      ingest:OnReplicateRequested()
      ingest:OnReplicateUpdate()
      drain()
      assert.are.same({ magic }, learned)
    end)
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

  describe("browse summary scans", function()
    local EMPTY = { searchString = "", sorts = {}, filters = {}, itemClassFilters = {} }

    it("reads an unfiltered browse once all pages are in", function()
      ingest:OnBrowseQuery(EMPTY)
      api.browse = { { 10, 500, 5 } }
      ingest:OnBrowseResults() -- first page, more to come
      drain()
      assert.are.equal(0, #got)
      api.browse = { { 10, 500, 5 }, { 10, 300, 2, 60 }, { 20, 1000, 1 }, { 30, 0, 4 } }
      api.browseFull = true
      ingest:OnBrowseResults()
      ingest:OnBrowseResults() -- later events are ignored
      drain()
      assert.are.equal(1, #got)
      local snap = got[1].snap
      assert.are.equal("full", got[1].kind)
      assert.are.equal("browse", got[1].info.source)
      assert.are.same({ 10, 20 }, snap.ids) -- item 30 has no price
      assert.are.equal(300, snap.min[1]) -- cheapest of the item's keys
      assert.are.equal(300, snap.market[1])
      assert.are.equal(7, snap.qty[1])
    end)

    it("records category browsing and text searches as partial scans once results settle", function()
      api.browse, api.browseFull = { { 10, 500, 5 }, { 20, 900, 1 } }, true
      ingest:OnBrowseQuery({ searchString = "", filters = {}, itemClassFilters = { { classID = 7 } } })
      ingest:OnBrowseResults()
      drain()
      assert.are.equal(0, #got) -- still arriving
      fireTimers()
      drain()
      assert.are.equal(1, #got)
      assert.are.equal("partial", got[1].kind)
      assert.are.same({ 10, 20 }, got[1].snap.ids)
      ingest:OnBrowseQuery({ searchString = "linen", filters = {}, itemClassFilters = {} })
      api.browse = { { 30, 70, 9 } }
      ingest:OnBrowseResults()
      fireTimers()
      drain()
      assert.are.equal("partial", got[2].kind)
      assert.are.same({ 30 }, got[2].snap.ids)
    end)

    it("records only the newly shown rows when the list is scrolled further", function()
      api.browse, api.browseFull = { { 10, 500, 5 }, { 20, 900, 1 } }, false
      ingest:OnBrowseQuery({ searchString = "", filters = {}, itemClassFilters = { { classID = 7 } } })
      ingest:OnBrowseResults()
      fireTimers()
      drain()
      api.browse[3], api.browse[4] = { 30, 100, 2 }, { 40, 200, 3 }
      ingest:OnBrowseResults()
      fireTimers()
      drain()
      assert.are.equal(2, #got)
      assert.are.same({ 30, 40 }, got[2].snap.ids)
      ingest:OnBrowseResults() -- an update with nothing new records nothing
      fireTimers()
      drain()
      assert.are.equal(2, #got)
    end)

    it("an unfiltered scan scrolled only part way is a partial; reaching the end is the full scan", function()
      api.browse, api.browseFull = { { 10, 500, 5 } }, false
      ingest:OnBrowseQuery({ searchString = "", sorts = {}, filters = {}, itemClassFilters = {} })
      ingest:OnBrowseResults()
      fireTimers()
      drain()
      assert.are.equal("partial", got[1].kind)
      api.browse[2], api.browseFull = { 20, 900, 1 }, true
      ingest:OnBrowseResults()
      drain()
      assert.are.equal("full", got[2].kind)
      assert.are.same({ 10, 20 }, got[2].snap.ids)
    end)

    it("is dropped when the AH closes mid-read", function()
      for i = 1, 3000 do
        api.browse[i] = { i, 100, 1 }
      end
      api.browseFull = true
      ingest:OnBrowseQuery(EMPTY)
      ingest:OnBrowseResults()
      runner:Tick()
      ingest:OnAuctionHouseClosed()
      drain()
      assert.are.equal(0, #got)
    end)
  end)

  describe("legacy getAll scans", function()
    local legacy, list

    local function legacyIngest()
      list = { rows = {}, total = nil }
      legacy = {
        GetNumAuctionItems = function(kind)
          assert(kind == "list")
          return #list.rows, list.total or #list.rows
        end,
        GetAuctionItemInfo = function(kind, i) -- 1-based like the classic API; index 0 returns nothing
          assert(kind == "list")
          local r = list.rows[i]
          if not r then
            return
          end
          return "x", nil, r[3], 1, true, 1, "", 0, 0, r[2], 0, false, nil, nil, nil, 0, r[1], true
        end,
      }
      return ns.Ingest.New({
        api = api,
        jobs = runner,
        legacy = legacy,
        now = function()
          return 6000
        end,
        after = function(_, fn)
          timers[#timers + 1] = fn
        end,
        onSnapshot = function(snap, t, kind, info)
          got[#got + 1] = { snap = snap, t = t, kind = kind, info = info }
        end,
      })
    end

    it("waits for the list to be complete and stable, then reads it once", function()
      local ing = legacyIngest()
      ing:OnGetAllRequested()
      fireTimers() -- nothing yet
      list.rows = { { 10, 500, 5 }, { 10, 300, 1 } }
      list.total = 3
      fireTimers() -- partial batch
      list.rows[3] = { 20, 1000, 1 }
      fireTimers() -- complete, first sighting
      assert.are.equal(0, #got)
      fireTimers() -- stable: read
      drain()
      fireTimers()
      assert.are.equal(1, #got)
      assert.are.equal("full", got[1].kind)
      assert.are.same({ 10, 20 }, got[1].snap.ids)
      assert.are.equal(100, row(got[1].snap, 10).min)
    end)

    it("skips rows without an item id", function()
      local ing = legacyIngest()
      list.rows = { { 0, 500, 1 }, { 30, 700, 1 } }
      ing:OnGetAllRequested()
      fireTimers()
      fireTimers()
      drain()
      assert.are.same({ 30 }, got[1].snap.ids)
    end)

    it("stops waiting when the AH closes", function()
      local ing = legacyIngest()
      ing:OnGetAllRequested()
      fireTimers()
      ing:OnAuctionHouseClosed()
      list.rows = { { 10, 500, 5 } }
      fireTimers()
      fireTimers()
      drain()
      assert.are.equal(0, #got)
      assert.are.equal(0, #timers)
    end)

    it("is ignored without the legacy API", function()
      ingest:OnGetAllRequested()
      assert.are.equal(0, #timers)
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

    it("reads an item search row as several identical auctions priced each (not one stack)", function()
      api.items[7] = { { 500, 3 } } -- 3 auctions at 5s each
      ingest:OnItemResults({ itemID = 7, itemLevel = 10 })
      fireTimers()
      drain()
      local r = row(got[1].snap, 7)
      assert.are.equal(500, r.min)
      assert.are.equal(500, r.market)
      assert.are.equal(3, r.qty)
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
