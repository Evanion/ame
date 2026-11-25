local addon = require("spec.helpers.addon")

local DAY = 86400

describe("Store", function()
  local ns, Store
  local clock
  local compressor

  before_each(function()
    ns = addon.load({ "Core/Init.lua", "Core/Codec.lua", "Core/Store.lua" })
    Store = ns.Store
    clock = 1000 * DAY + 3600 -- day 1000, 01:00 UTC
    compressor = {
      calls = 0,
      Compress = function(self, s)
        self.calls = self.calls + 1
        return "z" .. s
      end,
      Decompress = function(_, s)
        return s:sub(1, 1) == "z" and s:sub(2) or nil
      end,
    }
  end)

  local function newStore(data)
    return Store.New(data or {}, {
      compressor = compressor,
      now = function()
        return clock
      end,
    })
  end

  -- snapshot from {itemID = {min, market, median, qty, auctions}}
  local function snap(items)
    local ids = {}
    for id in pairs(items) do
      ids[#ids + 1] = id
    end
    table.sort(ids)
    local s = { ids = ids, min = {}, market = {}, median = {}, qty = {}, auctions = {} }
    for i, id in ipairs(ids) do
      local v = items[id]
      s.min[i], s.market[i], s.median[i], s.qty[i], s.auctions[i] = v[1], v[2], v[3], v[4], v[5]
    end
    return s
  end

  describe("raw tier", function()
    it("stores scans packed, with time and provenance", function()
      local data = {}
      local store = newStore(data)
      store:AddScan(snap({ [10] = { 100, 110, 120, 5, 2 } }), clock, "Tyken Evanion")
      assert.are.equal(1, #data.raw)
      assert.are.equal(clock, data.raw[1].t)
      assert.are.equal("Tyken Evanion", data.raw[1].src)
      assert.are.equal("string", type(data.raw[1].s))
      assert.are.equal("z", data.raw[1].s:sub(1, 1)) -- went through the compressor
    end)

    it("Latest returns the newest scan's stats for an item", function()
      local store = newStore()
      store:AddScan(snap({ [10] = { 100, 110, 120, 5, 2 } }), clock - 600, "a")
      store:AddScan(snap({ [10] = { 90, 105, 115, 7, 3 } }), clock, "b")
      local l = store:Latest(10)
      assert.are.same({ t = clock, min = 90, market = 105, median = 115, qty = 7, auctions = 3, src = "b" }, l)
    end)

    it("Intraday lists every recent scan that saw the item, full and partial, oldest first", function()
      local store = newStore()
      store:AddScan(snap({ [10] = { 100, 110, 120, 5, 2 } }), clock - 3 * 86400, "old")
      store:AddScan(snap({ [10] = { 90, 105, 115, 7, 3 }, [11] = { 1, 1, 1, 1, 1 } }), clock - 7200, "a")
      store:AddScan(snap({ [11] = { 2, 2, 2, 2, 2 } }), clock - 3600, "b")
      store:AddScan(snap({ [10] = { 80, 95, 100, 2, 1 } }), clock - 60, "me", "partial")
      local pts = store:Intraday(10, clock - 2 * 86400)
      assert.are.equal(2, #pts)
      assert.are.equal(clock - 7200, pts[1].t)
      assert.are.equal(105, pts[1].market)
      assert.are.equal("partial", pts[2].kind)
      assert.are.equal(95, pts[2].market)
    end)

    it("Latest is nil for unknown items", function()
      local store = newStore()
      store:AddScan(snap({ [10] = { 1, 1, 1, 1, 1 } }), clock, "a")
      assert.is_nil(store:Latest(11))
    end)

    it("keeps raw scans in time order even if added out of order", function()
      local data = {}
      local store = newStore(data)
      store:AddScan(snap({ [1] = { 1, 1, 1, 1, 1 } }), clock, "a")
      store:AddScan(snap({ [1] = { 2, 2, 2, 1, 1 } }), clock - 60, "b")
      assert.are.equal(clock - 60, data.raw[1].t)
      assert.are.equal(1, store:Latest(1).min)
    end)

    it("ignores an exact duplicate scan (same time and source)", function()
      local data = {}
      local store = newStore(data)
      local s = snap({ [1] = { 1, 1, 1, 1, 1 } })
      store:AddScan(s, clock, "a")
      store:AddScan(s, clock, "a")
      assert.are.equal(1, #data.raw)
    end)

    it("prunes raw scans older than 48 hours", function()
      local data = {}
      local store = newStore(data)
      store:AddScan(snap({ [1] = { 1, 1, 1, 1, 1 } }), clock - 49 * 3600, "old")
      store:AddScan(snap({ [1] = { 2, 2, 2, 1, 1 } }), clock, "new")
      assert.are.equal(1, #data.raw)
      assert.are.equal("new", data.raw[1].src)
    end)
  end)

  describe("hourly points", function()
    local variant = 12 + 1000000 * 7 -- item 12 with suffix 7

    it("Round3 keeps 3 significant figures", function()
      assert.are.equal(999, ns.Codec.Round3(999))
      assert.are.equal(1230, ns.Codec.Round3(1234))
      assert.are.equal(123000, ns.Codec.Round3(123456))
      assert.are.equal(100000, ns.Codec.Round3(99960))
    end)

    it("a full scan leaves one per hour: plain items, rounded prices; partial scans don't", function()
      local data = {}
      local store = newStore(data)
      store:AddScan(snap({ [10] = { 12345, 23456, 1, 5, 2 }, [variant] = { 1, 1, 1, 1, 1 } }), clock, "a")
      store:AddScan(snap({ [11] = { 1, 1, 1, 1, 1 } }), clock + 60, "b", "partial")
      local hour = math.floor(clock / 3600)
      local e = data.hours[hour]
      assert.are.equal(clock, e.t)
      assert.are.equal("a", e.src)
      local p = store:HourPoint(e)
      assert.are.same({ 10 }, p.ids)
      assert.are.same({ 12300 }, p.min)
      assert.are.same({ 23500 }, p.market)
      assert.are.same({ 5 }, p.qty)
      assert.are.same({ 2 }, p.auctions)
      assert.are.equal(
        1,
        (function()
          local n = 0
          for _ in pairs(data.hours) do
            n = n + 1
          end
          return n
        end)()
      )
    end)

    it("the newest full scan of an hour wins", function()
      local data = {}
      local store = newStore(data)
      local h0 = clock - clock % 3600
      store:AddScan(snap({ [10] = { 1, 1, 1, 1, 1 } }), h0 + 1200, "later")
      store:AddScan(snap({ [10] = { 2, 2, 2, 2, 2 } }), h0 + 600, "earlier")
      assert.are.equal("later", data.hours[math.floor(h0 / 3600)].src)
      store:AddScan(snap({ [10] = { 3, 3, 3, 3, 3 } }), h0 + 1800, "latest")
      assert.are.equal("latest", data.hours[math.floor(h0 / 3600)].src)
    end)

    it("are kept 7 days; a pruned full scan from before them leaves its hour", function()
      local data = {}
      local store = newStore(data)
      local old = clock - 47 * 3600
      store:AddScan(snap({ [10] = { 100, 110, 120, 5, 2 } }), old, "a")
      data.hours = {} -- as if stored by an older version
      clock = clock + 2 * 3600
      store:AddScan(snap({ [10] = { 90, 100, 100, 4, 2 } }), clock, "b") -- prunes the old raw scan
      assert.are.equal(1, #data.raw)
      local e = data.hours[math.floor(old / 3600)]
      assert.are.equal(old, e.t)
      assert.are.same({ 110 }, store:HourPoint(e).market)
      clock = clock + 7 * 86400 - 3600 -- the scan at "old" is now more than 7 days back
      store:Rollup()
      assert.is_nil(data.hours[math.floor(old / 3600)])
      assert.is_not_nil(data.hours[math.floor((clock - 7 * 86400 + 3600) / 3600)])
    end)

    it("Intraday plots them before the scans kept in full, without repeating a scan", function()
      local store = newStore()
      store:AddScan(snap({ [10] = { 100, 110, 120, 5, 2 } }), clock - 5 * 86400, "a")
      store:AddScan(snap({ [10] = { 90, 105, 115, 7, 3 } }), clock - 7200, "b")
      store:AddScan(snap({ [10] = { 80, 95, 100, 2, 1 } }), clock - 60, "me", "partial")
      local pts = store:Intraday(10, clock - 7 * 86400)
      assert.are.equal(3, #pts)
      assert.are.equal("hour", pts[1].kind)
      assert.are.equal(clock - 5 * 86400, pts[1].t)
      assert.are.equal(110, pts[1].market)
      assert.is_nil(pts[1].median)
      assert.are.equal("full", pts[2].kind) -- its hourly point isn't repeated
      assert.are.equal("partial", pts[3].kind)
      -- a 2-day window leaves the old hour out; a variant has no hourly points
      assert.are.equal(2, #store:Intraday(10, clock - 2 * 86400))
      assert.are.same({}, store:Intraday(variant, clock - 7 * 86400))
    end)
  end)

  describe("daily rollup", function()
    it("keeps the day's highest market price (the upper candle wick) next to the average", function()
      local store = newStore()
      local day0 = clock - clock % 86400
      store:AddScan(snap({ [10] = { 90, 100, 100, 5, 2 } }), day0 + 3600, "a")
      store:AddScan(snap({ [10] = { 150, 200, 200, 5, 2 } }), day0 + 3 * 3600, "b")
      local p = store:Series(10)[1]
      assert.are.equal(150, p.market)
      assert.are.equal(200, p.high)
    end)

    it("reads segments written before the high column existed, and adds highs to them", function()
      local data = {}
      local store = newStore(data)
      local day0 = clock - clock % 86400
      store:AddScan(snap({ [10] = { 90, 100, 100, 5, 2 } }), day0 + 3600, "a")
      -- rewrite the day's segment in the old 8-column format
      local day = math.floor((day0 + 3600) / 86400)
      for b, packed in pairs(data.days[day]) do
        local cols = ns.Codec.Decode(Store.SEGMENT_FIELDS, ns.Codec.Unpack(packed, compressor))
        local old = { "ids", "min", "market", "median", "qty", "auctions", "scans", "hours" }
        data.days[day][b] = ns.Codec.Pack(ns.Codec.Encode(old, cols), compressor)
      end
      local fresh = newStore(data)
      local p = fresh:Series(10)[1]
      assert.are.equal(100, p.market)
      assert.is_nil(p.high) -- unknown for old data
      fresh:AddScan(snap({ [10] = { 150, 300, 300, 5, 2 } }), day0 + 5 * 3600, "b")
      assert.are.equal(300, fresh:Series(10)[1].high)
    end)

    it("records liquidity: units gone between consecutive full scans and the minutes covered", function()
      local store = newStore()
      local day0 = clock - clock % 86400
      store:AddScan(snap({ [10] = { 100, 100, 100, 100, 5 }, [11] = { 50, 50, 50, 20, 2 } }), day0 + 3600, "a")
      store:AddScan(snap({ [10] = { 100, 100, 100, 130, 5 }, [11] = { 50, 50, 50, 20, 2 } }), day0 + 7200, "a")
      -- 3 hours later: 60 of item 10 gone, item 11 sold out (not listed any more)
      store:AddScan(snap({ [10] = { 100, 100, 100, 70, 5 } }), day0 + 4 * 3600, "a")
      local p10 = store:Series(10)[1]
      assert.are.equal(60, p10.drain) -- 100 -> 130 adds nothing (new listings), 130 -> 70 drains 60
      assert.are.equal(60 + 120, p10.obs) -- minutes covered by both scan pairs
      local p11 = store:Series(11)[1]
      assert.are.equal(20, p11.drain) -- everything gone
      assert.are.equal(60 + 120, p11.obs)
    end)

    it("doesn't add liquidity for a scan that arrives late (relayed), so no interval counts twice", function()
      local store = newStore()
      local day0 = clock - clock % 86400
      store:AddScan(snap({ [10] = { 100, 100, 100, 100, 5 } }), day0 + 3600, "a")
      store:AddScan(snap({ [10] = { 100, 100, 100, 40, 5 } }), day0 + 5 * 3600, "a")
      store:AddScan(snap({ [10] = { 100, 100, 100, 70, 5 } }), day0 + 3 * 3600, "relayed")
      local p = store:Series(10)[1]
      assert.are.equal(60, p.drain)
      assert.are.equal(240, p.obs)
    end)

    it("writes today's daily point on every scan", function()
      local store = newStore()
      store:AddScan(snap({ [10] = { 100, 110, 120, 5, 2 } }), clock, "a")
      local s = store:Series(10)
      assert.are.equal(1, #s)
      local expected = { day = 1000, res = "day", min = 100, market = 110, high = 110, median = 120 }
      expected.qty, expected.auctions, expected.scans = 5, 2, 1
      assert.is_true(s[1].hours > 0) -- the hour it was sampled in
      expected.hours = s[1].hours
      assert.are.same(expected, s[1])
    end)

    it("drops an item's mixed history once its suffixes show up, and stores no plain-ID data for it after", function()
      local store = newStore()
      local magic = ns.ItemKey(15211, 1234)
      store:AddScan(snap({ [15211] = { 900, 2000, 2000, 5, 5 }, [10] = { 5, 5, 5, 1, 1 } }), clock - DAY, "a")
      assert.are.equal(1, #store:Series(15211))
      store:AddScan(snap({ [magic] = { 3500, 3500, 3500, 1, 1 } }), clock, "a")
      assert.are.equal(0, #store:Series(15211)) -- the blend of every suffix is gone
      assert.are.equal(1, #store:Series(magic))
      assert.are.equal(1, #store:Series(10)) -- other items untouched
      assert.is_true(store:Mixed(15211))
      -- plain-ID data for it later (an older version over sync, a backfill) isn't stored
      store:AddScan(snap({ [15211] = { 900, 2000, 2000, 5, 5 } }), clock + 60, "old")
      assert.are.equal(0, #store:Series(15211))
      store:ImportDay(990, { { 15211, 1, 1, 1, 1, 1, 1 } }, "backfill")
      assert.are.equal(0, #store:Series(15211))
    end)

    it("aggregates several scans of the same day", function()
      local store = newStore()
      store:AddScan(snap({ [10] = { 100, 100, 100, 4, 2 } }), clock, "a")
      store:AddScan(snap({ [10] = { 80, 120, 130, 6, 4 } }), clock + 2 * 3600, "b")
      local p = store:Series(10)[1]
      assert.are.equal(80, p.min) -- lowest seen
      assert.are.equal(110, p.market) -- mean
      assert.are.equal(115, p.median) -- mean
      assert.are.equal(5, p.qty) -- mean
      assert.are.equal(3, p.auctions) -- mean
      assert.are.equal(2, p.scans)
    end)

    it("only averages over scans that listed the item", function()
      local store = newStore()
      store:AddScan(snap({ [10] = { 100, 100, 100, 4, 2 } }), clock, "a")
      store:AddScan(snap({ [11] = { 5, 5, 5, 1, 1 } }), clock + 60, "b")
      local p = store:Series(10)[1]
      assert.are.equal(100, p.market)
      assert.are.equal(1, p.scans)
    end)

    it("keeps separate points per UTC day, sorted oldest first", function()
      local store = newStore()
      store:AddScan(snap({ [10] = { 100, 100, 100, 1, 1 } }), clock - DAY, "a")
      store:AddScan(snap({ [10] = { 200, 200, 200, 1, 1 } }), clock, "a")
      local s = store:Series(10)
      assert.are.equal(2, #s)
      assert.are.equal(999, s[1].day)
      assert.are.equal(1000, s[2].day)
      assert.are.equal(200, s[2].market)
    end)

    it("keeps a closed day's point after its raw scans are pruned", function()
      local store = newStore()
      store:AddScan(snap({ [10] = { 100, 100, 100, 1, 1 } }), clock - 3 * DAY, "a")
      store:AddScan(snap({ [10] = { 200, 200, 200, 1, 1 } }), clock, "a")
      local s = store:Series(10)
      assert.are.equal(997, s[1].day)
      assert.are.equal(100, s[1].market)
    end)

    it("merges a late scan (e.g. from sync) into a day whose raw scans are gone, exactly once", function()
      local store = newStore()
      local early = clock - 3 * DAY
      store:AddScan(snap({ [10] = { 100, 100, 100, 2, 1 } }), early, "me")
      store:AddScan(snap({ [10] = { 999, 999, 999, 1, 1 } }), clock, "me") -- prunes the early raw scan
      local late = snap({ [10] = { 80, 200, 200, 4, 3 } })
      assert.is_true(store:AddScan(late, early + 2 * 3600, "guildmate"))
      assert.is_false(store:AddScan(late, early + 2 * 3600, "guildmate")) -- re-sent: ignored
      local p = store:Series(10, 997, 997)[1]
      p.hours = nil
      assert.are.same(
        { day = 997, res = "day", min = 80, market = 150, high = 200, median = 150, qty = 3, auctions = 2, scans = 2 },
        p
      )
    end)

    it("is idempotent", function()
      local data = {}
      local store = newStore(data)
      store:AddScan(snap({ [10] = { 100, 110, 120, 5, 2 } }), clock, "a")
      local before = store:Series(10)
      store:Rollup()
      store:Rollup()
      assert.are.same(before, store:Series(10))
    end)

    it("stores daily points as packed per-bucket strings", function()
      local data = {}
      local store = newStore(data)
      store:AddScan(snap({ [10] = { 1, 1, 1, 1, 1 }, [10 + Store.BUCKETS] = { 2, 2, 2, 1, 1 } }), clock, "a")
      local buckets = data.days[1000]
      assert.are.equal("string", type(buckets[10 % Store.BUCKETS]))
      assert.are.equal(2, store:Series(10 + Store.BUCKETS)[1].min)
    end)
  end)

  describe("hourly sampling (incremental scans)", function()
    it("counts at most one sample per item per hour toward daily means", function()
      local store = newStore()
      store:AddScan(snap({ [10] = { 100, 100, 100, 4, 2 } }), clock, "a", "full")
      for k = 1, 20 do -- someone keeps searching the item during a dip
        store:AddScan(snap({ [10] = { 50, 50, 50, 1, 1 } }), clock + k * 60, "a", "partial")
      end
      local p = store:Series(10)[1]
      assert.are.equal(100, p.market)
      assert.are.equal(1, p.scans)
      assert.are.equal(50, p.min) -- the lowest price seen today is still a fact worth keeping
    end)

    it("same-hour samples still update Latest", function()
      local store = newStore()
      store:AddScan(snap({ [10] = { 100, 100, 100, 4, 2 } }), clock, "a", "full")
      store:AddScan(snap({ [10] = { 50, 55, 60, 1, 1 } }), clock + 60, "a", "partial")
      assert.are.equal(55, store:Latest(10).market)
    end)

    it("samples in different hours all count", function()
      local store = newStore()
      for h = 0, 3 do
        store:AddScan(snap({ [10] = { 100 + h, 100 + h, 100 + h, 1, 1 } }), clock + h * 3600, "a", "partial")
      end
      local p = store:Series(10)[1]
      assert.are.equal(4, p.scans)
      assert.are.equal(102, p.market) -- round(101.5)
    end)

    it("an item's hour slot does not block other items in the same hour", function()
      local store = newStore()
      store:AddScan(snap({ [10] = { 1, 1, 1, 1, 1 } }), clock, "a", "partial")
      store:AddScan(snap({ [10] = { 9, 9, 9, 1, 1 }, [11] = { 7, 7, 7, 1, 1 } }), clock + 60, "a", "full")
      assert.are.equal(1, store:Series(10)[1].market)
      assert.are.equal(7, store:Series(11)[1].market)
    end)

    it("accepts different partial scans from the same source in the same second", function()
      local data = {}
      local store = newStore(data)
      assert.is_true(store:AddScan(snap({ [10] = { 1, 1, 1, 1, 1 } }), clock, "a", "partial"))
      assert.is_true(store:AddScan(snap({ [11] = { 2, 2, 2, 1, 1 } }), clock, "a", "partial"))
      assert.are.equal(2, #data.raw)
      assert.are.equal("partial", data.raw[1].k)
    end)
  end)

  describe("ImportDay (backfill)", function()
    it("adds points for items the day doesn't have yet, once per import key", function()
      local store = newStore()
      store:AddScan(snap({ [10] = { 100, 100, 100, 1, 1 } }), clock, "me")
      local rows = { { 10, 1, 1, 1, 1, 0, 1 }, { 11, 50, 60, 60, 3, 0, 1 } }
      assert.is_true(store:ImportDay(1000, rows, "auctionator"))
      assert.is_false(store:ImportDay(1000, rows, "auctionator"))
      assert.are.equal(100, store:Series(10)[1].market) -- own data wins
      local p = store:Series(11)[1]
      assert.are.equal(60, p.market)
      assert.are.equal(1, p.scans)
    end)

    it("imports into days that have no data at all", function()
      local store = newStore()
      store:ImportDay(990, { { 11, 50, 60, 60, 3, 0, 1 } }, "auctionator")
      assert.are.equal(990, store:Series(11)[1].day)
    end)
  end)

  describe("time slicing", function()
    it("calls the injected yield between buckets so a full scan can be spread over frames", function()
      local yields = 0
      local store = Store.New({}, {
        compressor = compressor,
        now = function()
          return clock
        end,
        yield = function()
          yields = yields + 1
        end,
      })
      local items = {}
      for id = 1, 3 * Store.BUCKETS do
        items[id] = { 1, 1, 1, 1, 1 }
      end
      coroutine.wrap(function() -- background jobs run in a coroutine; outside one the store never yields
        store:AddScan(snap(items), clock, "a")
      end)()
      assert.is_true(yields >= Store.BUCKETS, "yields " .. yields)
      yields = 0
      store:Series(1) -- on the main thread (a slash command): no yielding
      assert.are.equal(0, yields)
    end)

    -- A guildmate's full scan received over sync (SyncService:Merge): checked against our prices, the spread learnt,
    -- then stored. Work is counted in Lua instructions between pauses; no stretch may run through more than a small
    -- share of the scan (a whole pass over its items without a pause made 30-80 ms frames in game).
    it("a large received scan pauses all through: checking, the spread and storing (many items)", function()
      ns = addon.load({ "Core/Sync.lua", "Core/Spread.lua" }, ns)
      local ITEMS = 12000
      local function big(seed)
        local items = {}
        for id = 1, ITEMS do
          local p = 1000 + (id * seed) % 50000
          items[id * 3] = { p, p + 50, p + 80, 1 + id % 200, 1 + id % 9 }
        end
        return snap(items)
      end
      local work, stretch, longest, stretches = 0, 0, 0, 0
      local store = Store.New({}, {
        compressor = compressor,
        now = function()
          return clock
        end,
        yield = function()
          longest = math.max(longest, stretch)
          stretch, stretches = 0, stretches + 1
        end,
      })
      local function measured(fn)
        local ok, err = pcall(coroutine.wrap(function() -- a hook is per coroutine in Lua 5.1: set inside it
          debug.sethook(function()
            work, stretch = work + 1, stretch + 1
          end, "", 100)
          fn()
          debug.sethook()
        end))
        assert(ok, err)
        longest = math.max(longest, stretch)
      end
      measured(function()
        store:AddScan(big(7), clock - 3600, "me", "full") -- ours, an hour earlier: the drain pairs with it
      end)
      work, stretch, longest, stretches = 0, 0, 0, 0
      local received = big(11)
      local packed = ns.Codec.Pack(ns.Codec.EncodeSnapshot(received), compressor)
      local ref = {}
      for i, id in ipairs(received.ids) do
        ref[id] = { market = received.market[i] }
      end
      measured(function()
        local pause = store:pauser()
        assert.is_true((ns.Sync.Plausible(received, ref, pause)))
        ns.Spread.Learn({}, received, pause)
        assert.is_true(store:AddScan(received, clock, "Zakzu", "full", packed))
      end)
      assert.is_true(stretches > 100, "pauses " .. stretches)
      assert.is_true(longest * 40 < work, ("longest stretch %d of %d"):format(longest, work))
      assert.are.equal(2, #store.data.raw) -- stored alongside ours
      assert.are.equal(packed, store.data.raw[2].s) -- as it came
    end)

    it("works inside a coroutine that yields", function()
      local store = Store.New({}, {
        compressor = compressor,
        now = function()
          return clock
        end,
        yield = coroutine.yield,
      })
      local co = coroutine.create(function()
        store:AddScan(snap({ [10] = { 5, 5, 5, 1, 1 }, [11] = { 6, 6, 6, 1, 1 } }), clock, "a")
      end)
      local steps = 0
      while coroutine.status(co) ~= "dead" do
        assert(coroutine.resume(co))
        steps = steps + 1
      end
      assert.is_true(steps > 1)
      assert.are.equal(6, store:Series(11)[1].market)
    end)
  end)

  describe("queries", function()
    it("Series filters by day range", function()
      local store = newStore()
      for d = 3, 0, -1 do
        store:AddScan(snap({ [10] = { d, d, d, 1, 1 } }), clock - d * DAY, "a")
      end
      local s = store:Series(10, 998, 999)
      assert.are.equal(2, #s)
      assert.are.equal(998, s[1].day)
      assert.are.equal(999, s[2].day)
    end)

    it("Series of an unknown item is empty", function()
      local store = newStore()
      store:AddScan(snap({ [10] = { 1, 1, 1, 1, 1 } }), clock, "a")
      assert.are.same({}, store:Series(12345))
    end)

    it("a new Store over the same data sees the same history (no hidden state)", function()
      local data = {}
      newStore(data):AddScan(snap({ [10] = { 100, 110, 120, 5, 2 } }), clock, "a")
      assert.are.same(newStore(data):Series(10), newStore(data):Series(10))
      assert.are.equal(110, newStore(data):Series(10)[1].market)
    end)
  end)

  describe("storing scans cheaply", function()
    it("stores an already-packed scan as is, and pairs full scans without decompressing the previous one", function()
      local data = {}
      local store = newStore(data)
      local first = snap({ [10] = { 100, 100, 100, 10, 2 } })
      local packed = ns.Codec.Pack(ns.Codec.EncodeSnapshot(first), store.compressor)
      store:AddScan(first, clock, "guildmate", "full", packed)
      assert.are.equal(packed, data.raw[1].s)
      local unpacks = 0
      local unpack = ns.Codec.Unpack
      ns.Codec.Unpack = function(s, ...)
        if s == packed then -- the previous scan (merging into the day's segment unpacks that, which is fine)
          unpacks = unpacks + 1
        end
        return unpack(s, ...)
      end
      store:AddScan(snap({ [10] = { 100, 100, 100, 4, 1 } }), clock + 3600, "me")
      ns.Codec.Unpack = unpack
      assert.are.equal(0, unpacks)
      local p = store:Series(10)[1]
      assert.are.equal(6, p.drain) -- 10 -> 4 units between the two scans
    end)
  end)

  describe("decompressed segments kept between index builds", function()
    it("decompresses only what changed since the last build, and gives the same series", function()
      local data = {}
      local store = newStore(data)
      for d = 990, 1000 do
        clock = d * DAY + 3600
        store:AddScan(snap({ [10] = { d, d, d, 1, 1 }, [42] = { 5, 5, 5, 1, 1 } }), clock, "a")
      end
      local b = 10 % Store.BUCKETS
      local plain = store:BucketSeries(b, 991, 1000)
      local unpacks = 0
      local unpack = ns.Codec.Unpack
      ns.Codec.Unpack = function(...)
        unpacks = unpacks + 1
        return unpack(...)
      end
      local function build()
        store.cache, store.cacheOrder = {}, {} -- no help from the decoded-segment cache
        store:KeepTexts(true)
        return store:BucketSeries(b, 991, 1000)
      end
      build()
      unpacks = 0
      assert.are.same(plain, build())
      assert.are.equal(0, unpacks) -- nothing changed
      store:AddScan(snap({ [10] = { 1, 1, 1, 1, 1 } }), clock + 60, "a") -- today's segment changes
      unpacks = 0
      local after = build()
      assert.are.equal(1, unpacks)
      assert.are.equal(1, after[10][#after[10]].min)
      store:KeepTexts(false)
      assert.is_nil(store.texts)
      ns.Codec.Unpack = unpack
    end)
  end)

  describe("weekly compaction", function()
    it("folds daily points older than DAYS_KEEP into weekly points", function()
      local data = {}
      local store = newStore(data)
      -- 7 days of one week, long ago: week 140 = days 980..986
      for d = 980, 986 do
        clock = d * DAY + 3600
        store:AddScan(snap({ [10] = { d - 900, 100, 100, 10, 2 } }), clock, "a")
      end
      clock = (986 + Store.DAYS_KEEP + 1) * DAY + 3600
      store:AddScan(snap({ [10] = { 50, 50, 50, 1, 1 } }), clock, "a")

      assert.is_nil(data.days[980])
      local s = store:Series(10)
      assert.are.equal(2, #s)
      local expected = { week = 140, day = 980, res = "week", min = 80, market = 100, high = 100, median = 100 }
      expected.qty, expected.auctions, expected.scans = 10, 2, 7
      assert.are.same(expected, s[1])
      assert.are.equal("day", s[2].res)
    end)

    it("does not compact a partial week that still has recent days", function()
      local data = {}
      local store = newStore(data)
      clock = 1000 * DAY
      store:AddScan(snap({ [10] = { 1, 1, 1, 1, 1 } }), clock, "a")
      clock = clock + (Store.DAYS_KEEP - 1) * DAY
      store:AddScan(snap({ [10] = { 1, 1, 1, 1, 1 } }), clock, "a")
      assert.is_not_nil(data.days[1000])
    end)

    it("drops weekly points older than WEEKS_KEEP", function()
      local data = {}
      local store = newStore(data)
      clock = 1000 * DAY
      store:AddScan(snap({ [10] = { 1, 1, 1, 1, 1 } }), clock, "a")
      clock = clock + (Store.DAYS_KEEP + 14) * DAY
      store:AddScan(snap({ [10] = { 2, 2, 2, 1, 1 } }), clock, "a")
      assert.is_not_nil(next(data.weeks)) -- folded
      clock = clock + (Store.WEEKS_KEEP + 2) * 7 * DAY
      store:AddScan(snap({ [10] = { 3, 3, 3, 1, 1 } }), clock, "a")
      for week in pairs(data.weeks) do
        assert.truthy(week >= math.floor(clock / DAY / 7) - Store.WEEKS_KEEP)
      end
      assert.are.equal(3, store:Series(10)[#store:Series(10)].min)
    end)
  end)
end)

describe("Store split parts (the item charts' recent scans)", function()
  local ns, Store
  before_each(function()
    ns = addon.load({ "Core/Init.lua", "Core/Codec.lua", "Core/Store.lua" })
    Store = ns.Store
  end)

  it("splits columns by item bucket, keeping the rows in order and the missing columns out", function()
    local cols = { ids = { 1, 33, 34, 65 }, min = { 10, 20, 30, 40 }, market = { 11, 21, 31, 41 } }
    local parts = Store.Split({ "ids", "min", "market", "median" }, cols)
    assert.are.same({ "ids", "min", "market" }, parts.fields)
    local one = ns.Codec.Decode(parts.fields, parts[1])
    assert.are.same({ 1, 33, 65 }, one.ids)
    assert.are.same({ 10, 20, 40 }, one.min)
    assert.are.same({ 34 }, ns.Codec.Decode(parts.fields, parts[2]).ids)
    assert.is_nil(parts[3])
  end)
end)
