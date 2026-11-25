-- Crafting (boards CraftingOne, CraftingReady, CraftingMissing, CraftingQueued, CraftingLearn; shared:
-- CraftingFilters, QueueStrip, the professions sidebar): one screen, every recipe your characters can make, narrowed
-- by the five filters. A profession picked on the left shows the game's own sections (foldable), skill-up arrows and
-- Create / Create all / Queue; All professions is the flat list across characters. The rows come from
-- Core/CraftingPage.lua.
--
--   params: filter "all" | "ready" | "queued" | "missing" | "learn", profession (skill line), selected (row key),
--           count (Make N)
local _, ns = ...
local L = ns.L

local App, CP, Kit, W = ns.App, ns.CraftingPage, ns.Kit, ns.Widgets

local Screen = {}
ns.CraftingScreen = Screen

Screen.CACHE = 5 -- seconds a gather is reused (every click redraws; prices don't change that fast)

-- the facts, gathered at most every few seconds (Screen.Dirty() after something changed them)
function Screen.Facts()
  local now = GetTime and GetTime() or 0
  local c = Screen.cache
  if c and now - c.at < Screen.CACHE then
    return c.f
  end
  local f = CP.Gather()
  Screen.cache = { at = now, f = f }
  return f
end

function Screen.Dirty()
  Screen.cache = nil
end

local function queueDB()
  AME_DB.craftQueue = AME_DB.craftQueue or {}
  return ns.CraftQueue.New(AME_DB.craftQueue)
end

local function say(...)
  if ns.AME and ns.AME.Say then
    ns.AME.Say(...)
  end
end

-- ------------------------------------------------------------------------------------------------ shared pieces

-- the toolbar (board CraftingFilters): search, the five filters, Leveling and Professions; one profession picked:
-- Collapse all and the game's Filter menu
function Screen.Filters(filter, sections, state, allFolded)
  local kids = {
    {
      id = "craft.search",
      type = "input",
      props = { value = state.search or "", hint = L["Search recipes or items"], action = "search" },
      meta = { w = 180, h = 24 },
    },
    { id = "craft.filter", type = "segmented", props = { options = CP.FILTERS, selected = filter, action = "filter" }, meta = { h = 24 } },
  }
  if sections then
    kids[#kids + 1] = {
      id = "craft.collapse",
      type = "button",
      props = { label = allFolded and L["Expand all"] or L["Collapse all"], action = "collapse" },
      meta = { h = 24 },
    }
    local on = (state.skillUp or state.fav) and "selected" or nil
    kids[#kids + 1] = {
      id = "craft.filtermenu",
      type = "button",
      props = { label = L["Filter"] .. (W.ARROW_DOWN or ""), action = "filterMenu", variant = on },
      meta = { h = 24 },
    }
  end
  kids[#kids + 1] = { id = "craft.filters.gap", type = "spacer", meta = { grow = 1 } }
  kids[#kids + 1] = { id = "craft.leveling", type = "button", props = { label = L["Leveling"], action = "leveling" }, meta = { h = 24 } }
  kids[#kids + 1] = { id = "craft.professions", type = "button", props = { label = L["Professions"], action = "professions" }, meta = { h = 24 } }
  -- AME has taken over the game's profession window: the way back to it, as "Use the game's AH" (board CraftingFilters)
  if ns.CraftingSidecar and ns.CraftingSidecar.TookOver and ns.CraftingSidecar.TookOver() then
    kids[#kids + 1] = { id = "craft.gamewindow", type = "button", props = { label = L["Use the game's window"], action = "gameWindow" }, meta = { h = 24 } }
  end
  return { id = "craft.filters", type = "row", props = { gap = 6, align = "center" }, meta = { h = 26 }, children = kids }
end

function Screen.Sidebar(f, profession, compact)
  return {
    id = "craft.side",
    type = "sidebar",
    props = { entries = CP.Sidebar(f, profession), action = "side" },
    meta = { w = compact and 130 or 160 },
  }
end

function Screen.Strip(app, f)
  return { id = "craft.strip", type = "queuestrip", props = CP.Strip(f, app:AtAH()), meta = { h = 42 } }
end

local function hint(id, text)
  return { id = id, type = "text", props = { text = text, color = "dim", size = 11, wrap = true }, meta = { h = 30 } }
end

-- a card of label / value lines (KeyValue rows)
local function kvCard(id, title, list)
  local kids = {}
  for i, kv in ipairs(list) do
    kids[i] = { id = id .. "." .. i, type = "keyvalue", props = kv, meta = { h = 18 } }
  end
  return {
    id = id,
    type = "card",
    props = { title = title, gap = 2 },
    meta = { h = (title and 26 or 10) + #list * 20 + 8 },
    children = kids,
  }
end
Screen.KvCard = kvCard

local NEED_COLS = {
  { key = "item", label = L["Reagent"], width = 130, item = true },
  { key = "need", label = L["Need"], width = 40, format = "count" },
  { key = "have", label = L["Have"], width = 40, format = "count" },
  { key = "toBuy", label = L["To buy"], width = 70, format = "money" },
}

-- ------------------------------------------------------------------------------------------------ the list

local function columns(sectioned)
  if sectioned then
    return {
      { key = "item", label = L["Recipe"], width = 210, item = true },
      { key = "skill", label = L["Skill"], width = 44 },
      { key = "profit", label = L["Profit"], width = 80, format = "signedMoney" },
      { key = "ready", label = L["Ready"], width = 190, align = "LEFT" },
      { key = "queued", label = L["Queued"], width = 50 },
    }
  end
  return {
    { key = "item", label = L["Recipe"], width = 200, item = true },
    { key = "crafter", label = L["Crafter"], width = 80, align = "LEFT" },
    { key = "profit", label = L["Profit"], width = 80, format = "signedMoney" },
    { key = "ready", label = L["Ready"], width = 180, align = "LEFT" },
    { key = "queued", label = L["Queued"], width = 50 },
    { key = "queue", label = "", width = 60, button = { label = L["Queue"], action = "queueRow" } },
  }
end

-- the table's rows (plain data) from the model's
local function tableRows(list)
  local out = {}
  for _, r in ipairs(list) do
    if r.header then
      out[#out + 1] = { key = r.key, header = true, label = ns.CraftingUI.HeaderLabel(r.label, r.count, r.folded) }
    else
      out[#out + 1] = {
        key = r.key,
        item = r.item,
        label = not r.item and r.name or nil,
        skill = ns.CraftingUI.Arrows(r.diff),
        crafter = r.crafter,
        profit = r.profit,
        ready = r.ready,
        queued = r.queued and tostring(r.queued) or "",
        queue = (r.profit or 0) > 0 and L["Queue"] or false,
        faded = (r.profit and r.profit < 0 and r.n > 0 and r.short == 0) or nil,
      }
    end
  end
  return out
end

local function find(list, key)
  for _, r in ipairs(list) do
    if r.key == key and not r.header then
      return r
    end
  end
end

local function firstRow(list)
  for _, r in ipairs(list) do
    if not r.header then
      return r
    end
  end
end

-- the right column for a picked recipe
local function detail(app, f, r, filter, profession, count)
  local d = CP.Detail(f, r, count)
  local kids = {}
  if not d then
    kids[1] = hint("craft.d.none", L["Pick a recipe for what it needs and what it earns."])
    return kids
  end
  kids[#kids + 1] = { id = "craft.d.head", type = "crafthead", props = { item = d.item, title = d.title, subtitle = d.subtitle }, meta = { h = 48 } }
  if #d.tools > 0 then
    kids[#kids + 1] = { id = "craft.d.tools", type = "toolscard", props = { tools = d.tools } }
  end
  app:Source("craft.needs", d.needs)
  kids[#kids + 1] = {
    id = "craft.d.needs",
    type = "crafttable",
    props = { source = "craft.needs", columns = NEED_COLS },
    meta = { h = math.min(124, 26 + 20 * math.max(1, #d.needs)) },
  }
  if filter == "ready" and d.raw then
    local raw = d.raw
    local list = {
      { item = raw.item, count = raw.qty, label = L["sold raw"], copper = raw.raw },
      { item = raw.product, count = raw.sold and raw.sold.n, label = L["sold"], copper = raw.sold and raw.sold.copper },
      { label = L["That nets"], copper = raw.net, total = true },
      { label = raw.gain >= 0 and L["More than selling it raw"] or L["Less than selling it raw"], copper = raw.gain, signed = true },
    }
    kids[#kids + 1] = kvCard("craft.d.raw", L["Raw or refined"], list)
    if raw.rate and raw.rate > 0 then
      local days = raw.sold and raw.sold.n / raw.rate or 0
      kids[#kids + 1] = hint(
        "craft.d.rawnote",
        L["After the cut and deposits. The market takes about %d a day: list over %d days."]:format(
          math.floor(raw.rate + 0.5),
          math.max(1, math.ceil(days))
        )
      )
    end
  else
    kids[#kids + 1] = kvCard("craft.d.sell", L["Selling it"], d.sell)
  end
  kids[#kids + 1] = { id = "craft.d.gap", type = "spacer", meta = { grow = 1 } }
  local buttons, text
  -- a recipe the character you are on knows: Create (it opens the profession's window first if that is closed)
  local can = ns.CraftingUI.CanCreate(r.id)
  local me = ns.Trading and ns.Trading.CharKey and ns.Trading.CharKey()
  local mine = can
  for _, key in ipairs(r.crafters or {}) do
    if key == me then
      mine = true
    end
  end
  if mine or profession then
    buttons = {
      { key = "create", label = L["Create"], variant = mine and "primary" or "disabled", call = "create" },
      { key = "createAll", label = L["Create all"], variant = not can and "disabled" or nil, call = "createAll" },
      { key = "queue", label = L["Queue"] },
    }
    if not profession and filter == "ready" and d.raw and app:AtAH() then
      buttons[4] = { key = "sellRaw", label = L["Sell the %s raw"]:format(f.itemName(d.raw.item) or "?") }
    end
    local _, profName = ns.CraftingUI.ProfessionOf(r.id)
    if can then
      text = L["Create makes them now; Queue lines them up for later. Missing reagents: at the auction house Buy missing searches and buys; away from it, they go on a shopping list."]
    elseif mine then
      text = L["Create opens %s if its window is closed; click again to make them. Ready counts bags, bank and mail."]:format(profName or L["its profession"])
    else
      text = L["Create works on a character who knows the recipe; Queue lines it up for later."]
    end
  else
    buttons = { { key = "queue", label = L["Queue"], variant = "primary" } }
    if filter == "ready" and d.raw and app:AtAH() then
      buttons[2] = { key = "sellRaw", label = L["Sell the %s raw"]:format(f.itemName(d.raw.item) or "?") }
    end
    if filter == "missing" and #d.tools > 0 then
      text = L["Hover the tool for where it comes from: who makes it, who sells it, and its price."]
    else
      text = L["Ready counts what your characters hold: bags, bank and mail."]
    end
  end
  kids[#kids + 1] = hint("craft.d.hint", text)
  kids[#kids + 1] = {
    id = "craft.d.make",
    type = "makebar",
    props = { count = count, recipe = r.id, buttons = buttons, action = "make" },
    meta = { h = 24 },
  }
  return kids
end

local NOTES = {
  sections = L["Sections and skill-up arrows are the game's own. Ready: what you could make now from bags, bank and mail, or what stands in the way. Sections, filters and search stay as you left them."],
  all = L["All professions is one list across your characters, sorted by profit. Ready counts bags, bank and mail. Pick a profession on the left for its sections."],
  ready = L["All professions is one list across your characters, sorted by profit. Ready counts bags, bank and mail. Pick a profession on the left for its sections."],
  missing = L["What you could make if one thing were not missing: a reagent, or a tool. Sorted by profit."],
}

local function listBody(app, f, params, filter, profession, state)
  local all = CP.Rows(f)
  local list = CP.Filter(all, filter, {
    profession = profession,
    search = state.search,
    skillUp = profession and state.skillUp,
    fav = profession and state.fav,
    itemName = f.itemName,
  })
  local counts = { shown = #list, total = 0, ready = 0, queued = 0 }
  for _, r in ipairs(all) do
    if not profession or r.profession == profession then
      counts.total = counts.total + 1
      counts.ready = counts.ready + ((r.n > 0 and r.short == 0) and 1 or 0)
      counts.queued = counts.queued + (r.queued and 1 or 0)
    end
  end
  local shown, sections = list, 0
  local allFolded = false
  if profession then
    shown, sections = CP.Sectioned(list, CP.Categories(f, profession), state.folds, profession)
    allFolded = sections > 0
    for _, r in ipairs(shown) do
      if r.header and not r.folded then
        allFolded = false
      end
    end
  end
  counts.sections = sections
  Screen.counts = counts
  local picked = find(list, params.selected) or firstRow(shown)
  app:Source("craft.rows", tableRows(shown))
  local empty = f.loading and L["Crafting needs prices: scan the auction house once."]
    or #all == 0 and L["Open each of your professions once, so AME knows your recipes."]
    or L["Nothing here with these filters."]
  local center = {
    id = "craft.center",
    type = "column",
    props = { gap = 8 },
    meta = { grow = 1 },
    children = {
      {
        id = "craft.table",
        type = "crafttable",
        props = {
          source = "craft.rows",
          columns = columns(profession ~= nil),
          action = "row",
          selected = picked and picked.key,
          note = profession and NOTES.sections or NOTES[filter] or NOTES.all,
          empty = empty,
          flex = "item",
        },
        meta = { grow = 1 },
      },
      Screen.Strip(app, f),
    },
  }
  local right = {
    id = "craft.right",
    type = "column",
    props = { gap = 8 },
    meta = { w = app.compact and 250 or 300 },
    children = detail(app, f, picked, filter, profession, params.count or 1),
  }
  return center, right, profession ~= nil, allFolded
end

-- ------------------------------------------------------------------------------------------------ queued

local STEP_COLS = {
  { key = "n", label = "#", width = 24, format = "count" },
  { key = "item", label = L["Craft"], width = 190, item = true },
  { key = "who", label = L["Who"], width = 170, align = "LEFT" },
  { key = "profitText", label = L["Profit"], width = 120 },
  {
    key = "act",
    label = "",
    width = 50,
    button = {
      label = function(d)
        return d.act or "✕"
      end,
      variant = function(d)
        return d.actPrimary and "primary" or nil
      end,
      action = "stepAct",
    },
  },
}
local MAT_COLS = {
  { key = "item", label = L["Material"], width = 120, item = true },
  { key = "need", label = L["Need"], width = 40 },
  { key = "source", label = L["Source"], width = 140, format = "tag" },
}
Screen.STEP_COLS, Screen.MAT_COLS = STEP_COLS, MAT_COLS

local function stepRows(q)
  local out = {}
  for _, s in ipairs(q.steps) do
    out[#out + 1] = {
      key = s.key,
      n = s.n,
      item = s.item,
      label = s.label,
      suffix = Kit.Color("dim", "  ×" .. tostring(s.count or 0)),
      who = s.who,
      profitText = s.profitText,
      act = s.act,
      actPrimary = s.actPrimary,
    }
  end
  return out
end
Screen.StepRows = stepRows

local function queuedBody(app, f, params)
  local q = CP.Queue(f)
  app:Source("craft.steps", stepRows(q))
  local mats = {}
  for i, m in ipairs(q.mats) do
    mats[i] = {
      key = m.key,
      item = m.item,
      need = m.need,
      source = m.source,
      suffix = m.bought and Kit.Color("dim", "  " .. L["(click to make it)"]) or nil,
    }
  end
  app:Source("craft.mats", mats)
  local todo = #q.todo > 0 and q.todo or { { { text = L["Nothing to do: the queue is empty."], tone = "dim" } } }
  local center = {
    id = "craft.center",
    type = "column",
    props = { gap = 8 },
    meta = { grow = 1 },
    children = {
      {
        id = "craft.steps",
        type = "crafttable",
        props = {
          source = "craft.steps",
          columns = STEP_COLS,
          action = "stepRow",
          selected = params.selected,
          note = L["Parts first: what your characters can make is made. Where buying is cheaper the step says so; Buy switches it. Craft next skips steps this character can't do."],
          empty = L["Nothing queued. Pick a recipe and click Queue."],
          flex = "item",
        },
        meta = { grow = 1 },
      },
      { id = "craft.todo", type = "partslines", props = { title = L["To do"], lines = todo } },
    },
  }
  local right = {
    id = "craft.right",
    type = "column",
    props = { gap = 8 },
    meta = { w = app.compact and 250 or 300 },
    children = {
      kvCard("craft.q.totals", L["The queue"], {
        { label = L["To buy"], copper = q.toBuy },
        { label = L["Profit"], copper = q.profit, signed = true, total = true },
      }),
      {
        id = "craft.q.mats",
        type = "crafttable",
        props = { source = "craft.mats", columns = MAT_COLS, action = "matRow", note = L["The count is green when your bags cover it."], flex = "source" },
        meta = { h = 252 },
      },
      { id = "craft.q.gap", type = "spacer", meta = { grow = 1 } },
      hint("craft.q.hint", L["The queue is kept per account: each character sees its steps when you log in there. With the game's window, the same queue is in AME's frame beside it."]),
      {
        id = "craft.q.buttons",
        type = "row",
        props = { gap = 6 },
        meta = { h = 24 },
        children = {
          {
            id = "craft.q.next",
            type = "craftbutton",
            props = { label = L["Craft next"], variant = #q.steps > 0 and "primary" or "disabled", call = "craftNext", action = "craftedNext" },
          },
          { id = "craft.q.buy", type = "button", props = { label = app:AtAH() and L["Buy missing"] or L["Missing to a list"], action = "buyMissing" } },
          { id = "craft.q.clear", type = "button", props = { label = L["Clear"], action = "clear", variant = #q.steps == 0 and "disabled" or nil } },
        },
      },
    },
  }
  return center, right
end

-- ------------------------------------------------------------------------------------------------ to learn

local LEARN_COLS = {
  { key = "item", label = L["Recipe"], width = 190, item = true },
  { key = "who", label = L["For"], width = 70, align = "LEFT" },
  { key = "profit", label = L["Profit"], width = 80, format = "signedMoney" },
  { key = "where", label = L["Where from"], width = 210, align = "LEFT" },
  { key = "buy", label = "", width = 50, button = { label = L["Buy"], action = "learnRow" } },
}

local function learnBody(app, f, params, profession, state)
  local rows = CP.Learn({ learnRows = CP.LearnRows(f), recipeName = f.recipeName, itemName = f.itemName }, {
    profession = profession,
    search = state.search,
  })
  Screen.counts = { shown = #rows }
  local picked = find(rows, params.selected) or rows[1]
  local data = {}
  for i, r in ipairs(rows) do
    data[i] = { key = r.key, item = r.item, label = r.label, who = r.who, profit = r.profit, where = r.where, buy = r.buy, faded = r.faded }
  end
  app:Source("craft.learn", data)
  local center = {
    id = "craft.center",
    type = "column",
    props = { gap = 8 },
    meta = { grow = 1 },
    children = {
      {
        id = "craft.learn",
        type = "crafttable",
        props = {
          source = "craft.learn",
          columns = LEARN_COLS,
          action = "row",
          selected = picked and picked.key,
          note = L["For: the character who could learn it. Profit: per craft, after the cut."],
          empty = f.loading and L["Crafting needs prices: scan the auction house once."] or L["Nothing to learn that's for sale lately."],
          flex = "item",
        },
        meta = { grow = 1 },
      },
      Screen.Strip(app, f),
    },
  }
  local kids = {}
  local d = picked and CP.LearnDetail(f, picked)
  if d then
    kids[#kids + 1] = { id = "craft.l.head", type = "crafthead", props = { item = d.item, subtitle = d.subtitle }, meta = { h = 48 } }
    kids[#kids + 1] = kvCard("craft.l.worth", L["Is it worth it"], d.rows)
    if d.note then
      kids[#kids + 1] = hint("craft.l.note", d.note)
    end
  end
  kids[#kids + 1] = { id = "craft.l.gap", type = "spacer", meta = { grow = 1 } }
  kids[#kids + 1] = hint(
    "craft.l.hint",
    L["To learn lists what one of your characters could learn and none knows yet: recipes on the auction house, and ones a vendor sells."]
  )
  kids[#kids + 1] = {
    id = "craft.l.buttons",
    type = "row",
    props = { gap = 6 },
    meta = { h = 24 },
    children = {
      { id = "craft.l.search", type = "button", props = { label = L["Search the AH"], variant = picked and "primary" or "disabled", action = "learnSearch" } },
      { id = "craft.l.list", type = "button", props = { label = L["Add to a shopping list"] .. (W.ARROW_DOWN or ""), action = "learnList", variant = not picked and "disabled" or nil } },
    },
  }
  local right = { id = "craft.right", type = "column", props = { gap = 8 }, meta = { w = app.compact and 250 or 300 }, children = kids }
  return center, right
end

-- ------------------------------------------------------------------------------------------------ the screen

local function filterOf(params, state)
  local filter = params.filter or state.filter or "all"
  for _, o in ipairs(CP.FILTERS) do
    if o[1] == filter then
      return filter
    end
  end
  return "all"
end

function Screen.Build(app, params)
  local f = Screen.Facts()
  local state = CP.State()
  local filter = filterOf(params, state)
  local profession = tonumber(params.profession)
  local center, right, sections, allFolded
  if filter == "queued" then
    center, right = queuedBody(app, f, params)
    Screen.counts = {}
  elseif filter == "learn" then
    center, right = learnBody(app, f, params, profession, state)
  else
    center, right, sections, allFolded = listBody(app, f, params, filter, profession, state)
  end
  return {
    id = "craft",
    type = "column",
    props = { gap = 8 },
    children = {
      Screen.Filters(filter, sections, state, allFolded),
      {
        id = "craft.body",
        type = "row",
        props = { gap = 10 },
        meta = { grow = 1 },
        children = { Screen.Sidebar(f, profession, app.compact), center, right },
      },
    },
  }
end

-- ------------------------------------------------------------------------------------------------ actions

local function learnRow(app, key)
  local _, params = app:Current()
  local f = Screen.Facts()
  local rows = CP.Learn({ learnRows = CP.LearnRows(f), recipeName = f.recipeName, itemName = f.itemName }, { profession = tonumber(params.profession) })
  key = key or params.selected
  for _, r in ipairs(rows) do
    if r.key == key then
      return r
    end
  end
  return rows[1]
end

-- search the auction house for an item (at the AH), else open its page
local function searchOrOpen(app, item)
  if not item then
    return
  end
  if app:AtAH() and ns.AME and ns.AME.SearchAuctionHouse then
    ns.AME:SearchAuctionHouse(item)
  else
    app:Go("item", { item = item })
  end
end

-- a menu of shopping lists (and a new one) under a frame of the window; fill(index) adds to the picked one
local function listMenu(app, anchorID, newName, fill)
  local shop = ns.AME and ns.AME.shopping
  if not shop then
    return
  end
  local entries = {}
  for i, l in ipairs(shop:Lists()) do
    entries[#entries + 1] = {
      text = l.name,
      func = function()
        fill(shop, i)
      end,
    }
  end
  entries[#entries + 1] = {
    text = L["New list"],
    func = function()
      local i = shop:AddList(newName)
      if i then
        fill(shop, i)
      end
    end,
  }
  W.Menu(app.renderer:Frame(anchorID) or app.frame, entries)
end

local function addQueue(app, recipe, count)
  if not recipe then
    return
  end
  queueDB():Add(recipe, count or 1)
  Screen.Dirty()
  say(L["Queued: %s"], ns.Crafters and ns.Crafters.RecipeName and ns.Crafters.RecipeName(recipe) or recipe)
  app:Render()
end

local function buyMissing(app)
  local PB = ns.ProfessionBar
  if PB and PB.QueueToShopping then
    PB:QueueToShopping()
  end
  if app:AtAH() then
    app:Go("market", { mode = "lists" })
  end
end

Screen.actions = {
  filter = function(app, p)
    CP.State().filter = p.key
    app:Set({ filter = p.key, selected = false })
  end,
  search = function(app, p)
    local state = CP.State()
    if (state.search or "") ~= (p.text or "") then
      state.search = p.text
      app:Render()
    end
  end,
  side = function(app, p)
    if p.key == "book" then
      -- the game's profession book (K): this client's own way to open it, else say where it is
      local opened = false
      if _G.ToggleProfessionsBook then
        opened = pcall(_G.ToggleProfessionsBook)
      elseif _G.ToggleSpellBook then
        opened = pcall(_G.ToggleSpellBook, _G.BOOKTYPE_PROFESSION or "professions")
      end
      if not opened and ns.AME and ns.AME.Say then
        ns.AME.Say("%s", L["Your professions are in the game's spellbook: press K."])
      end
      return
    end
    local skillLine = tonumber(tostring(p.key):match("^prof:(%d+)$"))
    app:Set({ profession = skillLine or false, selected = false })
  end,
  row = function(app, p)
    if p.header then
      local folds = CP.State().folds
      folds[p.key] = not folds[p.key] or nil
      app:Render()
    else
      app:Set({ selected = p.key })
    end
  end,
  collapse = function(app)
    local _, params = app:Current()
    local skillLine = tonumber(params.profession)
    local f = Screen.Facts()
    local cats = skillLine and CP.Categories(f, skillLine)
    if not cats then
      return
    end
    local folds = CP.State().folds
    local shown = CP.Sectioned(CP.Filter(CP.Rows(f), "all", { profession = skillLine }), cats, folds, skillLine)
    local anyOpen = false
    for _, r in ipairs(shown) do
      anyOpen = anyOpen or (r.header and not r.folded)
    end
    for _, r in ipairs(shown) do
      if r.header then
        folds[r.key] = anyOpen or nil
      end
    end
    app:Render()
  end,
  filterMenu = function(app)
    local state = CP.State()
    W.Menu(app.renderer:Frame("craft.filtermenu") or app.frame, {
      {
        text = L["Has skill up"],
        checked = state.skillUp and true or false,
        func = function()
          state.skillUp = not state.skillUp or nil
          app:Render()
        end,
      },
      {
        text = L["Favourites"],
        checked = state.fav and true or false,
        func = function()
          state.fav = not state.fav or nil
          app:Render()
        end,
      },
    })
  end,
  leveling = function(app)
    local _, params = app:Current()
    app:Go("leveling", { profession = params.profession })
  end,
  professions = function(app)
    app:Go("professions")
  end,
  queueRow = function(app, p)
    addQueue(app, tonumber(tostring(p.key):match("^r:(%d+)$")), 1)
  end,
  make = function(app, p)
    if p.key == "count" then
      app:Set({ count = p.count })
      return
    end
    if p.key == "create" or p.key == "createAll" then
      if p.ran == "opened" then
        local _, name = ns.CraftingUI.ProfessionOf(p.recipe)
        say(L["opening %s: click Create again to make it"], name or L["its profession"])
      elseif not p.ran then
        say(L["open its profession on a character who knows it to create it"])
      end
      Screen.Dirty()
      app:Set({ count = p.count })
      return
    end
    if p.key == "queue" then
      app.state.params.count = p.count
      addQueue(app, p.recipe, p.count)
    elseif p.key == "sellRaw" then
      app:Go("sell")
    end
  end,
  openQueue = function(app)
    CP.State().filter = "queued"
    app:Set({ filter = "queued", selected = false })
  end,
  buyMissing = buyMissing,
  stepRow = function(app, p)
    app:Set({ selected = p.key })
  end,
  stepAct = function(app, p)
    local recipe = tonumber(tostring(p.key):match("^step:(%d+)$"))
    local f = Screen.Facts()
    local q = queueDB()
    for _, s in ipairs(f.plan and f.plan.steps or {}) do
      if s.recipe == recipe then
        if s.part then
          q:SetChoice(s.item, "buy") -- a part: buy it instead (the material's row switches it back)
        else
          q:Remove(recipe)
        end
      end
    end
    Screen.Dirty()
    app:Render()
  end,
  matRow = function(app, p)
    local item = tonumber(tostring(p.key):match("^mat:(%d+)$"))
    local db = AME_DB.craftQueue
    if item and db and db.choice and db.choice[item] == "buy" then
      queueDB():SetChoice(item, "make")
      Screen.Dirty()
      app:Render()
    end
  end,
  craftedNext = function(app)
    Screen.Dirty()
    app:Redraw()
  end,
  clear = function(app)
    queueDB():Clear()
    Screen.Dirty()
    app:Render()
  end,
  learnRow = function(app, p)
    local r = learnRow(app, p.key)
    if not r then
      return
    end
    if r.r.via == "vendor" then
      listMenu(app, "craft.learn", L["Recipes"], function(shop, i)
        shop:AddItem(i, r.recipeItem, 1)
      end)
    else
      searchOrOpen(app, r.recipeItem)
    end
  end,
  learnSearch = function(app)
    local r = learnRow(app)
    searchOrOpen(app, r and r.recipeItem)
  end,
  learnList = function(app)
    local r = learnRow(app)
    if r then
      listMenu(app, "craft.l.list", L["Recipes"], function(shop, i)
        shop:AddItem(i, r.recipeItem, 1)
        if ns.UI and ns.UI.ShoppingChanged then
          ns.UI:ShoppingChanged(i)
        end
      end)
    end
  end,
}

App.Screen("crafting", {
  tab = "crafting",
  Build = Screen.Build,
  Status = function(app, params)
    local f = Screen.Facts()
    if f.loading then
      return L["No prices yet"]
    end
    local filter = filterOf(params or {}, CP.State())
    return CP.Status(f, filter, tonumber(params and params.profession), Screen.counts)
  end,
  Title = function()
    return L["Crafting"]
  end,
  actions = Screen.actions,
})
