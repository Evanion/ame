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
      assert.truthy(k[4].value:find("+2.4%", 1, true)) -- green / red (W.Percent)
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

  it("Kit text swaps the symbols the game's fonts lack for textures, and keeps the ones they have", function()
    local Kit = ns.Kit
    local menu = Kit.Glyphs("Horde AH ▾")
    assert.truthy(menu:find("^Horde AH |T"), menu)
    assert.falsy(menu:find("▾", 1, true))
    assert.are.equal("<= 3 days · 12×", Kit.Glyphs("≤ 3 days · 12✕"))
    assert.are.equal("‹ back · plain — dash", Kit.Glyphs("‹ back · plain — dash"))
    local fs = Kit.Text(CreateFrame("Frame"))
    fs:SetText("Columns ▾")
    assert.falsy(fs:GetText():find("▾", 1, true))
  end)

  it("a font picked in Settings reaches Kit text already on screen (one font object per role and size)", function()
    local Kit = ns.Kit
    local made = {}
    _G.CreateFont = function(name)
      local o = { name = name }
      function o:SetFont(path, size)
        self.path, self.size = path, size
      end
      made[name] = o
      return o
    end
    local fs = { color = { 1, 1, 1, 1 } }
    function fs:SetFontObject(obj)
      self.obj = obj
    end
    function fs:GetTextColor()
      return unpack(self.color)
    end
    function fs:SetTextColor(r, g, b, a)
      self.color = { r, g, b, a }
    end
    fs:SetTextColor(0.5, 0.5, 0.5, 1)
    Kit.SetFont(fs, "ui", 12, true)
    assert.truthy(fs.obj.path:find("Inter%-SemiBold"), fs.obj.path)
    assert.are.same({ 0.5, 0.5, 0.5, 1 }, fs.color) -- its colour kept
    ns.SettingsScreen = {
      FontPath = function()
        return "Fonts\\picked.ttf"
      end,
    }
    Kit.ApplyFonts()
    assert.are.equal("Fonts\\picked.ttf", fs.obj.path)
    ns.SettingsScreen, _G.CreateFont = nil, nil
  end)

  it("prices are stale after 3 hours without a full scan; the market card says how old", function()
    assert.is_false(Home.Stale({ hasPrices = true, scanAge = 2 * 3600 }))
    assert.is_true(Home.Stale({ hasPrices = true, scanAge = 9 * 3600 }))
    assert.is_false(Home.Stale({ hasPrices = false, scanAge = 9 * 3600 })) -- the first run asks for a scan its own way
    assert.equals("9 h", Home.Age(9 * 3600))
    assert.equals("3 days", Home.Age(80 * 3600))
    local k = Home.Kpis({ hasPrices = true, scanAge = 9 * 3600, marketLevel = 91.3 })
    assert.equals("prices 9 h old", k[4].note)
    assert.equals("warn", k[4].deltaTone)
  end)

  it("the best refine names its recipe by id (SellOrRefine hands back the recipe itself)", function()
    local SMELT = { id = 2659, product = 2840, reagents = { { 2770, 1 } } }
    local m = {
      held = { [2770] = 40, [2771] = 0 },
      uses = { [2770] = { SMELT } },
      craft = {
        SellOrRefine = function(_, item, qty)
          return {
            item = item,
            qty = qty,
            raw = 4000,
            options = { { recipe = SMELT, gain = 1200 } },
            best = { recipe = SMELT, gain = 1200 },
          }
        end,
      },
    }
    local best = Home.BestRefine(m)
    assert.are.same({ item = 2770, qty = 40, recipe = 2659, product = 2840, gain = 1200 }, best)
    local rows = Home.Worth({ now = 1, hasPrices = true, bestRefine = best }, false)
    assert.are.equal("refine:2770:2659", rows[#rows].key)
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

  describe("the strip", function()
    local all = function()
      return true
    end

    it("draws a point a day: each character's last figure, the first standing for the days before it", function()
      local holdings = {
        ["R:A"] = { goldDays = { [100] = 10, [102] = 30 }, money = 40 },
        ["R:B"] = { goldDays = { [101] = 5 } },
        ["S:C"] = { goldDays = { [100] = 999 } },
      }
      local line = Home.GoldLine(holdings, function(key)
        return key:sub(1, 1) == "R"
      end, 103, 30)
      assert.are.same({ 100 * 86400, 101 * 86400, 102 * 86400, 103 * 86400 }, line.xs)
      assert.are.same({ 15, 15, 35, 45 }, line.ys)
      assert.is_nil(Home.GoldLine({ ["R:A"] = { money = 1 } }, all, 103)) -- one day is no line yet
    end)

    it("lists the mail by when it first runs out, marking under 3 days, and totals the gold", function()
      local now = 1000000
      local rows, total = Home.Mail({
        ["R:Kke"] = { inbox = { money = 96000, sales = 1, items = 2, firstOut = now + 26 * 86400 + 5 } },
        ["R:Tyken"] = { inbox = { money = 418000, sales = 3, items = 4, firstOut = now + 2 * 86400 + 5 } },
        ["R:Empty"] = { inbox = { money = 0, items = 0 } },
      }, all, now)
      assert.equals(514000, total)
      assert.equals(2, #rows)
      assert.equals("Tyken · 3 sales, 4 items", rows[1].label)
      assert.equals("first runs out in 2 days", rows[1].note)
      assert.equals("bad", rows[1].noteTone)
      assert.equals("Kke · 1 sale, 2 items", rows[2].label)
      assert.equals("first runs out in 26 days", rows[2].note)
      assert.is_nil(rows[2].noteTone)
    end)

    it("worth doing shows up to three of each kind", function()
      local crafts = {}
      for i = 1, 5 do
        crafts[i] = { recipe = i, product = i, profit = 100 }
      end
      local rows =
        Home.Worth({ now = 1, hasPrices = true, crafts = crafts, learns = { { item = 9, payback = 4 } } }, false)
      assert.equals(4, #rows)
      assert.equals("craft:3", rows[3].key)
      assert.equals("learn:9", rows[4].key)
    end)
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
        "Core/UI/Parts/Chart.lua",
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

    for _, case in ipairs({
      { "away", false, facts },
      { "at the AH", true, facts },
      { "first run", false, { hasPrices = false } },
    }) do
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

    it("old prices: a fresh scan leads To do now, and Worth doing waits for it (board HomeStale)", function()
      local stale = {}
      for k, v in pairs(facts) do
        stale[k] = v
      end
      stale.scanAge = 9 * 3600
      Home.Gather = function()
        return stale
      end
      ns.AME.ahOpen = true
      App:Show()
      App:Go("home")
      local tree = App:Tree()
      assert.same({}, ns.Layout.Validate(tree))
      local function find(node, id)
        if node.id == id then
          return node
        end
        for _, c in ipairs(node.children or {}) do
          local hit = find(c, id)
          if hit then
            return hit
          end
        end
      end
      local left, right = find(tree, "home.left").props, find(tree, "home.right").props
      assert.equals("scan", left.rows[1].key)
      assert.equals("scan", left.rows[1].action)
      assert.is_true(left.rows[1].primary)
      assert.is_nil(left.rows[2].primary)
      assert.is_true(right.rows[1].off)
      assert.equals("Worth doing today, after a fresh scan", right.title)
    end)
  end)
end)
