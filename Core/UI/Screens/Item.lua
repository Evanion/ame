-- Item (boards Main, ItemAH, ItemCompact, ItemAHCompact): one item's page. Away from the auction house: the header
-- (link, subtitle, search box), the action bar, the chart with its ranges and Line | Candles, the cards under it
-- (your position, other auction houses, crafting) and the right column (market price, numbers, what to post at,
-- the verdict). At the auction house the page is the same with the Buy card in the right column, and Search and Sell
-- wake up. The narrow window (app.compact) is a second layout over the same widgets: the right column folds into a
-- summary line with Details, and at the auction house the chart and the listings take turns.
-- The facts come from Core/ItemPage.lua.
local _, ns = ...
local L = ns.L

local App, ItemPage, Kit = ns.App, ns.ItemPage, ns.Kit

ns.ItemScreens = ns.ItemScreens or {}
local S = ns.ItemScreens

S.HINT = L["Scroll to zoom · drag to pan · double-click to reset"]
S.picked = nil -- the range you picked (yours from then on, for every item); until then each opens on 2D or 7D

local function W()
  return ns.Widgets
end

local function redraw(app)
  return function()
    app:Redraw()
  end
end

-- ------------------------------------------------------------------------------------------------ pieces

local function kv(id, props, h)
  return { id = id, type = "keyvalue", props = props, meta = { h = h or 18 } }
end

local function text(id, props, meta)
  return { id = id, type = "text", props = props, meta = meta or { h = 18 } }
end

local function spacer(id)
  return { id = id, type = "spacer", meta = { grow = 1 } }
end

local function card(id, title, children, meta, extra)
  local props = { title = title, gap = 2, pad = 10 }
  for k, v in pairs(extra or {}) do
    props[k] = v
  end
  return { id = id, type = "card", props = props, meta = meta, children = children }
end

-- keyvalue rows from a model's list (ids numbered)
local function rows(prefix, list)
  local out = {}
  for i, r in ipairs(list) do
    out[i] = kv(prefix .. i, r)
  end
  return out
end

