-- Loads the real addon (TOC file list) in a stubbed WoW client and drives the M1 flows end to end.
local wow = require("spec.helpers.wow")

local f = io.open("Libs/LibDeflate/LibDeflate.lua", "r")
local haveLibs = f ~= nil
if f then
  f:close()
end

describe("addon in a stubbed client", function()
  if not haveLibs then
    pending("Libs missing; run scripts/fetch-libs.sh")
    return
  end

  local env, ns

  local function boot(opts)
    env = wow.install(opts)
    ns = wow.loadAddon("AzerothMercantileExchange.toc", "AzerothMercantileExchange")
    if opts and opts.pre then
      opts.pre(ns)
    end
    env:fire("ADDON_LOADED", "AzerothMercantileExchange")
    env:fire("PLAYER_LOGIN")
  end

  local function drainJobs()
    for _ = 1, 5000 do
      if not ns.AME.jobs:Busy() then
        return
      end
      env:update(1)
    end
    error("jobs did not finish")
  end

  local function fullScan(rows)
    env.ah.rows = rows
    C_AuctionHouse.ReplicateItems() -- hooked by the addon, like Auctionator's call
    for _ = 1, 30 do
      env:fire("REPLICATE_ITEM_LIST_UPDATE")
    end
    drainJobs()
  end

  after_each(function()
    if env then
      env:restore()
    end
  end)

  it("records a full scan into the open auction house's shard and answers /ame item", function()
    boot()
    env.npcFaction = nil -- goblin auctioneer
    env:fire("AUCTION_HOUSE_SHOW")
    fullScan({ { 2589, 1000, 10 }, { 2589, 1500, 10 }, { 4306, 5000, 5 } })

    assert.is_true(env:chatContains("recorded full scan: 2 items from 3 listings %(TestRealm · Goblin AH%)"))
    local shard = AME_HistoryDB.shards["TestRealm|Neutral"]
    assert.are.equal(1, #shard.raw)

    env:slash("AZEROTHMERCANTILEEXCHANGE", "item 2589")
    assert.is_true(env:chatContains("latest"))
    assert.is_true(env:chatContains("day %d%d%d%d%-%d%d%-%d%d: min 100c"))
  end)

  it("records sell-tab rechecks as partial scans", function()
    boot()
    env.npcFaction = "Horde"
    env:fire("AUCTION_HOUSE_SHOW")
    env.ah.commodities[2589] = { { 90, 20 } }
    env:fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
    env:advance(2)
    drainJobs()
    local shard = AME_HistoryDB.shards["TestRealm|Horde"]
    assert.are.equal("partial", shard.raw[1].k)
    assert.are.equal(1, AME_DB.stats.partials)
  end)

  it("imports Auctionator history once on AH open", function()
    local DAY = 86400
    boot({
      auctionator = {
        Constants = { SCAN_DAY_0 = 20000 * DAY },
        Database = { db = { ["2589"] = { l = { ["5"] = 80 }, h = { ["5"] = 120 }, a = { ["5"] = 3 }, m = 100 } } },
      },
    })
    env.npcFaction = "Horde"
    env:fire("AUCTION_HOUSE_SHOW")
    drainJobs()
    assert.is_true(env:chatContains("imported 1 days of Auctionator price history"))
    local series = ns.AME:Store():Series(2589)
    assert.are.equal(20005, series[1].day)
    env:fire("AUCTION_HOUSE_SHOW")
    drainJobs()
    assert.are.equal(1, #ns.AME:Store():Series(2589))
  end)

  -- Real data spends the frame budget, so jobs really yield in game. Force a yield at every checkpoint here:
  -- Lua 5.1 can't yield across pcall, which the cheap test clock otherwise hides.
  it("background jobs survive yielding at every checkpoint", function()
    local DAY = 86400
    boot({
      pre = function(n)
        n.AME.jobs.budgetMs = -1
      end,
      auctionator = {
        Constants = { SCAN_DAY_0 = 20000 * DAY },
        Database = {
          db = {
            ["2589"] = { l = { ["5"] = 80 }, h = { ["5"] = 120, ["6"] = 110 }, a = { ["5"] = 3 }, m = 100 },
            ["4306"] = { h = { ["5"] = 500 }, m = 500 },
          },
        },
      },
    })
    env.npcFaction = "Horde"
    env:fire("AUCTION_HOUSE_SHOW")
    drainJobs()
    assert.is_true(env:chatContains("imported 2 days of Auctionator price history"))
    fullScan({ { 2589, 1000, 10 }, { 4306, 5000, 5 } })
    assert.is_true(env:chatContains("recorded full scan"))
    drainJobs()
    assert.is_false(env:chatContains("failed"))
    assert.is_not_nil(ns.AME.index)
  end)

  it("records a full scan on a day that Auctionator history already covers", function()
    local DAY = 86400
    local today = math.floor(1794825000 / DAY)
    boot({
      auctionator = {
        Constants = { SCAN_DAY_0 = (today - 5) * DAY },
        Database = {
          db = {
            ["2589"] = { l = { ["5"] = 80 }, h = { ["5"] = 120, ["4"] = 110 }, a = { ["5"] = 3 }, m = 100 },
            ["4306"] = { h = { ["5"] = 500 }, m = 500 },
          },
        },
      },
    })
    env.npcFaction = "Horde"
    env:fire("AUCTION_HOUSE_SHOW")
    drainJobs()
    fullScan({ { 2589, 1000, 10 }, { 4306, 5000, 5 }, { 774, 300, 1 } })
    assert.is_false(env:chatContains("failed"))
    assert.is_true(env:chatContains("recorded full scan"))
    assert.is_not_nil(AME_DB.stats.lastFull)
  end)

  it("records Auctionator's default browse summary scan", function()
    boot()
    env.npcFaction = "Horde"
    env:fire("AUCTION_HOUSE_SHOW")
    env.ah.browse = { { 2589, 120, 40 }, { 4306, 900, 12 } }
    C_AuctionHouse.SendBrowseQuery({ searchString = "", sorts = {}, filters = {}, itemClassFilters = {} })
    env:fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    drainJobs()
    assert.is_true(env:chatContains("reading full scan %(2 listings%)"))
    assert.is_true(env:chatContains("recorded full scan: 2 items"))
    assert.are.equal(1, AME_DB.stats.scan.browseRequests)
  end)

  it("records a legacy getAll full scan (classic AH)", function()
    boot()
    env.npcFaction = "Horde"
    env:fire("AUCTION_HOUSE_SHOW")
    env.legacyRows = { { 2589, 1000, 10 }, { 4306, 5000, 5 } }
    QueryAuctionItems("", nil, nil, 0, nil, nil, true, false, nil)
    env:advance(1)
    env:advance(1)
    drainJobs()
    assert.is_true(env:chatContains("reading full scan %(2 listings%)"))
    assert.is_true(env:chatContains("recorded full scan: 2 items"))
    assert.are.equal(1, AME_DB.stats.scan.getAllRequests)
    assert.are.equal(2, AME_DB.stats.lastFull.items)
  end)

  it("ignores ordinary legacy searches", function()
    boot()
    env:fire("AUCTION_HOUSE_SHOW")
    env.legacyRows = { { 2589, 1000, 10 } }
    QueryAuctionItems("Linen", nil, nil, 0, nil, nil, false, false, nil)
    env:advance(3)
    drainJobs()
    assert.is_false(env:chatContains("recorded full scan"))
  end)

  it("uses the ruleset as the market on Forever and migrates old realm-named history", function()
    boot({
      realm = "CAMWOWEU5Realm6PvP",
      pre = function()
        _G.AME_HistoryDB =
          { v = 1, shards = { ["CAMWOWEU5Realm6PvP|Horde"] = { raw = {}, seen = {}, days = {}, weeks = {} } } }
        _G.AME_DB = { v = 1, stats = {}, backfilled = { ["CAMWOWEU5Realm6PvP|Horde"] = 123 } }
      end,
    })
    env.npcFaction = "Horde"
    env:fire("AUCTION_HOUSE_SHOW")
    assert.are.equal("PvP|Horde", ns.AME:CurrentShard())
    assert.is_not_nil(AME_HistoryDB.shards["PvP|Horde"])
    assert.is_nil(AME_HistoryDB.shards["CAMWOWEU5Realm6PvP|Horde"])
    assert.are.equal(123, AME_DB.backfilled["PvP|Horde"])
    fullScan({ { 2589, 1000, 10 } })
    assert.is_true(env:chatContains("recorded full scan: 1 items from 1 listings %(PvP · Horde AH%)"))
  end)

  it("reads the Forever market from the game's rules (like Auctionator), Hardcore included", function()
    boot({ realm = "CAMWOWEU9Realm1" })
    _G.RegionalUniqueNamesEnabled = function()
      return true
    end
    _G.C_GameRules = {
      IsGameRuleActive = function(rule)
        return rule == "hc"
      end,
    }
    local savedEnum = _G.Enum
    _G.Enum = setmetatable({ GameRule = { PvPRuleset = "pvp", RPRuleset = "rp", HardcoreRuleset = "hc" } }, {
      __index = savedEnum,
    })
    env.npcFaction = "Horde"
    env:fire("AUCTION_HOUSE_SHOW")
    assert.are.equal("HC|Horde", ns.AME:CurrentShard())
    _G.RegionalUniqueNamesEnabled, _G.C_GameRules, _G.Enum = nil, nil, savedEnum
  end)

  it("imports Auctionator history only at the faction auction house", function()
    local DAY = 86400
    boot({
      auctionator = {
        Constants = { SCAN_DAY_0 = 20000 * DAY },
        Database = { db = { ["2589"] = { h = { ["5"] = 120 }, m = 100 } } },
      },
    })
    env.npcFaction = nil -- goblin auctioneer
    env:fire("AUCTION_HOUSE_SHOW")
    drainJobs()
    assert.is_false(env:chatContains("imported"))
    assert.is_nil(AME_DB.backfilled["TestRealm|Neutral"])
    env.npcFaction = "Horde"
    env:fire("AUCTION_HOUSE_SHOW")
    drainJobs()
    assert.is_true(env:chatContains("imported 1 days"))
  end)

  it("survives a client that lacks some events", function()
    boot({ unknownEvents = { COMMODITY_SEARCH_RESULTS_UPDATED = true } })
    env:fire("AUCTION_HOUSE_SHOW")
    fullScan({ { 1, 100, 1 } })
    assert.is_true(env:chatContains("recorded full scan"))
  end)

  it("/ame selftest runs every check and offers a reload button", function()
    boot()
    env.npcFaction = "Horde"
    env:fire("AUCTION_HOUSE_SHOW")
    fullScan({ { 2589, 1000, 10 }, { 4306, 5000, 5 } })
    env:slash("AZEROTHMERCANTILEEXCHANGE", "selftest")
    assert.is_true(env:chatContains("selftest: %d+ passed, %d+ warnings, 0 failed"))
    assert.are.equal(0, env.reloads) -- ReloadUI is protected outside hardware events
    local popup = StaticPopupDialogs.AME_SELFTEST_RELOAD
    assert.are.equal("AME_SELFTEST_RELOAD", env.popup)
    popup.OnAccept()
    assert.are.equal(1, env.reloads)
    assert.are.equal("PASS", AME_DB.selftest.results[1].status)
  end)

  describe("UI", function()
    local function seeded()
      boot()
      env.npcFaction = "Horde"
      env:fire("AUCTION_HOUSE_SHOW")
      for d = 0, 9 do
        env.now = env.now + 86400
        fullScan({ { 2589, 1000 + d * 10, 10 }, { 4306, 5000 - d * 100, 5 } })
      end
      env:advance(4) -- login timer: load history + build index
      drainJobs()
    end

    it("builds the market index after scans and feeds the screener", function()
      seeded()
      assert.is_not_nil(ns.AME.index)
      assert.are.equal(2, ns.AME.index.count)
      env:slash("AZEROTHMERCANTILEEXCHANGE", "")
      ns.UI:ShowTab("market")
      local rows = ns.UI.marketView.rows
      assert.is_not_nil(rows[1].itemID)
      assert.truthy(rows[1].cells[1].text:find("Item"))
    end)

    it("scrolls without re-filtering and filters by search and category", function()
      seeded()
      ns.UI:Toggle()
      ns.UI:ShowTab("market")
      local v = ns.UI.marketView
      local applies = 0
      local apply = ns.MarketFilter.Apply
      ns.MarketFilter.Apply = function(...)
        applies = applies + 1
        return apply(...)
      end
      for _ = 1, 20 do
        v.main.scripts.OnMouseWheel(v.main, -1)
      end
      assert.are.equal(0, applies) -- scrolling only re-renders rows
      v.search:SetText("2589")
      v.search.scripts.OnTextChanged(v.search)
      assert.are.equal(1, #ns.UI.list)
      assert.are.equal(2589, v.rows[1].itemID)
      v.search:SetText("")
      v.search.scripts.OnTextChanged(v.search)
      -- category sidebar: All items, watchlists, "+ New list", then classes; clicking a class filters to it
      local classLine = v.side.lines[4]
      assert.are.equal(7, classLine.entry.classID)
      classLine.scripts.OnClick(classLine)
      assert.are.equal(2, #ns.UI.list)
      -- quality dropdown: pick "Rare+" from the menu
      local rare = v.quality.menu.items[4]
      rare.scripts.OnClick(rare)
      assert.are.equal(3, ns.UI.mq.minQuality)
      assert.are.equal(0, #ns.UI.list) -- stub items are common quality
      assert.truthy(v.quality.label.text:find("Rare+", 1, true))
      ns.UI:ResetMarketFilters()
      assert.are.equal(1, ns.UI.mq.minQuality) -- back to the default: Common+ (no grey junk)
      assert.are.equal(2, v.quality.index)
      ns.MarketFilter.Apply = apply
    end)

    it("stars items into a watchlist, shows the list and fires alerts after a scan", function()
      seeded()
      ns.UI:Toggle()
      ns.UI:ShowTab("market")
      local v = ns.UI.marketView
      local row = v.rows[1]
      local id = row.itemID
      row.star.scripts.OnClick(row.star)
      assert.is_true(ns.AME.watch:Has(1, id))
      -- sidebar: line 2 is the watchlist; selecting it shows only watched items
      local listLine = v.side.lines[2]
      assert.are.equal(1, listLine.entry.list)
      listLine.scripts.OnClick(listLine, "LeftButton")
      assert.are.equal(1, #ns.UI.list)
      assert.are.equal(id, ns.UI.list[1].itemID)
      -- alert from the item page: below a price far above the current market
      ns.UI:ShowItem(id)
      drainJobs()
      local below = ns.UI.itemView.alertBelow
      below:SetText("1000")
      below.scripts.OnTextChanged(below, true)
      assert.are.equal(1000 * 10000, ns.AME.watch:Alert(id).below)
      assert.are.equal("Watching", ns.UI.itemView.watch.label.text)
      fullScan({ { 2589, 900, 10 }, { 4306, 4000, 5 } })
      drainJobs()
      assert.is_true(env:chatContains("Alert:"))
      assert.is_true(env:chatContains("dropped to"))
      -- the Guide tab exists and hover explanations are wired
      ns.UI:ShowTab("guide")
      local header = v.headers[#v.headers]
      header.scripts.OnEnter(header)
    end)

    it("ignores an outrageous one-day price in the index and on the item page", function()
      boot()
      env.npcFaction = "Horde"
      env:fire("AUCTION_HOUSE_SHOW")
      for d = 0, 9 do
        env.now = env.now + 86400
        local price = d == 5 and 10000 or 1000 -- one day with a single 10x listing
        fullScan({ { 2589, price, 1 } })
      end
      env:advance(4)
      drainJobs()
      local s = ns.AME.index.items[2589]
      assert.are.equal(1, s.outliers)
      assert.is_true(s.avg30 < 1500)
      ns.UI:ShowItem(2589)
      drainJobs()
      assert.truthy(ns.UI.itemView.sub.text:find("1 outlier price ignored"))
    end)

    it("finds buy-here-sell-there routes between the faction and goblin AH after the cut", function()
      boot()
      -- Horde AH: Linen cheap; goblin AH: Linen dear, Wool cheaper than at Horde
      env.npcFaction = "Horde"
      env:fire("AUCTION_HOUSE_SHOW")
      fullScan({ { 2589, 1000, 10 }, { 2592, 4000, 10 } })
      env:fire("AUCTION_HOUSE_CLOSED")
      env.now = env.now + 60
      env.npcFaction = nil
      env:fire("AUCTION_HOUSE_SHOW")
      fullScan({ { 2589, 3000, 10 }, { 2592, 4100, 10 } })
      env:advance(4)
      drainJobs()
      ns.UI:Toggle()
      ns.UI:ShowTab("arbitrage")
      local v = ns.UI.arbView
      assert.are.equal("Horde", ns.UI.arb.buy) -- standing at the goblin AH: default is own faction -> goblin
      assert.are.equal("Neutral", ns.UI.arb.sell)
      v.scripts.OnShow(v)
      drainJobs()
      local rows = ns.UI.arbRows
      assert.are.equal(1, #rows) -- Wool's 2.5% gap doesn't survive the 15% cut
      local r = rows[1]
      assert.are.equal(2589, r.itemID)
      assert.are.equal(100, r.buy) -- per unit
      assert.are.equal(300, r.sell)
      assert.are.equal(45, r.fee) -- 15% goblin cut
      assert.are.equal(155, r.profit)
      assert.are.equal(2589, v.rows[1].itemID)
      assert.truthy(v.status.text:find("15%% cut"))
      -- the other way round finds nothing
      v.swap.scripts.OnClick(v.swap)
      drainJobs()
      assert.are.equal(0, #ns.UI.arbRows)
      assert.truthy(ns.UI.footer.text:find("Tyken Evanion"))
    end)

    it("views any auction house of the market from the title bar, with readable labels", function()
      boot()
      env.npcFaction = "Horde"
      env:fire("AUCTION_HOUSE_SHOW")
      fullScan({ { 2589, 1000, 10 } })
      env:fire("AUCTION_HOUSE_CLOSED")
      env.npcFaction = nil
      env:fire("AUCTION_HOUSE_SHOW")
      fullScan({ { 2589, 3000, 10 }, { 4306, 5000, 5 } })
      env:advance(4)
      drainJobs()
      ns.UI:Toggle()
      ns.UI:ShowTab("market")
      assert.are.equal("Neutral", ns.UI:ViewHouse()) -- standing at the goblin AH
      assert.are.equal(2, #ns.UI.list)
      -- only houses with data are offered (no Alliance scans here); the theme follows the viewed house
      local offered = {}
      for _, o in ipairs(ns.UI.viewSelect.values) do
        offered[#offered + 1] = o[1]
      end
      assert.are.same({ "Horde", "Neutral" }, offered)
      assert.are.equal("Neutral", ns.Widgets.theme)
      -- pick the Horde AH in the title bar
      local horde = ns.UI.viewSelect.menu.items[1]
      horde.scripts.OnClick(horde)
      drainJobs()
      assert.are.equal("Horde", ns.UI:ViewHouse())
      assert.are.equal("Horde", ns.Widgets.theme)
      assert.are.equal(1, #ns.UI.list)
      assert.are.equal(1000 / 10, ns.UI.list[1].market)
      -- the item page follows the viewed house
      ns.UI:ShowItem(2589)
      drainJobs()
      assert.truthy(ns.UI.itemView.sub.text:find("Horde AH", 1, true))
      -- the auction house you're at is always offered, even before its first scan
      env:fire("AUCTION_HOUSE_CLOSED")
      env.npcFaction = "Alliance"
      env:fire("AUCTION_HOUSE_SHOW")
      ns.UI:ShowTab("market")
      assert.are.equal("Alliance", ns.UI:ViewHouse())
      assert.truthy(ns.UI.marketView.status.text:find("No price history for the Alliance AH"))
      assert.are.equal(3, #ns.UI.viewSelect.values)
      -- no raw shard keys ("|N" is an escape code in WoW text) anywhere in chat
      for _, line in ipairs(env.chat) do
        assert.is_nil(line:find("|Neutral", 1, true), line)
      end
      assert.are.equal("PvP · Goblin AH", ns.ShardLabel("PvP|Neutral"))
    end)

    it("lets you pick a fixed window theme in Settings, saved with the settings", function()
      boot()
      env.npcFaction = "Horde"
      env:fire("AUCTION_HOUSE_SHOW")
      ns.UI:Toggle()
      ns.UI:ShowTab("settings")
      local s = ns.UI.settingsView
      s.scripts.OnShow(s)
      local gold = s.theme.menu.items[4]
      gold.scripts.OnClick(gold)
      assert.are.equal("Neutral", AME_DB.settings.theme) -- persisted in the saved variables
      assert.are.equal("Neutral", ns.Widgets.theme) -- applied right away, though we're at the Horde AH
      ns.UI:ViewChanged()
      assert.are.equal("Neutral", ns.Widgets.theme) -- and it sticks when the view changes
      local follow = s.theme.menu.items[1]
      follow.scripts.OnClick(follow)
      assert.are.equal("Horde", ns.Widgets.theme)
    end)

    it("themes the window by auction house faction", function()
      boot()
      env.npcFaction = "Horde"
      env:fire("AUCTION_HOUSE_SHOW")
      ns.UI:Toggle()
      assert.truthy(ns.UI.title.text:find("|cffed4033Azeroth", 1, true))
      env.npcFaction = "Alliance"
      env:fire("AUCTION_HOUSE_SHOW")
      assert.truthy(ns.UI.title.text:find("|cff408fff", 1, true))
      env.npcFaction = nil
      env:fire("AUCTION_HOUSE_SHOW")
      assert.are.equal("Neutral", ns.Widgets.theme)
      local close = ns.UI.closeButton
      close.scripts.OnEnter(close)
      close.scripts.OnLeave(close)
      close.scripts.OnClick(close)
      assert.is_false(ns.UI.frame:IsShown())
    end)

    it("shows the last 2 days scan by scan on the 2D range", function()
      boot()
      env.npcFaction = "Horde"
      env:fire("AUCTION_HOUSE_SHOW")
      local times = {}
      for h = 1, 5 do
        env.now = env.now + 3 * 3600
        times[#times + 1] = env.now
        fullScan({ { 2589, 1000 + h * 100, 10 } })
      end
      env:advance(4)
      drainJobs()
      ns.UI:ShowItem(2589)
      drainJobs()
      local v = ns.UI.itemView
      local two = v.rangeButtons[1]
      assert.are.equal("2D", two.key)
      two.scripts.OnClick(two)
      drainJobs()
      local market = ns.UI.chart.series.market
      assert.are.same(times, market.xs) -- one point per scan, at the scan's time
      assert.is_nil(ns.UI.chart.series.sma)
      -- intraday candles: 2-hour candles from the scans
      v.style.scripts.OnClick(v.style)
      assert.are.equal(5, #ns.UI.candles.xs)
      assert.are.equal(2 * 3600, ns.UI.candles.period)
      v.style.scripts.OnClick(v.style)
      -- back to daily history
      local thirty = v.rangeButtons[3]
      thirty.scripts.OnClick(thirty)
      assert.is_not_nil(ns.UI.chart.series.sma)
    end)

    it("switches the item chart to candles and back", function()
      seeded()
      ns.UI:ShowItem(2589)
      drainJobs()
      local v = ns.UI.itemView
      v.style.scripts.OnClick(v.style)
      assert.are.equal("candles", AME_DB.settings.chartStyle)
      assert.is_not_nil(ns.UI.chart.series.candles)
      assert.is_nil(ns.UI.chart.series.market)
      assert.are.equal(10, #ns.UI.candles.xs)
      -- pooled textures that drew the market area's slanted top must come back rectangular
      local fills = ns.UI.chart.pools.fill
      for i = 1, fills.used do
        for _, off in pairs(rawget(fills.items[i], "offsets") or {}) do
          assert.are.same({ 0, 0 }, off)
        end
      end
      for _, b in ipairs(v.rangeButtons) do -- candle period follows the range
        b.scripts.OnClick(b)
      end
      local x = ns.UI.candles.xs[2]
      local lines = ns.UI.chart.hoverFormatter(ns.UI.chart, x, { candles = { x = x, y = 0, index = 2 } })
      assert.truthy(table.concat(lines, "\n"):find("Open"))
      v.style.scripts.OnClick(v.style)
      assert.is_nil(ns.UI.chart.series.candles)
      assert.is_not_nil(ns.UI.chart.series.market)
    end)

    it("opens an item chart from /ame <link> and fills stats after loading", function()
      seeded()
      env:slash("AZEROTHMERCANTILEEXCHANGE", "|cffffffff|Hitem:2589::::|h[Linen Cloth]|h|r")
      assert.are.equal(2589, ns.UI.itemID)
      drainJobs()
      local cards = ns.UI.itemView.cards
      assert.truthy(cards[1].value.text:find("c") or cards[1].value.text:find("s"))
      assert.is_not_nil(ns.UI.chart.view) -- chart rendered
    end)

    it("shows a friendly message for an item without history", function()
      seeded()
      ns.UI:ShowItem(99999)
      drainJobs()
      assert.truthy(ns.UI.chart.message.text:find("No history"))
    end)

    it("range buttons and zoom don't error", function()
      seeded()
      ns.UI:ShowItem(2589)
      drainJobs()
      for _, b in ipairs(ns.UI.itemView.rangeButtons) do
        b.scripts.OnClick(b)
      end
      local chartFrame = ns.UI.chart.frame
      chartFrame.scripts.OnEnter(chartFrame)
      chartFrame.scripts.OnMouseWheel(chartFrame, 1)
      chartFrame.scripts.OnDoubleClick(chartFrame)
    end)
  end)

  describe("guild sync", function()
    local sent, deliver

    local function bootSync()
      sent = {}
      boot({
        pre = function(n)
          n.AME.syncTransport = {
            Register = function(_, _, handler)
              deliver = handler
            end,
            Send = function(_, _, msg, distribution, target)
              sent[#sent + 1] = { msg = msg, distribution = distribution, target = target }
            end,
          }
        end,
      })
      env.inGuild = true
      env.npcFaction = "Horde"
      env:fire("AUCTION_HOUSE_SHOW")
    end

    -- a guildmate's packed full scan
    local function peerScan(prices)
      local acc = ns.Stats.NewAccumulator()
      for id, p in pairs(prices) do
        acc:Add(id, p, 1)
      end
      return {
        t = env.now - 600,
        src = "Guild Mate",
        k = "full",
        s = ns.Codec.Pack(ns.Codec.EncodeSnapshot(acc:Finish()), ns.AME.compressor),
      }
    end

    it("relays other players' scans for every auction house, and backfills a day of scans quickly", function()
      bootSync()
      -- we (player 2) received player 1's goblin-AH scan earlier and hold our own Horde scan
      fullScan({ { 2589, 1000, 10 } })
      local relayed = peerScan({ [2589] = 1500 })
      relayed.src = "Player One"
      local entry = relayed
      deliver(ns.Sync.EncodeAnnounce("TestRealm|Neutral", { { t = entry.t, src = entry.src } }), "GUILD", "Player One")
      local req = ns.Sync.Decode(sent[#sent].msg)
      assert.are.equal("request", req.type) -- standing at the Horde AH, the goblin AH's scan is still wanted
      assert.are.equal("TestRealm|Neutral", req.shard)
      deliver(ns.Sync.EncodeScan("TestRealm|Neutral", entry), "WHISPER", "Player One")
      drainJobs()
      assert.are.equal("Player One", AME_HistoryDB.shards["TestRealm|Neutral"].raw[1].src)
      -- player 1 logs off; our next announcement carries their scan (for player 3), for both houses
      local before = #sent
      ns.SyncService:Announce()
      local shards, srcs = {}, {}
      for i = before + 1, #sent do
        local m = ns.Sync.Decode(sent[i].msg)
        shards[m.shard] = true
        for _, s in ipairs(m.scans) do
          srcs[s.src] = true
        end
      end
      assert.is_true(shards["TestRealm|Horde"] and shards["TestRealm|Neutral"])
      assert.is_true(srcs["Player One"])
      -- a day of 6 scans from a guild mate: 4 requested from one announcement
      local scans = {}
      for i = 1, 6 do
        scans[i] = { t = env.now - i * 3600, src = "Busy Scanner" }
      end
      before = #sent
      deliver(ns.Sync.EncodeAnnounce("TestRealm|Horde", scans), "GUILD", "Busy Scanner")
      assert.are.equal(4, #sent - before)
    end)

    it("announces our full scan to the guild after recording it", function()
      bootSync()
      fullScan({ { 2589, 1000, 10 } })
      local last = sent[#sent]
      assert.are.equal("GUILD", last.distribution)
      assert.are.equal("announce", ns.Sync.Decode(last.msg).type)
    end)

    it("requests a scan it lacks and merges the reply", function()
      bootSync()
      local entry = peerScan({ [2589] = 120, [4306] = 900 })
      deliver(ns.Sync.EncodeAnnounce("TestRealm|Horde", { { t = entry.t, src = entry.src } }), "GUILD", "Guild Mate")
      local req = ns.Sync.Decode(sent[#sent].msg)
      assert.are.equal("request", req.type)
      assert.are.equal("Guild Mate", sent[#sent].target)

      deliver(ns.Sync.EncodeScan("TestRealm|Horde", entry), "WHISPER", "Guild Mate")
      drainJobs()
      local raw = AME_HistoryDB.shards["TestRealm|Horde"].raw
      assert.are.equal("Guild Mate", raw[#raw].src)
      assert.is_true(env:chatContains("received a full scan from Guild Mate"))
      assert.are.equal(1, AME_DB.stats.syncReceived)

      -- the same announcement again: nothing more to request
      local before = #sent
      deliver(ns.Sync.EncodeAnnounce("TestRealm|Horde", { { t = entry.t, src = entry.src } }), "GUILD", "Guild Mate")
      assert.are.equal(before, #sent)
    end)

    it("serves our scans to guildmates who ask", function()
      bootSync()
      fullScan({ { 2589, 1000, 10 } })
      local mine = AME_HistoryDB.shards["TestRealm|Horde"].raw[1]
      deliver(ns.Sync.EncodeRequest("TestRealm|Horde", mine.t, mine.src), "WHISPER", "Guild Mate")
      local reply = ns.Sync.Decode(sent[#sent].msg)
      assert.are.equal("scan", reply.type)
      assert.are.equal("Guild Mate", sent[#sent].target)
      assert.are.equal(mine.s, reply.packed)
    end)

    it("rejects a poisoned scan that disagrees wildly with our prices", function()
      bootSync()
      local rows = {}
      for id = 1, 10 do
        rows[#rows + 1] = { id, 1000, 1 }
      end
      fullScan(rows)
      env:advance(4)
      drainJobs()
      local prices = {}
      for id = 1, 10 do
        prices[id] = 1000000 -- 1000x our market
      end
      local entry = peerScan(prices)
      deliver(ns.Sync.EncodeAnnounce("TestRealm|Horde", { { t = entry.t, src = entry.src } }), "GUILD", "Guild Mate")
      deliver(ns.Sync.EncodeScan("TestRealm|Horde", entry), "WHISPER", "Guild Mate")
      drainJobs()
      assert.are.equal(1, AME_DB.stats.syncRejected)
      assert.are.equal(1, #AME_HistoryDB.shards["TestRealm|Horde"].raw)
    end)

    it("ignores scans nobody asked for from players it doesn't trust", function()
      bootSync()
      deliver(ns.Sync.EncodeScan("TestRealm|Horde", peerScan({ [2589] = 1000 })), "WHISPER", "Random Stranger")
      drainJobs()
      assert.is_nil(AME_HistoryDB.shards["TestRealm|Horde"])
    end)

    it("pairs trusted players with a hello / approve handshake and syncs over whispers", function()
      bootSync()
      local svc = ns.SyncService
      -- a stranger asks to share: becomes a pending request with a chat notice
      deliver(ns.Sync.EncodeHello("TestRealm|Horde"), "WHISPER", "Ada Lovelace")
      assert.are.equal(1, #svc.trust:PendingList())
      assert.is_true(env:chatContains("wants to share auction prices"))
      -- approving replies with an accept and trusts them both ways
      svc:Approve("Ada Lovelace")
      local last = sent[#sent]
      assert.are.equal("accept", ns.Sync.Decode(last.msg).type)
      assert.are.equal("Ada Lovelace", last.target)
      assert.is_true(svc.trust.db.trusted["ada lovelace"].mutual)
      -- their whispered announcements are now accepted and answered with requests
      local entry = peerScan({ [2589] = 1000 })
      deliver(
        ns.Sync.EncodeAnnounce("TestRealm|Horde", { { t = entry.t, src = entry.src } }),
        "WHISPER",
        "Ada Lovelace"
      )
      assert.are.equal("request", ns.Sync.Decode(sent[#sent].msg).type)
      deliver(ns.Sync.EncodeScan("TestRealm|Horde", entry), "WHISPER", "Ada Lovelace")
      drainJobs()
      assert.are.equal(1, AME_DB.stats.syncReceived)
      assert.are.equal(1, svc.trust.db.peers["ada lovelace"].received)
      -- adding someone sends them a hello; their accept makes it mutual
      svc:AddTrusted("Bob Builder")
      assert.are.equal("hello", ns.Sync.Decode(sent[#sent].msg).type)
      assert.is_false(svc.trust.db.trusted["bob builder"].mutual)
      deliver(ns.Sync.EncodeAccept("TestRealm|Horde"), "WHISPER", "Bob Builder")
      assert.is_true(svc.trust.db.trusted["bob builder"].mutual)
      -- announcements go to trusted players heard from recently (Ada, Bob), on top of the guild
      local before = #sent
      svc:Announce()
      local whispered = {}
      for i = before + 1, #sent do
        if sent[i].distribution == "WHISPER" then
          whispered[#whispered + 1] = sent[i].target
        end
      end
      table.sort(whispered)
      assert.are.same({ "Ada Lovelace", "Bob Builder" }, whispered)
    end)

    it("drops data from players blocked by the guild officers or by me, including relayed scans", function()
      bootSync()
      _G.GetGuildInfoText = function()
        return "Be nice.\nAME block: Price Fixer"
      end
      env:fire("GUILD_ROSTER_UPDATE")
      local svc = ns.SyncService
      assert.are.equal("guild", svc.trust:IsBlocked("Price Fixer"))
      -- an announce from the blocked player is ignored: no request goes out
      local entry = peerScan({ [2589] = 1000 })
      local before = #sent
      deliver(ns.Sync.EncodeAnnounce("TestRealm|Horde", { { t = entry.t, src = entry.src } }), "GUILD", "Price Fixer")
      assert.are.equal(before, #sent)
      -- a guild mate relaying a scan made by the blocked player is ignored too
      local relayed = peerScan({ [2589] = 1000 })
      relayed.src = "Price Fixer"
      deliver(
        ns.Sync.EncodeAnnounce("TestRealm|Horde", { { t = relayed.t, src = relayed.src } }),
        "GUILD",
        "Guild Mate"
      )
      assert.are.equal(before, #sent)
      assert.is_true(AME_DB.stats.syncBlocked >= 2)
      -- personal block from the Sync tab's peer list
      deliver(ns.Sync.EncodeHello("TestRealm|Horde"), "WHISPER", "Spam Bot")
      ns.UI:Toggle()
      ns.UI:ShowTab("sync")
      local v = ns.UI.syncView
      v.scripts.OnShow(v)
      local row
      for _, r in ipairs(v.peers) do
        if r.name == "Spam Bot" then
          row = r
        end
      end
      row.block.scripts.OnClick(row.block)
      assert.are.equal("me", svc.trust:IsBlocked("Spam Bot"))
      assert.are.equal(0, #svc.trust:PendingList())
      assert.truthy(v.guildBlocked.text:find("Price Fixer"))
      _G.GetGuildInfoText = nil
    end)

    it("drives trust from the Sync tab and options from the Settings tab", function()
      bootSync()
      deliver(ns.Sync.EncodeHello("TestRealm|Horde"), "WHISPER", "Ada Lovelace")
      ns.UI:Toggle()
      ns.UI:ShowTab("sync")
      local v = ns.UI.syncView
      v.scripts.OnShow(v)
      local req = v.pending[1]
      assert.are.equal("Ada Lovelace", req.name)
      req.approve.scripts.OnClick(req.approve)
      assert.is_true(ns.SyncService.trust.db.trusted["ada lovelace"].mutual)
      assert.are.equal("Ada Lovelace", v.trustedRows[1].name)
      -- add a player by name
      v.input:SetText("Bob Builder")
      v.input.scripts.OnEnterPressed(v.input)
      assert.truthy(v.addStatus.text:find("Asked Bob Builder"))
      assert.are.equal("hello", ns.Sync.Decode(sent[#sent].msg).type)
      -- turning guild sharing off stops guild announcements
      v.guild.scripts.OnClick(v.guild)
      assert.is_false(ns.Settings:Get("syncGuild"))
      -- settings tab
      ns.UI:ShowTab("settings")
      local s = ns.UI.settingsView
      s.scripts.OnShow(s)
      local tooltip = s.checks[1]
      tooltip.scripts.OnClick(tooltip)
      assert.is_false(ns.Settings:Get("tooltip"))
      local altShift = s.click.menu.items[2]
      altShift.scripts.OnClick(altShift)
      assert.are.equal("altshift", ns.Settings:Get("clickModifier"))
      assert.truthy(s.storage.text:find("Market:"))
      env:slash("AZEROTHMERCANTILEEXCHANGE", "config")
      assert.are.equal("settings", ns.UI.current)
    end)

    it("ignores other realms, its own messages and garbage", function()
      bootSync()
      deliver(ns.Sync.EncodeAnnounce("OtherRealm|Horde", { { t = env.now, src = "X" } }), "GUILD", "Guild Mate")
      deliver(ns.Sync.EncodeAnnounce("TestRealm|Horde", { { t = env.now, src = "X" } }), "GUILD", "Tyken")
      deliver("garbage", "GUILD", "Guild Mate")
      assert.are.equal(0, #sent)
    end)
  end)

  it("/ame status works before any scan", function()
    boot()
    env:slash("AZEROTHMERCANTILEEXCHANGE", "status")
    assert.is_true(env:chatContains("no full scan recorded yet"))
  end)
end)
