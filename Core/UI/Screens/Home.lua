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
    -- the newest full scan over 3 hours old (board HomeStale): a fresh scan first. It leads To do now, the rest stay
    -- but quiet; Worth doing is greyed until the scan is in, since it is ranked on the old prices.
    if Home.Stale(f) then
      local at = state == "ah"
      local quiet = {}
      for i, r in ipairs(left) do
        local q = {}
        for k, v in pairs(r) do
          q[k] = v
        end
        q.primary, q.selected = nil, nil
        quiet[i] = q
      end
      table.insert(quiet, 1, {
        key = "scan",
        pill = L["SCAN"],
        tone = "warn",
        title = L["Your prices are %s old"]:format(Home.Age(f.scanAge)),
        sub = at and L["Scan before acting on them · about a minute"] or L["Scan at your next visit to an auction house"],
        -- at the auction house: the scan button's own state (Scanning..., Full scan in 12:34: greyed while it waits)
        button = at and (App.ScanButtonState and App.ScanButtonState().label or L["Full scan"]) or L["At the AH"],
        action = "scan",
        off = not at or (App.ScanButtonState and App.ScanButtonState().off) or false,
        primary = at,
        selected = true,
      })
      left = quiet
      for _, r in ipairs(right) do
        r.off = true
      end
      rightTitle = L["Worth doing today, after a fresh scan"]
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
          -- halves: the gutter lines up with the KPI row's middle one
          { id = "home.left", type = "actionlist", props = { title = leftTitle, rows = left }, meta = { grow = 1 } },
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
      app:Go("sharing")
    end,
    goSettings = function(app)
      app:Go("settings")
    end,
    goGuide = function(app)
      app:Go("guide")
    end,
  },
})
