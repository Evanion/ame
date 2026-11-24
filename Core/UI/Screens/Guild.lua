-- Guild > Crafters (board CraftingCrafters), and what every Guild page shares: the nav on the left (GuildNav) and
-- the page's frame. Who can make it: type an item or enchant, pick what makes it, and Ask one of its crafters (the
-- request frame, Core/UI/Requests.lua). The model is Core/GuildPage.lua; the recipes come from Core/Crafters.lua.
local _, ns = ...
local L = ns.L

local App, GuildPage = ns.App, ns.GuildPage

local G = {}
ns.GuildScreen = G

-- the nav's counts: requests waiting on you, lists shared in the guild
function G.Counts()
  local AME = ns.AME or {}
  local lists = 0
  for _, l in ipairs(AME.watch and AME.watch.GuildLists and AME.watch:GuildLists() or {}) do
    lists = lists + (l and 1 or 0)
  end
  for _, l in ipairs(AME.shopping and AME.shopping.GuildLists and AME.shopping:GuildLists() or {}) do
    lists = lists + (l and 1 or 0)
  end
  local requests = ns.CraftRequests and ns.CraftRequests.Waiting and ns.CraftRequests.Waiting() or 0
  return { requests = requests, lists = lists }
end

-- a Guild page: the nav, the page, and its right-hand column (optional)
function G.Page(active, main, right, rightW)
  main.meta = main.meta or {}
  main.meta.grow = 1
  local kids = {
    {
      id = "guild.nav",
      type = "sidebar",
      props = { entries = GuildPage.Nav(active, G.Counts()), action = "guildNav" },
      meta = { w = 190 },
    },
    main,
  }
  if right then
    right.meta = right.meta or {}
    right.meta.w = rightW or 290
    kids[#kids + 1] = right
  end
  return { id = "guild", type = "row", props = { gap = 10 }, children = kids }
end

-- the title over a page's table: "Crafters  who can make it: ..."
function G.Heading(id, title, note)
  return { id = id, type = "heading", props = { title = title, note = note }, meta = { h = 20 } }
end

function G.Text(id, text, opts)
  opts = opts or {}
  return {
    id = id,
    type = "text",
    props = { text = text or "", color = opts.color or "dim", size = opts.size or 11, wrap = opts.wrap, justify = opts.justify },
    meta = opts.meta,
  }
end

-- every Guild page's actions
function G.Actions(own)
  local out = {
    guildNav = function(app, p)
      if p.key then
        app:Go(p.key)
      end
    end,
  }
  for k, v in pairs(own or {}) do
    out[k] = v
  end
  return out
end

-- ------------------------------------------------------------------------------------------------ crafters

local RECIPE_COLUMNS = {
  { key = "item", label = L["Makes"], width = 260, item = true, fallback = "name" },
  { key = "prof", label = L["Profession"], width = 110 },
  { key = "n", label = L["Can make it"], width = 80, format = "count" },
}

local CRAFTER_COLUMNS = {
  { key = "crafter", label = L["Crafter"], width = 170 },
  { key = "skill", label = L["Skill"], width = 44 },
  { key = "ask", label = "", width = 56, button = { label = L["Ask"], action = "ask" } },
}

-- what Crafters shows: { search, results, rows, picked = result?, crafterRows, formula = { item, price }? }
function G.CraftersData(params)
  local crafters = ns.Crafters and ns.Crafters.Shared()
  local search = params.search
  if not search and params.item then
    search = ns.ItemCache.Name(params.item) or ""
  end
  search = search or ""
  local results = crafters and search ~= "" and crafters:Search(search) or {}
  local d = { search = search, results = results, players = crafters and crafters:Players() or 0 }
  d.rows = GuildPage.RecipeRows(results, GuildPage.RecipeInfo)
  for _, r in ipairs(results) do
    if r.recipe == params.recipe then
      d.picked = r
    end
  end
  d.picked = d.picked or results[1]
  if d.picked then
    local svc = ns.SyncService
    d.crafterRows = GuildPage.CrafterRows(d.picked.who, {
      trusted = function(owner)
        return svc and svc.trust and svc.trust:IsTrusted(owner) or false
      end,
    })
    d.info = GuildPage.RecipeInfo(d.picked.recipe)
    local taught = ns.Recipes.TaughtBy and ns.Recipes.TaughtBy(d.picked.recipe) or {}
    if taught[1] then
      d.formula = { item = taught[1].item, price = GuildPage.Price()(taught[1].item) }
    end
  end
  return d
end

local function crafters(app, params)
  local d = G.CraftersData(params)
  app:Source("guild.recipes", d.rows)
  app:Source("guild.crafters", d.crafterRows or {})
  local picked = d.picked
  local main = {
    id = "guild.main",
    type = "column",
    props = { gap = 8 },
    children = {
      G.Heading("guild.h", L["Crafters"], L["who can make it: type an item or enchant above, pick what makes it"]),
      {
        id = "guild.recipes",
        type = "table",
        props = {
          source = "guild.recipes",
          columns = RECIPE_COLUMNS,
          action = "pickRecipe",
          selected = picked and tostring(picked.recipe) or nil,
          note = L["Your guild, trusted players and your own characters, as their profession windows recorded them."],
          empty = d.search == "" and L["Type part of an item or enchant name. Your guildmates' recipes arrive with sync; open each of your professions once so yours count too."]
            or L["Nobody you share with knows a recipe by that name yet."],
        },
        meta = { grow = 1 },
      },
    },
  }
  local rightKids = {}
  if picked then
    local whatKid = d.info.item
        and { id = "guild.what.item", type = "itemlink", props = { item = d.info.item, size = 13, bold = true }, meta = { h = 18 } }
      or { id = "guild.what.item", type = "text", props = { text = picked.name, color = "white", size = 13 }, meta = { h = 18 } }
    rightKids[#rightKids + 1] = {
      id = "guild.what",
      type = "card",
      props = { gap = 2 },
      meta = { h = 54 },
      children = {
        whatKid,
        G.Text("guild.what.sub", GuildPage.RecipeSub(d.info.profession, #picked.who), { meta = { h = 14 } }),
      },
    }
    rightKids[#rightKids + 1] = {
      id = "guild.crafters",
      type = "table",
      props = { source = "guild.crafters", columns = CRAFTER_COLUMNS, action = "pickCrafter", selected = params.crafter },
      meta = { grow = 1 },
    }
    rightKids[#rightKids + 1] =
      G.Text("guild.askhint", L["Ask opens the request: tick the reagents you bring, set the tip, and send."], { wrap = true, meta = { h = 28 } })
    if d.formula then
      rightKids[#rightKids + 1] = {
        id = "guild.formula",
        type = "card",
        meta = { h = 40 },
        children = {
          {
            id = "guild.formula.kv",
            type = "keyvalue",
            props = { item = d.formula.item, label = L["on the AH"], copper = d.formula.price, text = not d.formula.price and L["not on the AH"] or nil },
            meta = { h = 18 },
          },
        },
      }
    end
  else
    rightKids[1] = G.Text("guild.none", L["Pick a recipe to see who makes it."], { wrap = true, meta = { h = 30 } })
  end
  local right = { id = "guild.right", type = "column", props = { gap = 8 }, children = rightKids }
  return {
    id = "guild.screen",
    type = "column",
    props = { gap = 8 },
    children = {
      {
        id = "guild.toolbar",
        type = "row",
        props = { gap = 8 },
        meta = { h = 24 },
        children = {
          {
            id = "guild.search",
            type = "input",
            props = { value = d.search, hint = L["An item or enchant: crusader"], action = "search" },
            meta = { w = 320 },
          },
        },
      },
      (function()
        local page = G.Page("guild", main, right, 300)
        page.meta = { grow = 1 }
        return page
      end)(),
    },
  }
end

local function askNote(row, info)
  local parts = { row.online and L["online"] or L["offline"] }
  if info and info.profession ~= "" then
    parts[#parts + 1] = info.profession .. (row.skill and (" " .. row.skill) or "")
  end
  return table.concat(parts, " · ")
end

App.Screen("guild", {
  tab = "guild",
  Build = crafters,
  Title = function()
    return L["Crafters"]
  end,
  Status = function()
    local c = ns.Crafters and ns.Crafters.Shared()
    local n = c and c:Players() or 0
    return L["Recipes from %d players: your guild, trusted players and your characters · they arrive with guild sync"]:format(n)
  end,
  actions = G.Actions({
    search = function(app, p)
      app:Set({ search = p.text or "", recipe = false, item = false, crafter = false })
    end,
    pickRecipe = function(app, p)
      app:Set({ recipe = tonumber(p.key), crafter = false })
    end,
    pickCrafter = function(app, p)
      app:Set({ crafter = p.key })
    end,
    ask = function(app, p)
      local _, params = app:Current()
      local d = G.CraftersData(params)
      if not d.picked then
        return
      end
      local who
      for _, c in ipairs(d.picked.who) do
        if c.name == p.key then
          who = c
        end
      end
      if who and not who.mine and ns.Requests then
        ns.Requests.Ask(d.picked.recipe, who.name, askNote({ online = who.online, skill = who.skill }, d.info))
      end
    end,
  }),
})
