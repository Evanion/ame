-- Core/ItemPage.lua and the Item screen (boards Main, ItemAH, ItemCompact, ItemAHCompact), and Market's Overview
-- body (Core/Overview.lua, boards MarketOverview, MarketOverviewCompact): the model's rows and the trees, away,
-- at the auction house, and in the narrow window.
local wow = require("spec.helpers.wow")
local addon = require("spec.helpers.addon")

local DAY = 86400

describe("the Item page", function()
  local env, ns, P

  before_each(function()
    env = wow.install()
    ns = addon.load({
      "Core/Init.lua",
      "Core/Settings.lua",
      "Core/ItemCache.lua",
      "Core/Analytics.lua",
      "Core/MarketStats.lua",
      "Core/Watch.lua",
      "Core/Shopping.lua",
      "Core/UI/Tokens.lua",
      "Core/UI/Kit.lua",
      "Core/UI/Layout.lua",
      "Core/UI/Widgets.lua",
      "Core/ItemPage.lua",
      "Core/Overview.lua",
    })
    _G.AME_DB = { settings = {} }
    P = ns.ItemPage
  end)

  after_each(function()
    env:restore()
  end)

  -- n days of a rising market with growing supply
  local function series(n, base)
    local out = {}
    for i = 1, n do
      out[i] = { day = 90 + i, market = (base or 600) + i * 25, min = (base or 600) + i * 24, qty = 1000 + i * 150, scans = 2 }
    end
    return out
  end

  describe("model", function()
    it("ranges: 2D with a scan in the last two days, else 7D; the narrow window has no 1Y", function()
      local now = 100 * DAY
      assert.equals("2D", P.Range(nil, { t = now - 3600 }, now))
      assert.equals("7D", P.Range(nil, { t = now - 5 * DAY }, now))
      assert.equals("30D", P.Range("30D", nil, now))
      assert.equals("All", P.Range("1Y", nil, now, true))
      assert.equals(5, #P.RangeOptions(true))
      assert.equals(6, #P.RangeOptions(false))
    end)

    it("summarizes: the market now against its average, with the confidence", function()
      local sum = P.Summarize(series(10), { market = 957, min = 904, qty = 3234, t = 0 }, { avgDays = 7, today = 100 })
      assert.equals(957, sum.market)
      assert.is_true(sum.change > 0)
      local pc = P.PriceCard(sum)
      assert.equals(957, pc.now)
      assert.matches("above", pc.vs)
      assert.equals("good", pc.vsTone)
      assert.matches("scans this week", pc.note)
      local stats = P.StatRows(sum)
      assert.equals(904, stats[1].copper)
      assert.equals("Supply", stats[4].label)
      assert.equals("bad", stats[4].tone) -- supply growing: bad for sellers
      assert.is_nil(P.Summarize({}, nil, {}))
    end)

    it("the verdict says the call, how fast it sells, and why in one line", function()
      local sum = P.Summarize(series(10), { market = 1300, t = 0 }, { avgDays = 7, today = 100 })
      sum.s.soldPerDay = 2969
      local signal, head, line = P.Verdict(sum, { signal = "sell" })
      assert.equals("sell", signal)
      assert.equals("Dearer than usual, and selling fast.", head)
      assert.matches("over its 7%-day average while supply grows: a good time to sell what you hold%.", line)
      local _, none = P.Verdict(nil)
      assert.equals("No call yet", none)
    end)

    it("the posting ladder: Quick, Normal (picked), Patient, what you net", function()
      local advice = {
        quick = { price = 920, hours = 0.5 },
        normal = { price = 931, hours = 3, ahead = 85 },
        patient = { price = 980, hours = 24 },
        deposit = 0,
      }
      local p = P.PostLadder(advice, 120, 24, 0.05, 106080)
      assert.equals("Post 120 at (24 h listing)", p.head.label)
      assert.equals("85 ahead", p.head.text)
      assert.equals(3, #p.picks)
      assert.is_true(p.picks[2].selected)
      assert.equals(106080, p.net.copper)
      assert.equals(0, #P.PostLadder(nil, 1, 24).picks)
    end)

    it("your position: what you hold, where, the average cost and what it's up", function()
      local rows = P.Position(
        { total = 120, bags = 40, bank = 80, chars = { { name = "Tyken" }, { name = "Kke" } } },
        { unit = 610, units = 120 },
        957
      )
      assert.equals("120", rows[1].text)
      assert.equals("Tyken, Kke", rows[2].text)
      assert.equals(610, rows[3].copper)
      assert.equals((957 - 610) * 120, rows[4].copper)
      assert.equals("none", P.Position(nil)[1].text)
    end)

    it("other auction houses: here, how much better another nets, and no data", function()
      local rows, note = P.Houses({
        { house = "Horde", label = "Horde AH", market = 957, net = 900, mine = true },
        { house = "Neutral", label = "Goblin AH", market = 1120, net = 918, age = "1 day old" },
      }, "Horde", { Alliance = "Alliance AH" })
      assert.equals("here", rows[1].note)
      assert.equals("+2% net", rows[2].note)
      assert.equals("good", rows[2].noteTone)
      assert.equals("no data", rows[3].text)
      assert.matches("goblin data 1 day old", note)
    end)

    it("crafting: what it goes into, who of yours makes it, and the rest", function()
      local rows = P.CraftRows({ usedIn = 2459, makers = { { name = "Kke", profit = 120 } }, more = 2 })
      assert.equals(2459, rows[1].valueItem)
      assert.equals("Kke makes it", rows[2].label)
      assert.equals("and 2 more recipes", rows[3].label)
      assert.equals("showRecipes", rows[3].action)
    end)

    it("listings: cheapest first, the rows an order takes from picked", function()
      local book = { commodity = true, rows = { { price = 904, qty = 60 }, { price = 910, qty = 85 }, { price = 931, qty = 120, mine = true } }, at = 0 }
      local rows, cost, covered, units = P.Listings(book, 100, 0)
      assert.equals(60 * 904 + 40 * 910, cost)
      assert.equals(100, covered)
      assert.equals(265, units)
      assert.is_true(rows[2].selected)
      assert.is_nil(rows[3].selected)
      assert.is_true(rows[3].mine)
      assert.equals("265 on sale · just now", P.OnSale(book, units, 10))
    end)

    it("the action bar: Search and Sell need the auction house", function()
      local away = P.Actions({ sellable = 40, watchLists = { "Alchemy" }, alert = { below = 600 } }, false)
      assert.equals("Search the AH", away[1].label)
      assert.equals("disabled", away[1].variant)
      assert.equals("disabled", away[2].variant)
      assert.matches("Watching · Alchemy", away[4].label)
      assert.equals("disabled", away[6].variant) -- nobody makes it
      local at = P.Actions({ sellable = 40, whoCan = true }, true)
      assert.equals("Search again", at[1].label)
      assert.equals("Sell 40", at[2].label)
      assert.equals("normal", at[2].variant)
      assert.equals("normal", at[6].variant)
    end)

    it("the chart's points: daily on the long ranges, scan by scan on 2D with the average over a week", function()
      local now = 100 * DAY
      local sum = P.Summarize(series(10), nil, { avgDays = 7, today = 100 })
      local scans = {}
      for i = 1, 24 do
        scans[i] = { t = now - 30 * 3600 + i * 3600, market = 800 + i, min = 790, qty = 100 }
      end
      local entry = { series = series(10), intraday = scans }
      local daily = P.ChartData(entry, sum, "30D", now)
      assert.equals(10, #daily.points)
      assert.is_false(daily.intraday)
      local d2 = P.ChartData(entry, sum, "2D", now)
      assert.is_true(d2.intraday)
      assert.equals(24, #d2.points)
      assert.is_not_nil(d2.points[24].avg)
      local none = P.ChartData({ series = {} }, nil, "7D", now)
      assert.matches("No history", none.message)
      assert.matches("Loading", P.ChartData(nil, nil, "7D", now).message)
    end)

    it("the rolling average moves by one hour's share per scan", function()
      local xs, vs = {}, {}
      for i = 1, 3 do
        xs[i], vs[i] = i * 3600, 100
      end
      local avg = P.RollingAverage(xs, vs, {})
      assert.equals(100, avg[3])
    end)
  end)

  describe("Overview model", function()
    local o = {
      day = 99,
      level = 104.2,
      levelChange = 0.009,
      value = 486000000000,
      valueChange = 0.031,
      turnover = 23100000000,
      auctions = 312480,
      auctionsChange = -0.024,
      items = 18412,
      units = 4860000,
      basket = 3940,
      up = 2281,
      down = 1659,
      buy = 412,
      sell = 287,
      risers = { { itemID = 2452, market = 957, change7 = 0.56 } },
      fallers = { { itemID = 3818, market = 1443, change7 = -0.43 } },
      sectors = {
        { classID = 7, value = 165000000000, share = 0.34, change = 0.06, turnover = 11500000000 },
        { classID = -1, value = 4000000, share = 0.01 },
      },
      top = { { id = 12640, qty = 1, price = 250000000, value = 250000000, rawValue = 2500000000 } },
      series = { days = { 98, 99 }, value = { 1, 2 }, auctions = { 3, 4 }, levelDays = { 98, 99 }, level = { 100, 104.2 } },
    }

    it("headline cards with their changes; the narrow window four without notes", function()
      local k = ns.Overview.Kpis(o, 4)
      assert.equals(5, #k)
      assert.equals("104.2", k[1].value)
      assert.equals("▲ 0.9%", k[1].delta)
      assert.equals("good", k[1].deltaTone)
      assert.equals("bad", k[4].deltaTone)
      assert.equals("58%", k[5].value)
      local c = ns.Overview.Kpis(o, 4, true)
      assert.equals(4, #c)
      assert.is_nil(c[1].note)
    end)

    it("movers, categories, the largest items and the chart", function()
      local m = ns.Overview.Movers(o.risers, 7)
      assert.equals(0.56, m[1].change)
      assert.equals(2452, m[1].item)
      local cats, max = ns.Overview.Categories(o, function()
        return "Trade goods"
      end)
      assert.equals("Trade goods", cats[1].name)
      assert.equals("Other", cats[2].name)
      assert.equals(0.34, max)
      local big = ns.Overview.Largest(o.top)
      assert.equals("1 ×", big[1].count.text)
      assert.matches("capped from", big[1].value.text)
      local ch = ns.Overview.ChartData(o, "index")
      assert.equals(100, ch.base)
      assert.equals(2, #ch.xs)
      assert.is_nil(ns.Overview.ChartData(o, "value").base)
    end)

    it("works a summary out once per index, period, hidden items and outlier setting", function()
      local runs, steps, real = 0, 0, ns.MarketStats.Summary
      ns.MarketStats.Summary = function(_, period, _, _, _, _, _, step)
        runs = runs + 1
        if step then
          step()
          steps = steps + 1
        end
        return { day = 1, period = period }
      end
      local watch = ns.Watch.New({})
      ns.AME = { watch = watch }
      local a, b = { items = {} }, { items = {} }
      local first = ns.Overview.Summary(a, 7)
      assert.equals(first, ns.Overview.Summary(a, 7))
      assert.equals(1, runs)
      ns.Overview.Summary(a, 30)
      assert.equals(2, runs)
      ns.Overview.Summary(b, 7) -- a new scan is a new index
      assert.equals(3, runs)
      watch:SetHidden(2452, true)
      ns.Overview.Summary(b, 7)
      assert.equals(4, runs)
      ns.Settings:Set("outlierFactor", 6)
      ns.Overview.Summary(b, 7)
      assert.equals(5, runs)
      -- after a scan, the default period is worked out in a background job, pausing as it goes
      local queued
      ns.AME.jobs = {
        Add = function(_, name, fn)
          queued = name
          fn({ Checkpoint = function() end })
        end,
      }
      ns.AME.CurrentShard = function()
        return "R|Horde"
      end
      local c = { items = {}, stats = {} }
      ns.Overview.Warm("R|Neutral", c) -- another market: not now
      assert.is_nil(queued)
      ns.Overview.Warm("R|Horde", c)
      assert.equals("overview-warm", queued)
      assert.equals(1, steps)
      local before = runs
      ns.Overview.Summary(c, ns.Overview.DEFAULT_PERIOD)
      assert.equals(before, runs) -- the first open finds it ready
      ns.MarketStats.Summary, ns.AME = real, nil
    end)
  end)

  describe("the screen", function()
    local App, stores

    local function fakeStore()
      return {
        Series = function()
          return stores.series
        end,
        Latest = function()
          return stores.latest
        end,
        Mixed = function()
          return false
        end,
        Intraday = function()
          return stores.intraday or {}
        end,
      }
    end

    before_each(function()
      addon.load({
        "Core/UI/Help.lua",
        "Core/UI/DataTable.lua",
        "Core/UI/Parts/Primitives.lua",
        "Core/UI/Parts/Chrome.lua",
        "Core/UI/Parts/Table.lua",
        "Core/UI/Parts/Composites.lua",
        "Core/UI/App.lua",
        "Core/UI/Parts/Chart.lua",
        "Core/UI/Parts/Trade.lua",
        "Core/UI/Parts/Item.lua",
        "Core/UI/Screens/Item.lua",
        "Core/UI/Screens/MarketOverview.lua",
      }, ns)
      App = ns.App
      stores = { series = series(10), latest = { market = 957, min = 904, qty = 3234, t = 100 * DAY - 7200 } }
      ns.ShardKey = ns.ShardKey or function(r, h)
        return r .. "|" .. h
      end
      local index = { items = { [2452] = { market = 957, signal = "sell", day = 99 } } }
      ns.AME = {
        ahOpen = false,
        CurrentHouse = function()
          return "Horde"
        end,
        MarketRealmName = function()
          return "Forever"
        end,
        HasData = function()
          return true
        end,
        HistoryLoaded = function()
          return true
        end,
        CachedIndex = function()
          return index
        end,
        WithStore = function(_, _, _, fn, onDone)
          onDone(true, fn(fakeStore()))
        end,
        watch = ns.Watch.New({}),
        shopping = ns.Shopping.New({}),
        ledger = {
          db = { entries = { { itemID = 2452, kind = "buy", qty = 10, amount = 6100, t = 95 * DAY } } },
          CostBasis = function()
            return { [2452] = { unit = 610, units = 120 } }
          end,
        },
      }
      ns.Trading = {
        Held = function()
          return { total = 120, bags = 40, bank = 80, chars = { { name = "Tyken" } } }
        end,
      }
      ns.Posting = {
        Suggest = function()
          return {
            quick = { price = 920, hours = 0.5 },
            normal = { price = 931, hours = 3, ahead = 85 },
            patient = { price = 980, hours = 24 },
            deposit = 0,
            qty = 120,
          }
        end,
      }
      ns.AHSearch = {
        results = { [2452] = { commodity = true, rows = { { price = 904, qty = 60 }, { price = 910, qty = 85 } }, at = 100 * DAY } },
        Push = function() end,
      }
      env.now = 100 * DAY
      ns.ItemPage.cache = {}
      App.state, App.back, App.ahead = nil, {}, {}
    end)

    local cases = {
      { "away", false, false },
      { "at the AH", true, false },
      { "narrow", false, true },
      { "narrow at the AH", true, true },
    }
    for _, case in ipairs(cases) do
      it("draws a valid tree " .. case[1], function()
        ns.AME.ahOpen = case[2]
        App:Show()
        App.frame:SetSize(case[3] and 760 or 1100, case[2] and 830 or 640)
        App.compact = case[3]
        App:Go("item", { item = 2452 })
        local tree = App:Tree()
        assert.same({}, ns.Layout.Validate(tree))
        assert.is_nil(ns.Layout.Find(tree, "error"))
        assert.same({}, ns.ItemPage.errors)
        App:Render()
        assert.is_not_nil(App.renderer:Frame("item.name"))
        if case[2] then
          assert.is_not_nil(App.renderer:Frame("item.buy"))
        else
          assert.is_nil(App.renderer:Frame("item.buy"))
        end
        if not case[3] then
          assert.is_not_nil(App.renderer:Frame("item.verdict"))
          assert.is_not_nil(App.renderer:Frame("item.position"))
        end
      end)
    end

    it("narrow with Details open: the right column beside the chart", function()
      App:Show()
      App.frame:SetSize(760, 460)
      App.compact = true
      App:Go("item", { item = 2452, details = true })
      assert.same({}, ns.Layout.Validate(App:Tree()))
      assert.is_not_nil(ns.Layout.Find(App:Tree(), "item.right"))
    end)

    it("draws a valid tree with no item, and while the history loads", function()
      App:Show()
      App:Go("item", {})
      assert.same({}, ns.Layout.Validate(App:Tree()))
      assert.is_nil(ns.Layout.Find(App:Tree(), "error"))
      ns.AME.WithStore = function() end -- never answers
      ns.ItemPage.cache = {}
      App:Go("item", { item = 2452 })
      assert.same({}, ns.Layout.Validate(App:Tree()))
      assert.is_nil(ns.Layout.Find(App:Tree(), "error"))
    end)

    it("a range click is yours from then on; the search box opens an item", function()
      App:Show()
      App:Go("item", { item = 2452 })
      App.ctx:Dispatch("range", { key = "90D" })
      local _, params = App:Current()
      assert.equals("90D", params.range)
      assert.equals("90D", ns.ItemScreens.picked)
      ns.ItemCache.Learn = function()
        return 3818
      end
      App.ctx:Dispatch("find", { text = "Fadeleaf" })
      local id, p2 = App:Current()
      assert.equals("item", id)
      assert.equals(3818, p2.item)
    end)

    it("the alert menu sets an alert below a price; Hide from lists hides it", function()
      App:Show()
      App:Go("item", { item = 2452 })
      App.ctx:Dispatch("setAlert", { key = "below:800" })
      assert.equals(800, ns.AME.watch:Alert(2452).below)
      App.ctx:Dispatch("toggleHidden", {})
      assert.is_true(ns.AME.watch:IsHidden(2452))
      App.ctx:Dispatch("watchList", { key = "list:1" })
      assert.is_true(ns.AME.watch:Has(1, 2452))
    end)

    it("the status says where the prices come from", function()
      App:Show()
      ns.AME.history = { shards = { ["Forever|Horde"] = { raw = { { k = "full", t = 100 * DAY - 7200 }, { k = "search", t = 100 * DAY - 60 } } } } }
      App:Go("item", { item = 2452 })
      App:Tree()
      local status = ns.ItemScreens.Status(App, { item = 2452 })
      assert.matches("Prices from your full scan", status)
      assert.matches("1 searches since", status)
    end)

    describe("Market overview body", function()
      local summary

      before_each(function()
        ns.Settings:Set("marketOverview", true)
        summary = {
          day = 99,
          level = 104.2,
          levelChange = 0.009,
          value = 100,
          turnover = 10,
          auctions = 5,
          up = 3,
          down = 1,
          risers = { { itemID = 2452, market = 957, change7 = 0.5 } },
          fallers = {},
          sectors = { { classID = 7, value = 100, share = 1 } },
          top = {},
          series = { days = { 98, 99 }, value = { 1, 2 }, auctions = { 1, 2 }, levelDays = { 98, 99 }, level = { 100, 104.2 } },
        }
        ns.MarketStats.Summary = function()
          return summary
        end
        ns.AME.CachedIndex = function()
          return { items = {}, stats = {} }
        end
      end)

      local function screen(compact, params)
        App.Screen("market", {
          tab = "market",
          Build = function(app, p)
            return ns.ItemScreens.OverviewBody(app, p)
          end,
        })
        App:Show()
        App.compact = compact
        App:Go("market", params or { mode = "overview" })
        return App:Tree()
      end

      it("draws a valid tree, wide and narrow", function()
        assert.same({}, ns.Layout.Validate(screen(false)))
        assert.is_nil(ns.Layout.Find(App:Tree(), "error"))
        assert.is_not_nil(ns.Layout.Find(App:Tree(), "ov.risers"))
        assert.same({}, ns.Layout.Validate(screen(true)))
        assert.is_nil(ns.Layout.Find(App:Tree(), "ov.risers"))
        assert.is_not_nil(ns.Layout.Find(App:Tree(), "ov.categories"))
      end)

      it("says why when there's nothing to show", function()
        ns.AME.CachedIndex = function()
          return { items = {} }
        end
        ns.Settings:Set("marketOverview", false)
        local tree = screen(false)
        assert.same({}, ns.Layout.Validate(tree))
        assert.matches("switch on", ns.Layout.Find(tree, "ov.message").props.text)
      end)

      it("the period and the category answer as actions", function()
        screen(false)
        App.ctx:Dispatch("overviewPeriod", { key = "30" })
        local _, params = App:Current()
        assert.equals("30", params.period)
        App.ctx:Dispatch("overviewCategory", { key = "class:7" })
        local id, p = App:Current()
        assert.equals("market", id)
        assert.equals(7, p.classID)
        assert.equals("screener", p.mode)
      end)
    end)
  end)
end)
