-- Crafting · Leveling (board CraftingLeveling): the cheapest path to raise a profession at today's prices
-- (Core/Leveling.lua). The toolbar picks the character's profession, the target and the goal; four cards say what the
-- path costs, gets back and nets, and how many crafts; the table is the steps with learn and train lines between
-- them; the right column is the picked step: its skill colours, reagents and net.
--
--   params: who (character key), profession (skill line), target, goal, selected (row key)
local _, ns = ...
local L = ns.L

local App, CP, W = ns.App, ns.CraftingPage, ns.Widgets
local Screen = ns.CraftingScreen

local Lv = {}
ns.CraftingLevelingScreen = Lv

local function pick(choices, params)
  local who, prof = params.who, tonumber(params.profession)
  for _, c in ipairs(choices) do
    if (not who or c.key == who) and (not prof or c.profession == prof) then
      return c
    end
  end
  return choices[1]
end

local function targetFor(choice, params)
  local t = tonumber(params.target)
  if t then
    return t
  end
  local skill = choice and choice.p.skill or 0
  for _, r in ipairs(CP.TARGETS) do
    if r > skill and r >= (choice and choice.p.max or 0) then
      return r
    end
  end
  return CP.TARGETS[#CP.TARGETS]
end

-- plans under every goal, worked out once per (character, profession, target) until the facts change
function Lv.Plans(f, choice, target)
  local key = tostring(choice.key) .. ":" .. tostring(choice.profession) .. ":" .. tostring(target)
  local c = Lv.cache
  if c and c.f == f and c.key == key then
    return c.plans
  end
  local ok, plans = pcall(CP.LevelingPlans, f, choice, target)
  plans = ok and plans or nil
  Lv.cache = { f = f, key = key, plans = plans }
  return plans
end

local COLS = {
  { key = "skill", label = L["Skill"], width = 64 },
  { key = "item", label = L["Craft"], width = 230, item = true },
  { key = "crafts", label = L["Crafts"], width = 110, align = "LEFT" },
  { key = "net", label = L["Net"], width = 80 }, -- tinted green / red (CP.LevelingRows)
  { key = "results", label = L["Results"], width = 130, align = "LEFT" },
}
local MAT_COLS = {
  { key = "item", label = L["Item"], width = 150, item = true },
  { key = "cost", label = L["Cost"], width = 80 }, -- tinted red, a dim "-" without a price
}

local function bigCard(id, label, value)
  local kv = { label = label, big = true }
  for k, v in pairs(value) do
    kv[k] = v
  end
  return {
    id = id,
    type = "card",
    props = {},
    meta = { grow = 1 },
    children = { { id = id .. ".kv", type = "keyvalue", props = kv, meta = { h = 22 } } },
  }
end

function Lv.Build(app, params)
  local f = Screen.Facts()
  local choices = CP.LevelingChoices(f.chars)
  local choice = pick(choices, params)
  local target = choice and targetFor(choice, params) or 300
  local goal = params.goal or "recovery"
  local plans = choice and f.m and Lv.Plans(f, choice, target)
  local plan = plans and plans[goal]
  local rows = CP.LevelingRows(plan, f.recipeName)
  local data = {}
  for i, r in ipairs(rows) do
    data[i] = { key = r.key, skill = r.skill, item = r.item, label = r.label, crafts = r.crafts, net = r.net, results = r.results }
  end
  app:Source("lv.rows", data)
  local picked
  for _, r in ipairs(rows) do
    if r.st and (r.key == params.selected or not picked) then
      picked = r
    end
    if r.key == params.selected and r.st then
      break
    end
  end
  Lv.picked, Lv.plan, Lv.choice, Lv.target = picked, plan, choice, target

  -- the sidebar: each character's crafting professions
  local side = {}
  local lastChar
  for _, c in ipairs(choices) do
    if c.key ~= lastChar then
      side[#side + 1] = { heading = true, label = CP.CharName(c.key) }
      lastChar = c.key
    end
    side[#side + 1] = {
      key = "lv:" .. c.key .. "|" .. c.profession,
      label = c.p.name or tostring(c.profession),
      count = c.p.skill,
      selected = choice == c,
    }
  end

  local toolbar = {
    id = "lv.bar",
    type = "row",
    props = { gap = 6, align = "center" },
    meta = { h = 26 },
    children = {
      {
        id = "lv.prof",
        type = "button",
        props = {
          label = choice and (("%s · %s %d"):format(CP.CharName(choice.key), choice.p.name or "?", choice.p.skill or 0) .. (W.ARROW_DOWN or "")) or L["No professions recorded"],
          action = "pickProf",
        },
        meta = { h = 24 },
      },
      { id = "lv.target", type = "button", props = { label = L["to %d"]:format(target) .. (W.ARROW_DOWN or ""), action = "pickTarget" }, meta = { h = 24 } },
      { id = "lv.gap", type = "spacer", meta = { grow = 1 } },
      { id = "lv.goal", type = "segmented", props = { options = CP.GOALS, selected = goal, action = "goal" }, meta = { h = 24 } },
    },
  }

  local cards = {
    id = "lv.cards",
    type = "row",
    props = { gap = 8 },
    meta = { h = 42 },
    children = {
      bigCard("lv.cost", L["Cost"], { copper = plan and -(plan.cost or 0), signed = true }),
      bigCard("lv.back", L["Results get back"], { copper = plan and plan.back or 0, signed = true }),
      bigCard("lv.net", L["Net to %d"]:format(target), { copper = plan and plan.net or 0, signed = true }),
      bigCard("lv.crafts", L["Crafts"], { text = plan and ("~" .. tostring(plan.crafts or 0)) or "—" }),
    },
  }

  local right = {}
  local d = picked and CP.LevelingDetail(picked.st)
  if d then
    local mats = {}
    for i, m in ipairs(d.mats) do
      local price = f.craft and f.craft:Price(m.item)
      mats[i] = { key = m.key, item = m.item, suffix = ns.Kit.Color("dim", "  ×" .. m.count), cost = price and ns.Widgets.SignedMoney(-(price * m.count), { tint = true }) or ns.Widgets.Dim("-") }
    end
    app:Source("lv.mats", mats)
    right = {
      { id = "lv.d.head", type = "crafthead", props = { item = d.item, subtitle = d.subtitle }, meta = { h = 48 } },
      { id = "lv.d.bar", type = "skillbar", props = d.bar, meta = { h = 14 } },
      { id = "lv.d.matsTitle", type = "text", props = { text = L["Reagents for ~%d"]:format(d.crafts), font = "display", size = 14 }, meta = { h = 20 } },
      { id = "lv.d.mats", type = "crafttable", props = { source = "lv.mats", columns = MAT_COLS }, meta = { h = math.min(130, 26 + 20 * #mats) } },
      Screen.KvCard("lv.d.net", nil, { { label = L["Net for this step"], copper = d.net, signed = true, total = true } }),
    }
  else
    right = {
      {
        id = "lv.d.none",
        type = "text",
        props = { text = L["Pick a step for its skill colours and reagents."], color = "dim", wrap = true },
        meta = { h = 30 },
      },
    }
  end
  right[#right + 1] = { id = "lv.d.gap", type = "spacer", meta = { grow = 1 } }
  right[#right + 1] = {
    id = "lv.d.buttons",
    type = "row",
    props = { gap = 6 },
    meta = { h = 24 },
    children = {
      { id = "lv.queue", type = "button", props = { label = L["Queue the steps"], variant = plan and "primary" or "disabled", action = "queueSteps" } },
      { id = "lv.list", type = "button", props = { label = L["Mats, recipes to a list"] .. (W.ARROW_DOWN or ""), action = "toList", variant = not plan and "disabled" or nil } },
    },
  }

  local empty = not f.m and L["Leveling needs prices: scan the auction house once."]
    or not choice and L["Open a profession once on each character, so AME knows its skill."]
    or L["No path with today's data: learn more recipes or scan the AH."]
  return {
    id = "lv",
    type = "column",
    props = { gap = 8 },
    children = {
      toolbar,
      {
        id = "lv.body",
        type = "row",
        props = { gap = 10 },
        meta = { grow = 1 },
        children = {
          { id = "lv.side", type = "sidebar", props = { entries = side, action = "side" }, meta = { w = app.compact and 130 or 160 } },
          {
            id = "lv.center",
            type = "column",
            props = { gap = 8 },
            meta = { grow = 1 },
            children = {
              cards,
              {
                id = "lv.table",
                type = "crafttable",
                props = {
                  source = "lv.rows",
                  columns = COLS,
                  action = "row",
                  selected = picked and picked.key,
                  note = L["Recalculated from today's prices. Results sell as far as the market takes them in about 3 days; the rest go to a vendor, are disenchanted or kept for a later step."],
                  empty = empty,
                  flex = "item",
                },
                meta = { grow = 1 },
              },
            },
          },
          { id = "lv.right", type = "column", props = { gap = 8 }, meta = { w = app.compact and 240 or 270 }, children = right },
        },
      },
    },
  }
end

-- every reagent the path buys (less what an earlier step makes), for a shopping list
function Lv.ShoppingNeeds(plan)
  local need, made = {}, {}
  for _, st in ipairs(plan and plan.steps or {}) do
    if st.entry then
      for _, r in ipairs(st.entry.recipe.reagents or {}) do
        local n = r[2] * st.crafts
        local own = math.min(n, made[r[1]] or 0)
        made[r[1]] = (made[r[1]] or 0) - own
        if n - own > 0 then
          need[r[1]] = (need[r[1]] or 0) + n - own
        end
      end
      local p = st.entry.recipe.product
      if p and st.results then
        made[p] = (made[p] or 0) + (st.results.keep or 0)
      end
      if st.learn and st.entry.recipeItem then
        need[st.entry.recipeItem] = 1
      end
    end
  end
  return need
end

Lv.actions = {
  side = function(app, p)
    local who, prof = tostring(p.key):match("^lv:(.+)|(%d+)$")
    if who then
      app:Set({ who = who, profession = tonumber(prof), target = false, selected = false })
    end
  end,
  pickProf = function(app)
    local f = Screen.Facts()
    local entries = {}
    for _, c in ipairs(CP.LevelingChoices(f.chars)) do
      entries[#entries + 1] = {
        text = ("%s · %s %d"):format(CP.CharName(c.key), c.p.name or "?", c.p.skill or 0),
        func = function()
          app:Set({ who = c.key, profession = c.profession, target = false, selected = false })
        end,
      }
    end
    W.Menu(app.renderer:Frame("lv.prof") or app.frame, entries)
  end,
  pickTarget = function(app)
    local entries = {}
    local skill = Lv.choice and Lv.choice.p.skill or 0
    for _, t in ipairs(CP.TARGETS) do
      if t > skill then
        entries[#entries + 1] = {
          text = L["to %d"]:format(t),
          checked = t == Lv.target,
          func = function()
            app:Set({ target = t, selected = false })
          end,
        }
      end
    end
    W.Menu(app.renderer:Frame("lv.target") or app.frame, entries)
  end,
  goal = function(app, p)
    app:Set({ goal = p.key, selected = false })
  end,
  row = function(app, p)
    app:Set({ selected = p.key })
  end,
  queueSteps = function(app)
    local list = ns.Leveling and ns.Leveling.QueueList(Lv.plan) or {}
    if #list == 0 then
      return
    end
    AME_DB.craftQueue = AME_DB.craftQueue or {}
    local q = ns.CraftQueue.New(AME_DB.craftQueue)
    for _, item in ipairs(list) do
      q:Add(item.recipe, item.count)
    end
    Screen.Dirty()
    app:Go("crafting", { filter = "queued" })
  end,
  toList = function(app)
    local shop = ns.AME and ns.AME.shopping
    local choice, plan = Lv.choice, Lv.plan
    if not (shop and choice and plan) then
      return
    end
    local need = Lv.ShoppingNeeds(plan)
    local entries = {}
    local function fill(i)
      for id, n in pairs(need) do
        shop:AddItem(i, id, n)
      end
      if ns.UI and ns.UI.ShoppingChanged then
        ns.UI:ShoppingChanged(i)
      end
    end
    for i, l in ipairs(shop:Lists()) do
      entries[#entries + 1] = {
        text = l.name,
        func = function()
          fill(i)
        end,
      }
    end
    entries[#entries + 1] = {
      text = L["New list"],
      func = function()
        local i = shop:AddList(L["%s to %d"]:format(choice.p.name or "?", Lv.target))
        if i then
          fill(i)
        end
      end,
    }
    W.Menu(app.renderer:Frame("lv.list") or app.frame, entries)
  end,
}

App.Screen("leveling", {
  tab = "crafting",
  sub = true,
  Build = Lv.Build,
  Status = function()
    local c, plan = Lv.choice, Lv.plan
    if not c then
      return ""
    end
    local parts = { ("%s · %s %d/%d"):format(CP.CharName(c.key), c.p.name or "?", c.p.skill or 0, c.p.max or 0) }
    local unknown, estimated = 0, false
    for _, st in ipairs(plan and plan.steps or {}) do
      if st.entry and not st.entry.known then
        unknown = unknown + 1
      end
      estimated = estimated or (st.entry and st.entry.estimated) or false
    end
    if unknown > 0 then
      parts[#parts + 1] = L["%d steps use recipes not yet known"]:format(unknown)
    end
    if estimated then
      parts[#parts + 1] = L["trainer levels estimated where marked"]
    end
    return table.concat(parts, " · ")
  end,
  Title = function()
    return L["Leveling"]
  end,
  actions = Lv.actions,
})
