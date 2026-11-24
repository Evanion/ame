-- Home (boards Home, HomeAH, HomeFirstRun): four headline numbers and two action lists. One screen, three states:
-- away from the auction house, at it (what you came to do there leads), and the first run (the three steps that
-- fill AME in). The rows come from Core/Home.lua.
local _, ns = ...
local L = ns.L

local App, Home = ns.App, ns.Home

local function body(app)
  local f = Home.Gather()
  local state = Home.State(f, app:AtAH())
  local kpis = {}
  for i, k in ipairs(Home.Kpis(f)) do
    kpis[i] = { id = "home.kpi" .. i, type = "kpi", props = k }
  end
  local left, right, leftTitle, rightTitle
  if state == "first" then
    left, right = Home.Steps(f), Home.Know()
    leftTitle, rightTitle = L["Three steps to get going"], L["Good to know"]
  else
    left, right = Home.Todo(f, state == "ah"), Home.Worth(f, state == "ah")
    leftTitle = state == "ah" and L["To do now, at the auction house"] or L["To do now"]
    rightTitle = L["Worth doing today"]
    if #left == 0 then
      left = { { key = "none", pill = "—", title = L["Nothing needs you right now"], sub = L["Alerts, cooldowns, requests and your auctions show here"] } }
    end
    if #right == 0 then
      right = { { key = "none", pill = "—", title = L["Nothing stands out yet"], sub = L["More scans and your professions fill this in"] } }
    end
  end
  return {
    id = "home",
    type = "column",
    props = { gap = 10 },
    children = {
      { id = "home.kpis", type = "grid", props = { cols = 4, gap = 10, rowH = 66 }, meta = { h = 66 }, children = kpis },
      {
        id = "home.cols",
        type = "row",
        props = { gap = 10 },
        meta = { grow = 1 },
        children = {
          { id = "home.left", type = "actionlist", props = { title = leftTitle, rows = left }, meta = { grow = 1.08 } },
          { id = "home.right", type = "actionlist", props = { title = rightTitle, rows = right }, meta = { grow = 1 } },
        },
      },
    },
  }
end

-- a row key's parts: "craft:123" -> "craft", "123"
local function parts(key)
  local kind, rest = tostring(key):match("^(%a+):(.*)$")
  return kind, rest
end

local function queue(app, p)
  local kind, rest = parts(p.key)
  local recipe = tonumber(rest and rest:match("^(%d+)"))
  if kind == "refine" then
    recipe = tonumber(rest:match(":(%d+)$"))
  end
  if recipe and AME_DB then
    AME_DB.craftQueue = AME_DB.craftQueue or {}
    ns.CraftQueue.New(AME_DB.craftQueue):Add(recipe, 1)
    ns.AME.Say(L["Queued: %s"], ns.Crafters and ns.Crafters.RecipeName and ns.Crafters.RecipeName(recipe) or recipe)
  end
  app:Go("crafting", { filter = "queued" })
end

App.Screen("home", {
  tab = "home",
  Build = body,
  Status = function(app)
    local f = Home.Gather()
    if not f.hasPrices then
      return L["No prices yet"]
    end
    return app:AtAH() and L["At the auction house"] or ""
  end,
  actions = {
    openItem = function(app, p)
      local _, rest = parts(p.key)
      app:Go("item", { item = tonumber(rest and rest:match("^(%d+)")) })
    end,
    queue = queue,
    openRequest = function(app, p)
      local _, id = parts(p.key)
      app:Go("requests", { request = id })
    end,
    goAuctions = function(app)
      app:Go("auctions")
    end,
    goSell = function(app)
      app:Go("sell")
    end,
    goArbitrage = function(app)
      app:Go("market", { mode = "arbitrage" })
    end,
    goLearn = function(app)
      app:Go("crafting", { filter = "learn" })
    end,
    goCrafting = function(app)
      app:Go("crafting")
    end,
    goSharing = function(app)
      app:Go("settings", { section = "sharing" })
    end,
    goSettings = function(app)
      app:Go("settings")
    end,
    goGuide = function(app)
      app:Go("guide")
    end,
  },
})
