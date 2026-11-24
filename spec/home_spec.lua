-- Core/Home.lua and its screen: the headline numbers, "To do now" (ordered by where you are), "Worth doing today",
-- the first run's steps, and the screen's tree for each of its three states.
local wow = require("spec.helpers.wow")
local addon = require("spec.helpers.addon")

describe("Home", function()
  local env, ns, Home

  before_each(function()
    env = wow.install()
    ns = addon.load({
      "Core/Init.lua",
      "Core/Settings.lua",
      "Core/ItemCache.lua",
      "Core/UI/Tokens.lua",
      "Core/UI/Kit.lua",
      "Core/UI/Layout.lua",
      "Core/UI/Widgets.lua",
      "Core/Home.lua",
    })
    _G.AME_DB = { settings = {} }
    Home = ns.Home
  end)

  after_each(function()
    env:restore()
  end)

  local facts = {
    now = 1000000,
    hasPrices = true,
    gold = 30000000,
    itemsValue = 18120000,
    worthWeekAgo = 46700000,
    listed = { count = 38, value = 6120000 },
    undercut = 3,
    undercutFirst = 3825,
    ledger = { profit = 2410000, sales = 64, buys = 22 },
    marketChange = 0.024,
    alerts = { { itemID = 13468, text = "dropped to 62g (alert at 65g)", ago = "12 min" } },
    cooldowns = { { recipe = 17187, char = "Kke", name = "Transmute: Arcanite", product = 12360, profit = 230000 } },
    bags = { count = 14, value = 1420000, first = 13465, firstQty = 40 },
    bestCraft = { recipe = 1, product = 2, profit = 650000, sub = "Tyken" },
    bestBuy = { item = 3, under = 0.18, sub = "On your watchlist" },
  }

  describe("Kpis", function()
    it("net worth is gold and holdings, with the week's change; the rest from the ledger and the market", function()
      local k = Home.Kpis(facts)
      assert.equals(48120000, k[1].copper)
      assert.equals("+3.0%", k[1].delta)
      assert.equals("good", k[1].deltaTone)
      assert.equals(6120000, k[2].copper)
      assert.equals("3 undercut", k[2].delta)
      assert.equals("38 auctions", k[2].note)
      assert.is_true(k[3].signed)
      assert.equals("64 sales · 22 purchases", k[3].note)
      assert.equals("+2.4%", k[4].value)
    end)
    it("before any prices: dashes and what each waits for", function()
      local k = Home.Kpis({ hasPrices = false })
      assert.is_nil(k[1].copper)
      assert.equals("after the first scan", k[1].note)
    end)
  end)

  describe("Todo", function()
    it("away: what you can act on anywhere first; the auction house's rows greyed, naming where they work", function()
      local rows = Home.Todo(facts, false)
      assert.same({ "alert:13468", "cooldown:17187:Kke", "auctions", "bags" }, {
        rows[1].key,
        rows[2].key,
        rows[3].key,
        rows[4].key,
      })
      assert.is_true(rows[1].selected)
      assert.is_true(rows[3].off)
      assert.equals("At the AH", rows[4].button)
    end)
    it("at the auction house: bags and auctions lead, and their buttons act", function()
      local rows = Home.Todo(facts, true)
      assert.equals("auctions", rows[1].key)
      assert.equals("bags", rows[2].key)
      assert.is_nil(rows[2].off)
      assert.equals("goSell", rows[2].action)
      assert.is_true(rows[1].primary)
    end)
  end)

  it("Worth lists the best of each kind it found", function()
    local rows = Home.Worth(facts, false)
    assert.equals("craft:1", rows[1].key)
    assert.equals("18% under usual", rows[2].value)
    assert.equals(2, #rows)
  end)

  it("the first run's steps tick off what has happened", function()
    local rows = Home.Steps({
      hasPrices = false,
      bankSeen = true,
      professions = { { name = "Alchemy", read = true }, { name = "Tailoring" } },
      guildSharers = 14,
    })
    assert.equals("warn", rows[1].tone)
    assert.equals("good", rows[3].tone)
    assert.equals(4, #rows)
    assert.equals("step:guild", rows[4].key)
  end)

  it("keeps a value a day and reads last week's back", function()
    local log = { [90] = 100, [10] = 5 }
    assert.equals(100, Home.WeekAgo(log, 97, 120))
    assert.equals(120, log[97])
    assert.is_nil(log[10]) -- older than 40 days drops
  end)

  describe("the screen", function()
    local App

    before_each(function()
      addon.load({
        "Core/UI/Help.lua",
        "Core/UI/DataTable.lua",
        "Core/UI/Parts/Primitives.lua",
        "Core/UI/Parts/Chrome.lua",
        "Core/UI/Parts/Composites.lua",
        "Core/UI/App.lua",
        "Core/UI/Screens/Home.lua",
      }, ns)
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
      }
      ns.ShardKey = ns.ShardKey or function(r, h)
        return r .. "|" .. h
      end
    end)

    for _, case in ipairs({ { "away", false, facts }, { "at the AH", true, facts }, { "first run", false, { hasPrices = false } } }) do
      it("draws a valid tree " .. case[1], function()
        Home.Gather = function()
          return case[3]
        end
        ns.AME.ahOpen = case[2]
        App:Show()
        App:Go("home")
        assert.same({}, ns.Layout.Validate(App:Tree()))
        assert.is_not_nil(App.renderer:Frame("home.left"))
      end)
    end
  end)
end)
