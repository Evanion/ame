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
      for _, name in ipairs({ "market", "item", "arbitrage", "portfolio", "sync", "settings", "guide" }) do
        assert.is_not_nil(ns.UI.views[name], name)
      end
      drainJobs() -- item facts for the index load in the background
      assert.is_not_nil(rawget(ns.ItemCache.info, 2589))
      ns.UI:Toggle() -- opening is now just showing
      assert.is_true(ns.UI.frame:IsShown())
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
        assert.truthy(table.concat(why, " "):find("needs 7 days of history"))
        local sig, head2 = ns.UI.Verdict(
          { days = 20, scans7 = 10, day = 5, market = 300, avg30 = 400, phase = "dumping", sellRate = 50 },
          { signal = "wait", today = 5 }
        )
        assert.are.equal("wait", sig)
        assert.are.equal("Cheap, but still falling", head2)
        -- legend: one line per series, hidden while hovering the plot
        assert.truthy(v.legend.text:find("Market"))
        assert.truthy(v.legend.text:find("\n"))
        ns.UI.chart.frame.scripts.OnEnter(ns.UI.chart.frame)
        assert.is_false(v.legendBox:IsShown())
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
      -- category sidebar: All items, watchlists, "+ New list", then classes; clicking a class filters to it
      local classLine = v.side.lines[6]
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

    it("settings: Basic / Advanced, the colour-blind palette; sync: freshness per auction house", function()
      seeded()
      ns.UI:Toggle()
      ns.UI:ShowTab("settings")
      local s = ns.UI.settingsView
      s.scripts.OnShow(s)
      assert.are.equal("basic", s.level:Selected())
      for _, obj in ipairs(s.advanced) do
        assert.is_false(obj:IsShown())
      end
      s.level.byKey.advanced.scripts.OnClick(s.level.byKey.advanced)
      assert.are.equal("advanced", AME_DB.settings.settingsLevel)
      for _, obj in ipairs(s.advanced) do
        assert.is_true(obj:IsShown())
      end
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
        local text = (a.title .. table.concat(a.body, " ")):lower()
        assert.truthy(text:find("deposit"), a.key)
      end
      assert.is_false(guide.byKey.commands.link:IsShown()) -- doesn't mention deposits
      guide.search:SetText("")
      guide.search.scripts.OnTextChanged(guide.search, true)
      assert.is_true(guide.byKey.commands.link:IsShown())
      assert.are.equal("Market", guide.byKey.tabMarket.link.text.text) -- the sidebar label, not "Market tab"
      guide.byKey.tabMarket.link.scripts.OnClick(guide.byKey.tabMarket.link)
      assert.are.equal("Market tab", guide.title.text) -- the article keeps its full title
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
      assert.is_nil(ns.UI.chart.series.sma)
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

    it("learns each item's market from scans, suggests posting prices, and learns from your posts", function()
      seeded()
      local shard = ns.AME:CurrentShard()
      local profile = ns.Posting:Profile(shard, 2589)
      assert.truthy(profile.n >= 1) -- consecutive daily scans
      assert.truthy(AME_DB.pricing[shard][2589]:find(";")) -- saved compactly
      local advice = ns.Posting:Suggest(shard, 2589, 5, 24)
      assert.is_not_nil(advice)
      assert.truthy(advice.quick.price <= advice.normal.price and advice.normal.price <= advice.patient.price)
      assert.truthy(advice.deposit >= 100) -- 1 silver minimum per post
      -- you post 5 at the suggested price: recorded with the model's chance
      C_AuctionHouse.PostCommodity({ itemID = 2589 }, 3, 5, advice.normal.price)
      assert.are.equal(1, #AME_DB.listings)
      assert.are.equal(24, AME_DB.listings[1].hours)
      assert.is_number(AME_DB.listings[1].chance)
      -- it sold: the outcome calibrates the item
      env:fire("CHAT_MSG_SYSTEM", "A buyer has been found for your auction of Item 2589.")
      assert.are.equal(0, #AME_DB.listings)
      assert.are.equal(1, ns.Posting:Profile(shard, 2589).no)

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
      assert.is_false(bar.fill:IsShown()) -- the choices fill their own prices: no extra button
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
      assert.is_true(bar.fill:IsShown()) -- "Use X": just under the listing you clicked
      assert.truthy(bar.fill.label.text:find("^Use"))
      bar.fill.scripts.OnClick(bar.fill)
      assert.are.equal(listing - 1, filled)
      env:update(40)
      assert.truthy(bar.title.text:find("Under that listing")) -- our own fill isn't a new target
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

    it("switches the item chart to candles and back", function()
      seeded()
      ns.UI:ShowItem(2589)
      drainJobs()
      local v = ns.UI.itemView
      v.style.byKey.candles.scripts.OnClick(v.style.byKey.candles)
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
      for k, line in ipairs(lines) do -- label / value rows
        lines[k] = type(line) == "table" and (line[1] .. " " .. line[2]) or line
      end
      assert.truthy(table.concat(lines, "\n"):find("Open"))
      v.style.byKey.line.scripts.OnClick(v.style.byKey.line)
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
