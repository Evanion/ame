-- The Guild tab (Core/GuildPage.lua and Core/UI/Screens/Guild*.lua): the nav, Crafters, Requests, Your crafts, Guild
-- lists and Sharing prices, each tree validated in its states; and the request frames (Core/UI/Requests.lua).
local wow = require("spec.helpers.wow")
local addon = require("spec.helpers.addon")

describe("Guild", function()
  local env, ns, GuildPage, R

  before_each(function()
    env = wow.install()
    ns = addon.load({
      "Core/Init.lua",
      "Core/Codec.lua",
      "Core/Settings.lua",
      "Core/ItemCache.lua",
      "Core/Sync.lua",
      "Core/Watch.lua",
      "Core/Shopping.lua",
      "Core/Crafters.lua",
      "Core/CraftRequests.lua",
      "Core/UI/Tokens.lua",
      "Core/UI/Kit.lua",
      "Core/UI/Layout.lua",
      "Core/UI/Widgets.lua",
      "Core/GuildPage.lua",
    })
    _G.AME_DB = { settings = {}, crafters = {}, crafting = { chars = {} } }
    GuildPage, R = ns.GuildPage, ns.CraftRequests
  end)

  after_each(function()
    env:restore()
  end)

  local function req(over)
    local r = R.New({
      id = over.id or "Zakzu-1-1",
      asker = "Zakzu",
      crafter = "Kke",
      recipe = 17580,
      item = 13444,
      count = 5,
      reagents = { { item = 13463, need = 15, bring = 15 }, { item = 18256, need = 5, bring = 0 } },
      offer = 4500,
      tip = 50000,
      message = "Could you make these?",
    }, 100)
    for k, v in pairs(over) do
      r[k] = v
    end
    return r
  end

  describe("the model", function()
    it("the nav lists the pages, the requests waiting on you counted", function()
      local e = GuildPage.Nav("requests", { requests = 2, lists = 0 })
      assert.is_true(e[1].heading)
      assert.equals("guild", e[2].key)
      assert.equals(2, e[3].count)
      assert.is_true(e[3].selected)
      assert.is_nil(e[6].count)
      assert.equals("sharing", e[7].key)
    end)

    it("crafter rows: yours without Ask, trusted marked, online in green", function()
      local rows = GuildPage.CrafterRows({
        { name = "Tyken", mine = true, online = true, skill = 300 },
        { name = "Mistwalker", owner = "mist", online = true, skill = 285 },
        { name = "Gromm", online = false, skill = 300 },
      }, {
        trusted = function(owner)
          return owner == "mist"
        end,
      })
      assert.is_false(rows[1].ask)
      assert.equals("Ask", rows[2].ask)
      assert.equals("● Mistwalker (trusted)", rows[2].crafter.text)
      assert.equals("good", rows[2].crafter.color)
      assert.equals("dim", rows[3].crafter.color)
    end)

    it("a request reads per side: what it waits for, who brings the mats", function()
      local r = req({ side = "crafter" })
      local row = GuildPage.RequestRow(r, 100 + 720, {})
      assert.equals("new", row.state.text)
      assert.equals("warn", row.state.color)
      assert.equals("brings most", row.mats)
      r.side = "asker"
      assert.equals("sent · waiting for Kke", (GuildPage.StateText(r)))
      assert.equals("you bring most", GuildPage.MatsText(r))
      R.Answer(r, "crafter", { offer = 6000 }, nil, 200)
      assert.equals("answered · yours to approve", (GuildPage.StateText(r)))
      local acts = GuildPage.Actions(r)
      assert.equals("answer", acts.buttons[1].action)
      assert.equals("Accept", acts.buttons[2].label)
    end)

    it("splits requests into asked of you and you asked, ended ones last", function()
      local a = req({ id = "a", side = "crafter", changed = 300 })
      local b = req({ id = "b", side = "crafter", changed = 400, state = "handed" })
      local c = req({ id = "c", side = "asker", changed = 200 })
      local into, out = GuildPage.Split({ a, b, c }, 500, {})
      assert.same({ "a", "b" }, { into[1].key, into[2].key })
      assert.is_true(into[2].faded)
      assert.equals("c", out[1].key)
    end)

    it("the strip lights where it stands; worth adds up the craft", function()
      local r = req({ side = "crafter" })
      assert.equals(1, GuildPage.Strip(r).current)
      r.state = "declined"
      assert.equals("declined", GuildPage.Strip(r).ended)
      local price = function(id)
        return ({ [13463] = 950, [18256] = 200 })[id]
      end
      local w = GuildPage.WorthRows(r, 98000, price)
      assert.equals(490000, w[1].copper)
      assert.equals(15 * 950 + 5 * 200, w[2].copper)
      assert.equals(490000 - (15 * 950 + 5 * 200), w[3].copper)
      assert.is_true(w[4].total)
    end)

    it("your crafts: most asked first; the month's requests and tips", function()
      local rows = GuildPage.OfferRows({
        { recipe = 1, name = "A", who = { "Kke" } },
        { recipe = 2, name = "B", who = { "Kke", "Tyken" } },
      }, {
        asked = function(id)
          return id == 2 and 3 or 0
        end,
        tip = function(id)
          return id == 1 and 50000 or nil
        end,
      })
      assert.equals("2", rows[1].key)
      assert.equals("Kke, Tyken", rows[1].yours)
      assert.equals("suggested", rows[1].tip.text)
      local month = GuildPage.Month({ req({ side = "crafter", state = "handed", at = 1000 }), req({ side = "crafter", at = 1000 }) }, 2000)
      assert.equals("2", month[1].text)
      assert.equals("1", month[2].text)
      assert.equals(50000, month[3].copper)
    end)

    it("the advert links what's most asked", function()
      local parts, text = GuildPage.Advert("Kke", "Alchemy", 300, { 13444 }, function(id)
        return "[" .. id .. "]"
      end)
      assert.equals("Kke (Alchemy 300) is taking orders:", parts[1])
      assert.same({ item = 13444 }, parts[3])
      assert.equals("Kke (Alchemy 300) is taking orders: [13444] Whisper me, or ask through AME.", text)
    end)

    it("guild lists: theirs newest first with Copy, yours last with Stop sharing", function()
      local rows = GuildPage.ListRows({
        watch = { { key = "Klydig/Herbs", owner = "Klydig", name = "Herbs", items = { [1] = true, [2] = true }, t = 100 } },
        shopping = { { key = "Zakzu/Raid", owner = "Zakzu", name = "Raid", items = { [3] = { need = 40 } }, t = 200 } },
        mineWatch = { { i = 1, name = "Alchemy", n = 8 } },
      }, 300)
      assert.equals("s:Zakzu/Raid", rows[1].key)
      assert.equals("w:Klydig/Herbs", rows[2].key)
      assert.equals(2, rows[2].items)
      assert.equals("mw:1", rows[3].key)
      assert.equals("Stop sharing", rows[3].act)
      local items = GuildPage.ListItems({ [3] = { need = 40 }, [4] = { need = 5 } }, function()
        return 100
      end)
      assert.equals(3, items[1].item)
      assert.equals(40, items[1].need)
    end)
  end)

  describe("the screens", function()
    local App

    before_each(function()
      addon.load({
        "Core/UI/Help.lua",
        "Core/UI/DataTable.lua",
        "Core/UI/Parts/Primitives.lua",
        "Core/UI/Parts/Chrome.lua",
        "Core/UI/Parts/Table.lua",
        "Core/UI/Parts/Composites.lua",
        "Core/UI/Parts/Guild.lua",
        "Core/UI/App.lua",
        "Core/UI/Requests.lua",
        "Core/UI/Screens/Guild.lua",
        "Core/UI/Screens/GuildRequests.lua",
        "Core/UI/Screens/GuildOffers.lua",
        "Core/UI/Screens/GuildLists.lua",
        "Core/UI/Screens/GuildSharing.lua",
      }, ns)
      App = ns.App
      AME_DB.watch, AME_DB.shopping = {}, {}
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
        watch = ns.Watch.New(AME_DB.watch),
        shopping = ns.Shopping.New(AME_DB.shopping),
        Say = function() end,
      }
      ns.ShardKey = ns.ShardKey or function(r, h)
        return r .. "|" .. h
      end
      ns.Recipes = {
        Get = function(id)
          return { id = id, product = 13444, made = 1, profession = 171, reagents = { { 13463, 3 }, { 18256, 1 } } }
        end,
        TaughtBy = function()
          return { { item = 13501 } }
        end,
        Stamp = function()
          return 1
        end,
      }
      ns.UI = {
        Freshness = function()
          return { { house = "Horde", t = env.now - 7200, src = "Tyken", items = 6782 }, { house = "Neutral" } }
        end,
        SyncActivityData = function()
          return {
            next = "Next announce in 8 min",
            moving = { { who = "From Klydig", what = "Goblin AH: full scan", frac = 0.4, left = "~6 min left", why = "slow" } },
            rows = { { "Klydig", "Goblin AH", "1 day newer", "14", "—", "~186 KB", "~14 min", "receiving" } },
            total = "In all: full scan",
            receivingFrom = 1,
            catchUp = 600,
          }
        end,
      }
      AME_DB.crafting.chars["Forever:Kke"] = {
        professions = { [171] = { name = "Alchemy", skill = 300, learned = { [17580] = true } } },
      }
      AME_DB.crafters.Sela = { owner = "sela", t = env.now, profs = { [171] = { skill = 300, ids = { [17580] = true } } } }
      ns.Crafters.RecipeName = function()
        return "Major Mana Potion"
      end
      ns.ItemCache.Name = function()
        return "Major Mana Potion"
      end
    end)

    local function draws(id, params)
      App:Show()
      App:Go(id, params)
      local tree = App:Tree()
      assert.same({}, ns.Layout.Validate(tree))
      assert.is_nil(ns.Layout.Find(tree, "error"))
      assert.equals("string", type(App.screens[id].Status(App, params or {})))
      return tree
    end

    it("Crafters: empty, then a search with its crafters and the formula", function()
      draws("guild")
      local tree = draws("guild", { search = "mana" })
      assert.is_not_nil(ns.Layout.Find(tree, "guild.crafters"))
      assert.is_not_nil(ns.Layout.Find(tree, "guild.formula"))
      local rows = App.ctx.sources["guild.crafters"]
      assert.equals(2, #rows)
      assert.is_false(rows[1].ask) -- Kke is yours
      assert.equals("Ask", rows[2].ask)
      assert.equals("guild", App:TabScreen("guild"))
    end)

    it("Ask opens the request form, and it draws", function()
      App:Show()
      App:Go("guild", { search = "mana" })
      App.ctx:Dispatch("ask", { key = "Sela" })
      local Q = ns.Requests
      assert.equals("form", Q.state.mode)
      assert.equals("Sela", Q.state.crafter)
      assert.same({}, ns.Layout.Validate(Q.Tree()))
      assert.is_true(Q.frame:IsShown())
    end)

    it("Requests: empty, and with requests both ways in their states", function()
      draws("requests")
      local db = R.DB()
      db.list.a = req({ id = "a", side = "crafter", changed = 300 })
      db.list.b = req({ id = "b", side = "asker", state = "answered", by = "crafter", changed = 200, prev = { offer = 1, tip = 1, bring = { 15, 0 } } })
      db.list.c = req({ id = "c", side = "crafter", state = "handed", changed = 100 })
      for _, id in ipairs({ "a", "b", "c" }) do
        local tree = draws("requests", { request = id })
        assert.is_not_nil(ns.Layout.Find(tree, "req.strip"))
      end
      assert.equals(2, #App.ctx.sources["guild.in"])
      for _, s in ipairs({ "accepted", "crafted" }) do
        db.list.a.state = s
        draws("requests", { request = "a" })
      end
    end)

    it("the answer frame draws for the crafter and the asker", function()
      local db = R.DB()
      db.list.a = req({ id = "a", side = "crafter" })
      db.list.b = req({ id = "b", side = "asker", state = "answered", by = "crafter", note = "Vials are short", prev = { offer = 4000, tip = 50000, bring = { 15, 0 } } })
      local Q = ns.Requests
      for _, id in ipairs({ "a", "b" }) do
        Q.Answer(id)
        local tree = Q.Tree()
        assert.same({}, ns.Layout.Validate(tree))
        assert.equals("requestanswer", tree.type)
      end
      -- the crafter changes the price: the answer goes back
      Q.Answer("a")
      Q.ctx:Dispatch("offer", { text = "60s" })
      assert.is_not_nil(ns.Layout.Find(Q.Tree(), "ra.b.send"))
      Q.ctx:Dispatch("sendAnswer", {})
      assert.equals("answered", db.list.a.state)
      assert.equals(6000, db.list.a.offer)
    end)

    it("Your crafts, Guild lists and Sharing draw", function()
      draws("offers")
      R.DB().taking["Kke:171"] = true
      local tree = draws("offers", { recipe = "17580" })
      assert.is_not_nil(ns.Layout.Find(tree, "offers.tiprow"))
      assert.is_not_nil(ns.Layout.Find(tree, "offers.tell.text"))
      draws("guildlists")
      ns.AME.watch:SetGuildList("Klydig", "Herbs", 100, { 1, 2 })
      ns.AME.shopping:SetGuildList("Zakzu", "Raid", 200, { { 3, 40 } })
      ns.AME.watch:SetShared(1, true)
      tree = draws("guildlists")
      assert.is_not_nil(ns.Layout.Find(tree, "lists.copy"))
      draws("guildlists", { list = "mw:1" })
      draws("sharing")
    end)
  end)
end)
