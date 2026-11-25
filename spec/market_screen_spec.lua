-- Core/Market.lua and the Market screen: the screener's query, sidebar, chips and columns; your alerts; what's on
-- sale at the auction house; shopping lists and buying down them; arbitrage routes; and the screen's tree in every
-- mode and state (away, at the auction house, the narrow window).
local wow = require("spec.helpers.wow")
local addon = require("spec.helpers.addon")

describe("Market", function()
  local env, ns, Market

  before_each(function()
    env = wow.install()
    ns = addon.load({
      "Core/Init.lua",
      "Core/Settings.lua",
      "Core/ItemCache.lua",
      "Core/Analytics.lua",
      "Core/MarketFilter.lua",
      "Core/Watch.lua",
      "Core/Notices.lua",
      "Core/Shopping.lua",
      "Core/Arbitrage.lua",
      "Core/Depth.lua",
      "Core/AHSearch.lua",
      "Core/AHBrowse.lua",
      "Core/Market.lua",
    })
    _G.AME_DB = { settings = {} }
    Market = ns.Market
  end)

  after_each(function()
    env:restore()
  end)

  describe("the query", function()
    it("alerts take every alerted item, any quality or category", function()
      local q = Market.NewQuery()
      q.classID = 7
      local alerts = { [5] = { below = 1 } }
      local f = Market.FilterQuery(q, { alerts = alerts })
      assert.equals(alerts, f.only)
      assert.is_nil(f.minQuality)
      assert.is_nil(f.classID)
      assert.equals("name", f.sortKey)
    end)
    it("hidden items stay out of every list but their own", function()
      local q = Market.NewQuery()
      local hidden = { [9] = true }
      assert.equals(hidden, Market.FilterQuery(q, { hidden = hidden }).hide)
      q.list = "hidden"
      assert.is_nil(Market.FilterQuery(q, { hidden = hidden }).hide)
    end)
    it("Any quality is no quality filter; the Signal column sorts by its rank", function()
      local q = Market.NewQuery()
      q.minQuality = 0
      assert.is_nil(Market.FilterQuery(q).minQuality)
      assert.equals("signalRank", Market.SortKey("signal"))
      assert.equals("name", Market.SortKey("__name"))
      assert.equals("signal", Market.SortColumn("signalRank"))
    end)
  end)

  describe("the sidebar", function()
    local f = {
      total = 7004,
      lists = { { name = "Watchlist", count = 0 }, { name = "Alchemy", count = 8 } },
      alerts = 3,
      categories = { { classID = 7, name = "Trade goods", count = 399, subs = { { subClassID = 1, name = "Parts", count = 4 } } } },
    }
    it("lists All items, the watchlists, + New list, Your alerts and the categories with counts", function()
      local e = Market.Sidebar(f, Market.NewQuery())
      local keys = {}
      for _, x in ipairs(e) do
        keys[#keys + 1] = x.key or ("#" .. x.label)
      end
      assert.same({ "all", "#Watchlists", "list:1", "list:2", "newlist", "#Alerts", "alerts", "#Categories", "class:7" }, keys)
      assert.equals("7,004", e[1].count)
      assert.is_true(e[1].selected)
      assert.is_true(e[5].link)
    end)
    it("an open category shows its subcategories; Your alerts is lit in its view", function()
      local q = Market.NewQuery()
      q.classID = 7
      local e = Market.Sidebar(f, q)
      assert.equals("sub:7:1", e[#e].key)
      assert.is_true(e[#e - 1].selected)
      local a = Market.Sidebar(f, Market.NewQuery(), "alerts")
      assert.is_true(a[7].selected)
      assert.is_false(a[1].selected)
    end)
    it("a pick changes the query: a list, a category (again closes it), a subcategory", function()
      local q = Market.NewQuery()
      local sets = { lists = { {}, { [3] = true } } }
      assert.equals("list", Market.PickEntry(q, "list:2", sets))
      assert.equals(2, q.list)
      assert.same({ [3] = true }, q.only)
      assert.is_nil(Market.PickEntry(q, "class:7", sets))
      assert.is_nil(q.list)
      assert.equals(7, q.classID)
      Market.PickEntry(q, "class:7", sets)
      assert.is_nil(q.classID)
      Market.PickEntry(q, "sub:7:1", sets)
      assert.same({ 7, 1 }, { q.classID, q.subClassID })
      assert.equals("alerts", Market.PickEntry(q, "alerts", sets))
      assert.equals("newlist", Market.PickEntry(q, "newlist", sets))
    end)
  end)

  describe("chips", function()
    it("one per active filter, each removable; Clear all keeps the sort", function()
      local q = Market.NewQuery()
      q.text, q.minQuality, q.minPrice, q.classID, q.sortKey = "lotus", 2, 10000, 7, "market"
      local chips = Market.Chips(q, { className = "Trade goods" })
      local keys = {}
      for i, c in ipairs(chips) do
        keys[i] = c.key
      end
      assert.same({ "text", "quality", "min", "class" }, keys)
      assert.equals('"lotus"', chips[1].label)
      assert.equals("Uncommon+", chips[2].label)
      Market.ClearChip(q, "quality")
      assert.equals(1, q.minQuality)
      Market.ClearAll(q)
      assert.is_nil(q.text)
      assert.equals("market", q.sortKey)
    end)
    it("Your alerts is a chip of its own, and the search at the auction house too", function()
      local chips = Market.Chips(Market.NewQuery(), { ahText = "lotus" }, "alerts")
      assert.equals("alerts", chips[1].key)
      assert.equals("ahtext", chips[2].key)
    end)
  end)

  describe("columns", function()
    it("the screener's: optional ones off until chosen, counted as hidden", function()
      local cols, hidden = Market.Columns("screener", {}, 7)
      local keys = {}
      for i, c in ipairs(cols) do
        keys[i] = c.key
      end
      assert.same({ "name", "market", "vsAvg", "qty", "soldPerDay", "hold", "signal", "score" }, keys)
      assert.equals(4, hidden)
      assert.equals("vs 7-day avg", cols[3].label)
      local more = Market.Columns("screener", { avg = true, score = false }, 7)
      assert.equals("avg", more[3].key)
      assert.equals("Columns · 4 hidden", Market.ColumnsLabel(4))
    end)
    it("alerts, at the auction house and narrow have their own", function()
      assert.equals("below", Market.Columns("alerts")[4].key)
      assert.equals("min", Market.Columns("ah")[2].key)
      assert.equals(5, #Market.Columns("compact"))
      assert.equals(5, #Market.Columns("ahcompact"))
    end)
  end)

  describe("rows", function()
    it("the screener's carry the summary, what you hold, and fade when old", function()
      local rows = Market.ScreenerRows({ { itemID = 1, market = 5, day = 90 }, { itemID = 2, market = 6, day = 100 } }, {
        today = 100,
        held = { [2] = 14 },
      })
      assert.equals(1, rows[1].key)
      assert.equals(5, rows[1].market)
      assert.is_true(rows[1].faded)
      assert.equals("14", rows[2].hold)
      assert.equals("", rows[1].hold)
    end)
    it("alerts: newest fired first, never last, the unread one lit", function()
      local alerts = { [1] = { below = 650000, state = { below = true } }, [2] = { above = 1200, state = {} }, [3] = { above = 1 } }
      local fired = { [1] = { at = 1000000, unread = true }, [2] = { at = 700000 } }
      local rows, lit = Market.AlertRows({ { itemID = 1, market = 620000 }, { itemID = 2, market = 957 } }, alerts, {
        fired = fired,
        now = 1000100,
        date = function()
          return "14:02"
        end,
      })
      assert.same({ 1, 2, 3 }, { rows[1].key, rows[2].key, rows[3].key })
      assert.equals(1, lit)
      assert.equals("today 14:02 · below", rows[1].fired.text)
      assert.equals("warn", rows[1].fired.color)
      assert.equals("3 days ago", rows[2].fired.text)
      assert.equals("never", rows[3].fired.text)
      assert.equals(650000, rows[1].below)
    end)
    it("the newest alert notice per item, and how many fired today", function()
      local fired = Market.FiredFrom({
        { kind = "alert", itemID = 1, at = 90000 },
        { kind = "alert", itemID = 1, at = 80000 },
        { kind = "sale", itemID = 2, at = 85000 },
      })
      assert.equals(90000, fired[1].at)
      assert.is_nil(fired[2])
      assert.equals(1, Market.FiredToday(fired, 90010))
    end)
    it("on sale now, narrowed by the screener's filters", function()
      local found = {
        { key = 1, qty = 14, cheapest = 620000, market = 655000 },
        { key = 2, qty = 3087, cheapest = 580 },
      }
      local items = { [1] = { market = 655000, avg7 = 690000, signal = "buy" } }
      local quality = { [1] = 2, [2] = 1 }
      local rows = Market.AHRows(found, items, { minQuality = 2 }, function(k)
        return { quality = quality[k] }
      end)
      assert.equals(1, #rows)
      assert.equals(620000, rows[1].min)
      assert.equals(14, rows[1].onSale)
      assert.equals("buy", rows[1].signal)
      assert.is_true(rows[1].vsAvg < 0)
    end)
  end)

  describe("lists", function()
    local progress = {
      { itemID = 1, need = 12, have = 4, held = 4, missing = 8, market = 42000, max = 45000, cost = 336000 },
      { itemID = 3, need = 2, have = 0, held = 0, missing = 2, market = 110000, max = 90000, cost = 220000 },
      { itemID = 2, need = 40, have = 40, held = 52, missing = 0, market = 1800 },
    }
    local results = {
      [1] = { commodity = true, rows = { { price = 41500, qty = 5 }, { price = 41500, qty = 10 } } },
      [3] = { commodity = true, rows = { { price = 110000, qty = 4 } } },
    }
    it("away: what's still short at market price, and done when covered", function()
      local rows = Market.ListRows(progress, {})
      assert.equals("8", rows[1].tobuy)
      assert.equals(336000, rows[1].cost)
      assert.equals("done", rows[3].tobuy.text)
      assert.equals(52, rows[3].have)
    end)
    it("at the auction house: the lowest listing, the cost at the listings, over your top price flagged", function()
      local rows, at = Market.ListRows(progress, { ah = true, results = results, onlyTop = true })
      assert.equals(41500, rows[1].price)
      assert.equals(8 * 41500, rows[1].cost)
      assert.equals("warn", rows[2].tobuy.color)
      assert.is_nil(rows[2].cost)
      assert.equals(8 * 41500, at.left)
      assert.equals(1, at.over)
    end)
    it("buying down the list: the next item still short, then the one after; skipped ones passed over", function()
      local n, after = Market.NextBuy(progress, results, { onlyTop = true })
      assert.equals(1, n.key)
      assert.equals(8, n.qty)
      assert.equals(2, n.listings)
      assert.is_true(n.allUnder)
      assert.is_nil(after) -- the pearls are over the top price
      local n2, after2 = Market.NextBuy(progress, results, { onlyTop = false })
      assert.equals(3, after2)
      assert.equals(1, n2.key)
      local n3 = Market.NextBuy(progress, results, { onlyTop = false, skip = { [1] = true } })
      assert.equals(3, n3.key)
    end)
    it("the Buy card's listings: the rows an order takes from picked, the last partly", function()
      local book = { rows = { { price = 620000, qty = 1 }, { price = 625000, qty = 3 }, { price = 640000, qty = 4 } } }
      local rows, cost, onSale = Market.Listings(book, 2)
      assert.is_true(rows[1].selected)
      assert.equals("1 of 3", rows[2].qty)
      assert.is_nil(rows[3].selected)
      assert.equals(1245000, cost)
      assert.equals(8, onSale)
    end)
    it("the sidebar: shopping lists with what's short, watchlists, the guild's", function()
      local e = Market.ListSidebar({
        shopping = { { name = "Mooncloth Robe", missing = 3 }, { name = "Craft queue", done = true } },
        watch = { { name = "Watchlist", count = 0 } },
        guild = { { key = "Zakzu/Raid", name = "Raid consumables", owner = "Zakzu", count = 5, kind = "shop" } },
      }, "shop:1")
      assert.equals("shop:1", e[2].key)
      assert.is_true(e[2].selected)
      assert.equals("done", e[3].count)
      assert.equals("good", e[3].tone)
      assert.equals("sg:Zakzu/Raid", e[#e - 1].key)
      assert.equals("guildlists", e[#e].key)
    end)
    it("status lines away and at the auction house", function()
      local totals = { items = 5, missing = 3, cost = 556000, unpriced = 1 }
      assert.truthy(Market.ListStatus(totals):find("3 of 5 items still to buy", 1, true))
      assert.truthy(Market.ListStatus(totals):find("1 without a price yet", 1, true))
      assert.truthy(Market.ListStatus(totals, { left = 332000 }, "Horde AH"):find("At the Horde AH", 1, true))
      assert.equals("", Market.ListStatus(nil))
    end)
  end)

  describe("arbitrage", function()
    it("routes as rows: margin, units, data age; Search only at the buy house", function()
      local rows = Market.ArbRows({ { itemID = 1, buy = 100, sell = 200, net = 80, margin = 0.3, buyQty = 2, units = 1, age = 1 } }, {})
      assert.truthy(rows[1].margin:find("+30%", 1, true)) -- green / red, as the old Arbitrage tab
      assert.equals("1 of 2", rows[1].units)
      assert.equals("1 day", rows[1].age)
      assert.is_false(rows[1].search)
      assert.equals("Search", Market.ArbRows({ { itemID = 1, buy = 1, sell = 2, margin = 1 } }, { atBuy = true })[1].search)
    end)
    it("the route's sums and how fresh it is", function()
      local e = { buy = 5750000, sell = 7850000, fee = 392500, deposit = 10000, net = 1707500, buyAge = 1, soldPerDay = 1.2 }
      local cost = Market.RouteCost(e, { buyHouse = "Goblin AH", sellHouse = "Horde AH", cutPct = 5 })
      assert.equals("Buy at the Goblin AH", cost[1].label)
      assert.equals(-392500, cost[3].copper)
      assert.is_true(cost[5].total)
      assert.equals("Units", Market.RouteData(e, {})[4].label)
      assert.truthy(Market.RouteNote(e):find("One-day-old", 1, true))
    end)
    it("the newest full scan", function()
      local full = Market.LastFull({ { k = "full", t = 5 }, { k = "item", t = 9 }, { k = "full", t = 7, src = "Klydig" } })
      assert.equals("Klydig", full.src)
    end)
  end)

  -- ------------------------------------------------------------------------------------------------ the screen

  describe("the screen", function()
    local App, index, other

    local function tree()
      local t = App:Tree()
      local err = ns.Layout.Find(t, "error.text")
      assert.is_nil(err and err.props.text)
      assert.same({}, ns.Layout.Validate(t))
      App.renderer:Render(t)
      assert.is_nil(ns.Layout.lastWarning)
      return t
    end

    before_each(function()
      addon.load({
        "Core/UI/Tokens.lua",
        "Core/UI/Kit.lua",
        "Core/UI/Layout.lua",
        "Core/UI/Widgets.lua",
        "Core/UI/Help.lua",
        "Core/UI/DataTable.lua",
        "Core/UI/Parts/Primitives.lua",
        "Core/UI/Parts/Chrome.lua",
        "Core/UI/Parts/Table.lua",
        "Core/UI/Parts/Composites.lua",
      }, ns)
      local f = io.open("Core/UI/Parts/Trade.lua")
      if f then
        f:close()
        addon.load({ "Core/UI/Parts/Trade.lua" }, ns)
      end
      if not ns.Layout.Get("buycard") then -- the Item area's widget, as its contract has it
        ns.Layout.Register("buycard", {
          props = { summary = "string?", listings = "string", qty = "any?", total = "number?", itemKey = "any?" },
          create = function(parent)
            return CreateFrame("Frame", nil, parent)
          end,
          update = function() end,
        })
      end
      addon.load({ "Core/UI/Parts/Market.lua", "Core/UI/App.lua", "Core/UI/Screens/Market.lua" }, ns)
      App = ns.App
      local function item(id, market, signal, day)
        return { itemID = id, market = market, avg7 = market * 1.1, avg30 = market, qty = 100, soldPerDay = 12, signal = signal, signalRank = 1, score = 50 + id, day = day or 100, scans7 = 6, days = 9 }
      end
      index = { day = 100, count = 3, items = { [1] = item(1, 957, "sell"), [2] = item(2, 187, "buy"), [3] = item(3, 90000, "hold", 90) } }
      other = { day = 100, count = 2, items = { [1] = { itemID = 1, min = 100, market = 120, qty = 3, day = 99 }, [2] = { itemID = 2, min = 50, market = 60, qty = 1, day = 100 } } }
      local shards = {}
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
        history = { shards = { [ns.ShardKey("Forever", "Horde")] = { raw = { { k = "full", t = 0 } } } } },
        CachedIndex = function(_, shard)
          shards[shard] = true
          return shard:find("Neutral") and other or index
        end,
        IndexFor = function(self, shard, cb)
          cb(self:CachedIndex(shard))
        end,
        Say = function() end,
        watch = ns.Watch.New({}),
        shopping = ns.Shopping.New({}),
        notices = ns.Notices.New({}),
      }
      ns.ItemCache.Get = function(id)
        return { classID = 7, subClassID = 1, name = "Item " .. tostring(id), quality = 2, sellPrice = 10 }
      end
      ns.ItemCache.ClassName = function()
        return "Trade goods"
      end
      ns.ItemCache.SubClassName = function()
        return "Parts"
      end
      ns.Holdings.Of = function()
        return { [1] = { qty = 120 } }
      end
      ns.AME.watch:SetAlert(1, { below = 650000 })
      ns.AME.notices:Add({ kind = "alert", text = "dropped", itemID = 1 }, GetServerTime())
      ns.AME.shopping:AddList("Mooncloth Robe")
      ns.AME.shopping:SetItem(1, 1, 12, 45000)
      ns.AME.shopping:SetItem(1, 2, 4)
      ns.MarketScreen.q = ns.Market.NewQuery()
      ns.MarketScreen.cache = {}
      ns.MarketScreen.routes, ns.MarketScreen.routesPending, ns.MarketScreen.arb = nil, nil, nil
      App:Show()
    end)

    it("draws the screener: modes, filters, the sidebar and the table", function()
      App:Go("market", { mode = "screener" })
      local t = tree()
      assert.is_not_nil(ns.Layout.Find(t, "market.side"))
      assert.is_not_nil(ns.Layout.Find(t, "market.chips"))
      assert.equals("segmented", ns.Layout.Find(t, "market.mode").type)
      assert.equals(3, #App.ctx.sources["market.rows"])
      assert.truthy(App.screens.market.Status(App):find("3 items", 1, true))
      assert.is_not_nil(App.renderer:Frame("market.table"))
    end)

    it("filters, sorts and picks through its actions", function()
      App:Go("market", { mode = "screener" })
      App.ctx:Dispatch("signal", { key = "buy" })
      App:Tree()
      assert.equals(1, #App.ctx.sources["market.rows"])
      App.ctx:Dispatch("clearAll", {})
      App.ctx:Dispatch("sort", { key = "signal", ascending = true })
      assert.equals("signalRank", ns.MarketScreen.q.sortKey)
      App.ctx:Dispatch("side", { key = "class:7" })
      local t = tree()
      local chips = ns.Layout.Find(t, "market.chips").props.chips
      assert.equals("class", chips[#chips].key)
      App.ctx:Dispatch("chip", { key = "class" })
      assert.is_nil(ns.MarketScreen.q.classID)
      App.ctx:Dispatch("row", { key = 2, button = "LeftButton" })
      assert.equals("item", App:Current())
    end)

    it("draws Your alerts with the alert's columns", function()
      App:Go("market", { view = "alerts" })
      local t = tree()
      local cols = ns.Layout.Find(t, "market.table").props.columns
      assert.equals("below", cols[4].key)
      local rows = App.ctx.sources["market.rows"]
      assert.equals(1, #rows)
      assert.equals(1, ns.Layout.Find(t, "market.table").props.selected)
      assert.truthy(App.screens.market.Status(App):find("1 alerts", 1, true))
    end)

    it("draws narrow: the modes and categories as dropdowns, no sidebar", function()
      App.compact = true
      App:Go("market", { mode = "screener" })
      local t = tree()
      assert.is_nil(ns.Layout.Find(t, "market.side"))
      assert.equals("button", ns.Layout.Find(t, "market.mode").type)
      assert.is_not_nil(ns.Layout.Find(t, "market.category"))
      App.compact = false
    end)

    describe("at the auction house", function()
      before_each(function()
        ns.AME.ahOpen = true
        ns.AHBrowse.results = {
          { itemKey = { itemID = 1, itemSuffix = 0, itemLevel = 10 }, minPrice = 900, totalQuantity = 14 },
          { itemKey = { itemID = 2, itemSuffix = 0, itemLevel = 10 }, minPrice = 150, totalQuantity = 3 },
        }
        ns.AHSearch.results[1] = { commodity = true, rows = { { price = 900, qty = 5 }, { price = 950, qty = 20 } }, at = GetServerTime() }
      end)

      it("searches the auction house: what's on sale now, and the picked row's Buy card", function()
        App:Go("market", { mode = "screener" })
        ns.MarketScreen.ah.text = "item"
        ns.MarketScreen.ah.at = GetServerTime()
        App.ctx:Dispatch("row", { key = 1, button = "LeftButton" })
        assert.equals("market", App:Current())
        local t = tree()
        assert.equals("min", ns.Layout.Find(t, "market.table").props.columns[2].key)
        assert.equals(2, #App.ctx.sources["market.rows"])
        assert.equals("buycard", ns.Layout.Find(t, "market.buy").type)
        assert.equals(2, #App.ctx.sources["market.listings"])
        assert.truthy(App.screens.market.Status(App):find("2 found", 1, true))
      end)

      it("draws narrow at the auction house", function()
        App.compact = true
        App:Go("market", { mode = "screener" })
        ns.MarketScreen.ah.at = GetServerTime()
        local t = tree()
        assert.equals(5, #ns.Layout.Find(t, "market.table").props.columns)
        assert.is_nil(ns.Layout.Find(t, "market.pick"))
        App.compact = false
      end)

      it("a shopping list: Search all and the bar for buying down it", function()
        ns.Holdings.Of = function()
          return { [1] = { qty = 4 } }
        end
        App:Go("market", { mode = "lists" })
        local t = tree()
        assert.is_not_nil(ns.Layout.Find(t, "market.searchAll"))
        local bar = ns.Layout.Find(t, "market.buybar")
        assert.equals(1, bar.props.key)
        assert.equals(8, bar.props.qty) -- 12 needed, 4 held
        assert.equals(5 * 900 + 3 * 950, bar.props.copper)
        App.ctx:Dispatch("buySkip", { key = 1 })
        assert.is_nil(ns.Layout.Find(tree(), "market.buybar").props.key)
      end)
    end)

    it("draws a shopping list away from the auction house", function()
      ns.Holdings.Of = function()
        return { [1] = { qty = 4 } }
      end
      App:Go("market", { mode = "lists" })
      local t = tree()
      assert.is_not_nil(ns.Layout.Find(t, "market.searchAH"))
      assert.is_nil(ns.Layout.Find(t, "market.buybar"))
      local rows = App.ctx.sources["market.list"]
      assert.equals(2, #rows)
      assert.truthy(App.screens.market.Status(App):find("still to buy", 1, true))
    end)

    it("draws arbitrage once both indexes are in, with the picked route", function()
      ns.MarketScreen.arb = { buy = "Neutral", sell = "Horde", minProfit = 1, minMargin = 0, maxAge = 0 }
      App:Go("market", { mode = "arbitrage" })
      local t = tree()
      assert.is_true(#App.ctx.sources["market.routes"] > 0)
      assert.is_not_nil(ns.Layout.Find(t, "market.routeCost"))
      App.ctx:Dispatch("arbSwap", {})
      tree()
    end)

    it("opens on the mode you last used, the overview the first time", function()
      App:Go("market")
      local _, p = App:Current()
      assert.equals("overview", p.mode)
      App:Go("market", { mode = "arbitrage" })
      App:Go("home")
      App:Go("market")
      _, p = App:Current()
      assert.equals("arbitrage", p.mode)
    end)

    it("draws the overview: the Item area's body, or a placeholder until it's there", function()
      App:Go("market", { mode = "overview" })
      tree()
      local had = ns.ItemScreens and ns.ItemScreens.OverviewBody
      ns.ItemScreens = ns.ItemScreens or {}
      ns.ItemScreens.OverviewBody = function()
        return { id = "ov", type = "text", props = { text = "overview" } }
      end
      local t = tree()
      assert.is_not_nil(ns.Layout.Find(t, "ov"))
      ns.ItemScreens.OverviewBody = had
    end)
  end)
end)
