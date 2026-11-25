-- Core/CraftingPage.lua and the Crafting screens: the rows (ready, missing, sections, the sidebar), the right column,
-- the queue page, To learn, Your professions, Leveling's rows, and every screen's tree in each of its states, the
-- frame beside the game's window too. Create runs the game's craft from the click.
local wow = require("spec.helpers.wow")
local addon = require("spec.helpers.addon")

describe("Crafting", function()
  local env, ns, CP

  local recipes, facts

  local function makeFacts()
    recipes = {
      [101] = { id = 101, product = 1001, made = 1, reagents = { { 2001, 2 }, { 2002, 1 } }, yellow = 100, grey = 140 },
      [102] = {
        id = 102,
        product = 1002,
        made = 1,
        reagents = { { 2003, 5 } },
        tools = { "Salt Shaker" },
        toolIDs = { ["Salt Shaker"] = 3001 },
      },
      [103] = { id = 103, product = 1003, made = 1, reagents = { { 2001, 1 } } },
      [104] = { id = 104, product = nil, made = 1, reagents = { { 2001, 3 } } }, -- an enchant
    }
    local craft = {
      Price = function()
        return 100
      end,
      SalesPerDay = function()
        return 2
      end,
      SellOrRefine = function(_, item, qty)
        return {
          raw = qty * 50,
          options = { { sold = { n = qty, copper = qty * 80 }, net = qty * 80, gain = qty * 30, others = {}, left = { n = 0, copper = 0 } } },
        }
      end,
    }
    local plan = {
      steps = {
        { recipe = 103, count = 4, item = 2002, made = 4, crafter = "R:Zakzu", mine = false, part = true, saved = 400 },
        { recipe = 101, count = 2, item = 1001, made = 2, crafter = "R:Kke", mine = true, profit = 1000 },
      },
      materials = {
        { item = 2001, need = 4, sources = { { kind = "carried", qty = 4 } } },
        { item = 2002, need = 2, sources = { { kind = "alt", qty = 1, char = "Zakzu" }, { kind = "ah", qty = 1, cost = 100 } } },
        { item = 1003, need = 4, sources = { { kind = "made", qty = 4 } }, part = 103, choice = "make" },
      },
      todo = {
        { kind = "buy", item = 2002, qty = 1, cost = 100 },
        { kind = "alt", item = 2002, qty = 1, char = "Zakzu" },
        { kind = "craft", item = 1003, qty = 4, char = "R:Zakzu" },
        { kind = "craft", item = 1001, qty = 2, char = "R:Kke" },
      },
      toBuy = 100,
      profit = 1000,
    }
    plan.materials[3].sources[1].step = plan.steps[1]
    facts = {
      me = "R:Kke",
      chars = {
        ["R:Kke"] = { professions = { [171] = { name = "Alchemy", skill = 110, max = 150, learned = { [101] = true, [102] = true, [104] = true } } } },
        ["R:Zakzu"] = {
          professions = {
            [164] = { name = "Blacksmithing", skill = 200, max = 225, learned = { [103] = true }, cooldowns = { [103] = 1 } },
            [171] = { name = "Alchemy", skill = 50, max = 75, learned = {} },
            [182] = { name = "Herbalism", skill = 300, max = 300, learned = {} },
          },
        },
      },
      entries = {
        { recipe = recipes[101], crafters = { "R:Kke" }, profession = 171, eval = { profit = 500, cost = 100, revenue = 600, perDay = 900 } },
        { recipe = recipes[102], crafters = { "R:Kke" }, profession = 171, eval = { profit = 9000, cost = 500, revenue = 9500 } },
        { recipe = recipes[103], crafters = { "R:Zakzu" }, profession = 164, eval = { profit = -100, cost = 200, revenue = 100 } },
        { recipe = recipes[104], crafters = { "R:Kke" }, profession = 171, eval = { why = "enchant" } },
      },
      held = { [2001] = 10, [2002] = 0, [2003] = 5 },
      craft = craft,
      queue = { items = { { recipe = 101, count = 2 } }, choice = {} },
      plan = plan,
      live = {
        skillLine = 171,
        recipes = {
          [101] = { learned = true, available = 0, diff = "orange", cat = 11 },
          [102] = { learned = true, available = 1, cat = 12, fav = true },
          [104] = { learned = true, available = 3, diff = "green", cat = 12 },
        },
        categories = {
          [10] = { name = "Potions", order = 1 },
          [11] = { name = "Healing", order = 1, parent = 10 },
          [12] = { name = "Reagents", order = 2 },
        },
      },
      learnRows = {
        {
          item = 4001,
          price = 50000,
          spell = 105,
          rank = 100,
          recipe = { id = 105, product = 1005 },
          eval = { profit = 2000, perDay = 1000, sellRate = 3 },
          learners = { { char = "R:Kke", skill = 110, ready = true } },
          ready = true,
          payback = 0.5,
          via = "ah",
          teaches = { profession = 171 },
        },
        {
          item = 4002,
          price = 2000,
          spell = 106,
          rank = 200,
          recipe = { id = 106, product = 1006 },
          eval = { profit = 300 },
          learners = { { char = "R:Zakzu", skill = 200, ready = false } },
          ready = false,
          via = "vendor",
          where = "Qia, Winterspring",
          teaches = { profession = 164 },
        },
      },
      itemName = function(id)
        return "Item" .. id
      end,
      recipeName = function(id)
        return "Recipe" .. id
      end,
      recipe = function(id)
        return recipes[id]
      end,
      profName = function(skillLine)
        return ({ [171] = "Alchemy", [164] = "Blacksmithing" })[skillLine] or "?"
      end,
      heldOf = function(id)
        return ({ [3001] = 0 })[id] or 0
      end,
      toolWays = function()
        return { line = "Made by Engineering (250) · on the auction house", price = 450000 }
      end,
      usual = function()
        return 80000
      end,
      guildCrafters = function()
        return 0
      end,
    }
    return facts
  end

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
      "Core/CraftQueue.lua",
      "Core/Leveling.lua",
      "Core/CraftingPage.lua",
    })
    _G.AME_DB = { settings = {} }
    CP = ns.CraftingPage
    makeFacts()
  end)

  after_each(function()
    env:restore()
  end)

  describe("the rows", function()
    it("counts what you hold into crafts, and says what's short", function()
      local n, missing = CP.Ready(recipes[101], { [2001] = 10, [2002] = 0 })
      assert.equals(0, n)
      assert.same({ { item = 2002, short = 1, have = 0 } }, missing)
      assert.equals(5, (CP.Ready(recipes[103], { [2001] = 5 })))
    end)

    it("skill colours from the shipped data: orange, yellow, green, none at grey", function()
      assert.equals("orange", CP.Difficulty(90, 100, 140))
      assert.equals("yellow", CP.Difficulty(110, 100, 140))
      assert.equals("green", CP.Difficulty(125, 100, 140))
      assert.is_nil(CP.Difficulty(140, 100, 140))
    end)

    it("each recipe: ready count, the Ready words, a tool nobody holds, queued, the live window's skill-up", function()
      local rows = CP.Rows(facts)
      local by = {}
      for _, r in ipairs(rows) do
        by[r.id] = r
      end
      assert.equals(102, rows[1].id) -- by profit
      assert.equals("missing 1 Item 2002", (by[101].ready.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H[^|]*|h", ""):gsub("|h", ""))) -- amber count, the item in its colour
      assert.equals(2, by[101].queued)
      assert.equals("orange", by[101].diff)
      assert.equals("missing a tool: Salt Shaker", by[102].ready.text)
      assert.equals("ready ×10 · loses money", by[103].ready.text)
      assert.equals("dim", by[103].ready.color)
      assert.equals("Zakzu", by[103].crafter)
      assert.equals("Recipe104", by[104].name)
    end)

    it("filters: ready now, one thing short, a profession, search", function()
      local rows = CP.Rows(facts)
      local function ids(list)
        local out = {}
        for i, r in ipairs(list) do
          out[i] = r.id
        end
        return out
      end
      assert.same({ 103, 104 }, ids(CP.Filter(rows, "ready")))
      assert.same({ 102, 101 }, ids(CP.Filter(rows, "missing")))
      assert.same({ 102, 101, 104 }, ids(CP.Filter(rows, "all", { profession = 171 })))
      assert.same({ 103 }, ids(CP.Filter(rows, "all", { search = "item1003", itemName = facts.itemName })))
      assert.same({ 102 }, ids(CP.Filter(rows, "all", { profession = 171, fav = true })))
    end)

    it("sections in the game's order, folded ones closed", function()
      local rows = CP.Filter(CP.Rows(facts), "all", { profession = 171 })
      local out, n = CP.Sectioned(rows, facts.live.categories, { ["sec:171:12"] = true }, 171)
      assert.equals(2, n)
      assert.is_true(out[1].header)
      assert.equals("Healing", out[1].label)
      assert.equals(101, out[2].id)
      assert.equals("Reagents", out[3].label)
      assert.is_true(out[3].folded)
      assert.equals(2, out[3].count)
      assert.equals(3, #out)
      local flat = CP.Sectioned(rows, nil, {}, 171)
      assert.equals(rows, flat)
    end)

    it("keeps the sections a window showed", function()
      local state = {}
      assert.is_true(CP.RecordSections(state, facts.live))
      assert.equals(11, state.sections[171].recipes[101])
      assert.equals("Potions", state.sections[171].cats[10].name)
    end)

    it("the sidebar: All professions, each profession once under the character with the higher skill", function()
      local e = CP.Sidebar(facts, 171, true)
      assert.equals("all", e[1].key)
      assert.equals("Kke", e[2].label)
      assert.is_true(e[2].heading)
      assert.equals("prof:171", e[3].key)
      assert.is_true(e[3].selected)
      assert.equals("Zakzu", e[4].label)
      assert.equals("Blacksmithing", e[5].label)
      assert.equals("gamewindow", e[#e].key) -- no Herbalism: it has no window
      assert.equals(6, #e)
    end)
  end)

  describe("the right column", function()
    it("the picked recipe: its card, reagents for the count, Selling it, the tool and where it comes from", function()
      local rows = CP.Rows(facts)
      local d = CP.Detail(facts, rows[1], 2)
      assert.equals(1002, d.item)
      assert.equals("Alchemy · Kke · makes 1 · missing a tool · favourite", d.subtitle)
      assert.same({ key = "need:2003", item = 2003, need = 10, have = 5, toBuy = 500 }, d.needs[1])
      assert.equals(9000, d.sell[3].copper)
      assert.equals(3001, d.tools[1].item)
      assert.equals("none of yours has one", d.tools[1].have)
      assert.equals(450000, d.tools[1].price)
    end)

    it("raw or refined: the reagent you hold most of, sold as it is or made into this", function()
      local d = CP.Detail(facts, CP.Rows(facts)[3], 1) -- recipe 103, from 2001 (10 held)
      assert.equals(2001, d.raw.item)
      assert.equals(500, d.raw.raw)
      assert.equals(300, d.raw.gain)
    end)

    it("a place is the game's word, with whether you are near one", function()
      local t = CP.ToolLine(facts, { name = "Forge", kind = "place", met = false })
      assert.same({ place = "Forge", name = "Forge", have = "not nearby", tone = "warn" }, t)
      assert.equals("no Loom here · you hold one", CP.ReadyText({ n = 0, needs = { { name = "Loom", kind = "place", id = 5, held = 1, met = false } } }).text)
    end)

    it("UI.CraftTools' ways in one short line", function()
      local w = CP.WaysLine({ ways = { { kind = "make", profession = "Engineering", skill = 250 }, { kind = "ah", price = 450000 } } })
      assert.equals("Made by Engineering (250) · on the auction house", w.line)
      assert.equals(450000, w.price)
    end)
  end)

  describe("the queue", function()
    it("steps, parts first, with who and what making saves; to do in words; materials' sources", function()
      local q = CP.Queue(facts)
      assert.equals(2, #q.steps)
      assert.equals("Zakzu · a part for step 2", q.steps[1].who.text)
      assert.equals("Buy", q.steps[1].act)
      assert.equals("✕", q.steps[2].act)
      assert.equals(2, q.crafts)
      assert.equals(2, q.chars)
      assert.equals("good", q.mats[1].need.color) -- your bags cover it
      assert.truthy(q.mats[2].source.text:find("1 · Zakzu's bags or bank, 1 · AH", 1, true))
      assert.equals("ah", q.mats[2].source.kind)
      assert.equals("made", q.mats[3].source.kind)
      assert.equals("4 · made in step 1", q.mats[3].source.text)
      assert.equals(4, #q.todo)
      assert.equals("1. ", q.todo[1][1].text)
      assert.same({ item = 1003 }, q.todo[3][3])
      assert.equals("On Zakzu: craft 4 ", q.todo[3][2])
    end)

    it("the strip: what's lined up, what it still costs, Buy missing at the AH", function()
      local s = CP.Strip(facts, true)
      assert.same({ item = 1001, count = 2, label = nil }, { item = s.items[1].item, count = s.items[1].count })
      assert.equals(100, s.toBuy)
      assert.equals("Buy missing", s.button)
      assert.equals("Missing to a list", CP.Strip(facts, false).button)
    end)
  end)

  describe("to learn, your professions, leveling", function()
    it("To learn: where from, pays back, for whom; a profession narrows it", function()
      local rows = CP.Learn(facts)
      assert.equals(2, #rows)
      assert.equals("Kke", rows[1].who.text)
      assert.equals("link", rows[1].where.color)
      assert.equals("Buy", rows[1].buy)
      assert.equals("vendor", rows[2].where.color)
      assert.equals("List", rows[2].buy)
      assert.is_true(rows[2].faded)
      assert.equals(1, #CP.Learn(facts, { profession = 164 }))
      local d = CP.LearnDetail(facts, rows[1])
      assert.equals(4001, d.item)
      assert.equals("Teaches Recipe105 · Alchemy 100 · for Kke", d.subtitle)
      assert.equals("nobody", d.rows[#d.rows].text)
    end)

    it("Your professions: one row per character and profession, cooldowns, what isn't recorded faded", function()
      local rows = CP.ProfessionRows(facts.chars, CP.Rows(facts), 1000, { { key = "R:Bella", none = true } })
      assert.equals("Kke", rows[1].char)
      assert.equals(3, rows[1].known)
      local bs
      for _, r in ipairs(rows) do
        if r.profession == "Blacksmithing" then
          bs = r
        end
      end
      assert.equals("ready", bs.cooldown.text)
      assert.is_true(rows[#rows].unrecorded)
    end)

    it("Leveling: steps with a learn line before a bought recipe, and a train line", function()
      local entry = { recipe = { id = 101, product = 1001, reagents = { { 2001, 2 } } }, known = false, recipeItem = 4001, learnAt = 100, yellow = 100, grey = 140 }
      local plan = {
        steps = {
          { from = 100, to = 120, entry = entry, crafts = 22, net = -500, learn = 8400, results = { sell = 12, vendor = 10 } },
          { train = "Expert", from = 150 },
        },
      }
      local rows = CP.LevelingRows(plan)
      assert.equals("lv:learn:1", rows[1].key)
      assert.equals(4001, rows[1].item)
      assert.equals("100–120", rows[2].skill)
      assert.truthy(rows[2].results:find("sell 12", 1, true)) -- each result in its own colour
      assert.truthy(rows[2].results:find("vendor 10", 1, true))
      assert.equals("lv:train:2", rows[3].key)
      local d = CP.LevelingDetail(plan.steps[1])
      assert.equals(120, d.bar.green)
      assert.equals(44, d.mats[1].count)
    end)

    it("status lines", function()
      assert.equals("2 crafts queued in 2 steps on 2 characters · the queue is kept per account", CP.Status(facts, "queued"))
      assert.equals(
        "Alchemy · Kke · 110 · 3 recipes in 2 sections · 1 ready now · 1 queued",
        CP.Status(facts, "all", 171, { total = 3, sections = 2, ready = 1, queued = 1 })
      )
    end)
  end)

  describe("the screens", function()
    local App, Screen

    before_each(function()
      addon.load({
        "Core/UI/Help.lua",
        "Core/UI/DataTable.lua",
        "Core/UI/Parts/Primitives.lua",
        "Core/UI/Parts/Chrome.lua",
        "Core/UI/Parts/Table.lua",
        "Core/UI/Parts/Composites.lua",
        "Core/UI/App.lua",
        "Core/UI/Parts/Crafting.lua",
        "Core/UI/Screens/Crafting.lua",
        "Core/UI/Screens/CraftingLeveling.lua",
        "Core/UI/Screens/CraftingProfessions.lua",
        "Core/UI/Screens/CraftingSidecar.lua",
      }, ns)
      App, Screen = ns.App, ns.CraftingScreen
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
      CP.Gather = function()
        return facts
      end
      Screen.Dirty()
    end)

    local function valid(id, params)
      App:Show()
      App:Go(id, params)
      local problems = ns.Layout.Validate(App:Tree())
      assert.same({}, problems)
      return App:Tree()
    end

    local cases = {
      { "All professions", { filter = "all" } },
      { "one profession, in its sections", { filter = "all", profession = 171 } },
      { "Ready now", { filter = "ready" } },
      { "Missing something", { filter = "missing" } },
      { "Queued", { filter = "queued" } },
      { "To learn", { filter = "learn" } },
      { "To learn in one profession", { filter = "learn", profession = 164 } },
    }
    for _, case in ipairs(cases) do
      it("draws a valid tree: " .. case[1], function()
        valid("crafting", case[2])
        assert.is_not_nil(App.renderer:Frame("craft.side"))
        assert.is_not_nil(App.renderer:Frame("craft.filters"))
      end)
    end

    it("draws a valid tree at the auction house, narrow, and before any prices", function()
      ns.AME.ahOpen = true
      App.compact = true
      valid("crafting", { filter = "ready" })
      CP.Gather = function()
        return { loading = true, chars = {}, entries = {}, held = {}, queue = { items = {} }, itemName = facts.itemName }
      end
      Screen.Dirty()
      valid("crafting", { filter = "all" })
      valid("crafting", { filter = "learn" })
      valid("crafting", { filter = "queued" })
    end)

    it("a profession picked: the sections, Collapse all and the game's Filter menu", function()
      local tree = valid("crafting", { filter = "all", profession = 171 })
      assert.is_not_nil(ns.Layout.Find(tree, "craft.collapse"))
      assert.is_not_nil(ns.Layout.Find(tree, "craft.filtermenu"))
      local rows = App.ctx.sources["craft.rows"]
      assert.is_true(rows[1].header)
      assert.equals("r:101", rows[2].key)
      -- a click on a header folds it, and the fold is remembered
      App.ctx:Dispatch("row", { key = rows[1].key, header = true })
      assert.is_true(CP.State().folds[rows[1].key])
      assert.equals(2, #App.ctx.sources["craft.rows"] - 2) -- Healing folded: its recipe left out
    end)

    it("Create crafts from the click, through the game's own call", function()
      local crafted
      _G.C_TradeSkillUI = {
        GetRecipeInfo = function()
          return { learned = true, numAvailable = 3 }
        end,
        CraftRecipe = function(id, n)
          crafted = { id, n }
        end,
      }
      valid("crafting", { filter = "all", profession = 171, selected = "r:101", count = 2 })
      local bar = App.renderer:Frame("craft.d.make")
      local create = bar.buttons[1]
      create:GetScript("OnClick")(create)
      assert.same({ 101, 2 }, crafted)
      local all = bar.buttons[2]
      all:GetScript("OnClick")(all)
      assert.same({ 101, 3 }, crafted)
      _G.C_TradeSkillUI = nil
    end)

    it("Queue adds to the queue; the filters and search are remembered", function()
      valid("crafting", { filter = "ready" })
      App.ctx:Dispatch("make", { key = "queue", recipe = 103, count = 3 })
      assert.equals(3, AME_DB.craftQueue.items[1].count)
      App.ctx:Dispatch("filter", { key = "missing" })
      App.ctx:Dispatch("search", { text = "item" })
      assert.equals("missing", CP.State().filter)
      assert.equals("item", CP.State().search)
      local _, params = App:Current()
      assert.equals("missing", params.filter)
    end)

    it("Leveling draws, with and without a plan", function()
      valid("leveling", {})
      facts.m = {}
      local entry = { recipe = { id = 101, product = 1001, reagents = { { 2001, 2 } } }, known = true, yellow = 100, grey = 140 }
      local plan = { steps = { { from = 110, to = 130, entry = entry, crafts = 20, net = -100, results = { sell = 20 } } }, cost = 100, back = 0, net = -100, crafts = 20 }
      CP.LevelingPlans = function()
        return { cheapest = plan, recovery = plan, fewest = plan, materials = plan }
      end
      ns.CraftingLevelingScreen.cache = nil
      local tree = valid("leveling", { who = "R:Kke", profession = 171 })
      assert.is_not_nil(ns.Layout.Find(tree, "lv.d.bar"))
      App.ctx:Dispatch("queueSteps", {})
      assert.equals(20, AME_DB.craftQueue.items[1].count)
    end)

    it("Your professions draws", function()
      local tree = valid("professions", {})
      assert.is_not_nil(ns.Layout.Find(tree, "prof.d.cooldown"))
      assert.equals("crafting", App.screens.professions.tab)
    end)

    it("the frame beside the game's window: a valid tree, with a recipe picked and the queue", function()
      ns.Recipes = {
        Get = function(id)
          return recipes[id]
        end,
      }
      ns.ProfessionBar = {
        selected = 101,
        Summary = function()
          return { cost = 100, sells = 600, profit = 500, sellRate = 0.8, signal = "none", toBuy = 0 }
        end,
        RateText = function()
          return "0.8"
        end,
        NextStep = function()
          return facts.plan.steps[1]
        end,
      }
      local Side = ns.CraftingSidecar
      Side.Create()
      assert.same({}, ns.Layout.Validate(Side.Tree()))
      Side.frame:Show()
      Side:Render()
      assert.is_not_nil(Side.renderer:Frame("side.next"))
      facts.plan, facts.queue = nil, { items = {} }
      ns.ProfessionBar.selected = nil
      assert.same({}, ns.Layout.Validate(Side.Tree()))
    end)

    it("opening a profession: takeover opens Crafting on it; the setting picks the frame instead", function()
      local Side = ns.CraftingSidecar
      AME_DB.settings.newWindow = true
      _G.C_TradeSkillUI = {
        GetBaseProfessionInfo = function()
          return { professionID = 171 }
        end,
      }
      _G.ProfessionsFrame = CreateFrame("Frame")
      Side.Opened()
      local id, params = App:Current()
      assert.equals("crafting", id)
      assert.equals(171, params.profession)
      assert.is_true(Side.TookOver())
      assert.equals(0, _G.ProfessionsFrame.alpha or 0)
      Side.UseGameWindow()
      assert.equals("game", AME_DB.settings.professionMode)
      assert.is_false(Side.TookOver())
      _G.C_TradeSkillUI, _G.ProfessionsFrame = nil, nil
    end)
  end)
end)
