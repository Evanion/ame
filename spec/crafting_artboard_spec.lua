-- The Crafting tab's pages as the design's artboards draw them: Top earners' Signal and Queue, Your professions' rows
-- for what isn't recorded yet, Find a crafter's one row per recipe (and its recipe item), the craft queue page's
-- To do and per-step buttons, Sell or refine's and Leveling's queue buttons, and Leveling's search.
local wow = require("spec.helpers.wow")

local f = io.open("Libs/LibDeflate/LibDeflate.lua", "r")
local haveLibs = f ~= nil
if f then
  f:close()
end

describe("crafting artboard: pure parts", function()
  local ns

  before_each(function()
    ns = { Events = { On = function() end, Fire = function() end } }
    _G.AME_DB = _G.AME_DB or {}
    local load = function(path)
      assert(loadfile(path))("AzerothMercantileExchange", ns)
    end
    load("Core/Professions.lua")
    load("Core/Leveling.lua")
    load("Core/CraftQueue.lua")
  end)

  it("Professions.Unrecorded: spellbook professions not opened yet, and characters with nothing recorded", function()
    local chars = {
      ["R:Tyken"] = {
        professions = { [171] = { name = "Alchemy", skill = 300, max = 300 } },
        spellbook = {
          { name = "Alchemy", skillLine = 171, skill = 300, max = 300 },
          { name = "Herbalism", skillLine = 182, skill = 300, max = 300 },
          { name = "Tailoring", skillLine = 197, skill = 120, max = 150 },
        },
      },
    }
    local out = ns.Professions.Unrecorded(chars, { "R:Tyken", "R:Evanion" }, { [182] = true })
    assert.are.equal(3, #out)
    assert.are.same({ "R:Evanion", true }, { out[1].key, out[1].none })
    assert.are.equal("Herbalism", out[2].name)
    assert.is_true(out[2].noWindow) -- nothing to open: its skill is all there is
    assert.are.equal("Tailoring", out[3].name)
    assert.is_false(out[3].noWindow)
    assert.are.equal(120, out[3].skill)
  end)

  it("Leveling.QueueList: the path's crafts in order, a recipe two steps use once", function()
    local a, b = { recipe = { id = 10 } }, { recipe = { id = 20 } }
    local plan = {
      steps = {
        { entry = a, crafts = 5 },
        { train = "Expert" },
        { entry = b, crafts = 3 },
        { entry = a, crafts = 2 },
        { entry = b, crafts = 0 },
      },
    }
    assert.are.same({ { recipe = 10, count = 7 }, { recipe = 20, count = 3 } }, ns.Leveling.QueueList(plan))
    assert.are.same({}, ns.Leveling.QueueList(nil))
  end)

  it("CraftQueue.Plan: a part made rather than bought says what making all of it saves", function()
    local recipes = {
      [1] = { id = 1, product = 100, made = 1, reagents = { { 200, 2 } } }, -- the gauntlet from 2 bars
      [2] = { id = 2, product = 200, made = 1, reagents = { { 300, 1 } } }, -- a bar from 1 ore
    }
    local craft = {
      Price = function(_, id)
        return ({ [100] = 5000, [200] = 300, [300] = 100 })[id]
      end,
      CraftCost = function(_, r)
        return r.id == 2 and 100 or 600
      end,
      Evaluate = function()
        return { profit = 1000 }
      end,
    }
    local plan = ns.CraftQueue.Plan({ items = { { recipe = 1, count = 2 } } }, {
      recipe = function(id)
        return recipes[id]
      end,
      producers = function(id)
        return id == 200 and { { recipe = 2, crafters = { "R:Me" } } } or {}
      end,
      me = "R:Me",
      craft = craft,
    })
    local part
    for _, s in ipairs(plan.steps) do
      part = part or (s.part and s)
    end
    assert.is_not_nil(part)
    assert.are.equal(4, part.made)
    assert.are.equal(200, part.saves) -- a bar: 300 bought, 100 made
    assert.are.equal(800, part.saved)
  end)
end)

describe("crafting artboard: the pages", function()
  if not haveLibs then
    pending("Libs missing; run scripts/fetch-libs.sh")
    return
  end

  local env, ns

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
    C_AuctionHouse.ReplicateItems()
    for _ = 1, 30 do
      env:fire("REPLICATE_ITEM_LIST_UPDATE")
    end
    drainJobs()
  end

  -- a market with linen (2589), the bandage made of it (1251) worth more, and one character's First Aid recorded
  local function seeded()
    env = wow.install()
    ns = wow.loadAddon("AzerothMercantileExchange.toc", "AzerothMercantileExchange")
    env:fire("ADDON_LOADED", "AzerothMercantileExchange")
    env:fire("PLAYER_LOGIN")
    env.npcFaction = "Horde"
    env:fire("AUCTION_HOUSE_SHOW")
    for d = 0, 9 do
      env.now = env.now + 86400
      fullScan({ { 2589, 1000 + d * 10, 10 }, { 1251, 9000, 40 }, { 4306, 5000 - d * 100, 5 } })
    end
    env:advance(4)
    drainJobs()
    _G.AME_CraftingData = nil
    dofile("AzerothMercantileExchange_Crafting/Recipes.lua")
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
          spellbook = {
            { name = "First Aid", skillLine = 129, skill = 40, max = 75 },
            { name = "Tailoring", skillLine = 197, skill = 10, max = 75 },
          },
        },
      },
    }
    AME_DB.holdings[key] = { bags = { [2589] = 20 }, bank = {} }
    ns.UI:Toggle()
    ns.UI:ShowTab("crafting")
    local v = ns.UI.craftView
    v.scripts.OnShow(v)
    return v, key
  end

  after_each(function()
    if env then
      env:restore()
    end
  end)

  it("Your professions: a profession not opened yet and a character with nothing recorded, faded", function()
    local v, key = seeded()
    local other = key:match("^[^:]*:") .. "Evanion"
    AME_DB.holdings[other] = { bags = { [2589] = 1 }, bank = {} }
    ns.UI:ShowCraftingPage("professions")
    local rows, byProf = ns.UI.craftRows, {}
    for _, r in ipairs(rows) do
      byProf[r.profession or "none"] = r
    end
    assert.is_nil(byProf["First Aid"].unrecorded)
    local tailoring = byProf.Tailoring
    assert.is_true(tailoring.unrecorded)
    assert.are.equal(0.5, ns.UI.CRAFT_ROW_ALPHA.professions(tailoring))
    assert.is_true(byProf.none.none)
    assert.are.equal("Evanion", byProf.none.char)
    -- what to do, in the row and in the card; no leveling to plan for it
    local cols = v.tables.professions.opts.columns
    local wait
    for _, c in ipairs(cols) do
      wait = wait or (c.key == "wait" and c)
    end
    assert.truthy(wait.text(tailoring):find("open it once", 1, true))
    assert.truthy(wait.text(byProf.none):find("log in there once", 1, true))
    ns.UI.craftSelected = tailoring
    ns.UI:RenderCraftingDetail()
    assert.is_false(v.action:IsShown())
    assert.truthy(v.detail.cards[1].contentData.note:find("Open Tailoring once", 1, true))
    -- the selection survives a rebuild
    ns.UI:RefreshCrafting()
    assert.are.equal(ns.UI.CraftRowKey(tailoring), ns.UI.CraftRowKey(ns.UI.craftSelected))
  end)

  it("Top earners: a Signal column, Queue puts one craft on the queue, the reagents go to a list", function()
    local v = seeded()
    ns.UI:ShowCraftingPage("earners")
    local signal
    for _, c in ipairs(v.tables.earners.opts.columns) do
      signal = signal or (c.format == "signal" and c)
    end
    assert.is_not_nil(signal)
    assert.are.equal("signalRank", signal.sortKey)
    local e = ns.UI.craftRows[1]
    assert.are.equal(1251, e.itemID)
    assert.is_string(e.signal)
    ns.UI.craftSelected = e
    ns.UI:RenderCraftingDetail()
    assert.are.equal("Queue", v.action.label.text)
    assert.is_true(v.second:IsShown())
    assert.is_false(v.chart:IsShown()) -- two buttons share the width
    v.action.scripts.OnClick(v.action)
    assert.are.same({ { recipe = 3275, count = 1 } }, AME_DB.craftQueue.items)
    assert.are.equal(1, ns.UI.craftCounts.queue) -- the side menu counts the step
    assert.is_true(env:chatContains("Queued"))
  end)

  it("the craft queue page: totals in the heading, the To do, Buy / x per step, Clear", function()
    local v = seeded()
    ns.ProfessionBar.Queue():Add(3275, 3)
    ns.UI:ShowCraftingPage("queue")
    assert.are.equal(1, #ns.UI.craftRows)
    assert.truthy(v.heading.subtitle.text:find("to buy", 1, true), v.heading.subtitle.text)
    assert.is_true(v.todo:IsShown())
    local todo = v.todo.table.data
    -- the linen is in your bags: nothing to do for it; the craft itself is the one line
    assert.are.equal(1, #todo)
    assert.are.equal("Craft 3", todo[1].verb)
    assert.are.equal(1251, todo[1].itemID) -- the item is a link (the row's item column)
    -- the step's button: a queued craft comes off
    local act
    for _, c in ipairs(v.tables.queue.opts.columns) do
      act = act or (c.button and c)
    end
    assert.are.equal("x", act.button.label(ns.UI.craftRows[1]))
    assert.are.equal("Buy", act.button.label({ part = true }))
    act.button.onClick(ns.UI.craftRows[1])
    assert.are.equal(0, #AME_DB.craftQueue.items)
    assert.is_false(v.todo:IsShown())
    -- Clear, on the toolbar
    ns.ProfessionBar.Queue():Add(3275, 1)
    ns.UI:RefreshCrafting()
    local clear = v.toolbar.actions.queue[1]
    assert.are.equal("Clear", clear.label.text)
    clear.scripts.OnClick(clear)
    assert.are.equal(0, #AME_DB.craftQueue.items)
  end)

  it("the To do in words: buy, fetch and craft lines, the item kept apart as a link", function()
    seeded()
    local me = ns.Trading.CharKey()
    local row = ns.UI.QueueTodoRow(1, { kind = "buy", item = 2589, qty = 5, cost = 51000 }, me)
    assert.are.equal("Buy 5", row.verb)
    assert.are.equal(2589, row.itemID)
    assert.truthy(row.after:find("5", 1, true))
    row =
      ns.UI.QueueTodoRow(2, { kind = "craft", item = 1251, qty = 8, char = "R:Evanion", step = { part = true } }, me)
    assert.are.equal("On Evanion: craft 8", row.verb)
    assert.truthy(row.after:find("mail them over", 1, true))
    row = ns.UI.QueueTodoRow(3, { kind = "bank", item = 2589, qty = 4 }, me)
    assert.are.equal("Take 4", row.verb)
    assert.truthy(row.after:find("from the bank", 1, true))
    assert.is_nil(ns.UI.QueueTodoRow(4, { kind = "carried", item = 2589, qty = 1 }, me))
  end)

  it(
    "Find a crafter: one row per crafted thing; who can make it on the right, filling it, then the recipe item",
    function()
      local v = seeded()
      rawset(_G, "GetSpellInfo", function(id)
        return id == 3275 and "Linen Bandage" or nil
      end)
      local taughtBy = ns.Recipes.TaughtBy
      ns.Recipes.TaughtBy = function(spell)
        return spell == 3275 and { { item = 4306, rank = 1 } } or {}
      end
      finally(function()
        rawset(_G, "GetSpellInfo", nil)
        ns.Recipes.TaughtBy = taughtBy
      end)
      ns.UI.craftSearch = "bandage"
      ns.UI:ShowCraftingPage("crafters")
      local rows = ns.UI.craftRows
      assert.are.equal(1, #rows) -- the recipe item that teaches it isn't a row: nobody crafts it
      assert.are.equal(1251, rows[1].itemID)
      assert.are.equal("First Aid", rows[1].profession)
      assert.are.equal(1, rows[1].count)
      -- the recipe: its crafters in a table, then the recipe item's card with its price
      v.slots.right.pane:SetHeight(500) -- the column, as tall as a window gives it
      ns.UI.craftSelected = rows[1]
      ns.UI:RenderCraftingDetail()
      assert.is_false(v.action:IsShown()) -- Whisper is on each crafter's row
      local t = v.detail.tables.crafters
      assert.are.equal(1, #t.data)
      assert.are.equal(4306, v.detail.cards[2].parts.item.key)
      assert.is_number(ns.UI:CrafterRecipeItems(rows[1])[1].price) -- seen on the AH lately
      -- the crafters take the column's height left over: room for far more than one
      local room = (t.holder:GetHeight() - t.headH) / t.rowH
      assert.truthy(room >= 8, room)
    end
  )

  it("Sell or refine: crafting beats selling raw, and the button queues those crafts", function()
    local v = seeded()
    ns.UI:ShowCraftingPage("refine")
    local r = ns.UI.craftRows[1]
    assert.are.equal(2589, r.itemID)
    assert.is_not_nil(r.best)
    ns.UI.craftSelected = r
    ns.UI:RenderCraftingDetail()
    assert.are.equal("Queue the crafts", v.action.label.text)
    assert.are.equal("Queue the smelt", ns.UI.QueueRefineLabel({ profession = 186 }))
    v.action.scripts.OnClick(v.action)
    assert.are.same({ { recipe = 3275, count = r.best.crafts } }, AME_DB.craftQueue.items)
  end)

  it("Leveling: Queue the steps puts the path on the queue; the search narrows the steps", function()
    local v = seeded()
    ns.UI.levelTarget = 75
    ns.UI:ShowCraftingPage("leveling")
    assert.is_true(v.search:IsShown())
    local steps = 0
    for _, r in ipairs(ns.UI.craftRows) do
      steps = steps + (r.entry and 1 or 0)
    end
    assert.truthy(steps > 0)
    local step
    for _, r in ipairs(ns.UI.craftRows) do
      step = step or (r.entry and r)
    end
    ns.UI.craftSelected = step
    ns.UI:RenderCraftingDetail()
    assert.are.equal("Queue the steps", v.action.label.text)
    assert.are.equal("Reagents to a list", v.second.label.text)
    v.action.scripts.OnClick(v.action)
    local plan = ns.UI.leveling.plans.recovery
    assert.are.same(ns.Leveling.QueueList(plan), AME_DB.craftQueue.items)
    -- a search nothing matches: no steps
    ns.UI.craftSearch = "nothing like it"
    ns.UI:RefreshCrafting()
    assert.are.equal(0, #ns.UI.craftRows)
    ns.UI.craftSearch = nil
  end)
end)
