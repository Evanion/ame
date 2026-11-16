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

    assert.is_true(env:chatContains("recorded full scan: 2 items from 3 listings %(TestRealm|Neutral%)"))
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

  it("survives a client that lacks some events", function()
    boot({ unknownEvents = { COMMODITY_SEARCH_RESULTS_UPDATED = true } })
    env:fire("AUCTION_HOUSE_SHOW")
    fullScan({ { 1, 100, 1 } })
    assert.is_true(env:chatContains("recorded full scan"))
  end)

  it("/ame selftest runs every check and schedules a reload", function()
    boot()
    env.npcFaction = "Horde"
    env:fire("AUCTION_HOUSE_SHOW")
    fullScan({ { 2589, 1000, 10 }, { 4306, 5000, 5 } })
    env:slash("AZEROTHMERCANTILEEXCHANGE", "selftest")
    assert.is_true(env:chatContains("selftest: %d+ passed, %d+ warnings, 0 failed"))
    env:advance(6)
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
      deliver(ns.Sync.EncodeScan("TestRealm|Horde", peerScan(prices)), "WHISPER", "Guild Mate")
      drainJobs()
      assert.are.equal(1, AME_DB.stats.syncRejected)
      assert.are.equal(1, #AME_HistoryDB.shards["TestRealm|Horde"].raw)
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
