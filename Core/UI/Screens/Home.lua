-- Home (boards Home, HomeAH, HomeFirstRun): four headline numbers and two action lists. One screen, three states:
-- away from the auction house, at it (what you came to do there leads), and the first run (the three steps that
-- fill AME in). The rows come from Core/Home.lua.
local _, ns = ...
local L = ns.L

local App, Home = ns.App, ns.Home
local W = ns.Widgets

-- the strip under the lists (board Home), lined up with them: your gold over 30 days, and what waits in your mail.
-- Neither needs a fresh scan. -> { the strip's row }
local function strip(app, f)
  local line = f.goldLine
  local now = f.gold or 0
  local foot
  if line then
    local first = line.ys[1]
    app:Source(
      "home.gold",
      { xs = line.xs, ys = line.ys, color = "gold", label = L["Your gold"], format = "money", id = "home.gold" }
    )
    foot = {
      id = "home.gold.foot",
      type = "row",
      props = { gap = 8 },
      meta = { h = 16 },
      children = {
        {
          id = "home.gold.from",
          type = "text",
          props = { text = date("%b %d", line.xs[1]) .. " · " .. W.Money(first, true), size = 11, color = "dim" },
          meta = { grow = 1 },
        },
        {
          id = "home.gold.to",
          type = "text",
          props = { text = L["today · %s"]:format(W.Money(now, true)), size = 11, color = "dim", justify = "RIGHT" },
          meta = { grow = 1 },
        },
      },
    }
  else
    app:Source(
      "home.gold",
      { xs = {}, ys = {}, id = "home.gold", message = L["Your gold line fills in a point a day."] }
    )
  end
  local goldKids = {
    {
      id = "home.gold.chart",
      type = "chart",
      props = { source = "home.gold", kind = "spark", bare = true },
      meta = { grow = 1 },
    },
  }
  goldKids[#goldKids + 1] = foot
  local mailKids = {}
  for i, r in ipairs(f.mail or {}) do
    mailKids[i] = { id = "home.mail." .. i, type = "keyvalue", props = r, meta = { h = 18 } }
  end
  if #mailKids == 0 then
    mailKids[1] = {
      id = "home.mail.none",
      type = "text",
      props = { text = L["Nothing waiting, as each mailbox was last opened"], size = 12, color = "dim" },
      meta = { h = 18 },
    }
  else
    mailKids[#mailKids + 1] = {
      id = "home.mail.all",
      type = "keyvalue",
      props = { label = L["In all"], copper = f.mailTotal or 0, total = true },
      meta = { h = 18 },
    }
  end
  mailKids[#mailKids + 1] = { id = "home.mail.gap", type = "spacer", meta = { grow = 1 } }
  mailKids[#mailKids + 1] = {
    id = "home.mail.foot",
    type = "text",
    props = {
      text = L["As each character's mailbox was last opened. Mail runs out after 30 days."],
      size = 11,
      color = "dim",
    },
    meta = { h = 16 },
  }
  return {
    {
      id = "home.strip",
      type = "row",
      props = { gap = 10 },
      meta = { h = 150 },
      children = {
        {
          id = "home.goldcard",
          type = "card",
          props = { title = L["Your gold"], note = L["· 30 days, all your characters"], copper = now, gap = 4 },
          meta = { grow = 1 },
          children = goldKids,
        },
        {
          id = "home.mailcard",
          type = "card",
          props = {
            title = L["Waiting in your mail"],
            note = L["· gold and items, by when the first runs out"],
            gap = 4,
          },
          meta = { grow = 1 },
          children = mailKids,
        },
      },
    },
  }
end

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
      left = {
        {
          key = "none",
          pill = "—",
          title = L["Nothing needs you right now"],
          sub = L["Alerts, cooldowns, requests and your auctions show here"],
        },
      }
    end
    if #right == 0 then
      right = {
        {
          key = "none",
          pill = "—",
          title = L["Nothing stands out yet"],
          sub = L["More scans and your professions fill this in"],
        },
      }
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
        sub = at and L["Scan before acting on them · about a minute"]
          or L["Scan at your next visit to an auction house"],
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
  local children = {}
  if state ~= "first" then
    children = strip(app, f)
  end
  return {
    id = "home",
    type = "column",
    props = { gap = 10 },
    children = {
      {
        id = "home.kpis",
        type = "grid",
        props = { cols = 4, gap = 10, rowH = 66 },
        meta = { h = 66 },
        children = kpis,
      },
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
      children[1],
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

-- a Stock up row ("stock:<itemID>:<qty>:<usual>"): at the auction house the item opens with that amount in its buy
-- card; away from it, the amount goes on the Stock up shopping list, its top price the usual one
local function stockUp(app, p)
  local _, rest = parts(p.key)
  local id, qty, usual = (rest or ""):match("^(%d+):(%d+):(%d+)$")
  id, qty, usual = tonumber(id), tonumber(qty), tonumber(usual)
  if not (id and qty) then
    return
  end
  if app:AtAH() then
    app:Go("item", { item = id, qty = qty })
    return
  end
  local shop = ns.AME and ns.AME.shopping
  local i = shop and Home.ToStockList(shop, id, qty, usual)
  if i then
    if ns.UI and ns.UI.ShoppingChanged then
      ns.UI:ShoppingChanged(i)
    end
    ns.AME.Say(L["%s ×%d is on the %s shopping list"], W.LinkText(id), qty, L["Stock up"])
  end
end

App.Screen("home", {
  tab = "home",
  Build = body,
  Stamp = function(app)
    return Home.Current() .. (app:AtAH() and ":ah" or "")
  end,
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
    stockUp = stockUp,
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
