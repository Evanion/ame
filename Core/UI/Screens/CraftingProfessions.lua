-- Crafting · Your professions (board CraftingProfessions): every character on this market and its professions, as
-- their windows last showed them (skill, recipes known, cooldowns); what isn't recorded yet, faded, with what to do.
-- The picked row's card, its best earners, and the ways on: its top earners, Leveling, Your crafts.
--
--   params: selected (row key)
local _, ns = ...
local L = ns.L

local App, CP = ns.App, ns.CraftingPage
local Screen = ns.CraftingScreen

local Prof = {}
ns.CraftingProfessionsScreen = Prof

local COLS = {
  { key = "char", label = L["Character"], width = 100, align = "LEFT" },
  { key = "profession", label = L["Profession"], width = 120, align = "LEFT" },
  { key = "skillText", label = L["Skill"], width = 80 },
  { key = "known", label = L["Recipes"], width = 60, format = "count" },
  { key = "cooldown", label = L["Cooldown"], width = 130, align = "LEFT" },
}
local EARN_COLS = {
  { key = "item", label = L["Makes"], width = 150, item = true },
  { key = "perDay", label = L["Market/day"], width = 80, format = "money" },
}

-- characters seen on this market with nothing recorded (their bags were seen)
local function others()
  local out = {}
  local keep = ns.Holdings and ns.Holdings.Keep and ns.Holdings.Keep("market")
  for key in pairs(AME_DB and AME_DB.holdings or {}) do
    if not keep or keep(key) then
      out[#out + 1] = key
    end
  end
  return out
end

function Prof.Rows(f)
  local unrecorded = {}
  if ns.Professions and ns.Professions.Unrecorded then
    local ok, list = pcall(ns.Professions.Unrecorded, f.chars, others(), CP.GATHERING)
    unrecorded = ok and list or {}
  end
  return CP.ProfessionRows(f.chars, CP.Rows(f), GetServerTime and GetServerTime() or 0, unrecorded)
end

function Prof.Build(app, params)
  local f = Screen.Facts()
  local rows = Prof.Rows(f)
  local data, picked, first = {}, nil, nil
  for i, r in ipairs(rows) do
    data[i] = {
      key = r.key,
      char = r.char,
      profession = r.profession,
      skillText = r.skillText,
      known = r.known,
      cooldown = r.cooldown,
      faded = r.faded,
    }
    if r.key == params.selected then
      picked = r
    end
    first = first or r
  end
  picked = picked or first
  Prof.rows, Prof.picked = rows, picked
  app:Source("prof.rows", data)

  local right = {}
  if picked and not picked.unrecorded then
    right[#right + 1] = Screen.KvCard("prof.d.card", ("%s · %s"):format(picked.char, picked.profession), {
      { label = L["Skill"], text = picked.skillText },
      { label = L["Recipes"], text = picked.known and tostring(picked.known) or "—" },
      { label = L["Cooldown"], text = picked.cooldown.text, tone = picked.cooldown.color },
    })
    local earn = {}
    for i, e in ipairs(picked.earners) do
      earn[i] = {
        key = "earn:" .. e.id,
        item = e.item,
        label = not e.item and e.name or nil,
        perDay = e.eval and e.eval.perDay,
      }
    end
    app:Source("prof.earn", earn)
    right[#right + 1] = {
      id = "prof.d.earnTitle",
      type = "text",
      props = { text = L["Best earners"], font = "display", size = 14 },
      meta = { h = 20 },
    }
    right[#right + 1] = {
      id = "prof.d.earn",
      type = "crafttable",
      props = { source = "prof.earn", columns = EARN_COLS, empty = L["Nothing priced yet."] },
      meta = { h = 26 + 20 * math.max(2, #earn) },
    }
  elseif picked then
    right[#right + 1] = {
      id = "prof.d.none",
      type = "text",
      props = {
        text = L["Open this profession once on that character, so AME knows its recipes."],
        color = "dim",
        wrap = true,
      },
      meta = { h = 30 },
    }
  end
  right[#right + 1] = { id = "prof.d.gap", type = "spacer", meta = { grow = 1 } }
  right[#right + 1] = {
    id = "prof.d.cooldown",
    type = "check",
    props = {
      label = L["Tell me when a cooldown is ready"],
      checked = ns.Settings:Get("cooldownAlerts") ~= false,
      action = "cooldownAlerts",
    },
    meta = { h = 18 },
  }
  local usable = picked and not picked.unrecorded and picked.skillLine and not CP.GATHERING[picked.skillLine]
  right[#right + 1] = {
    id = "prof.d.buttons",
    type = "row",
    props = { gap = 6 },
    meta = { h = 24 },
    children = {
      {
        id = "prof.earners",
        type = "button",
        props = { label = L["Its top earners"], action = "earners", variant = not usable and "disabled" or nil },
      },
      {
        id = "prof.leveling",
        type = "button",
        props = { label = L["Leveling"], action = "leveling", variant = not usable and "disabled" or nil },
      },
      { id = "prof.offers", type = "button", props = { label = L["Your crafts"], action = "offers" } },
    },
  }

  return {
    id = "prof",
    type = "column",
    props = { gap = 8 },
    children = {
      {
        id = "prof.head",
        type = "row",
        props = { gap = 8, align = "center" },
        meta = { h = 26 },
        children = {
          { id = "prof.title", type = "text", props = { text = L["Your professions"], font = "display", size = 14 } },
          {
            id = "prof.note",
            type = "text",
            props = {
              text = L["every character on this market, as their profession windows last showed them"],
              color = "dim",
              size = 11,
            },
            meta = { grow = 1 },
          },
        },
      },
      {
        id = "prof.body",
        type = "row",
        props = { gap = 10 },
        meta = { grow = 1 },
        children = {
          Screen.Sidebar(f, nil, app.compact),
          {
            id = "prof.table",
            type = "crafttable",
            props = {
              source = "prof.rows",
              columns = COLS,
              action = "row",
              selected = picked and picked.key,
              note = L["Click a row for its recipes on the right. A profession counts once its window has been opened on that character."],
              empty = L["Open each of your professions once, so AME knows them."],
              flex = "cooldown",
            },
            meta = { grow = 1 },
          },
          {
            id = "prof.right",
            type = "column",
            props = { gap = 8 },
            meta = { w = app.compact and 240 or 270 },
            children = right,
          },
        },
      },
    },
  }
end

Prof.actions = {
  row = function(app, p)
    app:Set({ selected = p.key })
  end,
  side = function(app, p)
    local skillLine = tonumber(tostring(p.key):match("^prof:(%d+)$"))
    app:Go("crafting", { profession = skillLine, filter = "all" })
  end,
  cooldownAlerts = function(app, p)
    ns.Settings:Set("cooldownAlerts", p.checked and true or false)
    app:Render()
  end,
  earners = function(app)
    local r = Prof.picked
    if r and r.skillLine then
      app:Go("crafting", { profession = r.skillLine, filter = "all" })
    end
  end,
  leveling = function(app)
    local r = Prof.picked
    if r and r.skillLine then
      app:Go("leveling", { who = r.charKey, profession = r.skillLine })
    end
  end,
  offers = function(app)
    app:Go("offers")
  end,
}

App.Screen("professions", {
  tab = "crafting",
  sub = true,
  Build = Prof.Build,
  Status = function()
    local chars, recorded, hint = {}, 0, nil
    for _, r in ipairs(Prof.rows or {}) do
      chars[r.charKey] = true
      if r.unrecorded then
        local name = type(r.char) == "table" and r.char.text or r.char
        local what = type(r.profession) == "table" and r.profession.text or r.profession
        hint = hint or L["%s: open %s once to include it"]:format(name, what)
      else
        recorded = recorded + 1
      end
    end
    local n = 0
    for _ in pairs(chars) do
      n = n + 1
    end
    local s = L["%d characters · %d professions recorded"]:format(n, recorded)
    return hint and (s .. " · " .. hint) or s
  end,
  Title = function()
    return L["Your professions"]
  end,
  actions = Prof.actions,
})