-- the action bar: buttons, and the menus (shopping lists, watchlists, alerts)
local function menuEntries(kind, f)
  local AME, out = ns.AME or {}, {}
  if kind == "lists" then
    for i, l in ipairs(AME.shopping and AME.shopping:Lists() or {}) do
      out[#out + 1] = { key = "list:" .. i, label = l.name }
    end
    out[#out + 1] = { key = "new", label = L["New list..."] }
  elseif kind == "watch" then
    local watch = AME.watch
    for i, l in ipairs(watch and watch:Lists() or {}) do
      out[#out + 1] = { key = "list:" .. i, label = l.name, checked = watch:Has(i, f.key) }
    end
    out[#out + 1] = { key = "new", label = L["New list..."] }
  elseif kind == "alert" then
    for _, c in ipairs(ItemPage.AlertChoices(f.sum, f.alert)) do
      out[#out + 1] = { key = c.key, label = c.label, checked = c.checked }
    end
  end
  return out
end

local MENU_ACTION = { lists = "addToList", watch = "watchList", alert = "setAlert" }

local function actionBar(f, atAH)
  local left, right = {}, {}
  for _, a in ipairs(ItemPage.Actions(f, atAH)) do
    local item
    if a.menu then
      item = {
        id = "item.act." .. a.id,
        type = "itemmenu",
        props = { label = a.label, entries = menuEntries(a.menu, f), action = MENU_ACTION[a.menu] },
      }
    else
      item = {
        id = "item.act." .. a.id,
        type = "button",
        props = { label = a.label, action = a.action, variant = a.variant },
      }
    end
    if a.right then
      right[#right + 1] = item
    else
      left[#left + 1] = item
    end
  end
  left[#left + 1] = spacer("item.act.gap")
  for _, r in ipairs(right) do
    left[#left + 1] = r
  end
  return { id = "item.actions", type = "row", props = { gap = 6 }, meta = { h = 24 }, children = left }
end

local function header(f, compact, sub)
  return {
    id = "item.head",
    type = "row",
    props = { gap = 10, align = "center" },
    meta = { h = compact and 32 or 40 },
    children = {
      { id = "item.name", type = "itemhead", props = { item = f.key, sub = sub, compact = compact }, meta = { grow = 1 } },
      {
        id = "item.search",
        type = "input",
        props = { hint = compact and L["Search or Shift-click"] or L["Search item, or Shift-click one"], action = "find" },
        meta = { w = compact and 170 or 260, h = 24 },
      },
    },
  }
end

local function chartBar(range, style, compact)
  return {
    id = "item.bar",
    type = "row",
    props = { gap = 4 },
    meta = { h = 24 },
    children = {
      {
        id = "item.ranges",
        type = "segmented",
        props = { options = ItemPage.RangeOptions(compact), selected = range, action = "range" },
      },
      spacer("item.bar.gap"),
      {
        id = "item.style",
        type = "segmented",
        props = { options = { { "line", L["Line"] }, { "candles", L["Candles"] } }, selected = style, action = "style" },
      },
    },
  }
end

local function hiddenLayers()
  local t = ns.Settings and ns.Settings:Table("chartLayers") or {}
  local out = {}
  for k, on in pairs(t) do
    if on == false then
      out[k] = true
    end
  end
  return out
end

local function chart(range, style, compact)
  return {
    id = "item.chart",
    type = "chart",
    props = {
      source = "item.chart",
      kind = "item",
      range = range,
      style = style,
      compact = compact,
      hidden = hiddenLayers(),
      action = "layer",
      hint = S.HINT,
    },
    meta = { grow = 1 },
  }
end

-- the market price card: "Market price" with the signal and the phase at the right, Now, the change, confidence
local function priceCard(f, h)
  local pc = ItemPage.PriceCard(f.sum, f.indexed)
  local top = { text("item.price.title", { text = L["Market price"], font = "display", size = 14 }, { grow = 1 }) }
  if pc.signal then
    top[#top + 1] = { id = "item.price.signal", type = "signal", props = { signal = pc.signal }, meta = { w = 52, h = 16 } }
  end
  if pc.phase then
    top[#top + 1] = text("item.price.phase", { text = pc.phase, color = "dim", size = 11 }, { w = 70, h = 16 })
  end
  return card("item.price", nil, {
    { id = "item.price.top", type = "row", props = { gap = 4, align = "center" }, meta = { h = 18 }, children = top },
    kv("item.price.now", { label = L["Now"], copper = pc.now, text = pc.now == nil and "—" or nil, big = true }, 22),
    kv("item.price.vs", { label = pc.vsLabel, text = pc.vs, tone = pc.vsTone }),
    text("item.price.note", { text = pc.note, color = "dim", size = 11 }, { h = 16 }),
  }, { h = h or 104 })
end

local function statsCard(f)
  return card("item.stats", nil, rows("item.stat", ItemPage.StatRows(f.sum)), { h = 118 })
end

local function postCard(f)
  local p = ItemPage.PostLadder(f.advice, f.postQty, f.hours, f.cut, f.net)
  local kids = { kv("item.post.head", { label = p.head.label, text = p.head.text, tone = "dim" }) }
  if #p.picks > 0 then
    kids[#kids + 1] = {
      id = "item.post.ladder",
      type = "priceladder",
      props = { picks = p.picks, layout = "lines" },
      meta = { h = 18 * #p.picks },
    }
  end
  if p.net then
    kids[#kids + 1] = kv("item.post.net", { label = p.net.label, copper = p.net.copper })
  end
  for i, n in ipairs(p.notes) do
    kids[#kids + 1] = text("item.post.note" .. i, { text = n, color = "dim", size = 11, wrap = true }, { h = 28 })
  end
  local h = 20 + 18 + (#p.picks > 0 and 18 * #p.picks + 2 or 0) + (p.net and 20 or 0) + #p.notes * 30
  return card("item.post", nil, kids, { h = h })
end

local function verdictCard(f, meta)
  local _, head, line = ItemPage.Verdict(f.sum, {
    signal = f.indexed and f.indexed.signal,
    vendorPrice = f.indexed and f.indexed.vendorPrice,
    vendorNet = f.indexed and f.indexed.vendorNet,
  })
  return card("item.verdict", L["Verdict"], {
    text("item.verdict.head", { text = head }),
    text("item.verdict.why", { text = line, color = "dim", size = 11, wrap = true }, { grow = 1 }),
  }, meta or { grow = 1 })
end

-- the three cards under the chart: your position, other auction houses, crafting
local function lowerCards(f)
  local houses, note = ItemPage.Houses(f.houses or {}, ns.App:House(), ns.HOUSE_LABEL or {})
  local houseKids = rows("item.house", houses)
  houseKids[#houseKids + 1] = text("item.house.note", { text = note, color = "dim", size = 11 }, { h = 16 })
  return {
    id = "item.cards",
    type = "grid",
    props = { cols = 3, gap = 8, rowH = 112 },
    meta = { h = 112 },
    children = {
      card("item.position", L["Your position"], rows("item.pos", ItemPage.Position(f.held, f.basis, f.sum and f.sum.market))),
      card("item.houses", L["Other auction houses"], houseKids),
      card("item.craft", L["Crafting"], rows("item.craftrow", ItemPage.CraftRows(f.craft or {}))),
    },
  }
end

local function buyCard(f, params, bar)
  local qty = params.qty or 1
  local listings, cost, _, units = ItemPage.Listings(f.book, qty, f.now)
  if not bar then -- the narrow window's table has fed the source already (its own row keys)
    App:Source("item.listings", listings)
  end
  local props = {
    summary = ItemPage.OnSale(f.book, units, f.now),
    listings = "item.listings",
    qty = tostring(qty),
    total = cost > 0 and cost or nil,
    itemKey = f.key,
    action = "bought",
    qtyAction = "buyQty",
  }
  if bar then
    props.bar = true
    props.market = f.sum and f.sum.market
    local pc = ItemPage.PriceCard(f.sum, f.indexed)
    props.signal = pc.signal
  end
  return { id = "item.buy", type = "buycard", props = props, meta = bar and { h = 38 } or { h = 200 } }
end

-- ------------------------------------------------------------------------------------------------ the layouts

-- the right column: market price, (Buy), the numbers, what to post at, the verdict. At the auction house in a
-- window too short for all of it, the verdict gives way (the window grows at the AH: the boards' 830 px).
local function rightColumn(f, params, atAH, w)
  local kids = { priceCard(f) }
  if atAH then
    kids[#kids + 1] = buyCard(f, params)
  end
  kids[#kids + 1] = statsCard(f)
  kids[#kids + 1] = postCard(f)
  local h = App.frame and App.frame:GetHeight() or App.H
  if not atAH or h >= 800 then
    kids[#kids + 1] = verdictCard(f)
  end
  return { id = "item.right", type = "column", props = { gap = 8 }, meta = { w = w or 280 }, children = kids }
end

local function wide(f, params, atAH, range, style, sub)
  return {
    id = "item",
    type = "column",
    props = { gap = 8 },
    children = {
      header(f, false, sub),
      actionBar(f, atAH),
      {
        id = "item.main",
        type = "row",
        props = { gap = 10 },
        meta = { grow = 1 },
        children = {
          {
            id = "item.left",
            type = "column",
            props = { gap = 6 },
            meta = { grow = 1 },
            children = { chartBar(range, style, false), chart(range, style, false), lowerCards(f) },
          },
          rightColumn(f, params, atAH),
        },
      },
    },
  }
end

-- the narrow window's line under the chart: the market price and its change, the signal, what to post at, Details
local function summaryBar(f, details)
  local pc = ItemPage.PriceCard(f.sum, f.indexed)
  local w = W()
  local market = Kit.Color("dim", L["Market"]) .. " " .. (pc.now and w.Money(pc.now, true) or "—")
  if f.sum and f.sum.change then
    market = market .. " " .. Kit.Color(f.sum.change >= 0 and "good" or "bad", (f.sum.change >= 0 and "▲" or "▼") .. ("%d%%"):format(math.floor(math.abs(f.sum.change) * 100 + 0.5)))
  end
  local kids = { text("item.sum.market", { text = market }, { h = 18 }) }
  if pc.signal then
    kids[#kids + 1] = { id = "item.sum.signal", type = "signal", props = { signal = pc.signal }, meta = { w = 52, h = 16 } }
  end
  local n = f.advice and f.advice.normal
  if n then
    kids[#kids + 1] = text("item.sum.post", {
      text = Kit.Color("dim", L["Post at"]) .. " " .. w.Money(n.price, true) .. " " .. Kit.Color("dim", w.Hours(n.hours)),
    }, { h = 18 })
  end
  kids[#kids + 1] = spacer("item.sum.gap")
  kids[#kids + 1] = {
    id = "item.details",
    type = "button",
    props = { label = L["Details"] .. (details and " ▴" or " ▾"), action = "details", variant = details and "selected" or nil },
  }
  return card("item.summary", nil, kids, { h = 36 }, { layout = "row", gap = 12, pad = 6, align = "center" })
end

local function compactLayout(f, params, atAH, range, style, sub)
  local kids = { header(f, true, sub) }
  local main
  if atAH then
    local pane = params.pane or "listings"
    kids[#kids + 1] = {
      id = "item.panes",
      type = "row",
      props = { gap = 4, align = "center" },
      meta = { h = 24 },
      children = {
        {
          id = "item.pane",
          type = "segmented",
          props = {
            options = { { "chart", L["Chart"] }, { "listings", L["On sale now"] }, { "sell", L["Sell yours"] } },
            selected = pane,
            action = "pane",
          },
        },
        spacer("item.panes.gap"),
        text("item.panes.note", { text = L["cheapest first"] .. " · " .. ItemPage.OnSale(f.book, 0, f.now):gsub("^.-· ", ""), color = "dim", size = 11, justify = "RIGHT" }, { w = 220, h = 18 }),
      },
    }
    if pane == "chart" then
      main = chart(range, style, true)
    else
      local listings = ItemPage.Listings(f.book, params.qty or 1, f.now)
      App:Source("item.listings", listings)
      main = {
        id = "item.listings",
        type = "table",
        props = {
          source = "item.listings",
          columns = {
            { key = "each", label = L["Each"], width = 90, format = "money", align = "LEFT" },
            { key = "qty", label = L["Qty"], width = 90 },
            { key = "left", label = L["Time left"], width = 80 },
            { key = "yours", label = "", width = 60 },
          },
          selected = "picked",
          flex = "qty",
          empty = ItemPage.OnSale(f.book, 0, f.now),
        },
        meta = { grow = 1 },
      }
      -- the picked rows share one key: the table lights every row whose key is the picked one
      for _, r in ipairs(listings) do
        if r.selected then
          r.key = "picked"
        end
        r.left = { text = r.left, color = "dim" }
        r.yours = r.mine and { text = L["yours"], color = "gold" } or ""
      end
    end
  else
    kids[#kids + 1] = chartBar(range, style, true)
    if params.details then
      main = {
        id = "item.detailsrow",
        type = "row",
        props = { gap = 8 },
        meta = { grow = 1 },
        children = {
          chart(range, style, true),
          {
            id = "item.right",
            type = "column",
            props = { gap = 6 },
            meta = { w = 250 },
            children = { priceCard(f, 100), postCard(f), verdictCard(f) },
          },
        },
      }
    else
      main = chart(range, style, true)
    end
  end
  kids[#kids + 1] = main
  kids[#kids + 1] = atAH and buyCard(f, params, true) or summaryBar(f, params.details)
  return { id = "item", type = "column", props = { gap = 6 }, children = kids }
end

-- no item yet: the search box and how to pick one
local function empty(compact)
  return {
    id = "item",
    type = "column",
    props = { gap = 10 },
    children = {
      header({}, compact, L["Pick an item: search above, Shift-click one anywhere, or click a row on the Market tab."]),
      {
        id = "item.pick",
        type = "panel",
        props = { title = L["Item"] },
        meta = { grow = 1 },
        children = {
          text("item.pick.text", {
            text = L["Pick an item: search above, Shift-click one anywhere, or click a row on the Market tab."],
            color = "dim",
            wrap = true,
          }, { h = 40 }),
        },
      },
    },
  }
end

-- ------------------------------------------------------------------------------------------------ build

-- at the auction house: what's on sale now, searched once per item shown (Search again searches anew); the
-- purchase's progress redraws the page
local searched = {}
local function watchSearch(app, key)
  local AH = ns.AHSearch
  if not (AH and app:AtAH() and key) then
    return
  end
  AH.onChange = redraw(app)
  if not AH.results[key] and not searched[key] and AH.Push then
    searched[key] = true
    pcall(AH.Push, AH, key, redraw(app))
  end
end

function S.Build(app, params)
  local key = params.item
  local compact = app.compact and true or false
  if not key then
    S.facts = nil
    app:Source("item.chart", { points = {}, message = L["Pick an item: search above, Shift-click one anywhere, or click a row on the Market tab."] })
    return empty(compact)
  end
  local atAH = app:AtAH()
  watchSearch(app, key)
  local f = ItemPage.Gather(app, key, redraw(app))
  S.facts = f
  local range = ItemPage.Range(params.range or S.picked, f.entry and f.entry.latest, f.now, compact)
  local style = ns.Settings and ns.Settings:Get("chartStyle") == "candles" and "candles" or "line"
  app:Source("item.chart", ItemPage.ChartData(f.entry, f.sum, range, f.now, { vendor = f.vendor, trades = f.trades }))
  local sub = ItemPage.Subtitle({
    category = f.category,
    house = f.house,
    days = f.sum and #f.sum.series or 0,
    level = f.sum and f.sum.level,
    scans = f.sum and f.sum.scans,
    latest = f.entry and f.entry.latest,
    now = f.now,
    loading = f.loading,
  }, compact)
  if compact then
    return compactLayout(f, params, atAH, range, style, sub)
  end
  return wide(f, params, atAH, range, style, sub)
end

function S.Status(app, params)
  local f = S.facts
  if not (f and f.key == params.item) then
    return ""
  end
  local me = UnitName and UnitName("player")
  local out = ItemPage.PriceSource(f.raw, f.entry and f.entry.latest, f.now, me, app.compact)
  local dropped = f.sum and f.sum.dropped or 0
  if dropped > 0 then
    out = out .. " · " .. Kit.Color("warn", (dropped == 1 and L["%d outlier price ignored"] or L["%d outlier prices ignored"]):format(dropped))
  end
  return out
end

-- ------------------------------------------------------------------------------------------------ actions

local function current(app)
  local _, params = app:Current()
  return params.item, params
end

local function say(fmt, ...)
  if ns.AME and ns.AME.Say then
    ns.AME.Say(fmt, ...)
  end
end

S.actions = {
  -- the search box: a name (or a pasted link) opens that item
  find = function(app, p)
    local textIn = p and p.text or ""
    if textIn == "" then
      return
    end
    local id = ns.ItemCache and ns.ItemCache.Learn(textIn)
    if not id and ns.MarketFilter and ns.MarketFilter.FindByName and ns.AME and ns.AME.CachedIndex then
      local index = ns.AME:CachedIndex(app:Shard())
      local ok, hits = pcall(ns.MarketFilter.FindByName, index, textIn, function(i)
        return ns.ItemCache.Get(i)
      end, 1)
      id = ok and hits and hits[1] and hits[1].itemID
    end
    if id then
      app:Go("item", { item = id })
    else
      say(L["No item called %s"], textIn)
    end
  end,
  range = function(app, p)
    S.picked = p.key
    app:Set({ range = p.key })
  end,
  style = function(app, p)
    ns.Settings:Set("chartStyle", p.key)
    app:Render()
  end,
  layer = function(app, p)
    local t = ns.Settings:Table("chartLayers")
    t[p.key] = t[p.key] == false and true or false
    app:Render()
  end,
  searchAH = function(app)
    local key = current(app)
    local AH = ns.AHSearch
    if key and AH and app:AtAH() then
      AH.results[key] = nil
      searched[key] = true
      AH.onChange = redraw(app)
      pcall(AH.Push, AH, key, redraw(app))
      app:Render()
    end
  end,
  sell = function(app)
    app:Go("sell", { item = (current(app)) })
  end,
  addToList = function(app, p)
    local key = current(app)
    local shopping = ns.AME and ns.AME.shopping
    if not (key and shopping) then
      return
    end
    local i = tonumber(tostring(p.key):match("^list:(%d+)$"))
    if i then
      shopping:AddItem(i, key, 1)
      say(L["Added to %s"], shopping:Lists()[i] and shopping:Lists()[i].name or "")
      app:Render()
    elseif p.key == "new" and W().Prompt then
      W().Prompt("AME_NEW_SHOP", L["Name for the new shopping list (what it's for):"], function(name)
        local n = shopping:AddList(name)
        if n then
          shopping:AddItem(n, key, 1)
          app:Render()
        end
      end)
    end
  end,
  watchList = function(app, p)
    local key = current(app)
    local watch = ns.AME and ns.AME.watch
    if not (key and watch) then
      return
    end
    local i = tonumber(tostring(p.key):match("^list:(%d+)$"))
    if i then
      watch:Toggle(i, key)
      app:Render()
    elseif p.key == "new" and W().Prompt then
      W().Prompt("AME_NEW_LIST", L["Name for the new watchlist:"], function(name)
        local n = watch:AddList(name)
        if n then
          watch:Toggle(n, key)
          app:Render()
        end
      end)
    end
  end,
  setAlert = function(app, p)
    local key = current(app)
    local watch = ns.AME and ns.AME.watch
    if not (key and watch) then
      return
    end
    local kind, copper = tostring(p.key):match("^(%a+):(%d+)$")
    if kind == "below" then
      watch:SetAlert(key, { below = tonumber(copper), above = false })
    elseif kind == "above" then
      watch:SetAlert(key, { above = tonumber(copper), below = false })
    elseif p.key == "signal" then
      local a = watch:Alert(key)
      watch:SetAlert(key, { signal = not (a and a.signal) })
    elseif p.key == "clear" then
      watch:SetAlert(key, { below = false, above = false, signal = false })
    end
    app:Render()
  end,
  whoCan = function(app)
    app:Go("guild", { item = (current(app)) })
  end,
  toggleHidden = function(app)
    local key = current(app)
    local watch = ns.AME and ns.AME.watch
    if key and watch then
      watch:SetHidden(key, not watch:IsHidden(key))
      app:Render()
    end
  end,
  showRecipes = function(app)
    app:Go("crafting", { filter = "all", item = (current(app)) })
  end,
  details = function(app)
    local _, params = app:Current()
    app:Set({ details = not params.details })
  end,
  pane = function(app, p)
    if p.key == "sell" then
      app:Go("sell", { item = (current(app)) })
    else
      app:Set({ pane = p.key })
    end
  end,
  buyQty = function(app, p)
    local n = tonumber(p.text)
    app:Set({ qty = n and n > 0 and math.floor(n) or nil })
  end,
  -- the buy card made the game call itself; this follows the purchase's progress
  bought = function(app)
    if ns.AHSearch then
      ns.AHSearch.onChange = redraw(app)
    end
    app:Redraw()
  end,
  openItem = function(app, p)
    local key = p.item or tonumber(tostring(p.key or ""):match("(%d+)$"))
    if key then
      app:Go("item", { item = key })
    end
  end,
}

App.Screen("item", {
  tab = "item",
  Build = S.Build,
  Status = S.Status,
  actions = S.actions,
  Title = function(_, params)
    return params.item and ns.ItemCache and ns.ItemCache.Name(params.item) or L["Item"]
  end,
})

-- ------------------------------------------------------------------------------------------------ Shift-click

-- Shift-click on an item in your bags or a chat link while no chat box is open opens it here (while the new window
-- shows); with a chat box open the click is the chat's. Several hooks can report one click.
local last, lastAt
function S.OnModifiedClick(link)
  local app = ns.App
  if not (link and app and app.frame and app.frame:IsShown()) then
    return
  end
  if ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() then
    return
  end
  if not (IsModifiedClick and IsModifiedClick("CHATLINK")) then
    return
  end
  local id = ns.ItemCache and ns.ItemCache.Learn(link)
  if not id then
    return
  end
  local now = GetTime and GetTime() or 0
  if last == link and now - (lastAt or 0) < 0.3 then
    return
  end
  last, lastAt = link, now
  app:Go("item", { item = id })
end

if hooksecurefunc then
  pcall(hooksecurefunc, "HandleModifiedItemClick", function(link)
    S.OnModifiedClick(link)
  end)
end
