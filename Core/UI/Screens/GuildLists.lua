-- Guild > Guild lists (board GuildLists): the watchlists and shopping lists your guild shares, and yours that you
-- share. The picked list beside them: its items at market, Copy to my lists, Search the AH. The lists are
-- Core/Watch.lua's and Core/Shopping.lua's; they travel with guild sharing.
local _, ns = ...
local L = ns.L

local App, GuildPage, G = ns.App, ns.GuildPage, ns.GuildScreen

local COLUMNS = {
  { key = "list", label = L["List"], width = 180, align = "LEFT" },
  { key = "kind", label = L["Kind"], width = 100, align = "LEFT" },
  { key = "by", label = L["Shared by"], width = 110, align = "LEFT" },
  { key = "items", label = L["Items"], width = 50, format = "count" },
  { key = "changed", label = L["Changed"], width = 80 },
  { key = "act", label = "", width = 96, button = { label = L["Copy"], action = "listAct" } },
}

local ITEM_COLUMNS = {
  { key = "item", label = L["Item"], width = 170, item = true },
  { key = "need", label = L["Need"], width = 44, format = "count" },
  { key = "market", label = L["Market"], width = 70, format = "money" },
}

local function count(items)
  local n = 0
  for _ in pairs(items or {}) do
    n = n + 1
  end
  return n
end

