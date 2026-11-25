-- Market (boards Market, MarketAlerts, MarketAH, ShoppingList, MarketAHList, Arbitrage, MarketCompact,
-- MarketAHCompact): one screen with four modes (params.mode = "screener" | "overview" | "arbitrage" | "lists").
--   screener   the market index filtered (search, quality, price, signal, category or watchlist); view "alerts" is
--              the same screener over the items you set an alert on, with the alert's columns. At the auction house
--              the search box searches the auction house, the table shows what's on sale now and the picked row
--              (params.pick) gets a panel with the Buy card.
--   lists      a shopping list (params.list = "shop:<i>" | "sg:<key>"): need, have, to buy, cost; at the auction
--              house Search all and the bar for buying down the list.
--   arbitrage  routes between two auction houses (Core/Arbitrage.lua), worked out once both indexes are in.
--   overview   ns.ItemScreens.OverviewBody (Core/UI/Screens/MarketOverview.lua) under the mode switch.
-- The narrow window (app.compact) folds the modes and the categories into dropdowns and drops the sidebar.
-- Rows and words come from Core/Market.lua; the filters live here, per screen (MarketScreen.q), not in the old UI.
local _, ns = ...
local L = ns.L

local App, Market, Layout = ns.App, ns.Market, ns.Layout

local S = {
  q = Market.NewQuery(),
  ah = { text = "", filters = {} },
  lists = { onlyTop = true, skip = {} },
  cache = {},
  status = "",
}
ns.MarketScreen = S

-- ------------------------------------------------------------------------------------------------ helpers

local function try(fn, ...)
  return ns.Shield(fn, ...) -- a failing piece is left out; its error goes to the game's handler (BugSack)
end

local function W()
  return ns.Widgets or {}
end

local function now()
  return GetServerTime and GetServerTime() or os.time()
end

local function today()
  return ns.Today and ns.Today(now()) or nil
end

local function avgDays()
  return ns.Settings and ns.Settings:Get("tooltipAvgDays") or 7
end

local function info(key)
  return ns.ItemCache and ns.ItemCache.Get(key) or {}
end

local function itemName(key)
  return ns.ItemCache and ns.ItemCache.Name and ns.ItemCache.Name(key) or tostring(key)
end

local function money(copper)
  return W().Money and W().Money(copper, true) or tostring(copper)
end

local function arrow()
  return W().ARROW_DOWN or " v"
end

local function say(...)
  if ns.AME and ns.AME.Say then
    ns.AME.Say(...)
  end
end

local function redraw()
  App:Redraw()
end

local function houseLabel(house)
  return ns.HOUSE_LABEL and ns.HOUSE_LABEL[house] or tostring(house)
end

-- a menu under the button that was clicked (the frame under the mouse), or at the pointer
local function menu(app, entries, atCursor)
  local Menu = W().Menu
  if not Menu then
    return
  end
  local focus = GetMouseFoci and GetMouseFoci()
  focus = type(focus) == "table" and focus[1] or (GetMouseFocus and GetMouseFocus())
  local anchor = type(focus) == "table" and focus.IsVisible and focus or app.frame
  Menu(anchor, entries, atCursor and { cursor = true } or nil)
end

local function prompt(id, text, onAccept, data)
  if W().Prompt then
    W().Prompt(id, text, onAccept, data)
  end
end

local function gold(copper)
  if not copper then
    return ""
  end
  return ("%g"):format(copper / 10000)
end

local function btn(id, label, action, variant, payload)
  return { id = id, type = "button", props = { label = label, action = action, variant = variant, payload = payload } }
end

local function text(id, value, color, size, meta)
  return { id = id, type = "text", props = { text = value or "", color = color, size = size }, meta = meta }
end

-- money: the amount drawn in its coins' colours while it isn't being typed in
local function input(id, value, hint, action, w, money)
  return { id = id, type = "input", props = { value = value or "", hint = hint, action = action, money = money or nil }, meta = { w = w, h = 24 } }
end

local function gap(id, w)
  return { id = id, type = "spacer", meta = w and { w = w } or { grow = 1 } }
end

