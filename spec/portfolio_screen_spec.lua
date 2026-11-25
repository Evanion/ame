-- Core/PortfolioPage.lua and the Portfolio tab's screens (Portfolio, Sell and Auctions at the auction house): the
-- rows, cards and standings from facts, and each screen's tree in each of its states.
local wow = require("spec.helpers.wow")
local addon = require("spec.helpers.addon")

describe("Portfolio page", function()
  local env, ns, P

  before_each(function()
    env = wow.install()
    ns = addon.load({
      "Core/Init.lua",
      "Core/Settings.lua",
      "Core/ItemCache.lua",
      "Core/Portfolio.lua",
      "Core/UI/Tokens.lua",
      "Core/UI/Kit.lua",
      "Core/UI/Layout.lua",
      "Core/UI/Widgets.lua",
      "Core/UI/AHSelling.lua",
      "Core/PortfolioPage.lua",
    })
    _G.AME_DB = { settings = {}, listings = {} }
    P = ns.PortfolioPage
  end)

  after_each(function()
    env:restore()
  end)

  describe("Where", function()
    local holdings = {
      ["Forever:Tyken"] = { bags = { [10] = 10 }, bank = {} },
      ["Forever:Kke"] = { bags = {}, bank = { [10] = 8, [11] = 6 } },
    }
    it("one character, one place: the place alone", function()
      assert.equals("Kke · bank", P.Where(11, { chars = { ["Forever:Kke"] = 6 } }, holdings))
    end)
    it("several characters: the first's place and count, then the others", function()
      assert.equals(
        "Tyken · bags 10, Kke 8",
        P.Where(10, { chars = { ["Forever:Tyken"] = 10, ["Forever:Kke"] = 8 } }, holdings)
      )
    end)
  end)

  it("Since: a range's start; since reset uses the time to the next reset", function()
    assert.equals(0, P.Since("all", 1000000))
    assert.equals(1000000 - 7 * 86400, P.Since("7", 1000000))
    assert.equals(1000000 + 3600 - 86400, P.Since("reset", 1000000, 3600))
  end)

  describe("Standing", function()
    local a = { unit = 48600 }
    it("not searched yet", function()
      assert.equals("unchecked", P.Standing(a, nil).kind)
    end)
    it("not searched yet, with a full scan: the scan's lowest, as Home counts it", function()
      local st = P.Standing(a, nil, 48000)
      assert.equals("scanUndercut", st.kind)
      assert.equals(600, st.by)
      assert.equals("scanLowest", P.Standing(a, nil, 48600).kind)
      -- a search, once there is one, wins over the scan
      assert.equals("only", P.Standing(a, { rows = { { price = 48600, qty = 5, mine = true } } }, 48000).kind)
    end)
    it("counts and filters undercut by the scan the same as by a search", function()
      local rows, sum = P.AuctionRows(
        { { itemID = 1, unit = 500, total = 500 }, { itemID = 2, unit = 300, total = 300 } },
        {},
        {
          undercutOnly = true,
          scanMin = function(id)
            return id == 1 and 400 or 300
          end,
        }
      )
      assert.equals(1, sum.undercut)
      assert.equals(1, #rows)
      assert.equals(1, rows[1].item)
    end)
    it("only yours on sale: the only one", function()
      assert.equals("only", P.Standing(a, { rows = { { price = 48600, qty = 5, mine = true } } }).kind)
    end)
    it("cheaper listings than yours: undercut, by how much, how many ahead", function()
      local st = P.Standing(
        a,
        { rows = { { price = 48100, qty = 4 }, { price = 48300, qty = 10 }, { price = 48600, qty = 5, mine = true } } }
      )
      assert.equals("undercut", st.kind)
      assert.equals(500, st.by)
      assert.equals(2, st.ahead)
      assert.equals(14, st.units)
      assert.equals(48100, st.lowest)
    end)
    it("yours the cheapest: lowest", function()
      local st = P.Standing(
        { unit = 2600 },
        { rows = { { price = 2600, qty = 40, mine = true }, { price = 2700, qty = 3 } } }
      )
      assert.equals("lowest", st.kind)
      assert.equals(2600, st.lowest)
    end)
  end)

  it("AuctionRows: filters, counts, cancel only for this character's at the auction house", function()
    local auctions = {
      { itemID = 1, qty = 5, unit = 100, total = 500, char = "Tyken", auctionID = 7 },
      { itemID = 2, qty = 1, unit = 900, total = 900, char = "Zakzu" },
    }
    local books = { [1] = { at = 50, rows = { { price = 90, qty = 2 } } } }
    local rows, sum = P.AuctionRows(auctions, books, { me = "Tyken", atAH = true, now = 100 })
    assert.equals(2, sum.count)
    assert.equals(1, sum.undercut)
    assert.equals(1400, sum.asking)
    assert.equals(50, sum.checked)
    assert.equals("Cancel", rows[1].cancel)
    assert.is_false(rows[2].cancel)
    assert.is_true(rows[2].faded)
    local only = P.AuctionRows(auctions, books, { me = "Tyken", undercutOnly = true })
    assert.equals(1, #only)
    assert.is_false(only[1].cancel) -- away from the auction house
  end)

  it("FillAuctionIDs: this character's saved auctions take the game's IDs, each once", function()
    local auctions =
      { { itemID = 1, qty = 5, unit = 100, char = "Tyken" }, { itemID = 1, qty = 5, unit = 100, char = "Tyken" } }
    P.FillAuctionIDs(
      auctions,
      { { auctionID = 3, key = 1, qty = 5, unit = 100 }, { auctionID = 4, key = 1, qty = 5, unit = 100 } },
      "Tyken"
    )
    assert.equals(3, auctions[1].auctionID)
    assert.equals(4, auctions[2].auctionID)
  end)

  it("Ladder: Quick left out when no cheaper than Normal, Market apart, the pick selected", function()
    local advice = {
      quick = { price = 11800, hours = 1 },
      normal = { price = 11800, hours = 6 },
      patient = { price = 12400, hours = 24 },
      market = { price = 12000 },
      quickSame = true,
    }
    local picks, keys = P.Ladder(advice, "normal")
    assert.same({ "normal", "patient", "market" }, keys)
    assert.is_true(picks[1].selected)
    assert.is_true(picks[3].apart)
    assert.equals("the market price", picks[3].when)
  end)

  it("bag rows: Sell first, the most worth first; Vendor faded; the next Sell row after one", function()
    local entries = {
      { key = 3, qty = 8, signal = "vendor", where = "vendor", worth = 480 },
      { key = 1, qty = 43, where = "ah", worth = 482000 },
      { key = 2, qty = 1, where = "ah", worth = 210000 },
      { key = 4, qty = 1, signal = "disenchant", where = "ah", worth = 9000 },
    }
    P.SortBags(entries)
    local rows = P.BagRows(entries)
    assert.same({ "1", "2", "4", "3" }, { rows[1].key, rows[2].key, rows[3].key, rows[4].key })
    assert.equals("Sell", rows[1].tip.text)
    assert.equals("disenchant", rows[3].tip.color)
    assert.is_true(rows[4].faded)
    assert.equals(2, P.NextSell(entries, 1).key)
    assert.equals(1, P.NextSell(entries, 2).key)
    assert.is_nil(P.NextSell(entries, 1, { ["2"] = true }))
  end)

  it("Kpis: the listed card names the undercut ones; flow as sold / bought", function()
    local k = P.Kpis({
      totals = { value = 204100, unrealized = 11200 },
      listed = { count = 3, value = 140000 },
      summary = { profit = 7012, income = 7012, spent = 30000 },
    }, "7 days", 1)
    assert.equals(5, #k)
    assert.equals("3 auctions · 1 undercut", k[2].delta)
    assert.equals("bad", k[2].deltaTone)
    assert.equals("Realized profit · 7 days", k[4].label)
    assert.is_string(k[5].value)
  end)

  it("Craft card: crafts from what you hold, the leftover named", function()
    local c = P.CraftCard({
      key = 10,
      qty = 25,
      summary = { market = 300 },
      craft = {
        product = 20,
        each = 420,
        raw = 284,
        crafter = "Tyken",
        recipe = { id = 5, made = 1, reagents = { { 10, 4 } } },
      },
    })
    assert.equals(6, c.crafts)
    assert.equals(1, c.left)
    assert.equals(4, #c.rows)
    assert.equals(math.floor((420 - 284) * 24 + 0.5), c.rows[3].copper)
  end)

  describe("the screens", function()
    local App, facts

    local function stand(name, props)
      if not ns.Layout.Get(name) then
        ns.Layout.Register(name, {
          props = props,
          create = function(parent)
            return CreateFrame("Frame", nil, parent)
          end,
          update = function() end,
        })
      end
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
        "Core/UI/Parts/Portfolio.lua",
      }, ns)
      for _, file in ipairs({ "Core/UI/Parts/Trade.lua", "Core/UI/Parts/Chart.lua" }) do
        local chunk = loadfile(file)
        if chunk then
          pcall(chunk, addon.ADDON, ns)
        end
      end
      -- stand-ins for the Item area's widgets while their files aren't there (contracts: docs build brief)
      stand("priceladder", { picks = "table", layout = "string?", dense = "boolean?", action = "string?" })
      stand("chart", { source = "string", kind = "string", range = "any?", style = "string?" })
      addon.load({ "Core/UI/Screens/Portfolio.lua", "Core/UI/Screens/Sell.lua", "Core/UI/Screens/Auctions.lua" }, ns)
      App = ns.App
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
        CurrentShard = function()
          return "Forever|Horde"
        end,
        FactionShard = function()
          return "Forever|Horde"
        end,
        FactionIndex = function()
          return nil
        end,
      }
      ns.ShardKey = ns.ShardKey or function(r, h)
        return r .. "|" .. h
      end
      facts = {
        chars = 2,
        positions = {
          {
            itemID = 10,
            qty = 18,
            chars = { ["Forever:Tyken"] = 10, ["Forever:Kke"] = 8 },
            market = 352,
            value = 6336,
            signal = "hold",
            soldPerDay = 3392,
            daysToSell = 0.1,
          },
        },
        totals = { value = 6336, unrealized = 0 },
        listed = { count = 2, value = 140000 },
        summary = { profit = 7012, income = 7012, spent = 30000 },
        ledger = { { t = 1000, kind = "sale", itemID = 10, qty = 5, amount = 500, cut = 25, char = "Tyken" } },
        profits = {},
        customers = { { name = "Bob", trades = 2, amount = 900, units = 4, last = 1000, favourite = "Silk" } },
        suppliers = {},
        auctions = {
          {
            itemID = 10,
            qty = 5,
            unit = 48600,
            total = 243000,
            char = "Tyken",
            auctionID = 7,
            timeLeft = 36000,
            seen = env.now,
          },
          { itemID = 11, qty = 60, unit = 3600, total = 216000, char = "Zakzu" },
        },
        holdingsAll = {},
      }
      P.Gather = function()
        return facts
      end
      -- the Auctions screen's own list: the characters' saved auctions (copies, as Trading:ActiveAuctions makes)
      ns.Trading = {
        Holdings = function()
          return {}
        end,
        ActiveAuctions = function()
          local out = {}
          for i, a in ipairs(facts.auctions) do
            local e = {}
            for k, v in pairs(a) do
              e[k] = v
            end
            out[i] = e
          end
          return out
        end,
      }
      P.SellEntries = function()
        local list = {
          {
            key = 1,
            qty = 43,
            where = "ah",
            worth = 482000,
            commodity = true,
            summary = { market = 12000, signal = "buy", soldPerDay = 140 },
            locs = { {} },
          },
          {
            key = 2,
            qty = 25,
            signal = "vendor",
            where = "ah",
            worth = 7500,
            summary = { market = 300 },
            craft = {
              product = 20,
              each = 420,
              raw = 284,
              crafter = "Tyken",
              recipe = { id = 5, made = 1, reagents = { { 2, 4 } } },
            },
          },
          { key = 3, qty = 1, signal = "disenchant", where = "ah", worth = 9000, summary = { soldPerDay = 0.11 } },
          { key = 4, qty = 8, signal = "vendor", where = "vendor", worth = 480, summary = { market = 40 } },
        }
        P.bags = P.SortBags(list)
        return P.bags
      end
      P.Suggest = function()
        return {
          quick = { price = 11400, hours = 0.5 },
          normal = { price = 11800, hours = 6 },
          patient = { price = 12400, hours = 24 },
          market = { price = 12000 },
        }
      end
      P.cached, P.bagsAt = nil, nil
    end)

    local function valid()
      local tree = App:Tree()
      local err = ns.Layout.Find(tree, "error.text")
      assert.is_nil(err and err.props.text)
      assert.same({}, ns.Layout.Validate(tree))
    end

    for _, view in ipairs({ "positions", "ledger", "customers", "suppliers" }) do
      for _, compact in ipairs({ false, true }) do
        it("Portfolio " .. view .. (compact and " (narrow)" or "") .. " draws a valid tree", function()
          App:Show()
          App.compact = compact
          App:Go("portfolio", { view = view })
          valid()
          assert.is_not_nil(App.renderer:Frame("pf.table"))
          assert.is_string(App.screens.portfolio.Status(App, { view = view }))
        end)
      end
    end

    it("Portfolio's views: Auctions is its own screen; Sell shows at the auction house", function()
      App:Show()
      App:Go("portfolio")
      App.ctx:Dispatch("view", { key = "auctions" })
      assert.equals("auctions", (App:Current()))
      ns.AME.ahOpen = true
      App.ctx:Dispatch("view", { key = "sell" })
      assert.equals("sell", (App:Current()))
    end)

    for _, case in ipairs({
      { "a Sell row", 1 },
      { "a row tipped Craft", 2 },
      { "a row tipped DE", 3 },
      { "a row tipped Vendor", 4 },
    }) do
      for _, compact in ipairs({ false, true }) do
        it("Sell, " .. case[1] .. (compact and " (narrow)" or "") .. ", draws a valid tree", function()
          ns.AME.ahOpen = true
          App:Show()
          App.compact = compact
          App:Go("sell", { item = case[2] })
          valid()
          assert.is_not_nil(App.renderer:Frame("sell.card"))
        end)
      end
    end

    it("Sell: the ladder picks a price, Skip moves to the next Sell row, Sell it as it is shows the ladder", function()
      ns.AME.ahOpen = true
      App:Show()
      App:Go("sell")
      local _, p = App:Current()
      assert.equals(1, P.SellState(App, p).e.key)
      assert.equals(11800, P.SellState(App, p).price)
      App.ctx:Dispatch("pick", { index = 3 }) -- quick, normal, patient
      assert.equals(12400, P.SellState(App, p).price)
      App.ctx:Dispatch("pickBag", { item = 2 })
      assert.is_false(P.SellState(App, p).ladder)
      App.ctx:Dispatch("asis", {})
      assert.is_true(P.SellState(App, p).ladder)
      valid()
    end)

    it("Post runs the game's posting from the button's click", function()
      ns.AME.ahOpen = true
      local posted
      _G.C_AuctionHouse.PostCommodity = function(loc, duration, qty, price)
        posted = { qty = qty, price = price }
      end
      App:Show()
      App:Go("sell")
      local b = App.renderer:Frame("sell.post")
      b.scripts.OnClick(b)
      assert.same({ qty = 43, price = 11800 }, posted)
    end)

    for _, at in ipairs({ true, false }) do
      it("Auctions " .. (at and "at" or "away from") .. " the auction house draws a valid tree", function()
        ns.AME.ahOpen = at
        App:Show()
        App.compact = false
        App:Go("auctions")
        valid()
        App.ctx:Dispatch("undercutOnly", { checked = true })
        valid()
        assert.is_string(App.screens.auctions.Status(App, select(2, App:Current())))
      end)
    end

    it("Cancel this auction calls the game's cancel from the click", function()
      ns.AME.ahOpen = true
      local cancelled
      _G.C_AuctionHouse.CancelAuction = function(id)
        cancelled = id
      end
      App:Show()
      App:Go("auctions")
      local b = App.renderer:Frame("auc.cancel")
      b.scripts.OnClick(b)
      assert.equals(7, cancelled)
    end)

    it("a cancelled auction leaves the list at once, and the game is asked for your auctions again", function()
      ns.AME.ahOpen = true
      local queried = 0
      _G.C_AuctionHouse.CancelAuction = function() end
      ns.Trading.QueryAuctions = function()
        queried = queried + 1
      end
      P.cancelling = {}
      App:Show()
      App:Go("auctions")
      local before = #P.AuctionState(App, select(2, App:Current()))
      local b = App.renderer:Frame("auc.cancel")
      b.scripts.OnClick(b)
      local rows, sum = P.AuctionState(App, select(2, App:Current()))
      assert.equals(before - 1, #rows)
      assert.equals(1, sum.count)
      for _, r in ipairs(rows) do
        assert.is_not.equals(7, r.auctionID)
      end
      assert.equals(1, queried)
      valid()
      -- the game's list caught up (the auction is gone from it) before the hold runs out: it stays gone
      facts.auctions = { facts.auctions[2] }
      env.now = env.now + P.CANCEL_HIDE + 1
      assert.equals(1, #P.AuctionState(App, select(2, App:Current())))
    end)

    it("the Auctions screen is drawn again when your auctions change, not while it idles", function()
      ns.AME.ahOpen = true
      _G.AME_DB.holdings = { ["Forever:Tyken"] = { auctionList = {} } }
      App:Show()
      App:Go("auctions")
      local stamp = App:Stamp()
      assert.equals(stamp, App:Stamp())
      _G.AME_DB.holdings["Forever:Tyken"].auctionList = {} -- a rescan replaces the list
      assert.is_not.equals(stamp, App:Stamp())
    end)

    it("the Standing card shows the last scan's lowest as money, not the standing's words", function()
      local row = { a = { itemID = 10, unit = 2309 }, st = P.Standing({ unit = 2309 }, nil, 1500) }
      local d = P.AuctionDetail(row, nil, nil, 0.05, 1000)
      assert.equals(1500, d.rows[2].copper)
      assert.is_nil(d.rows[2].text)
    end)
  end)
end)