-- what's shared: the guild's lists and your own shared ones
function G.Lists()
  local AME = ns.AME or {}
  local watch, shopping = AME.watch, AME.shopping
  local out = {
    watch = watch and watch:GuildLists() or {},
    shopping = shopping and shopping:GuildLists() or {},
    mineWatch = {},
    mineShopping = {},
  }
  for i, l in ipairs(watch and watch:Lists() or {}) do
    if l.shared then
      out.mineWatch[#out.mineWatch + 1] = { i = i, name = l.name, n = count(l.items) }
    end
  end
  for i, l in ipairs(shopping and shopping:Lists() or {}) do
    if l.shared then
      out.mineShopping[#out.mineShopping + 1] = { i = i, name = l.name, n = count(l.items) }
    end
  end
  return out
end

-- a row key's list: kind ("w" | "s" | "mw" | "ms"), and its key or index
local function parse(key)
  local kind, rest = tostring(key or ""):match("^(%a+):(.*)$")
  return kind, rest
end

-- the picked list: { name, kind, by, items, guild (true: someone else's), key }
local function listFor(key, lists)
  local kind, rest = parse(key)
  local AME = ns.AME or {}
  if kind == "w" or kind == "s" then
    for _, l in ipairs(kind == "w" and lists.watch or lists.shopping) do
      if l.key == rest then
        return { name = l.name, kind = kind, by = l.owner, items = l.items, guild = true, key = rest }
      end
    end
  elseif kind == "mw" or kind == "ms" then
    local i = tonumber(rest)
    local src = kind == "mw" and AME.watch or AME.shopping
    local l = src and src:Lists()[i]
    if l then
      return { name = l.name, kind = kind, by = L["you"], items = l.items, i = i }
    end
  end
end

local function build(app, params)
  local now = GetServerTime()
  local lists = G.Lists()
  local rows = GuildPage.ListRows(lists, now, ns.CraftRequests.Online)
  app:Source("guild.lists", rows)
  local key = params.list or (rows[1] and rows[1].key)
  local l = key and listFor(key, lists)
  local price = GuildPage.Price()
  app:Source("guild.listitems", l and GuildPage.ListItems(l.items, price) or {})
  local main = {
    id = "lists.main",
    type = "column",
    props = { gap = 8 },
    children = {
      {
        id = "lists.head",
        type = "row",
        props = { gap = 8, align = "center" },
        meta = { h = 24 },
        children = {
          G.Heading("lists.h", L["Guild lists"], L["watchlists and shopping lists your guild shares"]),
          { id = "lists.fill", type = "spacer", meta = { grow = 1 } },
          { id = "lists.share", type = "button", props = { label = L["Share one of mine ▾"], action = "shareMenu" } },
        },
      },
      {
        id = "lists.table",
        type = "table",
        props = {
          source = "guild.lists",
          columns = COLUMNS,
          action = "pickList",
          selected = l and key or nil,
          note = L["A shared list updates as its owner changes it. A copy is yours: it stops following theirs."],
          empty = L["Nobody in your guild shares a list yet. Share one of yours: it travels with guild sharing."],
        },
        meta = { grow = 1 },
      },
    },
  }
  local right
  if l then
    local kindText = (l.kind == "w" or l.kind == "mw") and L["Watchlist"] or L["Shopping list"]
    local at = app:AtAH()
    right = {
      id = "lists.right",
      type = "column",
      props = { gap = 8 },
      children = {
        {
          id = "lists.card",
          type = "card",
          props = { gap = 2 },
          meta = { h = 54 },
          children = {
            G.Text("lists.card.name", l.name, { color = "white", size = 13, meta = { h = 18 } }),
            G.Text("lists.card.sub", L["%s · shared by %s · %d items"]:format(kindText, l.by, count(l.items)), { meta = { h = 14 } }),
          },
        },
        { id = "lists.items", type = "table", props = { source = "guild.listitems", columns = ITEM_COLUMNS }, meta = { grow = 1 } },
        G.Text("lists.hint", L["Search it at the auction house as it is, or copy it to count your own bags against it."], { wrap = true, meta = { h = 28 } }),
        {
          id = "lists.buttons",
          type = "row",
          props = { gap = 6 },
          meta = { h = 24 },
          children = {
            {
              id = "lists.copy",
              type = "button",
              props = { label = L["Copy to my lists"], variant = l.guild and "primary" or "disabled", action = "copyList" },
            },
            {
              id = "lists.search",
              type = "button",
              props = { label = at and L["Search the AH"] or L["At the AH"], variant = at and "normal" or "disabled", action = "searchList" },
            },
          },
        },
      },
    }
  end
  return G.Page("guildlists", main, right, 340)
end

local function copy(key)
  local kind, rest = parse(key)
  local AME = ns.AME or {}
  local src = kind == "w" and AME.watch or kind == "s" and AME.shopping or nil
  if not src then
    return nil
  end
  local i = src:CopyGuildList(rest)
  if i and AME.Say then
    AME.Say(L["Copied to your lists: %s"], src:Lists()[i].name)
  end
  if i and kind == "s" and src.changed then
    pcall(src.changed, src)
  end
  return i
end

local function unshare(key)
  local kind, rest = parse(key)
  local AME = ns.AME or {}
  local src = kind == "mw" and AME.watch or kind == "ms" and AME.shopping or nil
  local i = tonumber(rest)
  local l = src and i and src:Lists()[i]
  if not l then
    return
  end
  src:SetShared(i, false)
  local svc = ns.SyncService
  if svc and svc.QueueShare then
    if kind == "mw" then
      svc:QueueShare({ l.name })
    else
      svc:QueueShare(nil, { l.name })
    end
  end
end

-- share one of your lists: the game's menu of the ones not shared yet
local function shareMenu(app)
  local AME = ns.AME or {}
  local options = {}
  for i, l in ipairs(AME.watch and AME.watch:Lists() or {}) do
    if not l.shared then
      options[#options + 1] = { label = l.name .. " · " .. L["Watchlist"], src = AME.watch, i = i, kind = "w" }
    end
  end
  for i, l in ipairs(AME.shopping and AME.shopping:Lists() or {}) do
    if not l.shared then
      options[#options + 1] = { label = l.name .. " · " .. L["Shopping list"], src = AME.shopping, i = i, kind = "s" }
    end
  end
  local function share(o)
    o.src:SetShared(o.i, true)
    if ns.SyncService and ns.SyncService.QueueShare then
      ns.SyncService:QueueShare()
    end
    app:Render()
  end
  if #options == 0 then
    if AME.Say then
      AME.Say(L["All your lists are shared already"])
    end
    return
  end
  if MenuUtil and MenuUtil.CreateContextMenu then
    MenuUtil.CreateContextMenu(nil, function(_, root)
      for _, o in ipairs(options) do
        root:CreateButton(o.label, function()
          share(o)
        end)
      end
    end)
  else
    share(options[1])
  end
end

App.Screen("guildlists", {
  tab = "guild",
  sub = true,
  Build = build,
  Title = function()
    return L["Guild lists"]
  end,
  Status = function()
    local lists = G.Lists()
    local n = #lists.watch + #lists.shopping
    return (n == 1 and L["1 list shared in the guild"] or L["%d lists shared in the guild"]:format(n))
      .. " · "
      .. L["lists travel with guild sharing"]
  end,
  actions = G.Actions({
    pickList = function(app, p)
      app:Set({ list = p.key })
    end,
    listAct = function(app, p)
      local kind = parse(p.key)
      if kind == "mw" or kind == "ms" then
        unshare(p.key)
      else
        copy(p.key)
      end
      app:Render()
    end,
    copyList = function(app)
      local _, params = app:Current()
      local lists = G.Lists()
      local rows = GuildPage.ListRows(lists, GetServerTime())
      copy(params.list or (rows[1] and rows[1].key))
      app:Render()
    end,
    searchList = function(app)
      local _, params = app:Current()
      if app:AtAH() then
        app:Go("market", { mode = "lists", guildList = params.list })
      end
    end,
    shareMenu = shareMenu,
  }),
})