-- the market index for the viewed auction house: nil and "loading" (built in the background; the screen draws again
-- when it's in) or "empty" (no history there)
local function viewIndex(app)
  local AME = ns.AME
  if not (AME and AME.CachedIndex) then
    return nil, "loading"
  end
  local shard = app:Shard()
  local idx = AME:CachedIndex(shard)
  if idx then
    return idx
  end
  if AME.HistoryLoaded and AME:HistoryLoaded() and AME.HasData and not AME:HasData(shard) then
    return nil, "empty"
  end
  if S.loading ~= shard and AME.IndexFor then
    S.loading = shard
    try(AME.IndexFor, AME, shard, function()
      S.loading = nil
      redraw()
    end)
  end
  return AME:CachedIndex(shard), "loading"
end

local function loadingText(app, why)
  if why == "empty" then
    return L["No price history for the %s yet: scan there (any character on this account counts)."]:format(houseLabel(app:House()))
  end
  return ns.AME and ns.AME.HistoryLoaded and ns.AME:HistoryLoaded() and L["Building market index..."] or L["Loading history..."]
end

-- what you hold, by key (the screener's You hold): your characters on this market, counted lazily
local function heldQty(places, scope)
  local map = ns.Holdings and try(ns.Holdings.Of, places, scope) or {}
  return setmetatable({}, {
    __index = function(_, key)
      local h = map[key]
      return h and h.qty
    end,
  }),
    map
end

-- the modes: segmented on a wide window, a dropdown button on a narrow one
local function modeSwitch(app, mode)
  if app.compact then
    return btn("market.mode", Market.ModeLabel(mode) .. arrow(), "modeMenu")
  end
  return { id = "market.mode", type = "segmented", props = { options = Market.ModeOptions(), selected = mode, action = "mode" } }
end

-- the table widget takes confidence bars once it knows them (a proposed prop); until then they're left out
local function tableProps(p)
  local def = Layout.Get("table")
  if p.confidence and not (def and def.props.confidence) then
    p.confidence = nil
  end
  return p
end

-- ------------------------------------------------------------------------------------------------ screener facts

local function watch()
  return ns.AME and ns.AME.watch
end

local function sideFacts(idx)
  local w = watch()
  local f = { lists = {}, guild = {}, sets = { lists = {}, guild = {} }, star = W().StarInline and W().StarInline(12) }
  local hidden = w and w:Hidden() or {}
  f.sets.hidden = hidden
  local hiddenHere = 0
  for id in pairs(hidden) do
    if idx and idx.items[id] then
      hiddenHere = hiddenHere + 1
    end
  end
  f.total = (idx and (idx.count or Market.Size(idx.items)) or 0) - hiddenHere
  f.hidden = w and w:HiddenCount() > 0 and hiddenHere or 0
  if w then
    for i, l in ipairs(w:Lists()) do
      f.lists[i] = { name = l.name, count = w:Count(i) }
      f.sets.lists[i] = l.items
    end
    for _, g in ipairs(w:GuildLists()) do
      f.guild[#f.guild + 1] = { key = g.key, name = g.name, owner = g.owner, count = Market.Size(g.items) }
      f.sets.guild[g.key] = g.items
    end
    f.alerts = Market.Size(w.db and w.db.alerts)
  end
  if idx then
    if S.catIndex ~= idx or S.catHidden ~= f.hidden then
      S.catIndex, S.catHidden = idx, f.hidden
      S.categories = try(ns.MarketFilter.Categories, idx, info, hidden) or {}
      local C = ns.ItemCache
      for _, c in ipairs(S.categories) do
        c.name = C and C.ClassName and C.ClassName(c.classID) or tostring(c.classID)
        for _, s in ipairs(c.subs or {}) do
          s.name = C and C.SubClassName and C.SubClassName(c.classID, s.subClassID) or tostring(s.subClassID)
        end
      end
    end
    f.categories = S.categories
  end
  return f
end

-- the list the query names, current (a watchlist's items change under it)
local function resolveList(q, f)
  if type(q.list) == "number" then
    q.only = f.sets.lists[q.list]
    if not q.only then
      q.list = nil
    end
  elseif type(q.list) == "string" and q.list:match("^g:") then
    q.only = f.sets.guild[q.list:sub(3)]
    if not q.only then
      q.list = nil
    end
  elseif q.list == "hidden" then
    q.only = f.sets.hidden
  end
end

local function chipNames(q, f)
  local out = {}
  if type(q.list) == "number" and f.lists[q.list] then
    out.listName = f.lists[q.list].name
  elseif q.list == "hidden" then
    out.listName = L["Hidden"]
  elseif type(q.list) == "string" then
    for _, g in ipairs(f.guild) do
      if "g:" .. g.key == q.list then
        out.listName = g.name
      end
    end
  end
  if q.classID then
    for _, c in ipairs(f.categories or {}) do
      if c.classID == q.classID then
        out.className = c.name
        for _, s in ipairs(c.subs or {}) do
          if s.subClassID == q.subClassID then
            out.className = s.name
          end
        end
      end
    end
  end
  return out
end

-- the filtered, sorted list, built again only when the index, the filters or the sort change
local function screenerList(idx, q, opts)
  local C = ns.ItemCache or {}
  local sig = table.concat({
    tostring(idx),
    tostring(q.text),
    tostring(q.minQuality),
    tostring(q.minPrice),
    tostring(q.maxPrice),
    tostring(q.signal),
    tostring(q.classID),
    tostring(q.subClassID),
    tostring(q.list),
    tostring(q.sortKey),
    tostring(q.ascending),
    tostring(opts.alerts ~= nil),
    tostring(Market.Size(opts.alerts or q.only)),
    tostring(opts.hiddenN),
    tostring(avgDays()),
    tostring(C.warmDone),
  }, "|")
  local c = S.cache
  if c.sig ~= sig then
    Market.PrepareVsAvg(idx, avgDays())
    local list, unnamed = ns.MarketFilter.Apply(idx, Market.FilterQuery(q, opts), info)
    c = { sig = sig, list = list or {}, unnamed = unnamed }
    S.cache = c
  end
  return c.list, c.unnamed
end

-- where the index's data comes from: your newest full scan, or a guild member's
local function scanFacts(app)
  local AME = ns.AME
  local data = AME and AME.HistoryLoaded and AME:HistoryLoaded() and AME.history and AME.history.shards[app:Shard()]
  local full = data and Market.LastFull(data.raw)
  if not full then
    return nil
  end
  local me = UnitName and UnitName("player")
  return W().Ago and W().Ago(full.t, now()) or "", (full.src and full.src ~= me) and full.src or nil
end

-- ------------------------------------------------------------------------------------------------ toolbars

local function screenerToolbar(app, params, hidden, ah)
  local q = S.q
  local alerts = params.view == "alerts"
  local kids = { modeSwitch(app, "screener"), gap("market.gap1", 4) }
  if app.compact then
    local current = L["All items"]
    if alerts then
      current = L["Your alerts"]
    else
      local names = chipNames(q, S.side or { lists = {}, guild = {} })
      current = names.listName or names.className or current
    end
    kids[#kids + 1] = btn("market.category", current .. arrow(), "categoryMenu")
  end
  if ah then
    kids[#kids + 1] = input("market.search", S.ah.text, L["Search the auction house..."], "ahText", app.compact and 150 or 200)
    kids[#kids + 1] = btn("market.go", L["Search"], "ahSearch", "primary")
    if not app.compact then
      local n = ns.AHBrowse and ns.AHBrowse.Count and ns.AHBrowse.Count(S.ah.filters) or 0
      kids[#kids + 1] = btn("market.filtersBtn", n > 0 and L["Filters (%d)"]:format(n) or L["Filters"], "ahFilters")
    end
  else
    kids[#kids + 1] = input("market.search", q.text, L["Search items..."], "search", app.compact and 150 or 160)
  end
  kids[#kids + 1] = btn("market.quality", Market.QualityLabel(alerts and 0 or q.minQuality) .. arrow(), "quality")
  if app.compact then
    kids[#kids + 1] = {
      id = "market.signals",
      type = "signalfilter",
      props = { selected = q.signal or "all", signals = { "all", "buy", "hold", "sell" }, action = "signal" },
    }
    kids[#kids + 1] = btn("market.more", L["More"] .. arrow(), "more")
  else
    kids[#kids + 1] = input("market.min", gold(q.minPrice), L["min g"], "minPrice", 60, true)
    kids[#kids + 1] = input("market.max", gold(q.maxPrice), L["max g"], "maxPrice", 60, true)
    kids[#kids + 1] = gap("market.gap2")
    kids[#kids + 1] = btn("market.views", L["Views"] .. arrow(), "views")
    kids[#kids + 1] = btn("market.columns", Market.ColumnsLabel(hidden), "columns")
  end
  return { id = "market.bar", type = "row", props = { gap = 6, align = "center" }, meta = { h = 24 }, children = kids }
end

local function filterRow(app, params, ah)
  local q = S.q
  local names = chipNames(q, S.side or { lists = {}, guild = {} })
  names.ahText = ah and S.ah.text or nil
  return {
    id = "market.filters",
    type = "row",
    props = { gap = 6, align = "center" },
    meta = { h = 24 },
    children = {
      { id = "market.signal", type = "signalfilter", props = { selected = q.signal or "all", action = "signal" } },
      gap("market.gap3", 6),
      {
        id = "market.chips",
        type = "chips",
        props = { chips = Market.Chips(q, names, params.view), action = "chip", clearAction = "clearAll" },
        meta = { grow = 1, h = 20 },
      },
    },
  }
end

-- ------------------------------------------------------------------------------------------------ the AH panel

local function buyCard(app, key)
  local book = ns.AHSearch and ns.AHSearch.results and ns.AHSearch.results[key]
  local qty = S.buyQty and S.buyQty[key] or 1
  local listings, cost, onSale = Market.Listings(book, qty, now())
  app:Source("market.listings", listings)
  local summary
  if not book then
    summary = L["searching..."]
  elseif #listings == 0 then
    summary = L["none listed"]
  else
    summary = L["%s on sale · %s"]:format(W().Count and W().Count(onSale) or onSale, W().Ago and W().Ago(book.at, now()) or "")
  end
  local def = Layout.Get("buycard")
  if not def then -- the Item area's widget isn't there yet: say so rather than draw nothing
    return text("market.buy", L["Buy: on the item's page"], "dim", 11, { h = 20 })
  end
  local props = { summary = summary, listings = "market.listings", total = cost, itemKey = key }
  local kind = def.props.qty and tostring(def.props.qty):match("^%a+")
  props.qty = kind == "string" and tostring(qty) or qty
  if def.props.action then
    props.action = "bought"
  end
  if def.props.qtyAction then
    props.qtyAction = "buyQty"
  end
  return { id = "market.buy", type = "buycard", props = props, meta = { h = 200 } }
end

local function pickPanel(app, key, idx)
  local w = app.compact and 220 or 270
  if not key then
    return {
      id = "market.pick",
      type = "column",
      props = { gap = 8 },
      meta = { w = w },
      children = {
        text("market.pickHint", L["Click a row: its listings and Buy show here."], "dim", 11, { h = 18 }),
      },
    }
  end
  local s = idx and idx.items[key] or {}
  local avg = s["avg" .. avgDays()] or s.avg7
  local line2 = {}
  if s.market and avg and avg > 0 then
    local d = s.market / avg - 1
    line2[#line2 + 1] = d < 0 and L["%d%% under its %d-day average"]:format(math.floor(-d * 100 + 0.5), avgDays())
      or L["%d%% over its %d-day average"]:format(math.floor(d * 100 + 0.5), avgDays())
  end
  local held = heldQty("owned", "market")[key]
  if held and held > 0 then
    line2[#line2 + 1] = L["you hold %d"]:format(held)
  end
  return {
    id = "market.pick",
    type = "column",
    props = { gap = 8 },
    meta = { w = w },
    children = {
      {
        id = "market.pickCard",
        type = "card",
        props = { gap = 3 },
        meta = { h = 82 },
        children = {
          { id = "market.pickItem", type = "itemlink", props = { item = key, size = 14, bold = true }, meta = { h = 20 } },
          {
            id = "market.pickLine",
            type = "row",
            props = { gap = 5, align = "center" },
            meta = { h = 16 },
            children = {
              text("market.pickMarketLabel", L["market"], "dim", 11),
              { id = "market.pickMarket", type = "money", props = { copper = s.market, size = 11 } },
              text("market.pickDot", "·", "dim", 11),
              { id = "market.pickSignal", type = "signal", props = { signal = s.signal } },
              text("market.pickRate", s.soldPerDay and ("· " .. L["%s sells/day"]:format(W().Rate and W().Rate(s.soldPerDay):gsub("/d$", "") or tostring(s.soldPerDay))) or "", "dim", 11),
            },
          },
          text("market.pickNote", table.concat(line2, " · "), "dim", 11, { h = 16 }),
        },
      },
      buyCard(app, key),
      {
        id = "market.pickActions",
        type = "row",
        props = { gap = 6 },
        meta = { h = 24 },
        children = {
          btn("market.open", L["Open item"], "openItem", nil, key),
          btn("market.addList", L["Add to a shopping list"] .. arrow(), "addToList", nil, key),
        },
      },
    },
  }
end

-- ------------------------------------------------------------------------------------------------ screener

local function screenerBody(app, params)
  local q = S.q
  local ah = app:AtAH()
  local alerts = params.view == "alerts" and not ah
  local idx, why = viewIndex(app)
  local f = sideFacts(idx)
  S.side = f
  resolveList(q, f)
  local chosen = ns.Settings and ns.Settings:Table("marketColumns") or {}
  local state = ah and (app.compact and "ahcompact" or "ah") or alerts and "alerts" or app.compact and "compact" or "screener"
  local columns, hidden = Market.Columns(state, chosen, avgDays())
  local rows, empty, note, selected = {}, nil, nil, nil
  local hold = heldQty("owned", "market")
  -- a list or a category picked at the auction house, not searched yet: its items from your scans, as away (a click
  -- searches the row's item); the toolbar keeps the auction house's search box
  local listed = ah and (q.list ~= nil or q.classID ~= nil) and not S.ah.at
  if listed then
    state = app.compact and "compact" or "screener"
    columns, hidden = Market.Columns(state, chosen, avgDays())
  end
  if ah and not listed then
    local B = ns.AHBrowse
    local found = (B and S.ah.at) and B.Rows(B.results, S.ah.filters, idx and idx.items) or {}
    rows = Market.AHRows(found, idx and idx.items, { minQuality = q.minQuality, minPrice = q.minPrice, maxPrice = q.maxPrice, signal = q.signal, classID = q.classID, subClassID = q.subClassID, only = q.only }, info, avgDays())
    S.status = Market.AHStatus(houseLabel(app:House()), #rows, B and B.active, S.ah.at and W().Ago and W().Ago(S.ah.at, now()))
    empty = S.ah.at and L["Nothing on sale matches these filters."] or L["Search the auction house: type a name and press Enter."]
    note = app.compact and L["On sale now, from the auction house. Click a row to open the item: its listings, and Buy. Lists and categories are in the first dropdown."]
      or L["On sale now. Click a row: its listings and Buy show on the right. The item's name opens its page."]
    selected = params.pick or nil
  elseif not idx then
    empty = loadingText(app, why)
    S.status = ""
  elseif alerts then
    local w = watch()
    local set = w and w.db and w.db.alerts or {}
    local list = screenerList(idx, q, { alerts = set })
    local notices = ns.AME and ns.AME.notices
    local fired = Market.FiredFrom(notices and notices:List() or {}, notices and function(e)
      return notices:IsUnread(e)
    end)
    local lit
    rows, lit = Market.AlertRows(list, set, {
      fired = fired,
      now = now(),
      date = date,
      held = hold,
      today = idx.day or today(),
      filtered = (q.text and q.text ~= "") or q.signal ~= nil or q.minPrice ~= nil or q.maxPrice ~= nil,
    })
    selected = lit
    S.status = Market.AlertStatus(Market.Size(set), Market.FiredToday(fired, now()))
    empty = L["No alerts yet. Set one on an item's page, or from its right-click menu."]
    note = L["Click a row to open the item; right-click to change or remove its alert. A lit row has fired and not been opened yet."]
  else
    local list, unnamed = screenerList(idx, q, { only = q.only, hidden = f.sets.hidden, hiddenN = f.hidden })
    if S.cache.rows == nil or S.cache.rowsFor ~= S.cache.sig then
      S.cache.rows = Market.ScreenerRows(list, { today = idx.day or today(), held = hold })
      S.cache.rowsFor = S.cache.sig
    end
    rows = S.cache.rows
    local ago, by = scanFacts(app)
    S.status = Market.ScreenerStatus({ total = #rows, scanAgo = ago, scanBy = by, unnamed = unnamed })
    empty = L["Nothing matches these filters. Clear some (chips above) or pick All items."]
    note = app.compact and L["Narrow window: the category list is the first dropdown, and Supply and Score are hidden (Columns, in More)."]
      or L["Click a row to open the item; right-click for its menu. Faded rows: data older than 3 days."]
  end
  app:Source("market.rows", rows)
  local tbl = {
    id = "market.table",
    type = "table",
    props = tableProps({
      source = "market.rows",
      columns = columns,
      action = "row",
      selected = selected,
      star = true,
      note = note,
      empty = empty,
      confidence = not ah and not alerts or nil,
      sort = (not ah and not alerts) and { key = Market.SortColumn(q.sortKey or "score"), ascending = q.ascending or false } or nil,
      sortAction = (not ah and not alerts) and "sort" or nil,
    }),
    meta = { grow = 1 },
  }
  local main = {}
  if not app.compact then
    main[#main + 1] = {
      id = "market.side",
      type = "sidebar",
      props = { entries = Market.Sidebar(f, q, alerts and "alerts" or nil), action = "side" },
      meta = { w = 190 },
    }
  end
  main[#main + 1] = tbl
  if ah and not app.compact then
    main[#main + 1] = pickPanel(app, params.pick, idx)
  end
  local kids = { screenerToolbar(app, params, hidden, ah) }
  if not app.compact then
    kids[#kids + 1] = filterRow(app, params, ah)
  end
  kids[#kids + 1] = { id = "market.main", type = "row", props = { gap = 10 }, meta = { grow = 1 }, children = main }
  return { id = "market", type = "column", props = { gap = 8 }, children = kids }
end

-- ------------------------------------------------------------------------------------------------ lists

local function shopping()
  return ns.AME and ns.AME.shopping
end

-- the list shown: { name, items, own = index, guild = key, owner } or nil
local function selectedList(params)
  local shop = shopping()
  if not shop then
    return nil
  end
  local sel = params.list
  if not sel and shop:Lists()[1] then
    sel = "shop:1"
  end
  local own = type(sel) == "string" and tonumber(sel:match("^shop:(%d+)$"))
  if own and shop:Lists()[own] then
    local l = shop:Lists()[own]
    return { name = l.name, items = l.items, own = own, key = sel, shared = l.shared }
  end
  local g = type(sel) == "string" and sel:match("^sg:(.+)$")
  if g and shop.db.guild[g] then
    local l = shop.db.guild[g]
    return { name = l.name, items = l.items, guild = g, owner = l.owner, key = sel }
  end
  return nil
end

local function listSideFacts(held, items)
  local shop, w = shopping(), watch()
  local f = { shopping = {}, watch = {}, guild = {}, star = W().StarInline and W().StarInline(12) }
  for i, l in ipairs(shop and shop:Lists() or {}) do
    local _, totals = ns.Shopping.Progress(l.items, held, items)
    f.shopping[i] = { name = l.name, missing = totals.missing, done = totals.done }
  end
  for i, l in ipairs(w and w:Lists() or {}) do
    f.watch[i] = { name = l.name, count = w:Count(i) }
  end
  for _, g in ipairs(shop and shop:GuildLists() or {}) do
    f.guild[#f.guild + 1] = { key = g.key, name = g.name, owner = g.owner, count = Market.Size(g.items), kind = "shop" }
  end
  for _, g in ipairs(w and w:GuildLists() or {}) do
    f.guild[#f.guild + 1] = { key = g.key, name = g.name, owner = g.owner, count = Market.Size(g.items), kind = "watch" }
  end
  return f
end

local function listsBody(app, params)
  local ah = app:AtAH()
  local idx = viewIndex(app)
  local items = idx and idx.items or {}
  local _, held = heldQty("usable")
  local sel = selectedList(params)
  local progress, totals = {}, nil
  if sel then
    progress, totals = ns.Shopping.Progress(sel.items, held, items)
  end
  local results = ns.AHSearch and ns.AHSearch.results or {}
  local rows, at = Market.ListRows(progress, { ah = ah, results = results, onlyTop = S.lists.onlyTop })
  S.listRows = progress
  -- drawn as the old Shopping tab: what you have green once it covers the need, a price at or under your top price
  -- with a green "*"
  local W = ns.Widgets
  local shown = {}
  for i, r in ipairs(rows) do
    local d = {}
    for k, v in pairs(r) do
      d[k] = v
    end
    d.have = r.covered and { text = W.Count(r.have or 0), color = "good" } or W.Count(r.have or 0)
    if type(r.price) == "number" then
      d.price = W.Money(r.price, true) .. (r.under and ("  " .. W.Color("good", "*")) or "")
    end
    shown[i] = d
  end
  app:Source("market.list", shown)
  S.status = Market.ListStatus(totals, ah and at or nil, houseLabel(app:House()))
  local columns = {
    { key = "name", label = L["Item"], width = 220, item = true },
    { key = "need", label = L["Need"], width = 54, format = "count" },
    { key = "have", label = L["Have"], width = 54 }, -- green once it covers the need
    { key = "tobuy", label = L["To buy"], width = 190 },
    { key = "price", label = ah and L["Lowest listing"] or L["Market"], width = 100 }, -- money, "*" at or under your top price
    { key = "max", label = L["Top price"], width = 86, format = "money" },
    { key = "cost", label = L["Cost"], width = 90, format = "money" },
  }
  local header = {}
  local note
  if sel then
    header[#header + 1] = text("market.listName", sel.name .. (sel.owner and ("  (" .. sel.owner .. ")") or ""), "gold", 14)
    if ah then
      local S2 = ns.AHSearch
      if S2 and S2.Busy and S2:Busy() then
        note = L["searching %d of %d"]:format(math.min((S2.done or 0) + 1, S2.total or 0), S2.total or 0)
      else
        note = L["%d still to buy"]:format(totals and totals.missing or 0)
      end
    else
      note = sel.own and L["right-click the list in the sidebar to rename, share or delete it"] or L["right-click the list in the sidebar to copy it"]
    end
    header[#header + 1] = text("market.listNote", note, "dim", 11)
  else
    header[#header + 1] = text("market.listName", L["No shopping lists yet"], "gold", 14)
  end
  header[#header + 1] = gap("market.listGap")
  if ah then
    header[#header + 1] = { id = "market.onlyTop", type = "check", props = { label = L["Only at or under my top price"], checked = S.lists.onlyTop, action = "onlyTop" } }
    header[#header + 1] = btn("market.searchAll", L["Search all"], "searchAll", sel and nil or "disabled")
  else
    header[#header + 1] = btn("market.reagents", L["Add a recipe's reagents"] .. arrow(), "reagents", (sel and sel.own) and nil or "disabled")
    header[#header + 1] = btn("market.searchAH", L["Search the AH"], "searchAH", "primary")
  end
  local right = {
    { id = "market.listHead", type = "row", props = { gap = 8, align = "center" }, meta = { h = 24 }, children = header },
    {
      id = "market.listTable",
      type = "table",
      props = {
        source = "market.list",
        columns = columns,
        action = "listRow",
        note = ah and L["Click a row to open the item and its listings. Dearer than your top price: skipped while the box above is ticked."]
          or L["Right-click an item to change the quantity, set a top price or remove it."],
        empty = sel and (sel.own and L["Empty. Add items from any item's right-click menu, or a recipe's reagents."] or L["This list is empty."])
          or L["Make a shopping list with + New shopping list."],
      },
      meta = { grow = 1 },
    },
  }
  if ah then
    local nextBuy, after = Market.NextBuy(progress, results, { onlyTop = S.lists.onlyTop, skip = S.lists.skip })
    local bar = { action = "bought", skipAction = "buySkip", cancelAction = "buyCancel" }
    if nextBuy then
      bar.key, bar.item, bar.count, bar.copper, bar.qty, bar.commodity = nextBuy.key, nextBuy.key, nextBuy.qty, nextBuy.cost, nextBuy.qty, nextBuy.commodity
      if nextBuy.max and nextBuy.allUnder then
        bar.note = L["from %d listings, all under your top price of %s"]:format(nextBuy.listings, money(nextBuy.max))
      else
        bar.note = L["from %d listings"]:format(nextBuy.listings)
      end
      bar.after = after and itemName(after) or nil
    else
      bar.empty = (totals and totals.done) and L["Nothing left to buy on this list."] or L["Search all to find listings for what's still short."]
    end
    right[#right + 1] = { id = "market.buybar", type = "buybar", props = bar, meta = { h = 40 } }
  end
  local main = {}
  local listKey = sel and sel.key
  if not app.compact then
    main[#main + 1] = {
      id = "market.listSide",
      type = "sidebar",
      props = { entries = Market.ListSidebar(listSideFacts(held, items), listKey), action = "listSide" },
      meta = { w = 190 },
    }
  end
  main[#main + 1] = { id = "market.listMain", type = "column", props = { gap = 8 }, meta = { grow = 1 }, children = right }
  local top = { modeSwitch(app, "lists") }
  if app.compact then
    top[#top + 1] = btn("market.listPick", (sel and sel.name or L["Lists"]) .. arrow(), "listMenu")
  else
    top[#top + 1] = text("market.listsNote", L["your lists, your watchlists and the guild's, in one place"], "dim", 11)
  end
  return {
    id = "market",
    type = "column",
    props = { gap = 10 },
    children = {
      { id = "market.bar", type = "row", props = { gap = 8, align = "center" }, meta = { h = 24 }, children = top },
      { id = "market.main", type = "row", props = { gap = 10 }, meta = { grow = 1 }, children = main },
    },
  }
end

-- ------------------------------------------------------------------------------------------------ arbitrage

local function arbState()
  if not S.arb then
    local own = ns.AME and ns.AME.CurrentHouse and ns.AME:CurrentHouse() or "Horde"
    S.arb = {
      buy = own == "Neutral" and (UnitFactionGroup and UnitFactionGroup("player") or "Horde") or own,
      sell = "Neutral",
      minProfit = 1,
      minMargin = 0.1,
      maxAge = 3,
    }
  end
  return S.arb
end

local function shardOf(house)
  return ns.ShardKey(ns.AME:MarketRealmName(), house)
end

-- one side's data: "your scan · 2 h ago", "Klydig · 1 day"
local function sideData(house, days)
  local AME = ns.AME
  local data = AME.HistoryLoaded and AME:HistoryLoaded() and AME.history and AME.history.shards[shardOf(house)]
  local full = data and Market.LastFull(data.raw)
  local me = UnitName and UnitName("player")
  local who = full and ((not full.src or full.src == me) and L["your scan"] or full.src) or L["searches"]
  local age
  if (days or 0) <= 0 and full then
    age = W().Ago and W().Ago(full.t, now()) or ""
  else
    age = Market.AgeText(days)
  end
  return who .. " · " .. age
end

local function depthRoute(e, a)
  local book = ns.AME.BookFor and ns.AME:BookFor(shardOf(a.buy), e.itemID, 6 * 3600)
  if not (book and ns.Depth) then
    return nil
  end
  return ns.Depth.Route(book, e.sell - e.fee)
end

-- the routes, worked out when both indexes are in (built in the background), and again when either changes
local function routes()
  local a = arbState()
  local AME = ns.AME
  local buyShard, sellShard = shardOf(a.buy), shardOf(a.sell)
  local sig = table.concat({
    a.buy,
    a.sell,
    tostring(a.minProfit),
    tostring(a.minMargin),
    tostring(a.maxAge),
    tostring(AME:CachedIndex(buyShard)),
    tostring(AME:CachedIndex(sellShard)),
    tostring(watch() and watch():HiddenCount()),
  }, "|")
  if a.buy == a.sell then
    return { sig = sig, same = true, rows = {} }
  end
  if (S.routes and S.routes.sig == sig) or S.routesPending == sig then
    return S.routes and S.routes.sig == sig and S.routes or nil
  end
  S.routesPending = sig
  local function done(buyIndex, sellIndex)
    if S.routesPending ~= sig then
      return
    end
    S.routesPending = nil
    local r = { sig = sig, rows = {}, transfers = 0 }
    r.missing = (not buyIndex and houseLabel(a.buy)) or (not sellIndex and houseLabel(a.sell)) or nil
    if buyIndex and sellIndex then
      local q = ns.Quote.For(sellShard, sellIndex, { house = a.sell, fresh = false })
      r.cut = q.cut
      local rows, transfers = try(ns.Arbitrage.Find, buyIndex, sellIndex, {
        cut = q.cut,
        factor = q.factor,
        minProfit = a.minProfit,
        minMargin = a.minMargin,
        maxAge = (a.maxAge or 0) > 0 and a.maxAge or nil,
        today = today(),
        sortKey = "net",
        hide = watch() and watch():Hidden(),
        units = function(e)
          local units = depthRoute(e, a)
          return units and units > 0 and units or nil
        end,
        deposit = function(id, n)
          return info(id).sellPrice and q:Deposit(id, n) or nil
        end,
      })
      r.rows, r.transfers = rows or {}, transfers or 0
    end
    S.routes = r
    redraw()
  end
  try(AME.IndexFor, AME, buyShard, function(buyIndex)
    AME:IndexFor(sellShard, function(sellIndex)
      done(buyIndex, sellIndex)
    end)
  end)
  return S.routes and S.routes.sig == sig and S.routes or nil
end

local function atBuyHouse()
  local a = arbState()
  return ns.AME and ns.AME.ahOpen and ns.AME.CurrentHouse and ns.AME:CurrentHouse() == a.buy or false
end

local function kvRows(prefix, list)
  local out = {}
  for i, p in ipairs(list) do
    out[i] = { id = prefix .. i, type = "keyvalue", props = p, meta = { h = 18 } }
  end
  return out
end

local function arbitrageBody(app, params)
  local a = arbState()
  local r = routes()
  local here = atBuyHouse()
  local list = r and r.rows or {}
  local rows = Market.ArbRows(list, { atBuy = here })
  app:Source("market.routes", rows)
  local chosen = ns.Settings and ns.Settings:Table("arbColumns") or {}
  local columns, hidden = Market.ArbColumns(chosen)
  local message, summary
  if a.buy == a.sell then
    message = L["Pick two different auction houses."]
  elseif not r then
    message = L["Loading market data..."]
  elseif r.missing then
    message = L["No price history for the %s yet: scan there (any character on this account counts) to compare."]:format(r.missing)
  else
    summary = L["%d routes · buy cut %d%% at the %s, sell cut %d%% at the %s · deposits for %d h listings counted in net"]:format(
      #list,
      math.floor((ns.Quote.Cut and ns.Quote.Cut(a.buy) or 0) * 100 + 0.5),
      houseLabel(a.buy),
      math.floor((r.cut or 0) * 100 + 0.5),
      houseLabel(a.sell),
      ns.Settings and ns.Settings:Get("listingHours") or 24
    )
    if (r.transfers or 0) > 0 then
      summary = summary .. " · " .. L["%d hidden as likely gold transfers (over 2000%% margin)"]:format(r.transfers)
    end
  end
  S.status = r and not r.missing and (L["%d routes"]:format(#list) .. " · " .. houseLabel(a.buy) .. " " .. sideData(a.buy) .. " · " .. houseLabel(a.sell) .. " " .. sideData(a.sell)) or ""
  -- the picked route: kept while it's still a route, else the first
  local pick
  for _, e in ipairs(list) do
    if e.itemID == params.route then
      pick = e
    end
  end
  pick = pick or list[1]
  local side
  local w = app.compact and 220 or 260
  if pick then
    local units, _, profit = depthRoute(pick, a)
    local unitsText = units and (units == 0 and "0" or L["%d at this price"]:format(units) .. (profit and ("  " .. (W().SignedMoney and W().SignedMoney(profit) or "")) or "")) or L["search the buy house"]
    local cutPct = math.floor((r.cut or 0) * 100 + 0.5)
    local cost = Market.RouteCost(pick, { buyHouse = houseLabel(a.buy), sellHouse = houseLabel(a.sell), cutPct = cutPct })
    local data = Market.RouteData(pick, { buyData = sideData(a.buy, pick.buyAge), sellData = sideData(a.sell, pick.sellAge), units = unitsText })
    local dataKids = kvRows("market.routeData", data)
    dataKids[#dataKids + 1] = { id = "market.routeNote", type = "text", props = { text = Market.RouteNote(pick), color = "dim", size = 11, wrap = true }, meta = { h = 30 } }
    side = {
      {
        id = "market.routeHead",
        type = "card",
        props = { gap = 2 },
        meta = { h = 58 },
        children = {
          { id = "market.routeItem", type = "itemlink", props = { item = pick.itemID, bold = true }, meta = { h = 18 } },
          text("market.routeWay", L["%s → %s"]:format(houseLabel(a.buy), houseLabel(a.sell)), "dim", 11, { h = 16 }),
        },
      },
      { id = "market.routeCost", type = "card", props = { gap = 4 }, meta = { h = 20 + #cost * 22 }, children = kvRows("market.routeCost", cost) },
      { id = "market.routeDataCard", type = "card", props = { gap = 4 }, meta = { h = 20 + #data * 22 + 34 }, children = dataKids },
      btn("market.routeSearch", L["Search at the %s"]:format(houseLabel(a.buy)), "arbSearch", here and "primary" or "disabled", pick.itemID),
      {
        id = "market.routeActions",
        type = "row",
        props = { gap = 6 },
        meta = { h = 24 },
        children = {
          btn("market.routeAdd", L["Add to a shopping list"], "addToList", nil, pick.itemID),
          btn("market.routeOpen", L["Open item"], "openItem", nil, pick.itemID),
        },
      },
    }
    side[4].meta = { h = 28 }
  else
    side = { text("market.routeNone", L["Click a row for its route."], "dim", 11, { h = 18 }) }
  end
  local bar = {
    modeSwitch(app, "arbitrage"),
    gap("market.gap1", 4),
    text("market.buyAtLabel", L["Buy at"], "dim", 11),
    btn("market.buyAt", houseLabel(a.buy) .. arrow(), "arbBuy"),
    btn("market.swap", L["Swap"], "arbSwap"),
    text("market.sellAtLabel", L["Sell at"], "dim", 11),
    btn("market.sellAt", houseLabel(a.sell) .. arrow(), "arbSell"),
  }
  if not app.compact then
    bar[#bar + 1] = input("market.minProfit", a.minProfit and a.minProfit > 1 and gold(a.minProfit) or "", L["min profit g"], "arbMinProfit", 86, true)
    bar[#bar + 1] = input("market.minMargin", a.minMargin and tostring(math.floor(a.minMargin * 100 + 0.5)) or "", L["min margin %"], "arbMinMargin", 86)
    bar[#bar + 1] = btn("market.age", Market.AgeLabel(a.maxAge) .. arrow(), "arbAge")
    bar[#bar + 1] = gap("market.gap2")
    bar[#bar + 1] = btn("market.columns", Market.ColumnsLabel(hidden), "arbColumns")
  else
    bar[#bar + 1] = gap("market.gap2")
    bar[#bar + 1] = btn("market.more", L["More"] .. arrow(), "arbMore")
  end
  return {
    id = "market",
    type = "column",
    props = { gap = 8 },
    children = {
      { id = "market.bar", type = "row", props = { gap = 6, align = "center" }, meta = { h = 24 }, children = bar },
      text("market.arbSummary", summary or "", "dim", 11, { h = 16 }),
      {
        id = "market.main",
        type = "row",
        props = { gap = 10 },
        meta = { grow = 1 },
        children = {
          {
            id = "market.routes",
            type = "table",
            props = {
              source = "market.routes",
              columns = columns,
              action = "arbRow",
              selected = pick and pick.itemID or nil,
              star = true,
              sort = { key = "net", ascending = false },
              note = L["Click a row for its route; click the item's name to open the item. Right-click for its menu."],
              empty = message or L["No routes pay at these settings."],
            },
            meta = { grow = 1 },
          },
          { id = "market.route", type = "column", props = { gap = 8 }, meta = { w = w }, children = side },
        },
      },
    },
  }
end

-- ------------------------------------------------------------------------------------------------ overview

local function overviewBody(app, params)
  local body
  local O = ns.ItemScreens and ns.ItemScreens.OverviewBody
  if O then
    body = try(O, app, params, { toolbar = false })
  end
  local bar = { modeSwitch(app, "overview") }
  local tools = ns.ItemScreens and ns.ItemScreens.OverviewTools and try(ns.ItemScreens.OverviewTools, app, params)
  if type(tools) == "table" and #tools > 0 then
    bar[#bar + 1] = { id = "market.overviewGap", type = "spacer", meta = { grow = 1 } }
    for _, t in ipairs(tools) do
      bar[#bar + 1] = t
    end
  end
  if type(body) ~= "table" then
    body = text("market.overviewSoon", L["The overview is being rebuilt."], "dim", 12, { h = 20 })
  end
  body.meta = body.meta or {}
  body.meta.grow = 1
  local status = ns.ItemScreens and ns.ItemScreens.OverviewStatus and try(ns.ItemScreens.OverviewStatus, app, params)
  S.status = type(status) == "string" and status or ""
  return {
    id = "market",
    type = "column",
    props = { gap = 8 },
    children = {
      { id = "market.bar", type = "row", props = { gap = 6, align = "center" }, meta = { h = 24 }, children = bar },
      body,
    },
  }
end

-- ------------------------------------------------------------------------------------------------ build

-- what another screen hands over, applied once: a category (the overview), the hidden items (Settings), a guild
-- list (Guild · Lists: "s:<key>" a shopping list, "w:<key>" a watchlist)
local function handOver(params)
  if params.classID then
    S.q.list, S.q.only = nil, nil
    S.q.classID, S.q.subClassID = tonumber(params.classID), nil
    params.classID = nil
  end
  if params.view == "hidden" then
    S.q.classID, S.q.subClassID = nil, nil
    S.q.list, S.q.only = "hidden", nil
    params.view = nil
  end
  local g = params.guildList
  if type(g) == "string" then
    params.guildList = nil
    local kind, key = g:match("^(%a):(.+)$")
    if kind == "s" then
      params.mode, params.list = "lists", "sg:" .. key
    elseif kind == "w" then
      params.mode = "screener"
      S.q.classID, S.q.subClassID = nil, nil
      S.q.list, S.q.only = "g:" .. key, nil
    end
  end
end

local function build(app, params)
  handOver(params)
  -- the Market tab opens on the mode you last used (Overview the first time); a view (your alerts, hidden items)
  -- is the screener's
  if not params.mode then
    params.mode = params.view and "screener" or (ns.Settings and ns.Settings:Get("appMarketMode")) or "overview"
  end
  local mode = params.mode
  if ns.Settings then
    ns.Settings:Set("appMarketMode", mode)
  end
  if mode == "lists" then
    return listsBody(app, params)
  elseif mode == "arbitrage" then
    return arbitrageBody(app, params)
  elseif mode == "overview" then
    return overviewBody(app, params)
  end
  return screenerBody(app, params)
end

-- ------------------------------------------------------------------------------------------------ actions

local A = {}

local function changed(app)
  app:Set({})
end

A.mode = function(app, p)
  local current = app:Current()
  local _, params = app:Current()
  if current == "market" and (params.mode or "screener") == p.key and not params.view then
    return
  end
  app:Go("market", { mode = p.key })
end

A.modeMenu = function(app)
  local entries = {}
  local _, params = app:Current()
  for _, o in ipairs(Market.ModeOptions()) do
    entries[#entries + 1] = {
      text = o[2],
      checked = (params.mode or "screener") == o[1],
      func = function()
        A.mode(app, { key = o[1] })
      end,
    }
  end
  menu(app, entries)
end

A.search = function(app, p)
  local t = p.text ~= "" and p.text or nil
  if t ~= S.q.text then
    S.q.text = t
    changed(app)
  end
end

A.minPrice = function(app, p)
  local c = ns.ParseMoney(p.text)
  if c ~= S.q.minPrice then
    S.q.minPrice = c
    changed(app)
  end
end

A.maxPrice = function(app, p)
  local c = ns.ParseMoney(p.text)
  if c ~= S.q.maxPrice then
    S.q.maxPrice = c
    changed(app)
  end
end

A.quality = function(app)
  local entries = {}
  for _, o in ipairs(Market.QUALITIES) do
    entries[#entries + 1] = {
      text = o[2],
      checked = (S.q.minQuality or 0) == o[1],
      func = function()
        S.q.minQuality = o[1]
        changed(app)
      end,
    }
  end
  menu(app, entries)
end

A.signal = function(app, p)
  S.q.signal = p.key ~= "all" and p.key or nil
  changed(app)
end

A.chip = function(app, p)
  if p.key == "alerts" then
    app:Set({ view = false })
    return
  elseif p.key == "ahtext" then
    S.ah.text, S.ah.at, S.ah.last = "", nil, nil
  end
  Market.ClearChip(S.q, p.key)
  changed(app)
end

A.clearAll = function(app)
  Market.ClearAll(S.q)
  S.ah.text, S.ah.at, S.ah.last = "", nil, nil
  app:Set({ view = false })
end

A.sort = function(app, p)
  S.q.sortKey, S.q.ascending = Market.SortKey(p.key), p.ascending and true or false
  changed(app)
end

A.views = function(app)
  local views = ns.Settings:Table("marketViews")
  local entries = {}
  for _, view in ipairs(views) do
    entries[#entries + 1] = {
      text = view.name,
      func = function()
        S.q = Market.ApplyView(view)
        app:Set({ view = false })
      end,
    }
  end
  entries[#entries + 1] = {
    text = ns.Kit.Color("gold", L["Save these filters as a view..."]),
    func = function()
      prompt("AME_SAVE_VIEW", L["Name for this view:"], function(name)
        Market.SaveView(views, name, S.q)
      end)
    end,
  }
  for i, view in ipairs(views) do
    entries[#entries + 1] = {
      text = ns.Kit.Color("dim", L["Delete %s"]:format(view.name)),
      func = function()
        table.remove(views, i)
      end,
    }
  end
  menu(app, entries)
end

A.columns = function(app)
  local chosen = ns.Settings:Table("marketColumns")
  local entries = {}
  for _, c in ipairs(Market.ColumnChoices(chosen, avgDays())) do
    entries[#entries + 1] = {
      text = c.label,
      checked = c.on,
      func = function()
        chosen[c.key] = not c.on
        changed(app)
      end,
    }
  end
  menu(app, entries)
end

-- the item menu (watch, alert, hide, add to a list ...): the one the whole addon shares
local function itemMenu(app, key, extra)
  local UI = ns.UI
  if UI and UI.ItemMenu then
    try(UI.ItemMenu, UI, app.frame, key, { hide = true, extra = extra and function()
      return extra
    end or nil })
    S.cache.sig = nil -- hiding or watching it changes the list
  end
end

A.row = function(app, p)
  local _, params = app:Current()
  if p.button == "RightButton" then
    itemMenu(app, p.key)
    return
  end
  if app:AtAH() and not app.compact and (params.mode or "screener") == "screener" then
    if ns.AHSearch and ns.AHSearch.Push then
      try(ns.AHSearch.Push, ns.AHSearch, p.key, redraw)
    end
    local pending = ns.AHSearch and ns.AHSearch.pending
    if pending and not pending.sent and pending.key ~= p.key then
      ns.AHSearch:Cancel() -- a purchase priced for the item you left is never confirmed from another's listings
    end
    app:Set({ pick = p.key })
    return
  end
  app:Go("item", { item = p.key })
end

A.openItem = function(app, p)
  if p ~= nil then
    app:Go("item", { item = type(p) == "table" and (p.key or p.payload) or p })
  end
end

A.side = function(app, p)
  if app:AtAH() then
    S.ah.at = nil
  end
  local f = S.side or sideFacts(nil)
  local what = Market.PickEntry(S.q, p.key, f.sets)
  if what == "newlist" then
    prompt("AME_NEW_LIST", L["Name for the new watchlist:"], function(name)
      local w = watch()
      local i, why = w and w:AddList(name)
      if not i and why then
        say("%s", why)
      end
      redraw()
    end)
    return
  elseif what == "alerts" then
    local _, params = app:Current()
    if params.view ~= "alerts" then
      app:Go("market", { mode = "screener", view = "alerts" })
    end
    return
  end
  app:Set({ view = false })
end

A.categoryMenu = function(app)
  local f = S.side or sideFacts(nil)
  local _, params = app:Current()
  local entries = {}
  for _, e in ipairs(Market.Sidebar(f, S.q, params.view == "alerts" and "alerts" or nil)) do
    if not e.heading and not e.link then
      entries[#entries + 1] = {
        text = e.label .. (e.count and ("  " .. ns.Kit.Color("dim", e.count)) or ""),
        checked = e.selected,
        func = function()
          A.side(app, { key = e.key })
        end,
      }
    end
  end
  menu(app, entries)
end

A.more = function(app)
  local q = S.q
  local function signal(key)
    return {
      text = W().SignalGlyph and W().SignalGlyph(key) or key,
      checked = q.signal == key,
      func = function()
        q.signal = q.signal ~= key and key or nil
        changed(app)
      end,
    }
  end
  local function price(field, label, ask)
    return {
      text = label .. (q[field] and ("  " .. money(q[field])) or ""),
      func = function()
        prompt("AME_PRICE_" .. field, ask, function(t)
          q[field] = ns.ParseMoney(t)
          redraw()
        end)
      end,
    }
  end
  menu(app, {
    signal("wait"),
    signal("vendor"),
    signal("disenchant"),
    price("minPrice", L["Minimum price..."], L["Minimum price, e.g. 12 or 9s 50c (empty: none):"]),
    price("maxPrice", L["Maximum price..."], L["Maximum price, e.g. 12 or 9s 50c (empty: none):"]),
    {
      text = L["Views..."],
      func = function()
        C_Timer.After(0, function()
          A.views(app)
        end)
      end,
    },
    {
      text = L["Columns..."],
      func = function()
        C_Timer.After(0, function()
          A.columns(app)
        end)
      end,
    },
    {
      text = L["Clear all filters"],
      func = function()
        A.clearAll(app)
      end,
    },
  })
end

-- at the auction house: the search box searches it
-- pick: the row to show picked (nil: none, a new search)
local function searchAH(app, force, pick)
  local B = ns.AHBrowse
  if not (B and B.Search) then
    return
  end
  local t = S.ah.text or ""
  local at = now()
  if not force and S.ah.last == t and S.ah.at and at - S.ah.at < 2 then
    return -- the box lost focus to the Search button: one search, not two
  end
  S.ah.last, S.ah.at = t, at
  if ns.AHShopping and ns.AHShopping.Remember and AME_DB then
    AME_DB.recentSearches = AME_DB.recentSearches or {}
    try(ns.AHShopping.Remember, AME_DB.recentSearches, t, S.ah.filters)
  end
  try(B.Search, B, t, S.ah.filters, redraw)
  app:Set({ pick = pick or false })
end

A.ahText = function(app, p)
  if (p.text or "") ~= (S.ah.last or "") then
    S.ah.text = p.text or ""
    searchAH(app)
  end
end

A.ahSearch = function(app)
  searchAH(app, true)
end

A.ahFilters = function(app)
  local f = S.ah.filters
  local entries = { { text = L["Any category"], checked = f.category == nil, func = function()
    f.category = nil
  end } }
  for i, c in ipairs(_G.AuctionCategories or {}) do
    if c.name then
      entries[#entries + 1] = {
        text = c.name,
        checked = f.category == tostring(i),
        func = function()
          f.category = tostring(i)
          redraw()
        end,
      }
    end
  end
  entries[#entries + 1] = { separator = true }
  entries[#entries + 1] = { text = L["Exact name"], checked = f.exact or false, func = function()
    f.exact = not f.exact or nil
    redraw()
  end }
  entries[#entries + 1] = { text = L["Usable by you"], checked = f.usable or false, func = function()
    f.usable = not f.usable or nil
    redraw()
  end }
  menu(app, entries)
end

-- "Add to a shopping list": your lists (ticked when it's on one), then a new one; asks how many
local function askQuantity(i, key)
  local shop = shopping()
  local l = shop and shop:Lists()[i]
  if not l then
    return
  end
  prompt("AME_SHOP_QTY", L["How many do you need?"], function(t)
    shop:SetItem(i, key, tonumber(t) or 0)
    redraw()
  end)
end

A.addToList = function(app, p)
  local key = type(p) == "table" and (p.key or p.payload) or p
  local shop = shopping()
  if not (key and shop) then
    return
  end
  local entries = {}
  for i, l in ipairs(shop:Lists()) do
    entries[#entries + 1] = {
      text = l.name,
      checked = l.items[key] ~= nil,
      func = function()
        askQuantity(i, key)
      end,
    }
  end
  entries[#entries + 1] = {
    text = ns.Kit.Color("dim", L["New shopping list..."]),
    func = function()
      prompt("AME_NEW_SHOP", L["Name for the new shopping list (what it's for):"], function(name)
        local i, why = shop:AddList(name)
        if i then
          askQuantity(i, key)
        elseif why then
          say("%s", why)
        end
      end)
    end,
  }
  menu(app, entries)
end

-- lists ----------------------------------------------------------------------------------------------

local function shareChanged(names)
  if ns.SyncService and ns.SyncService.QueueShare then
    try(ns.SyncService.QueueShare, ns.SyncService, nil, names)
  end
end

local function listMenu(app, i)
  local shop = shopping()
  local l = shop and shop:Lists()[i]
  if not l then
    return
  end
  menu(app, {
    { text = ns.Kit.Color("gold", l.name), disabled = true },
    {
      text = L["Add a recipe's reagents"],
      func = function()
        A.reagents(app, { list = i })
      end,
    },
    {
      text = L["Rename..."],
      func = function()
        prompt("AME_SHOP_RENAME", L["New name:"], function(name)
          local old = l.name
          if shop:RenameList(i, name) and l.shared then
            shareChanged({ old })
          end
          redraw()
        end)
      end,
    },
    {
      text = l.shared and L["Stop sharing with my guild"] or L["Share with my guild"],
      func = function()
        shop:SetShared(i, not l.shared)
        shareChanged(l.shared and { l.name } or nil)
        redraw()
      end,
    },
    { separator = true },
    {
      text = ns.Kit.Color("bad", L["Delete"]),
      func = function()
        local wasShared = l.shared and l.name
        shop:RemoveList(i)
        if wasShared then
          shareChanged({ wasShared })
        end
        app:Set({ list = false })
      end,
    },
  }, true)
end

A.listSide = function(app, p)
  local key = tostring(p.key)
  local shop, w = shopping(), watch()
  local own = tonumber(key:match("^shop:(%d+)$"))
  local watchI = tonumber(key:match("^watch:(%d+)$"))
  if own then
    if p.button == "RightButton" then
      listMenu(app, own)
    else
      S.lists.skip = {}
      app:Set({ list = key })
    end
  elseif key:match("^sg:") then
    if p.button == "RightButton" and shop then
      menu(app, { { text = L["Copy to my shopping lists"], func = function()
        shop:CopyGuildList(key:sub(4))
        redraw()
      end } }, true)
    else
      app:Set({ list = key })
    end
  elseif key:match("^wg:") then
    if p.button == "RightButton" and w then
      menu(app, { { text = L["Copy to my watchlists"], func = function()
        w:CopyGuildList(key:sub(4))
        redraw()
      end } }, true)
    else
      S.q.list, S.q.classID, S.q.subClassID = "g:" .. key:sub(4), nil, nil
      app:Go("market", { mode = "screener" })
    end
  elseif watchI then
    S.q.list, S.q.classID, S.q.subClassID = watchI, nil, nil
    app:Go("market", { mode = "screener" })
  elseif key == "newshop" then
    prompt("AME_NEW_SHOP", L["Name for the new shopping list (what it's for):"], function(name)
      local i, why = shop and shop:AddList(name)
      if i then
        app:Set({ list = "shop:" .. i })
      elseif why then
        say("%s", why)
      end
    end)
  elseif key == "newwatch" then
    A.side(app, { key = "newlist" })
  elseif key == "guildlists" then
    app:Go("guildlists")
  end
end

A.listMenu = function(app)
  local _, params = app:Current()
  local idx = viewIndex(app)
  local _, held = heldQty("usable")
  local entries = {}
  for _, e in ipairs(Market.ListSidebar(listSideFacts(held, idx and idx.items or {}), (selectedList(params) or {}).key)) do
    if not e.heading then
      entries[#entries + 1] = {
        text = e.label .. (e.count and ("  " .. ns.Kit.Color("dim", e.count)) or ""),
        checked = e.selected,
        func = function()
          A.listSide(app, { key = e.key })
        end,
      }
    end
  end
  menu(app, entries)
end

A.listRow = function(app, p)
  local _, params = app:Current()
  local sel = selectedList(params)
  if p.button == "RightButton" then
    if not (sel and sel.own) then
      itemMenu(app, p.key)
      return
    end
    local shop, i, key = shopping(), sel.own, p.key
    menu(app, {
      { item = key },
      { text = L["Set quantity..."], func = function()
        askQuantity(i, key)
      end },
      { text = L["Set top price..."], func = function()
        prompt("AME_SHOP_MAX", L["The most you'd pay for one, in gold (empty: no limit):"], function(t)
          local g = tonumber(t)
          local cur = shop:Lists()[i] and shop:Lists()[i].items[key]
          if cur then
            shop:SetItem(i, key, cur.need, g and g > 0 and g * 10000 or false)
          end
          redraw()
        end)
      end },
      { text = L["Remove from list"], func = function()
        shop:SetItem(i, key, 0)
        redraw()
      end },
    }, true)
    return
  end
  if app:AtAH() and ns.AHSearch and ns.AHSearch.Push then
    try(ns.AHSearch.Push, ns.AHSearch, p.key, redraw)
  end
  app:Go("item", { item = p.key })
end

A.reagents = function(app, p)
  local _, params = app:Current()
  local i = p and p.list or (selectedList(params) or {}).own
  local UI = ns.UI
  if UI and UI.AddRecipeReagents then
    try(UI.AddRecipeReagents, UI, i) -- asks how many crafts; the list redraws on ShoppingChanged
  end
end

A.searchAH = function(app)
  if not app:AtAH() then
    say(L["open the auction house first"])
    return
  end
  A.searchAll(app)
end

-- what you buy from the bar is counted off the list (the mailbox counts; AHShopping does this when it's there)
local function hookBought()
  local AS = ns.AHSearch
  if not AS or S.boughtHooked == AS.onBought then
    return
  end
  local prev = AS.onBought
  AS.onBought = function(key, qty)
    if prev then
      prev(key, qty)
    elseif ns.Trading and ns.Trading.OnBought then
      try(ns.Trading.OnBought, ns.Trading, key, qty)
    end
    redraw()
  end
  S.boughtHooked = AS.onBought
end

A.searchAll = function(app)
  local AS = ns.AHSearch
  if not (AS and AS.Start) then
    return
  end
  local keys = {}
  for _, r in ipairs(S.listRows or {}) do
    if r.missing > 0 then
      keys[#keys + 1] = r.itemID
    end
  end
  hookBought()
  S.lists.skip = {}
  try(AS.Start, AS, keys, redraw)
  changed(app)
end

A.onlyTop = function(app, p)
  S.lists.onlyTop = p.checked and true or false
  changed(app)
end

A.bought = function(app)
  hookBought()
  if ns.AHSearch then
    ns.AHSearch.onChange = redraw
  end
  changed(app)
end

-- the Buy card's how-many: the listings it takes from follow as you type
A.buyQty = function(app, p)
  local _, params = app:Current()
  local key = params.pick
  local n = tonumber(p.text)
  if key and n and n > 0 then
    S.buyQty = S.buyQty or {}
    if S.buyQty[key] ~= n then
      S.buyQty[key] = math.floor(n)
      changed(app)
    end
  end
end

A.buySkip = function(app, p)
  if p.key ~= nil then
    S.lists.skip[p.key] = true
  end
  if ns.AHSearch and ns.AHSearch.pending and not ns.AHSearch.pending.sent then
    ns.AHSearch:Cancel()
  end
  changed(app)
end

A.buyCancel = function(app)
  changed(app)
end

-- arbitrage ------------------------------------------------------------------------------------------

local function houseMenu(app, field)
  local a = arbState()
  local entries = {}
  for _, h in ipairs(Market.HOUSES) do
    entries[#entries + 1] = {
      text = houseLabel(h),
      checked = a[field] == h,
      func = function()
        a[field] = h
        redraw()
      end,
    }
  end
  menu(app, entries)
end

A.arbBuy = function(app)
  houseMenu(app, "buy")
end

A.arbSell = function(app)
  houseMenu(app, "sell")
end

A.arbSwap = function(app)
  local a = arbState()
  a.buy, a.sell = a.sell, a.buy
  changed(app)
end

A.arbMinProfit = function(app, p)
  local a = arbState()
  local c = ns.ParseMoney(p.text) or 1
  if c ~= a.minProfit then
    a.minProfit = c
    changed(app)
  end
end

A.arbMinMargin = function(app, p)
  local a = arbState()
  local m = (tonumber(p.text) or 10) / 100
  if m ~= a.minMargin then
    a.minMargin = m
    changed(app)
  end
end

A.arbAge = function(app)
  local a = arbState()
  local entries = {}
  for _, o in ipairs(Market.AGES) do
    entries[#entries + 1] = {
      text = o[2],
      checked = (a.maxAge or 0) == o[1],
      func = function()
        a.maxAge = o[1]
        redraw()
      end,
    }
  end
  menu(app, entries)
end

A.arbColumns = function(app)
  local chosen = ns.Settings:Table("arbColumns")
  local _, _, all = Market.ArbColumns(chosen)
  local entries = {}
  for _, c in ipairs(all) do
    if not c.item and not c.button then
      entries[#entries + 1] = {
        text = c.label,
        checked = chosen[c.key] ~= false,
        func = function()
          chosen[c.key] = chosen[c.key] == false
          changed(app)
        end,
      }
    end
  end
  menu(app, entries)
end

A.arbMore = function(app)
  local a = arbState()
  menu(app, {
    {
      text = L["Minimum profit..."],
      func = function()
        prompt("AME_ARB_PROFIT", L["Minimum profit, e.g. 12 or 9s 50c (empty: none):"], function(t)
          a.minProfit = ns.ParseMoney(t) or 1
          redraw()
        end)
      end,
    },
    {
      text = L["Minimum margin..."],
      func = function()
        prompt("AME_ARB_MARGIN", L["Minimum margin in percent:"], function(t)
          a.minMargin = (tonumber(t) or 10) / 100
          redraw()
        end)
      end,
    },
    {
      text = Market.AgeLabel(a.maxAge),
      func = function()
        C_Timer.After(0, function()
          A.arbAge(app)
        end)
      end,
    },
  })
end

A.arbRow = function(app, p)
  if p.button == "RightButton" then
    itemMenu(app, p.key)
    return
  end
  app:Set({ route = p.key })
end

-- search the buy house: in this window's own auction house search, with the item picked
A.arbSearch = function(app, p)
  local key = type(p) == "table" and (p.key or p.payload) or p
  if not key then
    return
  end
  if not atBuyHouse() then
    say(L["Visit the %s to search and buy it there."], houseLabel(arbState().buy))
    return
  end
  S.ah.text = itemName(key) or ""
  app:Go("market", { mode = "screener", pick = key })
  searchAH(app, true, key)
  if ns.AHSearch and ns.AHSearch.Push then
    try(ns.AHSearch.Push, ns.AHSearch, key, redraw)
  end
end

-- ------------------------------------------------------------------------------------------------ the screen

App.Screen("market", {
  tab = "market",
  Build = build,
  Status = function()
    return S.status or ""
  end,
  Title = function(_, params)
    return Market.ModeLabel(params and params.mode)
  end,
  -- drawn again for a new market index (a scan), and on the lists for what you hold (they count it)
  Stamp = function(app, params)
    local AME = ns.AME
    local stamp = tostring(AME and AME.CachedIndex and AME:CachedIndex(app:Shard()))
    if params and params.mode == "lists" and ns.Trading and ns.Trading.Holdings then
      local h = ns.Trading:Holdings()[ns.Trading.CharKey()]
      stamp = stamp .. ":" .. tostring(h and h.bags) .. ":" .. tostring(h and h.bank)
    end
    return stamp
  end,
  actions = A,
})

-- a list changed anywhere (the craft queue, an item's menu, the old window): drawn again if it's on screen
if ns.Events and ns.Events.On then
  ns.Events.On("ShoppingChanged", function()
    local id = App:Current()
    if id == "market" and App.frame and App.frame:IsShown() then
      App:Redraw()
    end
  end)
end
