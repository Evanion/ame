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
    assert.is_true(env:chatContains("imported 1 days of price history from Auctionator"))
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
    assert.is_true(env:chatContains("imported 2 days of price history from Auctionator"))
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

    it("builds the window in idle steps after login, so the first open doesn't stutter", function()
      seeded()
      assert.is_nil(rawget(ns.UI, "frame") or nil) -- not built yet
      for _ = 1, 40 do -- the login timer starts it; each step schedules the next
        env:advance(0.5)
      end
      assert.is_not_nil(ns.UI.frame)
      assert.is_false(ns.UI.frame:IsShown()) -- built hidden
      for _, name in ipairs({ "market", "item", "arbitrage", "portfolio", "settings", "guide" }) do
        assert.is_not_nil(ns.UI.views[name], name)
      end
      drainJobs() -- item facts for the index load in the background
      assert.is_not_nil(rawget(ns.ItemCache.info, 2589))
      ns.UI:Toggle() -- opening is now just showing
      assert.is_true(ns.UI.frame:IsShown())
    end)

    it("logging in during combat: history and the packed tables wait until it's over", function()
      seeded()
      env:fire("PLAYER_LOGOUT")
      local db, combat = AME_DB, true
      boot({
        pre = function()
          _G.AME_DB = db
          _G.InCombatLockdown = function()
            return combat
          end
        end,
      })
      for _ = 1, 100 do
        env:advance(0.1)
      end
      assert.is_false(ns.AME:HistoryLoaded())
      assert.is_true(ns.Packed.Pending("pricing"))
      combat = false
      for _ = 1, 60 do
        env:advance(0.1)
      end
      assert.is_true(ns.AME:HistoryLoaded())
      assert.is_false(ns.Packed.Pending("pricing"))
      _G.InCombatLockdown = nil
    end)

    it("saves the big tables packed at logout, and unpacks them in the background after the next login", function()
      seeded()
      local shard = ns.AME:CurrentShard()
      local variant = ns.ItemKey(2589, 7)
      ns.ItemCache.setName(variant, "Linen Cloth of the Monkey")
      ns.itemStrings[variant] = "item:2589::::::7"
      assert.is_not_nil(AME_DB.pricing[shard][2589])
      local model = AME_DB.pricing[shard][2589]
      env:fire("PLAYER_LOGOUT")
      assert.is_nil(AME_DB.pricing)
      assert.are.equal("string", type(AME_DB.pricingPacked[shard]))
      assert.is_nil(AME_DB.variants)
      assert.truthy(AME_DB.variantsPacked:find("Linen Cloth of the Monkey", 1, true))
      assert.truthy(AME_DB.variantStringsPacked:find("item:2589::::::7", 1, true))

      -- the next login: nothing unpacked during loading, all of it shortly after
      local db = AME_DB
      boot({
        pre = function()
          _G.AME_DB = db
        end,
      })
      assert.is_true(ns.Packed.Pending("pricing"))
      assert.is_true(ns.Packed.Pending("variants"))
      assert.is_nil(ns.ItemCache.variants[variant])
      for _ = 1, 60 do
        env:advance(0.1)
      end
      assert.is_false(ns.Packed.Pending("pricing"))
      assert.is_false(ns.Packed.Pending("variants"))
      assert.are.equal(model, AME_DB.pricing[shard][2589])
      assert.are.equal("Linen Cloth of the Monkey", ns.ItemCache.variants[variant])
      assert.are.equal(variant, ns.ItemCache.KeyByName("Linen Cloth of the Monkey"))
      assert.are.equal("item:2589::::::7", ns.itemStrings[variant])

      -- needed before the background is done: unpacked on the spot
      env:fire("PLAYER_LOGOUT")
      db = AME_DB
      boot({
        pre = function()
          _G.AME_DB = db
        end,
      })
      assert.is_true(ns.Packed.Pending("pricing"))
      assert.truthy(ns.Pricing.Samples(AME_DB.pricingPacked == nil and ns.Posting.Pricing()[shard][2589]) >= 1)
      assert.is_false(ns.Packed.Pending("pricing"))
      assert.are.equal(variant, ns.ItemCache.KeyByName("Linen Cloth of the Monkey"))
    end)

    it("saves market indexes at logout and uses them at the next login, rebuilding only what changed", function()
      seeded()
      local shard = ns.AME:CurrentShard()
      local built = ns.AME:CachedIndex(shard)
      assert.is_not_nil(built)
      env:fire("PLAYER_LOGOUT")
      assert.truthy(AME_DB.indexCache[shard].s:find("|"))

      -- next session, nothing new since: the saved index is used as is, no rebuild
      local AME = ns.AME
      AME.indexes, AME.index, AME.indexShard = {}, nil, nil
      AME:RestoreIndexes()
      drainJobs()
      local restored = AME:CachedIndex(shard)
      assert.are.equal(built.count, restored.count)
      assert.are.equal(built.items[2589].market, restored.items[2589].market)
      assert.is_false(AME:IndexBusy())

      -- saved by an older version (no vendor prices yet): shown, then rebuilt once
      AME:SaveIndexes()
      AME_DB.indexCache[shard].v = nil
      AME.indexes, AME.index, AME.indexShard = {}, nil, nil
      AME:RestoreIndexes()
      for _ = 1, 50 do
        if AME:IndexBusy() then
          break
        end
        env:update(1)
      end
      assert.is_true(AME:IndexBusy())
      drainJobs()
      assert.is_false(AME:IndexBusy())

      -- the history changed since it was saved: shown right away (stale), rebuilt in the background
      AME:SaveIndexes()
      fullScan({ { 2589, 2000, 10 } })
      drainJobs()
      AME.indexes, AME.index, AME.indexShard = {}, nil, nil
      AME:RestoreIndexes()
      local steps = 0
      while not AME:CachedIndex(shard) and steps < 50 do -- the restore job runs first
        env:update(1)
        steps = steps + 1
      end
      assert.is_not_nil(AME:CachedIndex(shard))
      assert.is_true(AME:IndexBusy()) -- the rebuild is under way
      ns.UI:Toggle()
      for _ = 1, 40 do
        env:update(1)
        if not AME:IndexBusy() then
          break
        end
        env:advance(0.6) -- the footer checks twice a second
      end
      drainJobs()
      assert.is_false(AME:IndexBusy())
      assert.are_not.equal(restored, AME:CachedIndex(shard)) -- swapped for the fresh one
    end)

    it("follows the item the auction house searched, and marks your trades on its chart", function()
      seeded()
      ns.AME.ledger:Add({ t = env.now - 86400, kind = "buy", itemID = 2589, name = "Item 2589", qty = 5, amount = 5000 })
      ns.AME.ledger:Add({ t = env.now - 3600, kind = "sale", itemID = 2589, name = "Item 2589", qty = 2, amount = 2400 })
      ns.UI:ShowItem(4306)
      drainJobs()
      -- you pick Linen to sell (any AH window searches it): the Item tab follows
      env:fire("AUCTION_HOUSE_SHOW")
      env.ah.commodities[2589] = { { 117, 20 } } -- a little above its usual ~1s
      env:fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
      env:advance(2)
      drainJobs()
      assert.are.equal(2589, ns.UI.itemID)
      -- the search's listings were recorded after the page loaded: the cards show them, not the older scans
      assert.truthy(ns.UI.itemView.cards[2].value.text:find("17"), ns.UI.itemView.cards[2].value.text) -- 1s 17c
      local trades = ns.UI.chart.series.trades
      assert.are.equal("points", trades.kind)
      assert.are.same({ 1000, 1200 }, trades.ys) -- per unit: 5000 / 5 bought, 2400 / 2 sold
      assert.are.same(ns.UI.TRADE_COLORS.buy, trades.colors[1])
      assert.are.same(ns.UI.TRADE_COLORS.sale, trades.colors[2])
      assert.truthy(ns.UI.itemView.legend.text:find("You bought"))
      -- not on another tab
      ns.UI:ShowTab("market")
      env.ah.commodities[4306] = { { 4000, 5 } }
      env:fire("COMMODITY_SEARCH_RESULTS_UPDATED", 4306)
      env:advance(2)
      drainJobs()
      assert.are.equal("market", ns.UI.current) -- a search while not selling (buying, browsing) leaves the tab alone
      -- putting it up for sale (here in Auctionator's selling tab) switches to the Item tab
      _G.AuctionatorSellingFrame = CreateFrame("Frame")
      finally(function()
        _G.AuctionatorSellingFrame = nil
      end)
      env:fire("COMMODITY_SEARCH_RESULTS_UPDATED", 4306)
      env:advance(2)
      drainJobs()
      assert.are.equal("item", ns.UI.current)
      assert.are.equal(4306, ns.UI.itemID)
      -- unless that's turned off in Settings
      ns.Settings:Set("sellSwitchesTab", false)
      ns.UI:ShowTab("market")
      env:fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
      env:advance(2)
      drainJobs()
      assert.are.equal("market", ns.UI.current)
    end)

    it("follows a name typed into the game's search box, and an item put in its sell slot", function()
      seeded()
      ns.UI:ShowItem(4306)
      drainJobs()
      env:fire("AUCTION_HOUSE_SHOW")
      -- a typed search lists several items: the one named exactly that is followed
      C_AuctionHouse.SendBrowseQuery({ searchString = "  item 2589 ", sorts = {}, filters = {} })
      env.ah.browse = { { 2590, 500, 3 }, { 2589, 120, 40 } }
      env:fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
      env:advance(1)
      drainJobs()
      assert.are.equal(2589, ns.UI.itemID)
      -- a search listing several items, none named that: nothing picked
      ns.UI:ShowItem(4306)
      drainJobs()
      C_AuctionHouse.SendBrowseQuery({ searchString = "item", sorts = {}, filters = {} })
      env:fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
      env:advance(1)
      assert.are.equal(4306, ns.UI.itemID)
      -- one item listed: that one
      C_AuctionHouse.SendBrowseQuery({ searchString = "linen", sorts = {}, filters = {} })
      env.ah.browse = { { 2589, 120, 40 } }
      env:fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
      env:advance(1)
      drainJobs()
      assert.are.equal(2589, ns.UI.itemID)
      env:fire("AUCTION_HOUSE_CLOSED")
      -- the game's sell slot
      local sell = CreateFrame("Frame")
      function sell.SetItem() end
      local ah = CreateFrame("Frame")
      ah.CommoditiesSellFrame = sell
      _G.AuctionHouseFrame = ah
      local getItemID = C_Item.GetItemID
      rawset(C_Item, "GetItemID", function(location)
        return location.id
      end)
      finally(function()
        _G.AuctionHouseFrame = nil
        rawset(C_Item, "GetItemID", getItemID)
      end)
      env:fire("AUCTION_HOUSE_SHOW")
      sell:SetItem({ id = 4306 })
      env:advance(1)
      drainJobs()
      assert.are.equal(4306, ns.UI.itemID)
    end)

    it(
      "/amedev lag: measures each fight per addon with the game's addon profiler, and says who held frames up",
      function()
        seeded()
        local names = { "AzerothMercantileExchange", "SlowAddon", "QuickAddon" }
        local cost = { AzerothMercantileExchange = 0.2, SlowAddon = 6, QuickAddon = 0.5 } -- ms a frame
        local over5 = { SlowAddon = 0 }
        rawset(C_AddOns, "GetNumAddOns", function()
          return #names
        end)
        local info = C_AddOns.GetAddOnInfo
        rawset(C_AddOns, "GetAddOnInfo", function(i)
          if type(i) == "number" then
            return names[i]
          end
          return info(i)
        end)
        rawset(C_AddOns, "IsAddOnLoaded", function()
          return true
        end)
        rawset(Enum, "AddOnProfilerMetric", { LastTime = 1, CountTimeOver5Ms = 2, CountTimeOver50Ms = 3 })
        _G.C_AddOnProfiler = {
          IsEnabled = function()
            return true
          end,
          GetAddOnMetric = function(name, m)
            if m == 1 then
              over5[name] = (over5[name] or 0) + ((cost[name] or 0) > 5 and 1 or 0)
              return cost[name]
            end
            return m == 2 and over5[name] or 0
          end,
        }
        finally(function()
          _G.C_AddOnProfiler = nil
        end)
        env:slash("AMEDEV", "lag")
        assert.is_true(AME_DB.dev.lag.armed)
        env:fire("PLAYER_REGEN_DISABLED")
        env:update(60)
        env:fire("PLAYER_REGEN_ENABLED")
        local report = AME_DB.dev.lag.reports[1]
        assert.are.equal("fight", report.label)
        assert.are.equal(60, report.frames)
        assert.are.equal("SlowAddon", report.top[1].name)
        assert.are.equal(360, report.top[1].ms)
        assert.are.equal(60, report.top[1].over5)
        -- a fight too short to say anything: no report
        env:fire("PLAYER_REGEN_DISABLED")
        env:update(3)
        env:fire("PLAYER_REGEN_ENABLED")
        assert.are.equal(1, #AME_DB.dev.lag.reports)
        -- disarmed: fights aren't measured
        env:slash("AMEDEV", "lag")
        env:fire("PLAYER_REGEN_DISABLED")
        env:update(60)
        env:fire("PLAYER_REGEN_ENABLED")
        assert.are.equal(1, #AME_DB.dev.lag.reports)
      end
    )

    it("/amedev send: a tester whispers their profiler report; /amedev receive keeps it", function()
      seeded()
      env:slash("AMEDEV", "hud")
      env:update(70)
      local sent = {}
      _G.C_ChatInfo = {
        RegisterAddonMessagePrefix = function() end,
        SendAddonMessage = function(prefix, msg, channel, target)
          sent[#sent + 1] = { prefix = prefix, msg = msg, channel = channel, target = target }
        end,
      }
      finally(function()
        _G.C_ChatInfo = nil
      end)
      env:slash("AMEDEV", "send Developer")
      for _ = 1, 600 do
        env:advance(1.1)
      end
      assert.is_true(#sent >= 1)
      assert.are.equal("Developer", sent[1].target)
      for _, m in ipairs(sent) do
        assert.is_true(#m.msg <= 255)
      end
      -- not taking reports: ignored
      env:fire("CHAT_MSG_ADDON", sent[1].prefix, sent[1].msg, "WHISPER", "Tester")
      assert.is_nil(AME_DB.dev.received)
      env:slash("AMEDEV", "receive")
      for i = #sent, 1, -1 do -- in any order
        env:fire("CHAT_MSG_ADDON", sent[i].prefix, sent[i].msg, "WHISPER", "Tester")
      end
      local got = AME_DB.dev.received.Tester.report
      assert.are.equal(ns.VERSION, got.ame)
      assert.is_true(#got.minutes >= 1)
      assert.is_table(got.jobs)
    end)

    it("/amedev hud: a box on screen with what AME is doing", function()
      seeded()
      env:slash("AMEDEV", "hud")
      assert.is_true(AME_DB.dev.hud.on)
      ns.AME.jobs:Add("index-test", function()
        for _ = 1, 3 do
          coroutine.yield()
        end
      end)
      local text = table.concat(ns.Dev.Hud.Lines({}), "\n")
      assert.truthy(text:find("jobs: index-test", 1, true), text)
      assert.truthy(text:find("Lua memory", 1, true), text)
      -- sync kept / turned down, since the box came on
      local state = {}
      ns.Dev.Hud.Lines(state)
      ns.SyncService.stats.syncReceived = (ns.SyncService.stats.syncReceived or 0) + 2
      ns.SyncService.stats.syncRejected = (ns.SyncService.stats.syncRejected or 0) + 1
      ns.SyncService:CountRejection("undecodable")
      text = table.concat(ns.Dev.Hud.Lines(state), "\n")
      assert.truthy(text:find("accepted |cff66dd772|r", 1, true), text)
      assert.truthy(text:find("1|r (undecodable 1)", 1, true), text)
      env:update(70) -- a little over a second of frames: one line logged
      assert.is_true(#AME_DB.dev.hudLog.seconds >= 1)
      env:slash("AMEDEV", "hud")
      assert.is_false(AME_DB.dev.hud.on)
    end)

    it("background work waits out combat, unless AME's window is open (then on a smaller budget)", function()
      seeded()
      local fighting = true
      _G.InCombatLockdown = function()
        return fighting
      end
      finally(function()
        _G.InCombatLockdown = nil
      end)
      local ran = 0
      ns.AME.jobs:Add("test", function()
        ran = ran + 1
      end)
      env:update(5)
      assert.are.equal(0, ran)
      ns.UI:Toggle() -- the window open: you asked for something
      env:update(1)
      assert.are.equal(1, ran)
      assert.are.equal(ns.AME.COMBAT_JOB_BUDGET, ns.AME.jobs.budgetMs)
      fighting = false
      ns.AME.jobs:Add("test", function()
        ran = ran + 1
      end)
      env:update(1)
      assert.are.equal(2, ran)
      assert.are.equal(ns.AME.JOB_BUDGET, ns.AME.jobs.budgetMs)
    end)

    it("can open AME together with the auction house, and close it with it", function()
      seeded()
      env:fire("AUCTION_HOUSE_CLOSED")
      env:fire("AUCTION_HOUSE_SHOW") -- off by default
      assert.is_true(not ns.UI.frame or not ns.UI.frame:IsShown())
      env:fire("AUCTION_HOUSE_CLOSED")
      ns.Settings:Set("openWithAH", true)
      env:fire("AUCTION_HOUSE_SHOW")
      assert.is_true(ns.UI.frame:IsShown())
      env:fire("AUCTION_HOUSE_CLOSED")
      assert.is_true(ns.UI.frame:IsShown()) -- stays open unless closing is chosen too
      ns.UI.frame:Hide()
      ns.Settings:Set("closeWithAH", true)
      env:fire("AUCTION_HOUSE_SHOW")
      assert.is_true(ns.UI.frame:IsShown())
      env:fire("AUCTION_HOUSE_CLOSED")
      assert.is_false(ns.UI.frame:IsShown())
      -- opened by hand: stays open when the AH closes
      ns.UI:Toggle()
      env:fire("AUCTION_HOUSE_SHOW")
      env:fire("AUCTION_HOUSE_CLOSED")
      assert.is_true(ns.UI.frame:IsShown())
    end)

    describe("window", function()
      local function last(frame)
        return frame.points[#frame.points]
      end

      it("starts at a size that fits the screen, centred", function()
        boot()
        ns.UI:Toggle()
        local win = ns.UI.frame
        assert.are.same({ 900, 576 }, { win:GetSize() }) -- 1365x768: 60% wide (min 900), 75% high
        assert.are.equal("CENTER", last(win)[1])
        assert.is_false(ns.UI.compact)
        local screen = _G.UIParent
        screen.w, screen.h = 2560, 1440 -- a big screen: the full 1100x640
        ns.UI:ApplyPlacement()
        assert.are.same({ 1100, 640 }, { win:GetSize() })
        ns.Settings:Set("windowScale", 0.8)
        ns.UI:ApplyPlacement()
        assert.are.equal(0.8, win:GetScale())
      end)

      it("keeps the size you resize to, and a position with and without the auction house, across sessions", function()
        boot()
        ns.UI:Toggle()
        local win = ns.UI.frame
        win.GetLeft = function()
          return 40
        end
        win.GetTop = function()
          return 700
        end
        -- resize with the grip: saved while dragging, and on release
        ns.UI.grip.scripts.OnMouseDown(ns.UI.grip)
        win:SetSize(1000, 600)
        win.scripts.OnSizeChanged(win, 1000, 600)
        assert.are.equal(1000, ns.UI:Placements().w)
        ns.UI.grip.scripts.OnMouseUp(ns.UI.grip)
        win.scripts.OnDragStop(win) -- moved without the auction house
        env:fire("AUCTION_HOUSE_SHOW")
        env:advance(0)
        assert.are.same({ 1000, 600 }, { win:GetSize() }) -- one size, with or without the auction house
        win.GetLeft = function()
          return 300
        end
        win.scripts.OnDragStop(win) -- moved with it open (no AH frame on screen: nothing to dock to)
        local p = ns.UI:Placements()
        assert.are.same({ x = 40, y = 700 }, p.free)
        assert.are.same({ x = 300, y = 700 }, p.ah)
        assert.are.same({ 1000, 600 }, { p.w, p.h })
        env:fire("AUCTION_HOUSE_CLOSED") -- back to the free position
        assert.are.same({ "TOPLEFT", UIParent, "BOTTOMLEFT", 40, 700 }, last(win))
        -- next session: the saved variables bring it back
        local saved = AME_DB
        env:restore()
        boot({
          pre = function()
            _G.AME_DB = saved
          end,
        })
        ns.UI:Toggle()
        assert.are.same({ 1000, 600 }, { ns.UI.frame:GetSize() })
        assert.are.same({ "TOPLEFT", UIParent, "BOTTOMLEFT", 40, 700 }, last(ns.UI.frame))
        -- narrow and never below the minimum
        win = ns.UI.frame
        win:SetSize(800, 500)
        ns.UI:SavePlacement()
        ns.UI:ApplyPlacement()
        assert.is_true(ns.UI.compact) -- below 900 wide
        assert.is_truthy(ns.UI.title:GetText():find("AME|r$"))
        win:SetSize(500, 300)
        ns.UI:SavePlacement()
        ns.UI:ApplyPlacement()
        assert.are.same({ ns.UI.MIN_W, ns.UI.MIN_H }, { win:GetSize() })
        -- an oversized saved size (the old resize jump) is capped to the screen at AME's scale
        p = ns.UI:Placements()
        p.w, p.h = 99999, 99999
        ns.UI:ApplyPlacement()
        assert.are.same({ 1365, 768 }, { win:GetSize() })
        -- grabbing the corner first anchors the window by its top-left corner (no jump from a centre or dock anchor)
        win:ClearAllPoints()
        win:SetPoint("CENTER")
        ns.UI.grip.scripts.OnMouseDown(ns.UI.grip)
        assert.are.equal("TOPLEFT", last(win)[1])
        ns.UI.grip.scripts.OnMouseUp(ns.UI.grip)
      end)

      it("moves a size saved per position by the previous version over", function()
        boot({
          pre = function()
            _G.AME_DB = { window = { ["Tyken-?"] = { free = { x = 1, y = 2, w = 950, h = 580 } } } }
          end,
        })
        ns.UI:Toggle()
        assert.are.same({ 950, 580 }, { ns.UI.frame:GetSize() })
      end)

      it("docks beside the auction house window when there's room", function()
        boot()
        local ah = wow.newObject("Frame")
        ah.GetRight = function()
          return 400
        end
        _G.AuctionHouseFrame = ah
        ns.UI:Toggle()
        local win = ns.UI.frame
        env:fire("AUCTION_HOUSE_SHOW")
        env:advance(0)
        assert.are.same({ "TOPLEFT", ah, "TOPRIGHT", 6, 0 }, last(win)) -- 400 + 6 + 900 fits in 1365
        ah.GetRight = function()
          return 700
        end
        ns.UI:ApplyPlacement()
        assert.are.equal("CENTER", last(win)[1]) -- no room: its own place
        ah.GetRight = function()
          return 400
        end
        ns.Settings:Set("dockToAH", false)
        ns.UI:ApplyPlacement()
        assert.are.equal("CENTER", last(win)[1]) -- docking off
        _G.AuctionHouseFrame = nil
      end)

      it("tables show as many rows as fit and drop low-priority columns when narrow", function()
        seeded()
        ns.UI:Toggle()
        ns.UI:ShowTab("market")
        local t = ns.UI.marketView.table
        -- the table grew while no size event reached it (hidden behind another tab, window closed): the next draw
        -- notices and fits
        t.frame:SetHeight(20 + 30 * t.rowH)
        t:Render()
        assert.are.equal(30, t.visible)
        assert.is_true(#t.rows >= 30)
        t.frame:SetHeight(20 + 5 * t.rowH)
        t.frame.scripts.OnShow(t.frame)
        assert.are.equal(5, t.visible)
        assert.is_false(t.rows[6]:IsShown())
        -- a portfolio table that was hidden while the window opened fills its space when its mode is picked
        ns.UI:ShowTab("portfolio")
        local pv = ns.UI.pfView
        pv.ledger.frame:SetHeight(20 + 20 * pv.ledger.rowH)
        pv.ledgerButton.scripts.OnClick(pv.ledgerButton)
        assert.are.equal(20, pv.ledger.visible)
        t:SetUserHidden({}) -- every column on
        t:Layout(2000)
        assert.are.same({}, t.hiddenColumns)
        t:Layout(560)
        local keys = {}
        for c in pairs(t.hiddenColumns) do
          keys[#keys + 1] = t.opts.columns[c].key
        end
        assert.is_true(#keys > 0)
        assert.is_true(t.hiddenColumns[1] == nil) -- the item column stays
        for c in pairs(t.hiddenColumns) do
          assert.is_not_nil(t.opts.columns[c].drop) -- only droppable ones go
        end
      end)

      it("lays the item page out as chart + sidebar, and a summary + Details panel when narrow", function()
        seeded()
        ns.UI:ShowItem(2589)
        drainJobs()
        local v = ns.UI.itemView
        assert.is_true(v.sidebar:IsShown())
        assert.is_false(v.summaryBar:IsShown())
        assert.are.same({ "BOTTOMRIGHT", -(ns.UI.ITEM_SIDEBAR + ns.UI.SLOT_GAP), 0 }, v.slots.main.points[2])
        -- the call, with why in plain words, in the first card; every card sizes itself to its contents
        assert.truthy(v.call.text:find("HOLD") or v.call.text:find("BUY") or v.call.text:find("SELL"), v.call.text)
        assert.truthy(v.callWhy.text:find("day average", 1, true), v.callWhy.text)
        assert.truthy(v.callWhy.text:find("scans"))
        for _, it in ipairs(v.column.items) do
          assert.is_true(it[1]:GetHeight() > 20)
        end
        local _, head, why = ns.UI.Verdict({ days = 3, scans7 = 1, market = 100, avg30 = 100 }, { signal = "none" })
        assert.are.equal("No call yet", head)
        assert.truthy(table.concat(why, " "):find("Needs 7 days of history (has 3)", 1, true))
        local sig, head2 = ns.UI.Verdict(
          { days = 20, scans7 = 10, day = 5, market = 300, avg30 = 400, phase = "dumping", sellRate = 50 },
          { signal = "wait", today = 5 }
        )
        assert.are.equal("wait", sig)
        assert.are.equal("Cheap, but still falling", head2)
        -- legend: one line per series, faded while hovering the plot
        assert.truthy(v.legend.text:find("Market"))
        assert.truthy(v.legend.text:find("\n"))
        ns.UI.chart.frame.scripts.OnEnter(ns.UI.chart.frame) -- faded, still there to click
        assert.is_true(v.legendBox:IsShown())
        assert.is_true(v.legendBox:GetAlpha() < 1)
        ns.UI.chart.frame.scripts.OnLeave(ns.UI.chart.frame)
        assert.is_true(v.legendBox:IsShown())
        -- narrow window
        ns.UI.frame:SetSize(800, 500)
        ns.UI:OnResize(800)
        assert.is_false(v.sidebar:IsShown())
        assert.is_true(v.summaryBar:IsShown())
        assert.truthy(v.summary.text:find("Market"))
        assert.truthy(v.summary.text:find("Post at"))
        assert.are.same({ "BOTTOMRIGHT", 0, 0 }, v.slots.main.points[2]) -- the chart takes the width
        local hp = ns.UI.chartHolder.points
        assert.are.same({ "BOTTOMRIGHT", 0, ns.UI.ITEM_SUMMARY_H + 6 }, hp[#hp]) -- above the summary bar
        -- the legend folds into a button on the small chart
        assert.is_true(v.legendToggle:IsShown())
        assert.is_false(v.legendBox:IsShown())
        v.legendToggle.scripts.OnClick(v.legendToggle)
        assert.is_true(v.legendBox:IsShown())
        v.details.scripts.OnClick(v.details)
        assert.is_true(v.sidebar:IsShown()) -- over the chart
        v.details.scripts.OnClick(v.details)
        assert.is_false(v.sidebar:IsShown())
        ns.UI:OnResize(1000)
        assert.is_true(v.sidebar:IsShown())
        assert.is_false(v.summaryBar:IsShown())
      end)

      it("the Crafting tab: hidden until switched on, earners and sell-or-refine from recorded professions", function()
        seeded()
        ns.UI:Toggle()
        local tab = ns.UI.tabBar.byKey.crafting
        assert.is_false(tab:IsShown()) -- off by default
        ns.UI:ShowTab("crafting")
        assert.are.equal("market", ns.UI.current) -- a hidden tab can't be opened
        -- switched on, with one character's First Aid recorded: Linen Bandage (1 Linen Cloth -> 1 bandage)
        _G.AME_CraftingData = nil
        dofile("AzerothMercantileExchange_Crafting/Recipes.lua") -- the data addon, as LoadAddOn would run it
        ns.CraftingData.data = nil
        local key = ns.Trading.CharKey()
        AME_DB.crafting = {
          catalog = {
            [129] = {
              at = 0,
              name = "First Aid",
              recipes = { [3275] = { out = 1251, min = 1, max = 1, r = { { 2589, 1 } } } },
            },
          },
          chars = {
            [key] = {
              professions = {
                [129] = { name = "First Aid", skill = 40, max = 75, at = 0, learned = { [3275] = true } },
              },
            },
          },
        }
        AME_DB.holdings[key] = { bags = { [2589] = 20 }, bank = {} }
        ns.Settings:Set("crafting", true)
        ns.UI:CraftingChanged(true)
        assert.is_true(tab:IsShown())
        ns.UI:ShowTab("crafting")
        local v = ns.UI.craftView
        v.scripts.OnShow(v)
        local rows = ns.UI.craftRows
        assert.are.equal(1, #rows)
        assert.are.equal(1251, rows[1].itemID)
        assert.are.equal("unpriced", rows[1].eval.why) -- the bandage has no price in this market
        ns.UI.craftSelected = rows[1]
        ns.UI:RenderCraftingDetail()
        assert.truthy(v.note.text:find("Missing a price"), v.note.text)
        -- the sidebar's button says what it does (its label is AME's own font string)
        assert.are.equal("Add reagents to a shopping list", v.action.label.text)
        -- sell or refine: the linen sells raw (the bandage has no price)
        v.modes:Select("refine")
        rows = ns.UI.craftRows
        assert.are.equal(1, #rows)
        assert.are.equal(2589, rows[1].itemID)
        assert.are.equal(20, rows[1].qty)
        assert.is_nil(rows[1].best)
        assert.truthy(rows[1].raw > 0)
        -- recipes to buy: none listed in this market
        v.modes:Select("recipes")
        assert.are.equal(0, #ns.UI.craftRows)
        -- leveling: First Aid from 40 to 75 on linen (the only reagent with a price here)
        ns.UI.levelTarget = 75
        v.modes:Select("leveling")
        assert.is_true(v.levelProf:IsShown())
        assert.is_false(v.char:IsShown())
        local lv = ns.UI.leveling
        assert.are.equal(129, lv.choice.profession)
        local plan = lv.plans.recovery
        assert.is_true(plan.complete, tostring(plan.stuck))
        assert.are.equal(40, plan.steps[1].from)
        assert.truthy(plan.cost > 0)
        local step
        for _, r in ipairs(ns.UI.craftRows) do
          step = step or (not r.note and r)
        end
        assert.truthy(v.levelCards.cards[1].value.text:find("-"), v.levelCards.cards[1].value.text) -- a cost, in red
        -- no step picked: no button; a step picked: the whole path's reagents to a shopping list
        ns.UI.craftSelected = nil
        ns.UI:RenderCraftingDetail()
        assert.is_false(v.action:IsShown())
        ns.UI.craftSelected = step
        ns.UI:RenderCraftingDetail()
        assert.is_true(v.colorBar:IsShown())
        assert.is_true(v.action:IsShown())
        assert.are.equal("Add all reagents to a shopping list", v.action.label.text)
        -- a craft re-records the profession and rebuilds the rows: the same step stays selected
        ns.UI:RefreshCrafting()
        assert.is_not_nil(ns.UI.craftSelected)
        assert.are_not.equal(step, ns.UI.craftSelected) -- a new row...
        assert.are.equal(ns.UI.CraftRowKey(step), ns.UI.CraftRowKey(ns.UI.craftSelected)) -- ...for the same step
        local texts = {}
        for _, line in ipairs(v.lines) do
          texts[#texts + 1] = line.label.text or ""
        end
        assert.truthy(table.concat(texts, "|"):find("Skill%-up chance"))
        -- the reagent line is the item: clicking it searches the AH (or opens its chart)
        local linenLine
        for _, line in ipairs(v.lines) do
          linenLine = linenLine or (line.itemID == 2589 and line)
        end
        assert.is_not_nil(linenLine)
        assert.are.equal(step.entry.recipe.product, v.titleHit.itemID) -- the title is the product
        -- a learn / train note selected: its text in the sidebar (built when shown)
        local noteRow
        for _, r in ipairs(ns.UI.craftRows) do
          noteRow = noteRow or (r.note and type(r.text) == "function" and r)
        end
        assert.is_not_nil(noteRow)
        ns.UI.craftSelected = noteRow
        ns.UI:RenderCraftingDetail()
        assert.are.equal(noteRow.text(), v.subtitle.text)
        assert.is_nil(rawget(v.titleHit, "itemID")) -- a note is about no item
        -- the whole path's reagents on one shopping list
        ns.UI:CraftingAction()
        local list = ns.AME.shopping:Lists()[#ns.AME.shopping:Lists()]
        assert.are.equal("First Aid to 75", list.name)
        assert.truthy(list.items[2589].need > 0)
        -- switched off again: back to the Market tab, the tab gone
        ns.Settings:Set("crafting", false)
        ns.UI:CraftingChanged(false)
        assert.are.equal("market", ns.UI.current)
        assert.is_false(tab:IsShown())
        _G.AME_CraftingData = nil
      end)

      it("Crafting without its data addon: no tab, no setting, no guide page - even switched on", function()
        seeded()
        _G.AME_CraftingData = nil
        ns.CraftingData.data = nil
        ns.Settings:Set("crafting", true)
        ns.UI:Toggle()
        ns.UI:LayoutTabs()
        local tab
        for _, b in ipairs(ns.UI.tabBar.buttons) do
          if b.key == "crafting" then
            tab = b
          end
        end
        assert.is_false(ns.CraftingData:Installed())
        assert.is_false(tab:IsShown())
        ns.UI:ShowTab("crafting")
        assert.are.equal("market", ns.UI.current)
        ns.UI:ShowTab("settings")
        assert.is_nil(rawget(ns.UI.settingsView, "craftingCheck"))
        for _, g in ipairs(ns.Help.Articles()) do
          for _, article in ipairs(g[2]) do
            assert.are_not.equal("crafting", article.key)
          end
        end
        ns.Settings:Set("crafting", false)
      end)

      it("Crafting with its data addon installed but not loaded yet (load on demand): offered in Settings", function()
        -- the client says a load-on-demand addon that isn't loaded "isn't loadable", reason DEMAND_LOADED
        boot({
          pre = function()
            env.addons = { AzerothMercantileExchange_Crafting = "DEMAND_LOADED" }
          end,
        })
        _G.AME_CraftingData = nil
        ns.CraftingData.data = nil
        assert.is_true(ns.CraftingData:Installed())
        ns.UI:Toggle()
        ns.UI:ShowTab("settings")
        assert.is_not_nil(rawget(ns.UI.settingsView, "craftingCheck"))
        -- switched off in the addon list: not offered
        env.addons.AzerothMercantileExchange_Crafting = "DISABLED"
        assert.is_false(ns.CraftingData:Installed())
        env.addons = nil
      end)

      it("the Market tab's Overview: market statistics, categories into the screener, remembered", function()
        seeded()
        ns.UI:Toggle()
        ns.UI:ShowTab("market")
        -- off by default: no Screener | Overview switch, no statistics in the index
        local mv = ns.UI.marketView
        assert.is_false(mv.mode:IsShown())
        assert.is_nil(ns.AME.index.stats)
        ns.Settings:Set("marketMode", "overview") -- a mode remembered from before doesn't bring it back
        assert.are.equal("screener", ns.UI:MarketMode())
        -- switched on in Settings: the switch appears and the index is rebuilt with statistics
        ns.Settings:Set("marketOverview", true)
        ns.UI:MarketOverviewChanged(true)
        drainJobs()
        assert.is_true(mv.mode:IsShown())
        assert.is_table(ns.AME.index.stats)
        ns.UI:SetMarketMode("overview")
        drainJobs()
        local ov = ns.UI.overviewView
        assert.is_true(ov:IsShown())
        assert.is_false(ns.UI.marketView:IsShown())
        assert.are.equal("overview", ns.Settings:Get("marketMode"))
        assert.truthy(ns.UI.footerLeft.text:find("totals from the full scan of"), ns.UI.footerLeft.text)
        assert.are.equal("100.0", ov.cards[1].value.text) -- too few steady items to move it yet
        assert.truthy(ov.cards[3].value.text:find("%d"), ov.cards[3].value.text) -- listed value
        assert.truthy(ov.cards[5].value.text:find("^2"), ov.cards[5].value.text) -- 2 auctions at the last scan
        -- the period changes the cards' comparison
        ov.period:Select(1)
        assert.are.equal(1, ns.UI.ovPeriod)
        -- a category opens the screener filtered to it
        local row = ov.sectorRows[1]
        assert.is_true(row:IsShown())
        local classID = row.data.classID
        row.scripts.OnClick(row)
        assert.are.equal("screener", ns.Settings:Get("marketMode"))
        assert.is_true(ns.UI.marketView:IsShown())
        assert.is_false(ov:IsShown())
        assert.are.equal(classID, ns.UI.mq.classID)
        -- the statistics are saved with the index at logout
        ns.AME:SaveIndexes()
        local _, saved = next(AME_DB.indexCache)
        assert.is_table(saved.st)
        assert.is_table(saved.st.days)
        -- switched off again: back to the screener, statistics dropped
        ns.UI:SetMarketMode("overview")
        ns.Settings:Set("marketOverview", false)
        ns.UI:MarketOverviewChanged(false)
        assert.is_true(ns.UI.marketView:IsShown())
        assert.is_false(mv.mode:IsShown())
        assert.is_nil(ns.AME.index.stats)
      end)

      it("the Overview names its items once they load, even with no load callback or item data event", function()
        seeded()
        local getInfo = C_Item.GetItemInfo
        local known = false
        _G.C_Item.GetItemInfo = function(id)
          if not known then
            return nil
          end
          return getInfo(id)
        end
        -- an item load callback that never comes (the client only fires the event)
        _G.Item = {
          CreateFromItemID = function()
            return {
              IsItemEmpty = function()
                return false
              end,
              ContinueOnItemLoad = function() end,
            }
          end,
        }
        ns.Settings:Set("marketOverview", true)
        ns.UI:MarketOverviewChanged(true)
        ns.UI:Toggle()
        ns.UI:ShowTab("market")
        drainJobs()
        ns.UI:SetMarketMode("overview")
        drainJobs()
        local row = ns.UI.overviewView.largestRows[1]
        assert.is_true(row:IsShown())
        local id = row.data.id
        assert.truthy(row.cells[1].text:find("item:" .. id, 1, true), row.cells[1].text)
        known = true -- the client has it now, and says nothing
        env:advance(1)
        assert.truthy(row.cells[1].text:find("Item " .. id, 1, true), row.cells[1].text)
        -- one that takes longer than a minute: the next hover over it picks the name up
        known = false
        ns.UI:RenderOverview()
        assert.truthy(row.cells[1].text:find("item:" .. id, 1, true), row.cells[1].text)
        env:advance(61)
        known = true
        env:advance(1)
        assert.truthy(row.cells[1].text:find("item:" .. id, 1, true), "stopped looking after a minute")
        row.scripts.OnEnter(row)
        env:advance(1)
        assert.truthy(row.cells[1].text:find("Item " .. id, 1, true), row.cells[1].text)
        _G.C_Item.GetItemInfo, _G.Item = getInfo, nil
        ns.Settings:Set("marketOverview", false)
        ns.UI:MarketOverviewChanged(false)
      end)

      it("the footer is the window's: each tab's status text on the left, version on the right", function()
        seeded()
        ns.UI:Toggle()
        -- tabs end above the footer, so no sidebar reaches it
        local area = ns.UI.views.market
        assert.are.same({ "BOTTOMRIGHT", -10, 10 + ns.UI.FOOTER_H }, area.points[#area.points])
        ns.UI:ShowTab("market")
        ns.UI:RefreshMarket(true)
        -- where the data comes from in the footer; the table's own counts under the table
        assert.truthy(ns.UI.footerLeft.text:find("market data from"), ns.UI.footerLeft.text)
        assert.truthy(ns.UI.marketView.counts.text:find("2 items"))
        ns.UI:ShowTab("arbitrage")
        local arb = ns.UI.arbView
        arb.scripts.OnShow(arb)
        drainJobs()
        assert.are.equal(arb.status.text, ns.UI.footerLeft.text) -- the tab's text, shown by the window
        assert.is_not_nil(arb.counts)
        ns.UI:ShowTab("settings")
        assert.truthy(ns.UI.footerLeft.text:find("saved per account"))
        -- sharing is a section of Settings: the old Sync tab opens it
        assert.is_nil(ns.UI.views.sync)
        ns.UI:ShowTab("sync")
        assert.are.equal("settings", ns.UI.current)
        assert.are.equal("sharing", ns.UI.settingsView.current)
        assert.is_true(ns.UI.settingsView.sections.sharing.frame:IsShown())
        assert.is_false(ns.UI.settingsView.sections.general.frame:IsShown())
        ns.UI:ShowSettingsSection("data")
        assert.truthy(ns.UI.footerLeft.text:find("saved per account"))
        assert.truthy(ns.UI.footer.text:find(ns.VERSION, 1, true))
      end)

      it("scroll panes measure their content and scroll only as far as it goes", function()
        boot()
        local parent = CreateFrame("Frame")
        local pane = ns.Widgets.ScrollPane(parent)
        pane:SetSize(300, 200)
        local child = CreateFrame("Frame", nil, pane.content)
        child.GetBottom = function()
          return -488 -- content top is at 1 in the stub: 489 tall + 12 margin
        end
        pane.content.GetChildren = function()
          return child
        end
        pane:Measure()
        assert.are.equal(501, pane.content:GetHeight())
        assert.are.equal(301, pane:Range())
        pane.scripts.OnMouseWheel(pane, -1)
        assert.are.equal(40, pane:GetVerticalScroll())
        pane:SetScroll(9999)
        assert.are.equal(301, pane:GetVerticalScroll())
        child:Hide()
        pane:Measure() -- nothing shown below the top: no scrolling
        assert.are.equal(0, pane:GetVerticalScroll())
      end)
    end)

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
      -- category sidebar: All items, watchlists, "+ New list", shopping lists, then classes; clicking a class
      -- filters to it
      local classLine
      for _, line in ipairs(v.side.lines) do
        if not classLine and line.entry and line.entry.classID then
          classLine = line
        end
      end
      assert.are.equal(7, classLine.entry.classID)
      classLine.scripts.OnClick(classLine)
      assert.are.equal(2, #ns.UI.list)
      -- sorting by the Item header keeps the category's items (it used to filter everything out)
      local itemHeader = v.headers[1]
      itemHeader.scripts.OnClick(itemHeader)
      assert.are.equal(2, #ns.UI.list)
      assert.are.equal("__name", ns.UI.mq.sortKey)
      itemHeader.scripts.OnClick(itemHeader) -- and back the other way
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

    it("shopping lists: a goal in the sidebar shows what's still to buy and what it costs", function()
      seeded()
      ns.UI:Toggle()
      ns.UI:ShowTab("market")
      local v = ns.UI.marketView
      local shop = ns.AME.shopping
      local i = shop:AddList("Linen Robe")
      shop:SetItem(i, 2589, 12) -- Linen Cloth
      shop:SetItem(i, 4306, 2) -- Silk Cloth
      AME_DB.holdings["TestRealm:Altchar"] = { bags = { [2589] = 5, [4306] = 2 } }
      local entry
      for _, e in ipairs(ns.UI:CategoryEntries()) do
        if e.shop == i then
          entry = e
        end
      end
      assert.are.equal(1, entry.count) -- one item still short
      ns.UI:SelectCategory(entry)
      assert.is_true(v.shop:IsShown())
      assert.is_false(v.table.frame:IsShown())
      assert.is_false(v.search:IsShown())
      local rows = ns.UI.shopRows
      assert.are.equal(2589, rows[1].itemID)
      assert.are.equal(7, rows[1].missing)
      assert.are.equal(0, rows[2].missing)
      assert.truthy(v.status:GetText():find("1 of 2 items still to buy", 1, true), v.status:GetText())
      -- the item menu adds to a list; a list row's menu edits it
      local row = v.shop.table.rows[1]
      row.scripts.OnClick(row, "RightButton")
      local labels = {}
      for _, it in ipairs(ns.Widgets.menu.items) do
        if it:IsShown() then
          labels[#labels + 1] = it.text.text
        end
      end
      local all = table.concat(labels, "|")
      assert.truthy(all:find("Add to shopping list...", 1, true), all)
      assert.truthy(all:find("Set quantity...", 1, true), all)
      -- covered: done
      AME_DB.holdings["TestRealm:Altchar"].bags[2589] = 12
      ns.UI:RenderMarket()
      assert.truthy(v.status:GetText():find("covered", 1, true), v.status:GetText())
      -- back to all items: the screener returns
      ns.UI:SelectCategory({ all = true })
      assert.is_false(v.shop:IsShown())
      assert.is_true(v.table.frame:IsShown())
      assert.is_true(v.search:IsShown())
    end)

    it("right-click menu on a row: hide an item, find it under Hidden, unhide it", function()
      seeded()
      ns.UI:Toggle()
      ns.UI:ShowTab("market")
      local v = ns.UI.marketView
      local before = #ns.UI.list
      local row = v.table.rows[1]
      local key = row.itemID
      row.scripts.OnClick(row, "RightButton")
      local function pick(label)
        for _, it in ipairs(ns.Widgets.menu.items) do
          if it:IsShown() and (it.text.text or "") == label then
            it.scripts.OnClick(it)
            return true
          end
        end
        error("no menu entry " .. label)
      end
      assert.are_not.equal("item", ns.UI.current) -- right-click opens the menu, not the chart
      pick("Hide from lists")
      assert.is_true(ns.AME.watch:IsHidden(key))
      assert.are.equal(before - 1, #ns.UI.list)
      for _, s in ipairs(ns.UI.list) do
        assert.are_not.equal(key, s.itemID)
      end
      -- the sidebar's Hidden list shows it, with Unhide in its menu
      local hiddenEntry
      for _, e in ipairs(ns.UI:CategoryEntries()) do
        if e.hidden then
          hiddenEntry = e
        end
      end
      assert.are.equal(1, hiddenEntry.count)
      ns.UI:SelectCategory(hiddenEntry)
      assert.are.equal(1, #ns.UI.list)
      assert.are.equal(key, ns.UI.list[1].itemID)
      row = v.table.rows[1]
      row.scripts.OnClick(row, "RightButton")
      pick("Unhide")
      assert.is_false(ns.AME.watch:IsHidden(key))
      assert.is_nil(ns.UI.mq.list) -- nothing hidden any more: back to all items
      assert.are.equal(before, #ns.UI.list)
    end)

    it("screener: chips for active filters, saved views, a column chooser, stale rows and signal reasons", function()
      seeded()
      ns.UI:Toggle()
      ns.UI:ShowTab("market")
      local v = ns.UI.marketView
      local t = v.table
      -- default columns: optional ones are off, and the chooser says how many are hidden
      local hidden = ns.UI:MarketHiddenColumns()
      assert.is_true(hidden.avg and hidden.phase and hidden.min and true or false)
      assert.is_nil(hidden.vsAvg)
      assert.truthy(v.columns.label.text:find("hidden"))
      ns.UI:ColumnMenu(v.columns)
      local phase
      for _, it in ipairs(ns.Widgets.menu.items) do
        if it:IsShown() and (it.text.text or ""):find("Phase") then
          phase = it
        end
      end
      phase.scripts.OnClick(phase)
      assert.is_true(AME_DB.settings.marketColumns.phase) -- saved
      assert.is_nil(ns.UI:MarketHiddenColumns().phase)
      -- chips: one per active filter, each removable; Clear all resets
      v.maxBox:SetText("1")
      v.maxBox.scripts.OnTextChanged(v.maxBox, true)
      ns.UI.mq.signal = "hold"
      ns.UI:RefreshMarket(true)
      assert.are.equal(1, v.chips.count)
      assert.truthy(v.chips.pool[1].label.text:find("up to"))
      assert.are.equal("hold", v.signals:Selected())
      -- the picked signal is inverted: filled with its colour, its word in near-black
      local hold = v.signals.byKey.hold
      assert.truthy(hold.label.text:find("|cff" .. ns.Widgets.INVERTED_TEXT .. "HOLD", 1, true), hold.label.text)
      assert.truthy(v.signals.byKey.sell.label.text:find("|cff" .. ns.HEX.bad, 1, true)) -- the others: coloured
      -- save as a view, clear, and bring it back
      ns.UI:SaveMarketView("Cheap")
      v.chips.pool[1].scripts.OnClick(v.chips.pool[1])
      assert.is_nil(ns.UI.mq.maxPrice)
      assert.are.equal(0, v.chips.count)
      ns.UI:ApplyMarketView(AME_DB.settings.marketViews[1])
      assert.are.equal(10000, ns.UI.mq.maxPrice)
      assert.are.equal("hold", ns.UI.mq.signal)
      v.chips.clear.scripts.OnClick(v.chips.clear)
      assert.is_nil(ns.UI.mq.maxPrice)
      assert.is_nil(ns.UI.mq.signal)
      -- signal filter includes Wait, with glyphs (never colour alone)
      assert.truthy(v.signals.byKey.wait.label.text:find("Signals\\Pause", 1, true)) -- an icon, then the word
      assert.truthy(v.signals.byKey.wait.label.text:find("WAIT", 1, true))
      -- stale rows fade; row tooltips explain the signal
      local s = ns.UI.list[1]
      local day = s.day
      s.day = ns.UI.index.day - 5
      t:Render()
      assert.are.equal(0.5, t.rows[1].alpha)
      local reasons = table.concat(ns.UI.SignalReasons(s, ns.UI.index.day), "\n")
      assert.truthy(reasons:find("30%-day average"))
      assert.truthy(reasons:find("5 days old"))
      s.day = day
      t:Render()
      assert.are.equal(1, t.rows[1].alpha)
      -- a menu goes away with what opened it: switching tabs, or its button hidden
      ns.UI:ViewsMenu(v.views)
      local menu = ns.Widgets.menu
      assert.is_true(menu:IsShown())
      ns.UI:ShowTab("item")
      assert.is_false(menu:IsShown())
      ns.UI:ShowTab("market")
      ns.UI:ViewsMenu(v.views)
      v.views:Hide()
      menu.scripts.OnUpdate(menu, 0.016)
      assert.is_false(menu:IsShown())
      v.views:Show()
      -- narrow: the category sidebar becomes a dropdown on the toolbar
      ns.UI:OnResize(800)
      assert.is_false(v.side:IsShown())
      assert.is_true(v.category:IsShown())
      local opt
      for i, o in ipairs(v.category.entries) do
        if o.entry.classID == 7 then
          opt = i
        end
      end
      v.category.menu.items[opt].scripts.OnClick(v.category.menu.items[opt])
      assert.are.equal(7, ns.UI.mq.classID)
      -- one toolbar row like the design: no chips row, a short signal filter, the rest under More
      assert.is_false(v.slots.chips:IsShown())
      assert.is_true(v.signalsShort:IsShown())
      assert.is_false(v.columns:IsShown())
      assert.is_false(v.minBox:IsShown())
      assert.is_true(t.userHidden.qty and t.userHidden.score) -- Supply and Score give way when narrow
      assert.truthy(v.side.lines[2].entry.header) -- "Watchlists" heading
      assert.truthy(v.columns.label.text:find("hidden"))
      local mp = v.slots.main.points
      assert.are.equal(-(22 + ns.UI.SLOT_GAP), mp[1][3]) -- the table moves up into the chips row's space
      v.signalsShort.byKey.sell.scripts.OnClick(v.signalsShort.byKey.sell)
      assert.are.equal("sell", ns.UI.mq.signal)
      ns.UI:MarketMoreMenu(v.more)
      local wait = ns.Widgets.menu.items[1]
      wait.scripts.OnClick(wait)
      assert.are.equal("wait", ns.UI.mq.signal)
      ns.UI:RenderMarket()
      assert.is_false(v.signalsShort:Selected()) -- Wait isn't on the short filter
      ns.UI:OnResize(1000)
      assert.is_true(v.side:IsShown())
      assert.is_false(v.category:IsShown())
      assert.is_true(v.slots.chips:IsShown())
      assert.is_true(v.columns:IsShown())
    end)

    it("settings: the colour-blind palette, every setting in view; sync: freshness per auction house", function()
      seeded()
      ns.UI:Toggle()
      ns.UI:ShowTab("settings")
      local s = ns.UI.settingsView
      s.scripts.OnShow(s)
      assert.is_true(s.outliers:IsShown()) -- the outlier filter is a row in the Data card (no Advanced mode)
      -- colour-blind palette: gains and BUY turn blue, losses and SELL orange (text and chart colours)
      local green = ns.HEX.good
      s.colorBlind.scripts.OnClick(s.colorBlind)
      assert.is_true(ns.Settings:Get("colorBlind"))
      assert.are.equal("56b4e9", ns.HEX.good)
      assert.truthy(ns.Widgets.Signal("buy"):find("56b4e9"))
      assert.are.equal(0.9, ns.Widgets.COLORS.down[1])
      s.colorBlind.scripts.OnClick(s.colorBlind)
      assert.are.equal(green, ns.HEX.good)
      -- sync: how fresh each auction house's data is
      ns.UI:ShowTab("sync")
      local v = ns.UI.syncView
      v.scripts.OnShow(v)
      local horde = v.fresh[1] -- your own faction's auction house first
      assert.truthy(horde.label.text:find("Horde"))
      assert.truthy(horde.value.text:find("old"), horde.value.text)
      assert.truthy(horde.sub.text:find("Full scan by you"), horde.sub.text)
      assert.truthy(v.fresh[2].label.text:find("Goblin"))
      assert.truthy(v.fresh[3].value.text:find("No data"))
      -- lists are only as tall as what they show (an empty list: its wrapped message)
      local empty = v.trustedList
      assert.is_true(empty:GetHeight() < 22 * 3)
      assert.are.equal(empty:GetHeight(), empty.holder:GetHeight())
      -- settings: the Data buttons wrap onto a second line when the card is narrow
      ns.UI:ShowTab("settings")
      s.scripts.OnShow(s)
      s:FlowActions(150)
      assert.is_true(s.actionsRow:GetHeight() > 22) -- wrapped
      s:FlowActions(2000)
      assert.are.equal(22, s.actionsRow:GetHeight()) -- one line
    end)

    it("guides: scan progress, empty states, one-time hints, glossary links from explanations", function()
      seeded()
      ns.UI:Toggle()
      -- a full scan being read shows its real progress in the status row
      ns.AME.ingest.reading, ns.AME.ingest.progress = true, { done = 12345, total = 60000 }
      assert.truthy(ns.UI:FooterText():find("12,345 / 60,000", 1, true))
      ns.AME.ingest.reading = false
      assert.truthy(ns.UI:FooterText():find("^v"))
      -- empty states say what to do next
      ns.UI:ShowTab("market")
      ns.UI.mq.text = "nothing like this"
      ns.UI:RefreshMarket(true)
      assert.truthy(ns.UI.marketView.table.message.text:find("Nothing matches"))
      ns.UI:ResetMarketFilters()
      -- one-time hints: shown until "Got it"
      local anchor = CreateFrame("Frame")
      local hint = ns.Widgets.Hint(anchor, "test", "Hello")
      assert.is_not_nil(hint)
      hint.ok.scripts.OnClick(hint.ok)
      assert.is_true(AME_DB.settings.hintsSeen.test)
      assert.is_nil(ns.Widgets.Hint(anchor, "test", "Hello"))
      -- right-clicking an explained header opens its glossary entry on the Guide tab
      local header = ns.UI.marketView.headers[2] -- Market
      header.scripts.OnMouseUp(header, "RightButton")
      assert.are.equal("guide", ns.UI.current)
      assert.are.equal("market", ns.UI.views.guide.term)
      -- the Guide is a documentation page: sidebar of articles by group, one article at a time, searchable
      local guide = ns.UI.views.guide
      assert.are.equal("Glossary", guide.crumb.text)
      assert.truthy(guide.title.text:find("Market price"))
      assert.is_true(guide.byKey.market.link.sel:IsShown())
      guide.byKey.selling.link.scripts.OnClick(guide.byKey.selling.link)
      assert.are.equal("Trading", guide.crumb.text)
      assert.is_true(guide.paras[2]:IsShown()) -- two paragraphs
      guide.search:SetText("deposit")
      guide.search.scripts.OnTextChanged(guide.search, true)
      for _, a in ipairs(guide.matches) do
        local parts = { a.title }
        for _, b in ipairs(a.body) do
          parts[#parts + 1] = ns.Help.BlockText(b)
        end
        local text = table.concat(parts, " "):lower()
        assert.truthy(text:find("deposit"), a.key)
      end
      assert.is_false(guide.byKey.commands.link:IsShown()) -- doesn't mention deposits
      guide.search:SetText("")
      guide.search.scripts.OnTextChanged(guide.search, true)
      assert.is_true(guide.byKey.commands.link:IsShown())
      assert.are.equal("Market", guide.byKey.tabMarket.link.text.text) -- the sidebar label, not "Market tab"
      guide.byKey.tabMarket.link.scripts.OnClick(guide.byKey.tabMarket.link)
      assert.are.equal("Market tab", guide.title.text) -- the article keeps its full title
      assert.is_true(guide.examples["tabMarket:4"]:IsShown()) -- a live example in the article (the signal filter)
      -- every article opens, its drawn examples included (the Item article's candles)
      for key in pairs(guide.byKey) do
        guide:ShowArticle(key)
      end
      guide:ShowArticle("tabItem")
      local candles = 0
      for id, e in pairs(guide.examples) do
        if id:match("^tabItem:") and e:IsShown() then
          candles = candles + 1
        end
      end
      assert.is_true(candles >= 4) -- verdict, legend, candle anatomy, candle patterns
      assert.is_true(guide.heads[1]:IsShown()) -- and a section heading
      -- slash commands are links: a click puts the command in the chat box
      guide.byKey.commands.link.scripts.OnClick(guide.byKey.commands.link)
      local text = guide.paras[1].text
      assert.truthy(text:find("|Hamecmd:/ame status|h", 1, true), text)
      assert.truthy(text:find("|Hamecmd:/ame|h", 1, true)) -- "/ame <item link>": just /ame
      local typed
      _G.ChatFrame_OpenChat = function(t)
        typed = t
      end
      guide.pane.content.scripts.OnHyperlinkClick(guide.pane.content, "amecmd:/ame selftest")
      assert.are.equal("/ame selftest", typed)
      _G.ChatFrame_OpenChat = nil
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
      assert.is_true(row.star.watched) -- drawn as a filled star
      -- sidebar: line 2 is the watchlist; selecting it shows only watched items
      local listLine = v.side.lines[3]
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
      assert.truthy(ns.UI.itemView.watch.label.text:find("^Watching"))
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
      assert.truthy(ns.UI.itemView.slots.status.text:find("1 outlier price ignored"))
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
      assert.truthy(v.summary.text:find("15%% cut"))
      -- the first route is selected; the sidebar breaks it down: price, cut, deposit, buy, net
      local route = v.route
      assert.are.equal(2589, ns.UI.arbRoute.itemID)
      assert.are.equal(155, r.net) -- no vendor price known: no deposit
      assert.truthy(route.cut.label.text:find("15%%"))
      assert.truthy(route.buyAge.value.text:find("your scan"), route.buyAge.value.text) -- source and age
      assert.truthy(route.searchHint.text:find("Visit the Horde AH")) -- we're at the goblin AH
      ns.ItemCache.Get(2589).sellPrice = 1000
      ns.UI:RefreshArbitrage(true)
      drainJobs()
      r = ns.UI.arbRows[1]
      -- one post of 10 at the goblin AH: 60% x 5 of the vendor price per unit = 3000 per unit
      assert.are.equal(3000, r.deposit)
      assert.are.equal(155 - 3000, r.net)
      assert.truthy(route.deposit.value.text:find("30"))
      ns.ItemCache.Get(2589).sellPrice = nil
      r.sellAge = 5
      ns.UI:RenderRoute()
      assert.truthy(route.warn.text:find("5 days old"))
      v.rows[1].scripts.OnClick(v.rows[1]) -- a click selects (the Chart button opens the item)
      assert.are.equal(2589, ns.UI.arbSelected)
      -- the other way round finds nothing
      v.swap.scripts.OnClick(v.swap)
      drainJobs()
      assert.are.equal(0, #ns.UI.arbRows)
      assert.truthy(ns.UI.footer.text:find(ns.VERSION, 1, true))
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
      assert.truthy(ns.UI.marketView.table.message.text:find("No price history for the Alliance AH"))
      assert.are.equal(3, #ns.UI.viewSelect.values)
      -- no raw shard keys ("|N" is an escape code in WoW text) anywhere in chat
      for _, line in ipairs(env.chat) do
        assert.is_nil(line:find("|Neutral", 1, true), line)
      end
      assert.are.equal("PvP · Goblin AH", ns.ShardLabel("PvP|Neutral"))
    end)

    it("a recipe's tooltip shows what it makes at market, and what a craft earns after reagents", function()
      seeded()
      ns.CraftingData:Use({
        recipes = { [7001] = { 197, 4306, 1, 50, 75, 2589, 2 } }, -- 2 Linen -> 1 Silk, say
        items = { [99001] = { 197, 50, 7001 } }, -- the pattern teaching it
      })
      finally(function()
        ns.CraftingData:Use(nil)
      end)
      local rows = ns.Tooltip.RecipeLines(99001)
      assert.is_nil(rows) -- Crafting off: nothing
      ns.Settings:Set("crafting", true)
      rows = ns.Tooltip.RecipeLines(99001)
      assert.truthy(rows[1][1]:find("Makes", 1, true), rows[1][1])
      assert.truthy(rows[1][2]:find("[sgc]"), rows[1][2]) -- a price
      assert.truthy(rows[2][1]:find("Per craft", 1, true))
      assert.is_nil(ns.Tooltip.RecipeLines(2589)) -- not a recipe
    end)

    it("tooltips use your faction's auction house even right after visiting the goblin AH", function()
      boot()
      env.npcFaction = "Horde"
      env:fire("AUCTION_HOUSE_SHOW")
      fullScan({ { 2589, 1000, 10 } }) -- 1s each at the Horde AH
      env:fire("AUCTION_HOUSE_CLOSED")
      env.npcFaction = nil
      env:fire("AUCTION_HOUSE_SHOW")
      fullScan({ { 2589, 5000, 10 } }) -- 5s each at the goblin AH
      env:advance(4)
      drainJobs()
      assert.are.equal("Neutral", ns.AME:CurrentHouse())
      local s = ns.Tooltip.Summary(2589)
      assert.are.equal(100, s.market)
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

    it("shows how many units a route stays profitable for, from a search at the buy house", function()
      boot()
      env.npcFaction = nil
      env:fire("AUCTION_HOUSE_SHOW")
      fullScan({ { 2589, 3000, 10 } }) -- goblin AH: 3s each
      env:fire("AUCTION_HOUSE_CLOSED")
      env.npcFaction = "Horde"
      env:fire("AUCTION_HOUSE_SHOW")
      fullScan({ { 2589, 1000, 10 } }) -- Horde AH: 1s each
      -- searching it at the Horde AH shows the listings: 20 at 90c, 30 at 95c, 10 at 4s
      env.ah.commodities[2589] = { { 90, 20 }, { 95, 30 }, { 400, 10 } }
      env:fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
      env:advance(2)
      env:advance(4)
      drainJobs()
      ns.UI:Toggle()
      ns.UI:ShowTab("arbitrage")
      local v = ns.UI.arbView
      v.scripts.OnShow(v)
      drainJobs()
      local e = ns.UI.arbRows[1]
      assert.are.equal(2589, e.itemID)
      -- sells for 300c at the goblin AH, 255c after its 15% cut: the 90c and 95c tiers pay, the 4s tier doesn't
      local units, cost, profit = ns.Depth.Route(ns.AME:BookFor("TestRealm|Horde", 2589), 255)
      assert.are.equal(50, units)
      assert.are.equal(20 * 90 + 30 * 95, cost)
      local text = ns.UI:DepthText(e)
      assert.truthy(text:find("^50 "), text)
      assert.are.equal(50 * 255 - cost, profit)
    end)

    it("searches the buy auction house from an arbitrage row, via Auctionator or the default AH", function()
      local searched = {}
      boot({
        auctionator = {
          API = {
            v1 = {
              MultiSearchExact = function(caller, terms)
                searched[#searched + 1] = { caller = caller, term = terms[1] }
              end,
            },
          },
        },
      })
      env.npcFaction = nil
      env:fire("AUCTION_HOUSE_SHOW")
      fullScan({ { 2589, 3000, 10 } }) -- goblin AH: dear
      env:fire("AUCTION_HOUSE_CLOSED")
      env.npcFaction = "Horde"
      env:fire("AUCTION_HOUSE_SHOW")
      fullScan({ { 2589, 1000, 10 } }) -- Horde AH: cheap - and we're standing here
      env:advance(4)
      drainJobs()
      ns.UI:Toggle()
      ns.UI:ShowTab("arbitrage")
      local v = ns.UI.arbView
      v.scripts.OnShow(v)
      drainJobs()
      local row = v.rows[1]
      assert.are.equal(2589, row.itemID)
      assert.is_true(row.action:IsShown())
      row.action.scripts.OnClick(row.action)
      assert.are.same({ caller = "AzerothMercantileExchange", term = "Item 2589" }, searched[1])
      -- a random-suffix item: its full name, suffix included, searched exactly
      local variant = 2589 + 5 * ns.SUFFIX_STEP
      ns.ItemCache.setName(variant, "Item 2589 of Defense") -- learned from a link it saw
      assert.are.equal("Item 2589 of Defense", ns.ItemCache.Name(variant))
      assert.is_true(ns.AME:SearchAuctionHouse(variant))
      assert.are.same({ caller = "AzerothMercantileExchange", term = "Item 2589 of Defense" }, searched[2])
      -- a suffix whose full name AME hasn't seen yet: its base name, loosely (every suffix of it)
      _G.Auctionator.API.v1.MultiSearch = function(caller, terms)
        searched[#searched + 1] = { caller = caller, term = terms[1], loose = true }
      end
      local unseen = 2589 + 7 * ns.SUFFIX_STEP
      assert.is_true(ns.AME:SearchAuctionHouse(unseen))
      assert.are.same({ caller = "AzerothMercantileExchange", term = "Item 2589", loose = true }, searched[3])
      -- with the advanced API: one search, each term exact or not
      _G.Auctionator.API.v1.MultiSearchAdvanced = function(caller, terms)
        searched[#searched + 1] = { caller = caller, terms = terms }
      end
      assert.is_true(ns.AME:AuctionatorSearch({ 2589, variant, unseen }))
      assert.are.same({
        { searchString = "Item 2589", isExact = true },
        { searchString = "Item 2589 of Defense", isExact = true },
        { searchString = "Item 2589", isExact = false },
      }, searched[4].terms)
      -- without Auctionator: the default auction house window's search box
      _G.Auctionator = nil
      local text, started
      _G.AuctionHouseFrame = {
        IsShown = function()
          return true
        end,
        SearchBar = {
          SetSearchText = function(_, t)
            text = t
          end,
          StartSearch = function()
            started = true
          end,
        },
      }
      env.shiftDown = true
      row.scripts.OnClick(row) -- Shift-click the row
      env.shiftDown = false
      assert.are.equal("Item 2589", text)
      assert.is_true(started)
      _G.AuctionHouseFrame = nil
      -- away from the auction house the Search buttons stay, but can't be used
      env:fire("AUCTION_HOUSE_CLOSED")
      ns.UI:RenderArbitrage()
      assert.is_true(row.action:IsShown())
      assert.is_false(row.action.usable)
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
      -- the 7-day average at every scan, and MA 20 over 20 candles; each switched off and on in the legend
      assert.are.same(times, ns.UI.chart.series.sma.xs)
      local legendText = ns.UI.itemView.legend.text
      assert.truthy(legendText:find("7-day average", 1, true), legendText)
      assert.truthy(legendText:find("MA 20 (40 hours)", 1, true), legendText)
      assert.is_not_nil(ns.UI.chart.series.fast)
      local rows = ns.UI.itemView.legendBox.rows
      local function row(label)
        for _, r in ipairs(rows) do
          if r.click and r.click:IsShown() and r.click.label and r.click.label:find(label, 1, true) then
            return r.click
          end
        end
      end
      row("MA 20").scripts.OnClick(row("MA 20"))
      assert.is_nil(ns.UI.chart.series.fast)
      row("7-day average").scripts.OnClick(row("7-day average"))
      assert.is_nil(ns.UI.chart.series.sma)
      assert.is_false(AME_DB.settings.chartLayers.sma) -- remembered
      row("7-day average").scripts.OnClick(row("7-day average"))
      assert.is_not_nil(ns.UI.chart.series.sma)
      -- intraday candles: 2-hour candles from the scans
      v.style.byKey.candles.scripts.OnClick(v.style.byKey.candles)
      assert.are.equal(5, #ns.UI.candles.xs)
      assert.are.equal(2 * 3600, ns.UI.candles.period)
      v.style.byKey.line.scripts.OnClick(v.style.byKey.line)
      -- back to daily history
      local thirty = v.rangeButtons[3]
      thirty.scripts.OnClick(thirty)
      assert.is_not_nil(ns.UI.chart.series.sma)
    end)

    it("finds items by name in the item box, and Shift-clicked links open on the Item tab", function()
      seeded()
      ns.UI:ShowItem(4306)
      drainJobs()
      assert.are.equal("7D", ns.UI.rangeKey) -- 7 days by default (Forever is young)
      assert.truthy(ns.UI.itemView.cards[3].label.text:find("7%-day average"))
      local box = ns.UI.searchBox
      box.scripts.OnEditFocusGained(box)
      box:SetText("item 25")
      box.scripts.OnTextChanged(box, true)
      assert.truthy(ns.Widgets.menu:IsShown()) -- suggestions
      assert.truthy(ns.Widgets.menu.items[1].text.text:find("Item 2589"))
      box.scripts.OnEnterPressed(box)
      assert.are.equal(2589, ns.UI.itemID)
      -- Shift-click a chat link while the Item tab is up
      env.shiftDown = true
      HandleModifiedItemClick("|cffffffff|Hitem:4306::::::::::::|h[Item 4306]|h|r")
      assert.are.equal(4306, ns.UI.itemID)
      -- on the Market tab with its search focused, Shift-click searches for the item
      ns.UI:ShowTab("market")
      local search = ns.UI.marketView.search
      search.HasFocus = function()
        return true
      end
      env.now = env.now + 1
      HandleModifiedItemClick("|cffffffff|Hitem:2589::::::::::::|h[Item 2589]|h|r")
      assert.are.equal("Item 2589", ns.UI.mq.text)
      assert.are.equal(1, #ns.UI.list)
      env.shiftDown = false
      -- the screener's average column follows the period too
      assert.truthy(ns.UI.marketView.headers[3].text.text:find("7d avg"))
    end)

    it("estimates how fast items sell from supply draining between full scans", function()
      boot()
      env.npcFaction = "Horde"
      env:fire("AUCTION_HOUSE_SHOW")
      env.now = env.now - env.now % 86400 + 3600
      fullScan({ { 2589, 1000, 100 } })
      env.now = env.now + 6 * 3600
      fullScan({ { 2589, 1000, 70 } }) -- 30 gone in 6 hours
      env:advance(4)
      drainJobs()
      local s = ns.AME.index.items[2589]
      assert.are.equal(120, s.sellRate) -- 30 per 6 h = 120 a day
      ns.UI:Toggle()
      ns.UI:ShowTab("market")
      local v = ns.UI.marketView
      local col
      for c, h in ipairs(v.headers) do
        if h.text.text:find("Sales/day") then
          col = c
        end
      end
      assert.are.equal("~120/d", v.rows[1].cells[col].text)
    end)

    it("counts real auction outcomes: an item that leaves the AH every day but never sells isn't selling", function()
      boot()
      env.npcFaction = "Horde"
      env:fire("AUCTION_HOUSE_SHOW")
      env.now = env.now - env.now % 86400 + 3600
      fullScan({ { 2589, 1000, 100 } })
      env.now = env.now + 6 * 3600
      fullScan({ { 2589, 1000, 70 } }) -- 30 gone in 6 hours: 120 a day leave the AH (sold? expired? reposted?)
      env:advance(4)
      drainJobs()
      assert.are.equal(120, ns.AME.index.items[2589].sellRate)
      local shard = ns.AME:CurrentShard()
      -- you list it four times, 10 each for 24 hours
      for _ = 1, 4 do
        C_AuctionHouse.PostCommodity({ itemID = 2589 }, 3, 10, 1000)
      end
      -- you cancel one
      env.ah.owned = { { auctionID = 7, itemKey = { itemID = 2589 }, quantity = 10, buyoutAmount = 1000, status = 0 } }
      C_AuctionHouse.CancelAuction(7)
      -- a day later: one expires while you're online...
      env.now = env.now + 24 * 3600
      env:fire("CHAT_MSG_SYSTEM", "Your auction of Item 2589 has expired.")
      -- ...two while you were away: their items come back by mail, read twice (each counts once)
      local mails = { { days = 30 }, { days = 30 } }
      _G.GetInboxNumItems = function()
        return #mails
      end
      _G.GetInboxInvoiceInfo = function() end
      _G.GetInboxHeaderInfo = function(i)
        return nil, nil, "Auction House", "Auction expired: Item 2589", 0, 0, mails[i].days
      end
      _G.GetInboxItem = function(_, slot)
        if slot == 1 then
          return "Item 2589", 2589, 134400, 10
        end
      end
      env:fire("MAIL_INBOX_UPDATE")
      env.now = env.now + 600
      for _, m in ipairs(mails) do
        m.days = m.days - 600 / 86400
      end
      env:fire("MAIL_INBOX_UPDATE")
      _G.GetInboxNumItems, _G.GetInboxInvoiceInfo, _G.GetInboxHeaderInfo, _G.GetInboxItem = nil, nil, nil, nil
      assert.are.equal(0, #AME_DB.listings)
      local r = ns.SellThrough.Decode(AME_DB.sellThrough[shard][2589])
      assert.are.equal(0, r.s)
      assert.are.equal(30, math.floor(r.e + 0.5))
      assert.are.equal(10, math.floor(r.c + 0.5))
      assert.are.equal(4, math.floor(r.n + 0.5))
      -- the index takes it in: of what left the AH, about none sold
      env:advance(6)
      drainJobs()
      local s = ns.AME.index.items[2589]
      assert.are.equal(0, s.sellThrough)
      assert.are.equal(120, s.churnRate)
      assert.truthy(s.sellRate < 60, s.sellRate) -- four outcomes outweigh the scans' guess
      assert.truthy(s.value < 1000 * 0.5) -- worth the vendor's price (none here) as often as it doesn't sell
      local rows = ns.Tooltip.Lines(s)
      local found
      for _, row in ipairs(rows) do
        if row[1]:find("sell%-through") then
          found = row[2]
        end
      end
      assert.truthy(found and found:find("0%%") and found:find("0 of 40 sold"), found)
      -- saved with the index and read back
      local back = ns.MarketIndex.Decode(ns.MarketIndex.Encode(ns.AME.index)).items[2589]
      assert.are.equal(0, back.sellThrough)
      assert.are.equal(40, math.floor(back.stEnded + 0.5)) -- the cancel a day earlier has faded a little
    end)

    it("learns each item's market from scans, suggests posting prices, and learns from your posts", function()
      seeded()
      local shard = ns.AME:CurrentShard()
      local profile = ns.Posting:Profile(shard, 2589)
      assert.truthy(profile.n >= 1) -- consecutive daily scans
      assert.truthy(AME_DB.pricing[shard][2589]:find(";")) -- saved compactly
      local advice = ns.Posting:Suggest(shard, 2589, 5, 24)
      assert.is_not_nil(advice)
      assert.truthy(advice.quick.price <= advice.normal.price and advice.normal.price <= advice.patient.price)
      assert.truthy(advice.deposit >= 1) -- 1 copper minimum per post
      -- you post 5 at the suggested price: recorded with the model's chance
      C_AuctionHouse.PostCommodity({ itemID = 2589 }, 3, 5, advice.normal.price)
      assert.are.equal(1, #AME_DB.listings)
      assert.are.equal(24, AME_DB.listings[1].hours)
      assert.is_number(AME_DB.listings[1].chance)
      local expect = AME_DB.listings[1].expect
      assert.is_number(expect) -- the hours it should take, as predicted when posted
      -- it sold right away: the outcome calibrates the item, and the speed learns it sells faster than predicted
      env.now = env.now + 60
      env:fire("CHAT_MSG_SYSTEM", "A buyer has been found for your auction of Item 2589.")
      local learned = ns.Posting:Profile(shard, 2589)
      assert.are.equal(1, learned.no)
      assert.are.equal(1, learned.sn)
      assert.truthy(learned.speed > 0)
      -- how many sold comes with the invoice: the listing waits for it, then counts for the item's sell-through
      assert.are.equal("sold", AME_DB.listings[1].heard)
      assert.is_not_nil(ns.Posting:OnOutcome("Item 2589", true, env.now + 3600, 5))
      assert.are.equal(0, #AME_DB.listings)
      assert.are.equal(1, learned.no) -- learned from once
      assert.are.equal(5, ns.SellThrough.Decode(AME_DB.sellThrough[shard][2589]).s)
      -- a sale found only in the auction mail (you were offline): it sold some time before the mail
      C_AuctionHouse.PostCommodity({ itemID = 2589 }, 3, 5, advice.normal.price)
      assert.is_not_nil(ns.Posting:OnOutcome("Item 2589", true, env.now + 3600))
      assert.are.equal(0, #AME_DB.listings)
      assert.are.equal(2, learned.no)

      -- the item view shows it under the chart
      ns.UI:Toggle()
      ns.UI:ShowItem(2589)
      drainJobs()
      assert.truthy(ns.UI.itemView.postHead.text:find("Post at"))
      assert.truthy(ns.UI.itemView.postNet.text:find("% cut", 1, true))

      -- the auction house's sell window: a bar under it fills in the price you pick (you still click Post)
      local filled
      local sell = CreateFrame("Frame")
      sell.GetItem = function()
        return { itemID = 2589 }
      end
      sell.GetQuantity = function()
        return 5
      end
      sell.GetDuration = function()
        return 3
      end
      sell.PriceInput = {
        SetAmount = function(_, v)
          filled = v
        end,
        GetAmount = function()
          return filled
        end,
      }
      local ahFrame = CreateFrame("Frame")
      ahFrame.CommoditiesSellFrame = sell
      _G.AuctionHouseFrame = ahFrame
      finally(function()
        _G.AuctionHouseFrame = nil
      end)
      env:fire("AUCTION_HOUSE_SHOW")
      env:update(40)
      local bar = ns.SellAssist.bar
      assert.truthy(bar:IsShown())
      -- the auction house's tabs hang below its frame: the bar sits under them, not over them
      local tab = CreateFrame("Button")
      tab.GetBottom = function()
        return -30
      end
      _G.AuctionFrameTab1 = tab
      ns.SellAssist.Place(bar)
      assert.are.same({ "TOPLEFT", ahFrame, "BOTTOMLEFT", 0, -34 }, bar.points[1])
      _G.AuctionFrameTab1 = nil
      advice = ns.SellAssist.advice
      assert.truthy(bar.title.text:find("Post at"))
      assert.truthy(bar.info.text:find("% cut", 1, true))
      assert.truthy(bar.info.text:find("^Just under") or bar.info.text:find("listing"), bar.info.text)
      assert.truthy(bar.conf.text:find("WHITE8x8", 1, true)) -- just the confidence bars
      -- Quick, Normal and Patient are always there; the one in the price box is highlighted
      assert.is_true(bar.quick:IsShown() and bar.reset:IsShown() and bar.patient:IsShown())
      assert.truthy(bar.fill.label.text:find("^Market")) -- the fourth choice: the item's market price
      bar.reset.scripts.OnClick(bar.reset)
      assert.are.equal(advice.normal.price, filled)
      assert.is_true(bar.reset.selected)
      -- one button lit even when two choices share a price (Normal = Patient here)
      advice.patient.price = advice.normal.price
      ns.SellAssist:Draw()
      assert.is_true(bar.reset.selected)
      assert.is_false(bar.patient.selected)
      bar.patient.scripts.OnClick(bar.patient) -- the one you click is the one lit
      assert.is_true(bar.patient.selected)
      assert.is_false(bar.reset.selected)
      bar.quick.scripts.OnClick(bar.quick)
      assert.are.equal(advice.quick.price, filled)
      assert.is_true(bar.quick:IsShown() and bar.reset:IsShown() and bar.patient:IsShown()) -- nothing disappears
      bar.reset.scripts.OnClick(bar.reset)
      -- clicking a listing in the sell window puts its price in the box: the bar re-targets just under it
      local listing = advice.book.prices[#advice.book.prices]
      filled = listing
      env:update(40)
      assert.truthy(bar.title.text:find("Under that listing"), bar.title.text)
      assert.are.equal(listing - 1, ns.SellAssist.shown)
      assert.is_true(bar.reset:IsShown())
      bar.fill.scripts.OnClick(bar.fill) -- Market: fills the item's market price
      assert.are.equal(advice.market.price, filled)
      assert.is_true(bar.fill.selected)
      filled = listing + 7 -- a price you type: judged as yours
      env:update(40)
      assert.truthy(bar.title.text:find("Your price"))
      bar.reset.scripts.OnClick(bar.reset) -- back to the suggestion
      assert.are.equal(advice.normal.price, filled)
      env:update(40)
      assert.truthy(bar.title.text:find("Post at"))
      -- a vendor pays more than the auction house nets: say so
      ns.ItemCache.Get(2589).sellPrice = 10 ^ 7
      ns.SellAssist:Invalidate()
      env:update(40)
      assert.truthy(bar.title.text:find("Vendor it"))
      assert.truthy(bar.fill.label.text:find("^Post anyway at"))
      assert.is_false(bar.quick:IsShown()) -- one button in the vendor case
      assert.truthy(bar.info.text:find("a vendor pays"))
      ns.ItemCache.Get(2589).sellPrice = nil
      sell.GetItem = function() end -- slot emptied: the bar goes away
      env:update(40)
      assert.is_false(bar:IsShown())
      -- Auctionator's selling tab: the bar reads its item and fills its unit price box
      local unit
      local sale = CreateFrame("Frame")
      sale.itemInfo = { itemLink = "|cffffffff|Hitem:2589::::::::|h[Item 2589]|h|r", count = 20 }
      sale.GetStackSize = function()
        return 5
      end
      sale.Duration = {
        GetValue = function()
          return 48
        end,
      }
      sale.UnitPrice = {
        SetAmount = function(_, v)
          unit = v
        end,
        GetAmount = function()
          return unit
        end,
      }
      _G.AuctionatorSellingFrame = { SaleItemFrame = sale }
      ns.SellAssist:Invalidate()
      env:update(40)
      assert.truthy(bar:IsShown())
      assert.are.equal(5, ns.SellAssist.advice.qty)
      bar.reset.scripts.OnClick(bar.reset)
      assert.are.equal(ns.SellAssist.advice.normal.price, unit)
      _G.AuctionatorSellingFrame = nil
      _G.AuctionHouseFrame = nil
    end)

    it("builds the portfolio from bags and auction mail, with a ledger and realized profit", function()
      seeded()
      -- the item API resolves "Item <id>" names (invoices name items, they don't link them)
      local instant = C_Item.GetItemInfoInstant
      _G.C_Item.GetItemInfoInstant = function(x)
        if type(x) == "string" then
          return tonumber(x:match("Item (%d+)"))
        end
        return instant(x)
      end
      -- bags: two stacks of 20 Linen (2589), and one soulbound copy that isn't stock (can't be sold)
      _G.C_Container = {
        GetContainerNumSlots = function(bag)
          return bag == 0 and 3 or 0
        end,
        GetContainerItemInfo = function(bag, slot)
          if bag == 0 and slot <= 2 then
            return { itemID = 2589, stackCount = 20, isBound = false }
          elseif bag == 0 and slot == 3 then
            return { itemID = 2589, stackCount = 1, isBound = true }
          end
        end,
      }
      -- mailbox: bought 5 Linen for 5000 earlier, sold 10 for 30000 (1500 AH cut) just now
      local mails = {
        { "buyer", "Item 2589", "Seller", 5000, 0, 0, 0, 0, 0, 0, 5, days = 29 },
        { "seller", "Item 2589", "Buyer", 30000, 0, 100, 1500, 0, 0, 0, 10, days = 29.9 },
      }
      _G.GetInboxNumItems = function()
        return #mails
      end
      _G.GetInboxInvoiceInfo = function(i)
        return unpack(mails[i])
      end
      _G.GetInboxHeaderInfo = function(i)
        return nil, nil, "Auction House", "subject", 0, 0, mails[i].days
      end
      env:fire("MAIL_INBOX_UPDATE")
      -- ten minutes later the same mails are opened again: their days left have shrunk; still recorded once
      env.now = env.now + 600
      for _, m in ipairs(mails) do
        m.days = m.days - 600 / 86400
      end
      env:fire("MAIL_INBOX_UPDATE")
      env:fire("BAG_UPDATE_DELAYED")
      -- at the Horde AH: 2 auctions of Linen, 5 at 2s each and 1 at 3s
      local owned = {
        { itemKey = { itemID = 2589 }, quantity = 5, buyoutAmount = 200, status = 0 },
        { itemKey = { itemID = 2589 }, quantity = 1, buyoutAmount = 300, status = 0 },
        { itemKey = { itemID = 2589 }, quantity = 4, buyoutAmount = 200, status = 1 }, -- sold: not listed
      }
      env.ah.GetNumOwnedAuctions = function()
        return #owned
      end
      env.ah.GetOwnedAuctionInfo = function(i)
        return owned[i]
      end
      env:fire("OWNED_AUCTIONS_UPDATED")
      local ledger = ns.AME.ledger
      assert.are.equal(2, #ledger.db.entries)
      local week = ledger:Summary(env.now - 7 * 86400)
      assert.are.equal(30000 - 1500, week.income)
      -- the sale used up the 5 bought units (1000 each) and 5 never bought on the AH
      assert.are.equal(30000 - 1500 - 5000, week.profit)

      ns.UI:Toggle()
      ns.UI:ShowTab("portfolio")
      local v = ns.UI.pfView
      v.scripts.OnShow(v)
      local row = ns.UI.pfRows[1]
      assert.are.equal(2589, row.itemID)
      assert.are.equal(row.market * row.qty, ns.UI.pfTotals.value)
      assert.truthy(v.cards[1].value.text ~= "")
      assert.are.equal(2, ns.UI.pfListed.count)
      assert.are.equal(5 * 200 + 300, ns.UI.pfListed.value)
      assert.truthy(v.cards[2].sub.text:find("2 auctions"))
      assert.are.equal(46, row.qty) -- 40 in bags + 6 listed
      -- active auctions view
      v.auctionsButton.scripts.OnClick(v.auctionsButton)
      assert.are.equal(2, #ns.UI.pfAuctions)
      assert.are.equal(1000, ns.UI.pfAuctions[1].total) -- 5 x 2s, sorted by total
      -- the game says one sold: a pending ledger row (the game's own message is the notification)
      env:fire("CHAT_MSG_SYSTEM", "A buyer has been found for your auction of Item 2589.")
      assert.are.equal(1, #ledger:Pending())
      assert.are.equal("Item 2589", ledger:Pending()[1].name)
      env:fire("CHAT_MSG_SYSTEM", "Your auction of Item 2589 has expired.")
      assert.are.equal(1, #ledger:Pending()) -- expiries aren't sales
      env:fire("CHAT_MSG_SYSTEM", "Something else entirely.")
      assert.are.equal(1, #ledger:Pending())
      v.ledgerButton.scripts.OnClick(v.ledgerButton)
      assert.are.equal("ledger", ns.UI.pfMode)
      assert.truthy(v.ledger.rows[1].cells[2].text:find("sold"))
      -- periods: the KPI cards and the ledger follow them
      assert.truthy(v.cards[4].label.text:find("30 days"))
      local all = #ns.UI.pfLedger
      ns.UI.pfPeriod = "today"
      env.now = env.now + 2 * 86400 -- two days later: nothing happened today
      ns.UI:RefreshPortfolio()
      assert.are.equal(0, #ns.UI.pfLedger)
      assert.truthy(v.cards[4].label.text:find("Today"))
      assert.truthy(v.ledger.message.text:find("No sales"))
      ns.UI.pfPeriod = "all"
      ns.UI:RefreshPortfolio()
      assert.are.equal(all, #ns.UI.pfLedger)
      -- this character only: another character's holdings and trades drop out
      AME_DB.holdings["TestRealm:Altchar"] = { bags = { [4306] = 3 } }
      ledger.db.entries[#ledger.db.entries + 1] =
        { t = env.now, kind = "buy", itemID = 4306, name = "Item 4306", qty = 3, amount = 300, char = "Altchar" }
      ns.UI:RefreshPortfolio()
      local n = #ns.UI.pfLedger
      ns.UI.pfScope = "char"
      ns.UI:RefreshPortfolio()
      assert.are.equal(n - 1, #ns.UI.pfLedger)
      for _, e in ipairs(ns.UI.pfLedger) do
        assert.are_not.equal("Altchar", e.char)
      end
      ns.UI.pfScope = "account"
      -- export: the table as tab-separated text in a copy box
      ns.UI.pfMode = "positions"
      ns.UI:RefreshPortfolio()
      local box = ns.UI:ExportPortfolio()
      local text = box.edit:GetText()
      assert.truthy(text:find("^Item\tHeld"))
      assert.truthy(text:find("Item 2589\t46\t", 1, true))
      assert.truthy(text:find("Market (g)", 1, true)) -- money as gold numbers a spreadsheet can sum
      row = ns.UI.pfRows[1]
      assert.truthy(text:find(("%.4f"):format(row.market / 10000), 1, true))
      assert.is_nil(text:find("|c", 1, true)) -- no colour codes
      -- CSV: commas, quoted where needed
      box.formats.byKey.csv.scripts.OnClick(box.formats.byKey.csv)
      text = box.edit:GetText()
      assert.truthy(text:find("^Item,Held,"))
      assert.truthy(text:find("Item 2589,46,", 1, true))
      assert.truthy(box.hint.text:find("comma"))
      box.formats.byKey.tabs.scripts.OnClick(box.formats.byKey.tabs)
      _G.C_Container, _G.GetInboxNumItems, _G.GetInboxInvoiceInfo, _G.GetInboxHeaderInfo = nil, nil, nil, nil
      _G.C_Item.GetItemInfoInstant = instant
    end)

    it("keeps each list's scroll position when you open an item and come back", function()
      boot()
      env.npcFaction = nil
      env:fire("AUCTION_HOUSE_SHOW")
      local goblin, horde = {}, {}
      for i = 1, 40 do
        goblin[i] = { 1000 + i, 9000, 1 }
        horde[i] = { 1000 + i, 1000, 1 }
      end
      fullScan(goblin)
      env:fire("AUCTION_HOUSE_CLOSED")
      env.npcFaction = "Horde"
      env:fire("AUCTION_HOUSE_SHOW")
      fullScan(horde)
      env:advance(4)
      drainJobs()
      ns.UI:Toggle()
      for _, tab in ipairs({ "market", "arbitrage" }) do
        ns.UI:ShowTab(tab)
        local view = tab == "market" and ns.UI.marketView or ns.UI.arbView
        if view.scripts.OnShow then
          view.scripts.OnShow(view)
        end
        drainJobs()
        local t = view.table
        t:Scroll(-3) -- down 9 rows
        local first = t.rows[1].itemID
        assert.is_true(t:Offset() > 0, tab)
        ns.UI:ShowItem(t.rows[1].itemID)
        drainJobs()
        ns.UI:ShowTab(tab)
        if view.scripts.OnShow then
          view.scripts.OnShow(view)
        end
        drainJobs()
        assert.are.equal(first, t.rows[1].itemID, tab .. " should be where we left it")
      end
    end)

    it("sorts any table by clicking its column headers", function()
      seeded()
      _G.C_Container = {
        GetContainerNumSlots = function(bag)
          return bag == 0 and 2 or 0
        end,
        GetContainerItemInfo = function(_, slot)
          return slot == 1 and { itemID = 2589, stackCount = 50 } or { itemID = 4306, stackCount = 2 }
        end,
      }
      env:fire("BAG_UPDATE_DELAYED")
      ns.UI:Toggle()
      ns.UI:ShowTab("portfolio")
      local v = ns.UI.pfView
      v.scripts.OnShow(v)
      local t = v.positions
      local function order()
        return { t.rows[1].itemID, t.rows[2].itemID }
      end
      local function click(label)
        for _, h in ipairs(t.headers) do
          if h.text.text:find(label, 1, true) then
            h.scripts.OnClick(h)
            return
          end
        end
        error("no header " .. label)
      end
      local byValue = order()
      click("Held") -- most held first
      assert.are.same({ 2589, 4306 }, order())
      click("Held") -- again: fewest first
      assert.are.same({ 4306, 2589 }, order())
      click("Value")
      local first = order()
      click("Value")
      assert.are.same({ first[2], first[1] }, order())
      click("Item") -- by name, A-Z first
      assert.are.same({ 2589, 4306 }, order()) -- "Item 2589" < "Item 4306"
      click("Signal") -- sortable too
      assert.truthy(t.headers[7].text.text:find("Signal", 1, true))
      assert.are.equal(2, #ns.UI.pfRows) -- the owner's list isn't reordered
      assert.are.same(byValue, { ns.UI.pfRows[1].itemID, ns.UI.pfRows[2].itemID })
      _G.C_Container = nil
    end)

    it("fills in item names in every table once the client loads them (no 'item:<id>' left behind)", function()
      seeded()
      -- the client doesn't know Linen yet
      local getInfo = C_Item.GetItemInfo
      local known = false
      _G.C_Item.GetItemInfo = function(id)
        if id == 2589 and not known then
          return nil
        end
        return getInfo(id)
      end
      _G.C_Container = {
        GetContainerNumSlots = function(bag)
          return bag == 0 and 1 or 0
        end,
        GetContainerItemInfo = function()
          return { itemID = 2589, stackCount = 5 }
        end,
      }
      env:fire("BAG_UPDATE_DELAYED")
      ns.UI:Toggle()
      ns.UI:ShowTab("portfolio")
      local v = ns.UI.pfView
      v.scripts.OnShow(v)
      local cell = v.positions.rows[1].cells[1]
      assert.truthy(cell.text:find("item:2589", 1, true))
      known = true -- the client finishes loading the item
      env:advance(0.1)
      assert.truthy(cell.text:find("Item 2589", 1, true), cell.text)
      _G.C_Item.GetItemInfo, _G.C_Container = getInfo, nil
    end)

    it("marks the vendor price: a dashed line near the prices, a legend note far below them", function()
      seeded()
      ns.UI:ShowItem(2589)
      drainJobs()
      ns.UI:SetRange(30, "30D")
      local lowest
      for _, p in ipairs(ns.UI.series) do
        lowest = math.min(lowest or p.min, p.min, p.market)
      end
      local function redraw(price)
        env.sellPrices[2589] = price
        ns.ItemCache.info[2589] = nil -- facts are cached: read the price again
        ns.UI:DrawItemChart()
      end
      redraw(math.floor(lowest * 0.6))
      local line = ns.UI.chart.series.vendor
      assert.is_not_nil(line)
      assert.are.same({ math.floor(lowest * 0.6), math.floor(lowest * 0.6) }, line.ys)
      assert.is_not_nil(line.dash)
      assert.truthy(ns.UI.itemView.legend.text:find("Vendor price", 1, true))
      local hover = ns.UI.chart.hoverFormatter(ns.UI.chart, line.xs[1], {})
      local text = {}
      for _, l in ipairs(hover) do
        text[#text + 1] = type(l) == "table" and (l[1] .. " " .. l[2]) or l
      end
      assert.truthy(table.concat(text, "\n"):find("Vendor price", 1, true))
      redraw(math.max(1, math.floor(lowest * 0.05)))
      assert.is_nil(ns.UI.chart.series.vendor)
      assert.truthy(ns.UI.itemView.legend.text:find("below the chart", 1, true), ns.UI.itemView.legend.text)
      redraw(nil) -- no vendor price (can't be sold to one)
      assert.is_nil(ns.UI.chart.series.vendor)
      assert.is_nil(ns.UI.itemView.legend.text:find("Vendor", 1, true))
    end)

    it("plots the 7-day range from hourly points, and the longer ones by day", function()
      seeded()
      ns.UI:ShowItem(2589)
      drainJobs()
      assert.are.equal("7D", ns.UI.rangeKey)
      assert.is_true(ns.UI:ShowingIntraday())
      local kinds = {}
      for _, p in ipairs(ns.UI:IntradayPoints()) do
        kinds[p.kind or "day"] = true
      end
      assert.is_true(kinds.hour, "hourly points from before the scans kept in full")
      -- the 7-day average: at every point, up to the newest scan
      local sma = ns.UI.chart.series.sma
      assert.is_not_nil(sma)
      assert.truthy(ns.UI.itemView.legend.text:find("7-day average", 1, true))
      local shown = ns.UI:IntradayPoints()
      assert.are.equal(#shown, #sma.xs)
      assert.are.equal(shown[#shown].t, sma.xs[#sma.xs])
      -- hourly points only from the last 2 days (AME started keeping them then): the older days come by day, so
      -- the chart still spans the week
      local recent = {}
      for _, p in ipairs(ns.UI.intraday) do
        if p.t >= GetServerTime() - 2 * 86400 then
          recent[#recent + 1] = p
        end
      end
      ns.UI.intraday = recent
      local points = ns.UI:IntradayPoints()
      assert.is_true(points[1].daily)
      assert.is_true(points[#points].t - points[1].t > 5 * 86400)
      for i = 2, #points do
        assert.is_true(points[i].t > points[i - 1].t)
      end
      ns.UI:DrawItemChart()
      assert.truthy(ns.UI.itemView.legend.text:find("one point a day", 1, true), ns.UI.itemView.legend.text)
      ns.UI:SetRange(30, "30D")
      assert.is_false(ns.UI:ShowingIntraday())
      assert.is_false(ns.UI.chart.message:IsShown())
    end)

    it("the 7-day average on the scan-by-scan ranges rolls hour by hour: one odd scan barely moves it", function()
      seeded()
      local H = 3600
      local base = math.floor(env.now / H) * H
      local xs, values, byDay = {}, {}, {}
      for d = -10, 0 do
        byDay[math.floor(base / 86400) + d] = 100
      end
      for h = 48, 0, -1 do
        xs[#xs + 1], values[#values + 1] = base - h * H, 100
      end
      values[30] = 1000 -- one wild scan
      local ys = ns.UI.RollingAverage(xs, values, byDay)
      assert.are.equal(100, ys[1])
      assert.is_true(ys[30] < 100 + 900 / 168 + 0.001, tostring(ys[30]))
      assert.is_true(ys[30] > 100)
      -- and every step stays that small
      for i = 2, #ys do
        assert.is_true(math.abs(ys[i] - ys[i - 1]) <= 900 / 168 + 0.001)
      end
    end)

    it("after a search of the item on screen, its chart reads only the newer scans; the status row says so", function()
      seeded()
      ns.UI:ShowItem(2589)
      drainJobs()
      assert.is_true(ns.UI:ShowingIntraday())
      local before = #ns.UI.intraday
      local last = ns.UI.intraday[before].t
      local froms = {}
      local intraday = ns.Store.Intraday
      ns.Store.Intraday = function(store, id, from)
        froms[#froms + 1] = from
        return intraday(store, id, from)
      end
      finally(function()
        ns.Store.Intraday = intraday
      end)
      env:fire("AUCTION_HOUSE_SHOW")
      env:advance(60)
      env.ah.commodities[2589] = { { 117, 20 } }
      env:fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
      env:update(1)
      assert.truthy(ns.UI:FooterText():find("Storing scan", 1, true) or ns.UI:FooterText():find("Updating", 1, true))
      env:advance(2)
      drainJobs()
      assert.are.equal(last + 1, froms[#froms]) -- not the whole two days again
      assert.are.equal(before + 1, #ns.UI.intraday) -- the search's point added
      assert.is_nil(ns.UI:FooterText():find("…", 1, true))
    end)

    it("switches the item chart to candles and back", function()
      seeded()
      ns.UI:ShowItem(2589)
      drainJobs()
      ns.UI:SetRange(30, "30D") -- daily candles (7D plots the hourly points)
      local v = ns.UI.itemView
      v.style.byKey.candles.scripts.OnClick(v.style.byKey.candles)
      assert.are.equal("candles", AME_DB.settings.chartStyle)
      assert.is_not_nil(ns.UI.chart.series.candles)
      assert.is_nil(ns.UI.chart.series.market)
      assert.are.equal(10, #ns.UI.candles.xs)
      -- one supply bar per candle, under it
      local function barsUnderCandles()
        local bars, c = ns.UI.chart.series.qty, ns.UI.candles
        assert.are.equal(#c.xs, #bars.xs)
        for i = 1, #c.xs do
          assert.are.equal(c.xs[i], bars.xs[i])
        end
      end
      barsUnderCandles()
      ns.UI:SetRange(7, "7D") -- 6-hour candles from scans and hourly points
      drainJobs()
      assert.is_true(ns.UI:ShowingIntraday())
      barsUnderCandles()
      ns.UI:SetRange(30, "30D")
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
      for k, line in ipairs(lines) do -- label / value rows
        lines[k] = type(line) == "table" and (line[1] .. " " .. line[2]) or line
      end
      assert.truthy(table.concat(lines, "\n"):find("Open"))
      v.style.byKey.line.scripts.OnClick(v.style.byKey.line)
      assert.is_nil(ns.UI.chart.series.candles)
      assert.is_not_nil(ns.UI.chart.series.market)
    end)

    it("Full scan over the auction house window, without a scanning addon: one every 15 minutes", function()
      seeded()
      _G.AuctionHouseFrame = CreateFrame("Frame")
      local asked = 0
      hooksecurefunc(C_AuctionHouse, "ReplicateItems", function()
        asked = asked + 1
      end)
      ns.AME:ScanDiag().lastReplicateAt = nil -- seeded's scans were long enough ago
      env:fire("AUCTION_HOUSE_SHOW")
      local b = ns.ScanButton.button
      assert.is_not_nil(b)
      assert.is_true(b:IsShown())
      assert.are.equal("Full scan", b.label.text)
      b.scripts.OnClick(b)
      assert.are.equal(1, asked)
      assert.are.equal("Scanning...", b.label.text)
      -- beside it, what the scan is doing
      local status = ns.ScanButton.status
      assert.truthy(status.text:find("Waiting for the server", 1, true), status.text)
      local ingest = ns.AME.ingest
      ingest.reading, ingest.progress = true, { done = 2500, total = 10000 }
      ns.ScanButton:Refresh()
      assert.are.equal("Reading auctions 25%", status.text)
      ingest.reading, ingest.requested = false, false
      ns.AME:ScanDiag().readDoneAt, ns.AME:ScanDiag().readItems = GetServerTime(), 6812
      ns.ScanButton:Refresh()
      assert.are.equal("Full scan recorded", status.text)
      -- the scan is read: then the 15 minutes count down
      ns.AME:ScanDiag().readDoneAt = GetServerTime() + 30
      env.now = env.now + 60
      ns.ScanButton:Refresh()
      assert.truthy(b.label.text:find("Full scan in 14:", 1, true), b.label.text)
      b.scripts.OnClick(b)
      assert.are.equal(1, asked)
      assert.is_true(env:chatContains("one full scan every 15 minutes"))
      env:slash("AZEROTHMERCANTILEEXCHANGE", "scan")
      assert.are.equal(1, asked)
      env.now = env.now + 15 * 60
      env:slash("AZEROTHMERCANTILEEXCHANGE", "scan")
      assert.are.equal(2, asked)
      assert.is_true(env:chatContains("full scan started"))
      -- with a scanning addon loaded, it stays out of the way
      _G.Auctionator = {}
      ns.ScanButton:Refresh()
      assert.is_false(b:IsShown())
      _G.Auctionator, _G.AuctionHouseFrame = nil, nil
    end)

    it("Settings, Data: what AME holds per market, the one you're on first", function()
      seeded()
      ns.UI:ShowTab("settings")
      local s = ns.UI.settingsView
      s.scripts.OnShow(s)
      local text = s.storage.text
      assert.truthy(text:find("(this market)", 1, true), text)
      assert.truthy(text:find("history from", 1, true), text)
      assert.truthy(text:find("hourly prices for %d+ of the last 168 hours"), text)
      assert.truthy(text:find("full scans and", 1, true), text)
      assert.truthy(text:find("All markets:", 1, true), text)
      assert.truthy(text:find("Ledger:", 1, true), text)
    end)

    it("Full scan finds the old auction house window too, even when it loads after the event", function()
      seeded()
      env:fire("AUCTION_HOUSE_SHOW") -- no window yet
      assert.is_nil(ns.ScanButton.button)
      _G.AuctionFrame = CreateFrame("Frame")
      env:fire("ADDON_LOADED", "Blizzard_AuctionUI")
      local b = ns.ScanButton.button
      assert.is_not_nil(b)
      assert.is_true(b:IsShown())
      _G.AuctionFrame = nil
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
    local sent, deliver, handlers

    -- protocol: 2 for sync v2 (the default); these tests are v1's unless they say so
    local function bootSync(protocol)
      sent, handlers = {}, {}
      boot({
        pre = function(n)
          n.AME.syncTransport = {
            Register = function(_, prefix, handler)
              handlers[prefix] = handler
              if prefix == "AME1" then
                deliver = handler
              end
            end,
            Send = function(_, prefix, msg, distribution, target)
              sent[#sent + 1] = { prefix = prefix, msg = msg, distribution = distribution, target = target }
            end,
          }
        end,
      })
      if protocol ~= 2 then
        ns.Settings:Set("syncProtocol", 1)
        ns.SyncService:InitV2()
      end
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

    it("shares auction outcomes with the guild; guildmates' count in sell-through and posting advice", function()
      bootSync()
      env.now = env.now - env.now % 86400 + 3600
      fullScan({ { 2589, 1000, 100 } })
      env.now = env.now + 6 * 3600
      fullScan({ { 2589, 1000, 70 } }) -- 120 a day leave the AH
      env:advance(4)
      drainJobs()
      local shard = ns.AME:CurrentShard()
      -- a guildmate listed it 10 times: all 100 units expired, and their posting model learned it sells slower
      local items = ns.SellThrough.EncodeItems({ { 2589, { s = 0, e = 100, c = 0, n = 10 }, -0.5, 10, -1, 10 } })
      deliver(ns.Sync.EncodeOutcomes(shard, env.now, items), "GUILD", "Guild Mate")
      env:advance(61) -- guildmates' numbers are taken in once they have been quiet a minute
      drainJobs()
      local s = ns.AME.index.items[2589]
      assert.are.equal(0, s.sellThrough)
      assert.are.equal(1, s.stPeers)
      assert.truthy(s.sellRate < 30, s.sellRate)
      -- what their listings taught their posting model counts in yours
      local merged =
        ns.SellThrough.MergeProfile(ns.Posting:Profile(shard, 2589), ns.Posting:SharedOutcomes(shard, 2589))
      assert.are.equal(-1, merged.speed)
      assert.are.equal(-0.5, merged.calib)
      -- you share yours: a listing of yours expired
      C_AuctionHouse.PostCommodity({ itemID = 2589 }, 3, 10, 1000)
      env.now = env.now + 24 * 3600
      env:fire("CHAT_MSG_SYSTEM", "Your auction of Item 2589 has expired.")
      local before = #sent
      ns.SyncService:Announce()
      local shared
      for i = before + 1, #sent do
        local m = ns.Sync.Decode(sent[i].msg)
        if m and m.type == "outcomes" then
          shared = m
          assert.are.equal("GUILD", sent[i].distribution)
        end
      end
      assert.is_not_nil(shared)
      assert.are.equal(10, ns.SellThrough.DecodeItems(shared.items)[2589].r.e)
      -- nothing new: not sent again until an hour has passed
      before = #sent
      ns.SyncService:Announce()
      for i = before + 1, #sent do
        assert.are_not.equal("outcomes", (ns.Sync.Decode(sent[i].msg) or {}).type)
      end
      -- a blocked player's numbers don't count
      assert.are.equal(1, ns.Posting:SellThroughTotals(shard)[2589].peers)
      ns.SyncService:Block("Guild Mate")
      assert.are.equal(0, ns.Posting:SellThroughTotals(shard)[2589].peers)
    end)

    it("Sync now: announces ours and asks the guild to announce theirs; queries are answered once", function()
      bootSync()
      fullScan({ { 2589, 1000, 10 } })
      local function kinds(from)
        local out = {}
        for i = from + 1, #sent do
          local m = ns.Sync.Decode(sent[i].msg)
          out[#out + 1] = m and m.type .. ":" .. sent[i].distribution
        end
        return table.concat(out, " ")
      end
      -- the button under Settings, Sharing
      ns.UI:Toggle()
      ns.UI:ShowTab("sync")
      local v = ns.UI.syncView
      v.scripts.OnShow(v)
      local before = #sent
      v.syncNow.scripts.OnClick(v.syncNow)
      assert.truthy(kinds(before):find("query:GUILD", 1, true))
      assert.truthy(kinds(before):find("announce:GUILD", 1, true))
      assert.truthy(v.syncStatus.text:find("latest scans"))
      -- again right away: not yet
      local ok, why = ns.SyncService:SyncNow()
      assert.is_nil(ok)
      assert.truthy(why:find("try again"))
      -- a guildmate pressed it: we announce, once for several askers
      local shard = ns.AME:CurrentShard()
      env.now = env.now + 60
      before = #sent
      deliver(ns.Sync.EncodeQuery(shard), "GUILD", "Guild Mate")
      deliver(ns.Sync.EncodeQuery(shard), "GUILD", "Other Mate")
      assert.are.equal("announce:GUILD", kinds(before))
      -- with sync off, the button says so
      ns.Settings:Set("syncGuild", false)
      ns.Settings:Set("syncTrusted", false)
      env.now = env.now + 60
      v.syncNow.scripts.OnClick(v.syncNow)
      assert.truthy(v.syncStatus.text:find("Sync is off"))
    end)

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

    describe("v2", function()
      local SHARD = "TestRealm|Horde"

      -- A v2 guildmate: their own engine, on the guild channel with us. have: { [objKey] = { payload, t, src, key } }
      local function v2Peer(name)
        local V2 = ns.SyncV2
        local peer = { name = name, have = {}, got = {}, read = #sent }
        local function hours0()
          return math.floor(env.now / 3600), math.floor(env.now / 86400) - 1
        end
        peer.host = {
          Allowed = function()
            return true
          end,
          Shards = function()
            return { SHARD }
          end,
          Manifest = function()
            local hour0, day0 = hours0()
            local m = { scanT = 0, hour0 = hour0, hours = {}, day0 = day0, days = {} }
            for k in pairs(peer.have) do
              local kind, ref = k:match("#(%a)#(%d+)$")
              ref = tonumber(ref)
              if kind == "h" then
                m.hours[ref] = true
              elseif kind == "d" then
                m.days[ref] = true
              else
                m.scanT = math.max(m.scanT, ref)
              end
            end
            return m
          end,
          Has = function(_, shard, kind, ref)
            return peer.have[V2.ObjKey(shard, kind, ref)] ~= nil
          end,
          Wanted = function(_, shard, kind, ref)
            return peer.have[V2.ObjKey(shard, kind, ref)] == nil
          end,
          Wants = function(_, shard, m)
            local out = {}
            if m.scanT > 0 and not peer.have[V2.ObjKey(shard, "s", m.scanT)] then
              out[#out + 1] = { kind = "s", ref = m.scanT }
            end
            for hour in pairs(m.hours) do
              if not peer.have[V2.ObjKey(shard, "h", hour)] then
                out[#out + 1] = { kind = "h", ref = hour }
              end
            end
            return out
          end,
          Object = function(_, shard, kind, ref, done)
            local o = peer.have[V2.ObjKey(shard, kind, ref)]
            done(o and { kind = kind, ref = ref, payload = o[1], t = o[2], src = o[3], key = o[4] })
          end,
          Accept = function(_, shard, obj)
            peer.got[V2.ObjKey(shard, obj.kind, obj.ref)] = obj
          end,
        }
        peer.engine = V2.New({
          name = name,
          send = function(msg)
            handlers.AME2(msg, "GUILD", name)
          end,
          now = GetTime,
          after = function(seconds, fn)
            C_Timer.After(seconds, fn)
          end,
          random = math.random,
          host = peer.host,
        })
        -- what we sent on the v2 prefix reaches them
        function peer:pump()
          for i = self.read + 1, #sent do
            if sent[i].prefix == "AME2" then
              self.engine:OnMessage(sent[i].msg, "Tyken")
            end
          end
          self.read = #sent
        end
        return peer
      end

      -- time passes for us and the guildmate
      local function run(peer, seconds)
        for _ = 1, seconds * 2 do
          env:advance(0.5)
          drainJobs()
          peer:pump()
        end
      end

      -- the guildmate's own history (a store of their own), with a full scan at t
      local function peerHistory(t, prices)
        local data = {}
        local store = ns.Store.New(data, {
          compressor = ns.AME.compressor,
          now = function()
            return env.now
          end,
        })
        local acc = ns.Stats.NewAccumulator()
        for id, p in pairs(prices) do
          acc:Add(id, p, 5)
        end
        store:AddScan(acc:Finish(), t, "Guild Mate")
        return data, store
      end

      local function v2Sent(from)
        local out = {}
        for i = from + 1, #sent do
          if sent[i].prefix == "AME2" then
            out[#out + 1] = sent[i]
          end
        end
        return out
      end

      it("our full scan goes to the guild once, paced, and arrives whole", function()
        bootSync(2)
        local peer = v2Peer("Guild Mate")
        local before = #sent
        fullScan({ { 2589, 1000, 10 }, { 4306, 900, 4 } })
        run(peer, 60)
        local mine = AME_HistoryDB.shards[SHARD].raw[1]
        local got = peer.got[ns.SyncV2.ObjKey(SHARD, "s", mine.t)]
        assert.is_not_nil(got)
        assert.are.equal(mine.s, ns.AME.compressor:Unwire(got.payload))
        assert.are.equal("Tyken", got.src)
        -- over v2 only: no v1 announcement to the guild (nobody's on v1)
        local v1Guild = 0
        for i = before + 1, #sent do
          local s = sent[i]
          if s.prefix == "AME1" and s.distribution == "GUILD" and ns.Sync.Decode(s.msg).type == "announce" then
            v1Guild = v1Guild + 1
          end
        end
        assert.are.equal(0, v1Guild)
        for _, s in ipairs(v2Sent(before)) do
          assert.are.equal("GUILD", s.distribution)
          assert.truthy(#s.msg <= 255, #s.msg)
        end
      end)

      it("asks for hours it lacks, merges them into the chart and the day, and serves them on", function()
        bootSync(2)
        fullScan({ { 2589, 1000, 10 } })
        local peer = v2Peer("Guild Mate")
        local t = env.now - 5 * 3600
        local pdata = peerHistory(t, { [2589] = 1100, [4306] = 900 })
        local hour = math.floor(t / 3600)
        local e = pdata.hours[hour]
        peer.have[ns.SyncV2.ObjKey(SHARD, "h", hour)] = { ns.AME.compressor:Wire(e.s), e.t, e.src, e.key }
        peer.engine:Announce()
        run(peer, 60)
        local data = AME_HistoryDB.shards[SHARD]
        assert.is_not_nil(data.hours[hour])
        assert.are.equal(e.s, data.hours[hour].s)
        assert.are.equal("Guild Mate", data.hours[hour].src)
        assert.is_true(data.seen[math.floor(t / 86400)][e.key]) -- in the day's numbers, once
        assert.is_true(AME_DB.stats.syncReceived >= 1)
        -- the item chart's 7D range plots it
        local pts
        ns.AME:WithStore("t", SHARD, function(store)
          return store:Intraday(4306, env.now - 7 * 86400)
        end, function(_, p)
          pts = p
        end)
        drainJobs()
        assert.are.equal(1, #pts)
        assert.are.equal("hour", pts[1].kind)
        -- another guildmate without it gets it from us
        local other = v2Peer("Other Mate")
        ns.SyncService:Announce()
        run(other, 120)
        assert.is_not_nil(other.got[ns.SyncV2.ObjKey(SHARD, "h", hour)])
      end)

      it("takes a whole day it has nothing of", function()
        bootSync(2)
        fullScan({ { 2589, 1000, 10 } })
        local peer = v2Peer("Guild Mate")
        local day = math.floor(env.now / 86400) - 2
        local _, pstore = peerHistory(day * 86400 + 3600, { [2589] = 1100 })
        peer.have[ns.SyncV2.ObjKey(SHARD, "d", day)] = { ns.AME.compressor:Wire(pstore:ExportDay(day)), day * 86400 }
        -- this guildmate's manifest lists the day; we ask for it (days aren't in the test peer's Wants: it's us asking)
        peer.engine:Announce()
        run(peer, 60)
        local data = AME_HistoryDB.shards[SHARD]
        assert.is_not_nil(data.days[day])
        assert.are.same(pstore.data.days[day], data.days[day])
        assert.are.same(pstore.data.seen[day], data.seen[day]) -- with the scans it holds, so none comes twice
        assert.are.equal(
          1,
          #ns.Store.New(data, { compressor = ns.AME.compressor, now = GetServerTime }):Series(2589, day, day)
        )
      end)

      it("a blocked guildmate's objects aren't taken", function()
        bootSync(2)
        fullScan({ { 2589, 1000, 10 } })
        ns.SyncService:Block("Guild Mate")
        local peer = v2Peer("Guild Mate")
        local t = env.now - 5 * 3600
        local pdata = peerHistory(t, { [2589] = 1100 })
        local hour = math.floor(t / 3600)
        local e = pdata.hours[hour]
        peer.have[ns.SyncV2.ObjKey(SHARD, "h", hour)] = { ns.AME.compressor:Wire(e.s), e.t, e.src, e.key }
        peer.engine:Push(SHARD, "h", hour)
        run(peer, 60)
        assert.is_nil(AME_HistoryDB.shards[SHARD].hours[hour])
      end)

      it("serves v1 players alongside: announces over v1 while one is around, and takes their scans", function()
        bootSync(2)
        fullScan({ { 2589, 1000, 10 } })
        local function v1Announces(from)
          local n = 0
          for i = from + 1, #sent do
            local s = sent[i]
            if s.prefix == "AME1" and s.distribution == "GUILD" and ns.Sync.Decode(s.msg).type == "announce" then
              n = n + 1
            end
          end
          return n
        end
        local before = #sent
        ns.SyncService:Announce()
        assert.are.equal(0, v1Announces(before))
        -- a v1 player announces: we request their scan over v1, and announce over v1 from now on
        local entry = peerScan({ [2589] = 1200 })
        entry.src = "Old Timer"
        deliver(ns.Sync.EncodeAnnounce(SHARD, { { t = entry.t, src = entry.src } }), "GUILD", "Old Timer")
        assert.are.equal("request", ns.Sync.Decode(sent[#sent].msg).type)
        assert.are.equal("Old Timer", sent[#sent].target)
        before = #sent
        ns.SyncService:Announce()
        assert.are.equal(1, v1Announces(before))
        -- a v2 player's v1 announcement (sent because of the v1 player) isn't asked for over v1
        handlers.AME2(
          ns.SyncV2.EncodeManifest(SHARD, { hour0 = 1, hours = {}, day0 = 1, days = {} }),
          "GUILD",
          "New Mate"
        )
        before = #sent
        deliver(ns.Sync.EncodeAnnounce(SHARD, { { t = entry.t + 60, src = "New Mate" } }), "GUILD", "New Mate")
        assert.are.equal(before, #sent)
        -- on v1 (the setting), no v2 at all
        ns.Settings:Set("syncProtocol", 1)
        ns.SyncService:InitV2()
        assert.is_nil(ns.SyncService.v2)
        before = #sent
        ns.SyncService:Announce()
        assert.are.equal(0, #v2Sent(before))
        assert.are.equal(1, v1Announces(before))
      end)

      it("Settings, Sharing: the protocol switch, and how many of the week's hours are here", function()
        bootSync(2)
        fullScan({ { 2589, 1000, 10 } })
        ns.UI:Toggle()
        ns.UI:ShowTab("sync")
        local v = ns.UI.syncView
        v.scripts.OnShow(v)
        local function choose(i)
          local it = v.protocol.menu.items[i]
          it.scripts.OnClick(it)
        end
        assert.are.equal(1, v.protocol.index) -- v2
        assert.truthy(v.activity.text:find("Hours of the last week here: 1 of 168", 1, true), v.activity.text)
        -- a catch-up: a dozen objects queued from one guildmate read as one line, with the time left
        local incoming = ns.SyncService.v2.incoming
        for i = 1, 12 do
          incoming["Guild Mate#" .. i] =
            { kind = "h", ref = i, got = i == 1 and 50 or 0, n = 100, sender = "Guild Mate" }
        end
        ns.UI:RefreshSync()
        local lines = 0
        for _ in v.activity.text:gmatch("Receiving from") do
          lines = lines + 1
        end
        assert.are.equal(1, lines)
        assert.truthy(
          v.activity.text:find("Receiving from Guild Mate: 12 objects, 4%% %(~21 min left%)"),
          v.activity.text
        )
        for k in pairs(incoming) do
          incoming[k] = nil
        end
        choose(2) -- v1
        assert.are.equal(1, ns.Settings:Get("syncProtocol"))
        assert.is_nil(ns.SyncService.v2)
        assert.truthy(v.syncStatus.text:find("/reload", 1, true))
        assert.is_nil(v.activity.text:find("Hours of the last week", 1, true))
        choose(1)
        assert.is_not_nil(ns.SyncService.v2)
      end)

      it("asks for every hour before any whole day, and not for a day whose hours are coming", function()
        bootSync(2)
        fullScan({ { 2589, 1000, 10 } })
        local host = ns.SyncService:V2Host()
        local today = math.floor(env.now / 86400)
        local recent = math.floor(env.now / 3600) - 3
        local inDay = (today - 3) * 24 + 12 -- noon, three days ago
        local wants = host:Wants(SHARD, {
          scanT = 0,
          hours = { [recent] = true, [inDay] = true },
          days = { [today - 3] = true, [today - 5] = true },
        })
        local got = {}
        for _, w in ipairs(wants) do
          got[#got + 1] = w.kind .. ":" .. w.ref
        end
        assert.are.same({ "h:" .. recent, "h:" .. inDay, "d:" .. (today - 5) }, got)
      end)

      it("in combat, blocks still arrive, but checking and storing them waits until it ends", function()
        bootSync(2)
        fullScan({ { 2589, 1000, 10 } })
        local peer = v2Peer("Guild Mate")
        local t = env.now - 5 * 3600
        local pdata = peerHistory(t, { [2589] = 1100, [4306] = 900 })
        local hour = math.floor(t / 3600)
        local e = pdata.hours[hour]
        peer.have[ns.SyncV2.ObjKey(SHARD, "h", hour)] = { ns.AME.compressor:Wire(e.s), e.t, e.src, e.key }
        local fighting = true
        _G.InCombatLockdown = function()
          return fighting
        end
        finally(function()
          _G.InCombatLockdown = nil
        end)
        peer.engine:Announce()
        for _ = 1, 120 do
          env:advance(0.5)
          env:update(1)
          peer:pump()
        end
        local data = AME_HistoryDB.shards[SHARD]
        assert.are.equal(1, ns.SyncService.v2.stats.objectsReceived) -- all its blocks are here
        assert.is_nil(data.hours[hour]) -- not checked or stored yet
        assert.is_true(ns.AME.jobs:Busy())
        fighting = false
        run(peer, 10)
        assert.are.equal(e.s, data.hours[hour].s)
      end)

      it("Players heard from: v1 or v2 per player, a summary, and Show all for a big guild", function()
        bootSync(2)
        fullScan({ { 2589, 1000, 10 } })
        local peer = v2Peer("Guild Mate") -- on v2 only: heard all the same
        peer.engine:Announce()
        run(peer, 60) -- everything it had to say
        deliver(ns.Sync.EncodeAnnounce(SHARD, {}), "GUILD", "Old Timer") -- on v1
        env.now = env.now + 60
        for i = 1, 30 do
          deliver(ns.Sync.EncodeHello(SHARD), "GUILD", "Member" .. i)
        end
        ns.UI:Toggle()
        ns.UI:ShowTab("sync")
        local v = ns.UI.syncView
        v.scripts.OnShow(v)
        local function rowOf(name)
          for _, r in ipairs(v.peers) do
            if r:IsShown() and r.name == name then
              return r
            end
          end
        end
        assert.truthy(v.peerSummary.text:find("32 players", 1, true), v.peerSummary.text)
        assert.truthy(v.peerSummary.text:find("1 on v2, 1 on v1", 1, true), v.peerSummary.text)
        -- the five heard from last, then Show all, by name
        assert.is_nil(rowOf("Guild Mate"))
        assert.truthy(v.peersMore.label.text:find("Show all 32", 1, true))
        v.peersMore.scripts.OnClick(v.peersMore)
        assert.truthy(rowOf("Guild Mate").state.text:find("v2", 1, true))
        assert.truthy(rowOf("Old Timer").state.text:find("v1", 1, true))
        assert.are.equal("Guild Mate", v.peers[1].name) -- by name
        v.peersMore.scripts.OnClick(v.peersMore)
        assert.is_nil(rowOf("Guild Mate"))
      end)

      it("keeps a transfer that's under way for a /reload", function()
        bootSync(2)
        fullScan({ { 2589, 1000, 10 } })
        local peer = v2Peer("Guild Mate")
        local t = env.now - 5 * 3600
        local many = {}
        for id = 1000, 1400 do
          many[id] = 1000 + (id * 7919) % 50000
        end
        local pdata = peerHistory(t, many)
        local hour = math.floor(t / 3600)
        local e = pdata.hours[hour]
        local payload = ns.AME.compressor:Wire(e.s)
        assert.truthy(#payload > 2 * ns.SyncV2.BLOCK, #payload) -- several blocks
        peer.have[ns.SyncV2.ObjKey(SHARD, "h", hour)] = { payload, e.t, e.src, e.key }
        peer.engine:Push(SHARD, "h", hour)
        env:advance(0.1) -- the offer
        env:advance(1.1) -- the first block
        ns.SyncService:SaveV2()
        local saved = AME_DB.sync.v2Partial
        assert.is_not_nil(saved)
        assert.are.equal(1, #saved.items)
        assert.are.equal("Guild Mate", saved.items[1].sender)
        local got = ns.SyncService.v2:Status().receiving[1].got
        assert.truthy(got >= 1)
        for _, b in pairs(saved.items[1].blocks) do
          assert.is_nil(b:find("[^%w%(%)]")) -- print-safe in the saved file (EncodeForPrint's alphabet)
        end
        -- after the /reload: picked up where it was, and the rest arrives
        ns.SyncService:InitV2()
        assert.are.equal(got, ns.SyncService.v2:Status().receiving[1].got)
        run(peer, 120)
        assert.are.equal(e.s, AME_HistoryDB.shards[SHARD].hours[hour].s)
      end)
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

    it("stops whispering a player who logged off mid-transfer, and hides the bounce", function()
      bootSync()
      fullScan({ { 2589, 1000, 10 } })
      local mine = AME_HistoryDB.shards["TestRealm|Horde"].raw[1]
      deliver(ns.Sync.EncodeRequest("TestRealm|Horde", mine.t, mine.src), "WHISPER", "Guild Mate")
      assert.are.equal("Guild Mate", sent[#sent].target)
      -- the rest of the scan still queued in ChatThrottleLib, to them and to the guild
      local function send() end
      local toThem = { "AME1", "chunk", "WHISPER", "Guild Mate", f = send, nSize = 255, n = 4 }
      local toGuild = { "AME1", "announce", "GUILD", f = send, nSize = 100, n = 3 }
      _G.ChatThrottleLib = { Prio = { BULK = { ByName = { AME1 = { toThem, toGuild } } } } }
      -- they log off: the game says so for the next chunk
      local bounce = "No player named 'Guild Mate' is currently playing."
      assert.is_true(ns.SyncService:ChatFilter(bounce)) -- hidden from chat
      assert.is_false(ns.SyncService:ChatFilter("No player named 'Someone Else' is currently playing."))
      assert.is_true(ns.SyncService:OnSystemMessage(bounce))
      assert.are_not.equal(send, toThem.f) -- their chunk drains without being sent
      assert.are.equal(send, toGuild.f) -- the guild's traffic goes on
      -- no more whispers to them for a while
      local before = #sent
      deliver(ns.Sync.EncodeRequest("TestRealm|Horde", mine.t, mine.src), "WHISPER", "Other Mate")
      assert.are.equal(before + 1, #sent)
      ns.SyncService.transport:Send("AME1", "x", "WHISPER", "Guild Mate")
      assert.are.equal(before + 1, #sent)
      -- heard from again: back online
      deliver(ns.Sync.EncodeRequest("TestRealm|Horde", mine.t, mine.src), "WHISPER", "Guild Mate")
      assert.are.equal("Guild Mate", sent[#sent].target)
      _G.ChatThrottleLib = nil
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
      local svc = ns.SyncService
      -- roster updates fire whenever anyone logs on or off: the guild info is re-read at most once a minute
      env:fire("GUILD_ROSTER_UPDATE")
      env:advance(svc.GUILD_INFO_EVERY)
      assert.are.equal("guild", svc.trust:IsBlocked("Price Fixer"))
      -- in combat the game blocks reading it: it waits until combat ends
      _G.GetGuildInfoText = function()
        return "AME block: Price Fixer, Second Fixer"
      end
      _G.InCombatLockdown = function()
        return true
      end
      env:advance(svc.GUILD_INFO_EVERY)
      env:fire("GUILD_ROSTER_UPDATE")
      assert.is_falsy(svc.trust:IsBlocked("Second Fixer"))
      _G.InCombatLockdown = function()
        return false
      end
      env:fire("PLAYER_REGEN_ENABLED")
      assert.are.equal("guild", svc.trust:IsBlocked("Second Fixer"))
      _G.InCombatLockdown = nil
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

    it("shares watchlists with the guild and shows guild members' lists in the sidebar", function()
      bootSync()
      local watch = ns.AME.watch
      watch:Toggle(1, 2589)
      ns.UI:Toggle()
      ns.UI:ShowTab("market")
      -- right-click my list > Share with guild
      ns.UI:ListMenu(ns.UI.marketView.side.lines[3], 1)
      local share = ns.Widgets.menu.items[1]
      share.scripts.OnClick(share)
      assert.is_true(watch:Lists()[1].shared)
      env:advance(3)
      local m = ns.Sync.Decode(sent[#sent].msg)
      assert.are.equal("watchlist", m.type)
      assert.are.equal("GUILD", sent[#sent].distribution)
      assert.are.same({ 2589 }, m.ids)
      -- a guild member shares theirs; whispered or blocked lists are ignored
      deliver(ns.Sync.EncodeWatchlist("TestRealm|Horde", "Herbs", env.now, { 2589, 4306 }), "GUILD", "Guild Mate")
      deliver(ns.Sync.EncodeWatchlist("TestRealm|Horde", "Spam", env.now, { 1 }), "WHISPER", "Guild Mate")
      assert.are.equal(1, #watch:GuildLists())
      local v = ns.UI.marketView
      ns.UI:RenderCategories()
      local line
      for _, l in ipairs(v.side.lines) do
        local e = rawget(l, "entry")
        if type(e) == "table" and e.guild then
          line = l
        end
      end
      assert.are.equal("Guild Mate/Herbs", line.entry.guild)
      line.scripts.OnClick(line, "LeftButton")
      assert.are.equal("g:Guild Mate/Herbs", ns.UI.mq.list)
      -- copy it
      line.scripts.OnClick(line, "RightButton")
      local copy = ns.Widgets.menu.items[1]
      copy.scripts.OnClick(copy)
      assert.are.equal("Herbs (Guild Mate)", watch:Lists()[2].name)
      -- unsharing tells the guild to drop it
      ns.UI:ListMenu(v.side.lines[3], 1)
      share = ns.Widgets.menu.items[1]
      share.scripts.OnClick(share)
      env:advance(3)
      local gone = ns.Sync.Decode(sent[#sent].msg)
      assert.are.equal("Watchlist", gone.name)
      assert.are.same({}, gone.ids)
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
      -- never yourself: WoW Forever names senders "Name Suffix", and alts on this account share AME's data
      AME_DB.holdings["TestRealm:Altchar"] = { bags = {} }
      deliver(ns.Sync.EncodeHello("TestRealm|Horde"), "GUILD", "Tyken Evanion")
      deliver(ns.Sync.EncodeHello("TestRealm|Horde"), "GUILD", "Tyken-OtherRealm")
      assert.is_nil(ns.SyncService.trust.db.peers["tyken evanion"])
      ns.SyncService.trust:Heard("Altchar Evanion", env.now, "GUILD") -- heard before AME knew the alt
      ns.SyncService.trust:Heard("Guild Mate", env.now, "GUILD")
      ns.UI:RefreshSync()
      local listed = {}
      for _, row in ipairs(v.peers) do
        if row.name then
          listed[row.name] = true
        end
      end
      assert.is_true(listed["Guild Mate"])
      assert.is_nil(listed["Altchar Evanion"])
      assert.is_nil(listed["Tyken Evanion"])
      assert.is_nil(ns.SyncService:Block("Tyken Evanion"))
      assert.is_nil(ns.SyncService:Block("Altchar"))
      v.input:SetText("Altchar")
      v.input.scripts.OnEnterPressed(v.input)
      assert.truthy(v.addStatus.text:find("one of your characters"))
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
      -- chart clicks are off by default (loot addons such as Gargul use modified clicks on items and links)
      assert.are.equal("none", ns.Settings:Get("clickModifier"))
      local altShift = s.click.menu.items[3]
      altShift.scripts.OnClick(altShift)
      assert.are.equal("altshift", ns.Settings:Get("clickModifier"))
      local ctrlAlt = s.click.menu.items[4]
      ctrlAlt.scripts.OnClick(ctrlAlt)
      assert.are.equal("ctrlalt", ns.Settings:Get("clickModifier"))
      assert.truthy(s.storage.text:find("Ledger:", 1, true), s.storage.text)
      env:slash("AZEROTHMERCANTILEEXCHANGE", "config")
      assert.are.equal("settings", ns.UI.current)
      env:slash("AZEROTHMERCANTILEEXCHANGE", "sync") -- Settings, Sharing
      assert.are.equal("settings", ns.UI.current)
      assert.are.equal("sharing", ns.UI.settingsView.current)
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
