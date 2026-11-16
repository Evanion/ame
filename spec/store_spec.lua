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

  describe("daily rollup", function()
    it("writes today's daily point on every scan", function()
      local store = newStore()
      store:AddScan(snap({ [10] = { 100, 110, 120, 5, 2 } }), clock, "a")
      local s = store:Series(10)
      assert.are.equal(1, #s)
      assert.are.same(
        { day = 1000, res = "day", min = 100, market = 110, median = 120, qty = 5, auctions = 2, scans = 1 },
        s[1]
      )
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
      assert.are.same(
        { day = 997, res = "day", min = 80, market = 150, median = 150, qty = 3, auctions = 2, scans = 2 },
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
      store:AddScan(snap(items), clock, "a")
      assert.is_true(yields >= Store.BUCKETS, "yields " .. yields)
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

  describe("weekly compaction", function()
    it("folds daily points older than 180 days into weekly points", function()
      local data = {}
      local store = newStore(data)
      -- 7 days of one week, long ago: week 140 = days 980..986
      for d = 980, 986 do
        clock = d * DAY + 3600
        store:AddScan(snap({ [10] = { d - 900, 100, 100, 10, 2 } }), clock, "a")
      end
      clock = (986 + 181) * DAY + 3600
      store:AddScan(snap({ [10] = { 50, 50, 50, 1, 1 } }), clock, "a")

      assert.is_nil(data.days[980])
      local s = store:Series(10)
      assert.are.equal(2, #s)
      local expected = { week = 140, day = 980, res = "week", min = 80, market = 100, median = 100 }
      expected.qty, expected.auctions, expected.scans = 10, 2, 7
      assert.are.same(expected, s[1])
      assert.are.equal("day", s[2].res)
    end)

    it("does not compact a partial week that still has recent days", function()
      local data = {}
      local store = newStore(data)
      clock = 1000 * DAY
      store:AddScan(snap({ [10] = { 1, 1, 1, 1, 1 } }), clock, "a")
      clock = clock + 179 * DAY
      store:AddScan(snap({ [10] = { 1, 1, 1, 1, 1 } }), clock, "a")
      assert.is_not_nil(data.days[1000])
    end)
  end)
end)
