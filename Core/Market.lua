-- Market (boards Market, MarketAlerts, MarketAH, ShoppingList, MarketAHList, Arbitrage, MarketCompact,
-- MarketAHCompact): the screener, your alerts, the lists and arbitrage, as rows for the redesigned window. Pure
-- functions turn what AME knows (the market index, the watchlists, the shopping lists, the auction house's answers)
-- into table rows, sidebar entries, chips and status lines; Core/UI/Screens/Market.lua builds the screen from them.
--
--   Market.NewQuery() -> q                          the screener's filters: text, minQuality, minPrice, maxPrice,
--                                                    signal, classID, subClassID, list, sortKey, ascending
--   Market.FilterQuery(q, opts) -> MarketFilter query (opts: only, hidden, alerts)
--   Market.Sidebar(f, q, view) -> entries           All items, Watchlists, Alerts, Categories (counts)
--   Market.PickEntry(q, key, f) -> what             a sidebar pick changes q; "newlist" | "alerts" | "list" | nil
--   Market.Chips(q, f, view) -> { {key, label} }    the active filters, each removable
--   Market.Columns(state, chosen, days) -> columns, hidden   the table's columns for a state of the screen
--   Market.ScreenerRows(list, f) / AlertRows / AHRows / ListRows / ArbRows -> table rows
--   Market.ListSidebar(f, sel), Market.NextBuy(rows, results, opts), Market.Listings(book, qty, now)
--   Market.RouteCost(e, f), Market.RouteData(e, f), Market.RouteNote(e)
-- A row is a table row (Core/UI/Parts/Table.lua): { key, item, faded?, [column key] = value }.
local _, ns = ...
local L = ns.L

local Market = {}
ns.Market = Market

Market.STALE_DAYS = 3 -- rows whose data is older than this fade
Market.MODES = { "screener", "overview", "arbitrage", "lists" }
Market.VIEW_FIELDS = { "text", "minQuality", "minPrice", "maxPrice", "signal", "classID", "subClassID", "sortKey" }

local function money(copper)
  return ns.Widgets and ns.Widgets.Money and ns.Widgets.Money(copper, true) or tostring(copper)
end

local function count(n)
  return ns.Widgets and ns.Widgets.Count and ns.Widgets.Count(n) or tostring(n)
end

-- a whole percentage, green / red as the old Arbitrage tab drew it
local function percent(x)
  return ns.Widgets and ns.Widgets.Percent and ns.Widgets.Percent(x, 0) or ("%+d%%"):format(math.floor(x * 100 + 0.5))
end

local function dim(text)
  return ns.Widgets and ns.Widgets.Dim and ns.Widgets.Dim(text) or text
end

local function thousands(n)
  if ns.Widgets and ns.Widgets.Thousands then
    return ns.Widgets.Thousands(n)
  end
  local s = tostring(math.floor((n or 0) + 0.5))
  local out
  repeat
    s, out = s:gsub("^(%-?%d+)(%d%d%d)", "%1,%2")
  until out == 0
  return s
end

local function size(set)
  local n = 0
  for _ in pairs(set or {}) do
    n = n + 1
  end
  return n
end
Market.Size = size

function Market.ModeOptions()
  return {
    { "overview", L["Overview"] },
    { "screener", L["Screener"] },
    { "arbitrage", L["Arbitrage"] },
    { "lists", L["Lists"] },
  }
end

function Market.ModeLabel(mode)
  for _, o in ipairs(Market.ModeOptions()) do
    if o[1] == mode then
      return o[2]
    end
  end
  return L["Screener"]
end

-- ------------------------------------------------------------------------------------------------ the query

-- minQuality 0: any quality (a list can't hold nil)
Market.QUALITIES = {
  { 0, L["Any quality"] },
  { 1, L["Common+"] },
  { 2, L["Uncommon+"] },
  { 3, L["Rare+"] },
  { 4, L["Epic+"] },
}

function Market.QualityLabel(minQuality)
  for _, o in ipairs(Market.QUALITIES) do
    if o[1] == (minQuality or 0) then
      return o[2]
    end
  end
  return L["Any quality"]
end

-- Common+ hides grey junk by default
function Market.NewQuery()
  return { sortKey = "score", ascending = false, minQuality = 1 }
end

-- the table's sort column for a query key, and the other way round (the Signal column sorts by its rank)
local SORT_KEY = { signal = "signalRank", __name = "name" }
local SORT_COLUMN = { signalRank = "signal" }
function Market.SortKey(column)
  return SORT_KEY[column] or column
end
function Market.SortColumn(key)
  return SORT_COLUMN[key] or key
end

-- the query MarketFilter.Apply takes. opts: only (a list's items), hidden (the hidden set), alerts (the alerts:
-- your alerts view, any quality and category)
function Market.FilterQuery(q, opts)
  opts = opts or {}
  local out = {
    text = q.text,
    minPrice = q.minPrice,
    maxPrice = q.maxPrice,
    signal = q.signal,
    sortKey = q.sortKey or "score",
    ascending = q.ascending,
  }
  if opts.alerts then
    out.only = opts.alerts
    out.sortKey = "name" -- every alert stays in (a sort key drops rows without it); sorted by when they fired
    return out
  end
  out.minQuality = (q.minQuality or 0) > 0 and q.minQuality or nil
  out.classID, out.subClassID = q.classID, q.subClassID
  out.only = opts.only
  if q.list ~= "hidden" then
    out.hide = opts.hidden
  end
  return out
end

-- "vs N-day avg" follows the chosen average period: worked out on the summaries before they're filtered (sorting
-- reads it there), as the old screener did
function Market.PrepareVsAvg(index, days)
  local key = "avg" .. (days or 7)
  if index.vsAvgKey == key then
    return
  end
  for _, s in pairs(index.items or {}) do
    local avg = s[key]
    s.vsAvg = s.market and avg and avg > 0 and s.market / avg - 1 or nil
  end
  index.vsAvgKey = key
end

-- ------------------------------------------------------------------------------------------------ the sidebar

-- f: { total, lists = { {name, count, shared?} }, guild = { {key, name, owner, count} }, hidden (count),
--      alerts (count), categories = { {classID, name, count, subs = { {subClassID, name, count} }} }, star? }
-- keys: "all", "list:<i>", "newlist", "hidden", "guild:<key>", "alerts", "class:<id>", "sub:<id>:<sub>"
function Market.Sidebar(f, q, view)
  local alerts = view == "alerts"
  local entries = {}
  local function add(e)
    entries[#entries + 1] = e
  end
  local none = not alerts and q.list == nil
  add({ key = "all", label = L["All items"], count = thousands(f.total or 0), selected = none and q.classID == nil })
  add({ heading = true, label = L["Watchlists"] })
  for i, l in ipairs(f.lists or {}) do
    add({
      key = "list:" .. i,
      label = (f.star and (f.star .. " ") or "") .. l.name,
      count = thousands(l.count or 0),
      selected = not alerts and q.list == i,
    })
  end
  add({ key = "newlist", label = "+ " .. L["New list"], link = true })
  if (f.hidden or 0) > 0 then
    add({ key = "hidden", label = L["Hidden"], count = thousands(f.hidden), tone = "dim", selected = not alerts and q.list == "hidden" })
  end
  if f.guild and #f.guild > 0 then
    add({ heading = true, label = L["Guild watchlists"] })
    for _, g in ipairs(f.guild) do
      add({
        key = "guild:" .. g.key,
        label = g.name .. (g.owner and (" · " .. g.owner) or ""),
        count = thousands(g.count or 0),
        tone = "dim",
        selected = not alerts and q.list == "g:" .. g.key,
      })
    end
  end
  add({ heading = true, label = L["Alerts"] })
  add({ key = "alerts", label = L["Your alerts"], count = thousands(f.alerts or 0), selected = alerts })
  add({ heading = true, label = L["Categories"] })
  for _, c in ipairs(f.categories or {}) do
    add({
      key = "class:" .. c.classID,
      label = c.name or tostring(c.classID),
      count = thousands(c.count or 0),
      selected = none and q.classID == c.classID and q.subClassID == nil,
    })
    if q.classID == c.classID and not alerts then
      for _, s in ipairs(c.subs or {}) do
        add({
          key = "sub:" .. c.classID .. ":" .. s.subClassID,
          label = "   " .. (s.name or tostring(s.subClassID)),
          count = thousands(s.count or 0),
          tone = "dim",
          selected = none and q.subClassID == s.subClassID,
        })
      end
    end
  end
  return entries
end

-- a sidebar pick: changes q and says what else to do. lists: the watchlists' item sets (by index); guild: the
-- guild lists' item sets (by key); hidden: the hidden set
function Market.PickEntry(q, key, f)
  f = f or {}
  key = tostring(key)
  if key == "newlist" then
    return "newlist"
  elseif key == "alerts" then
    return "alerts"
  end
  q.list, q.only = nil, nil
  local i = tonumber(key:match("^list:(%d+)$"))
  local guild = key:match("^guild:(.+)$")
  local class, sub = key:match("^sub:(%-?%d+):(%-?%d+)$")
  if i then
    q.classID, q.subClassID = nil, nil
    q.list, q.only = i, f.lists and f.lists[i] or {}
    return "list"
  elseif guild then
    q.classID, q.subClassID = nil, nil
    q.list, q.only = "g:" .. guild, f.guild and f.guild[guild] or {}
    return "list"
  elseif key == "hidden" then
    q.classID, q.subClassID = nil, nil
    q.list, q.only = "hidden", f.hidden or {}
    return "list"
  elseif class then
    q.classID, q.subClassID = tonumber(class), tonumber(sub)
  elseif key:match("^class:") then
    local id = tonumber(key:match("^class:(%-?%d+)$"))
    if q.classID == id and q.subClassID == nil then
      q.classID = nil -- the open class again closes it
    else
      q.classID, q.subClassID = id, nil
    end
  else -- all
    q.classID, q.subClassID = nil, nil
  end
  return nil
end

-- ------------------------------------------------------------------------------------------------ chips

-- f: { listName = name of q.list, className = name of q.classID / subClassID, text (the AH search text) }
-- keys: "text", "quality", "min", "max", "list", "class", "alerts", "ahtext"
function Market.Chips(q, f, view)
  f = f or {}
  local out = {}
  local function add(key, label)
    out[#out + 1] = { key = key, label = label }
  end
  if view == "alerts" then
    add("alerts", L["Your alerts"])
  end
  if f.ahText and f.ahText ~= "" then
    add("ahtext", '"' .. f.ahText .. '"')
  end
  if q.text and q.text ~= "" then
    add("text", '"' .. q.text .. '"')
  end
  if view ~= "alerts" and (q.minQuality or 0) ~= 1 then
    add("quality", Market.QualityLabel(q.minQuality))
  end
  if q.minPrice then
    add("min", L["from %s"]:format(money(q.minPrice)))
  end
  if q.maxPrice then
    add("max", L["up to %s"]:format(money(q.maxPrice)))
  end
  if view ~= "alerts" then
    if q.list and f.listName then
      add("list", f.listName)
    elseif q.classID and f.className then
      add("class", f.className)
    end
  end
  return out
end

-- a chip's ✕: the filter it names goes
function Market.ClearChip(q, key)
  if key == "text" then
    q.text = nil
  elseif key == "quality" then
    q.minQuality = 1
  elseif key == "min" then
    q.minPrice = nil
  elseif key == "max" then
    q.maxPrice = nil
  elseif key == "list" then
    q.list, q.only = nil, nil
  elseif key == "class" then
    q.classID, q.subClassID = nil, nil
  end
end

-- Clear all: back to the defaults, keeping the sort
function Market.ClearAll(q)
  local keep = { sortKey = q.sortKey, ascending = q.ascending }
  for k in pairs(q) do
    q[k] = nil
  end
  q.sortKey, q.ascending, q.minQuality = keep.sortKey or "score", keep.ascending or false, 1
  return q
end

-- saved views (Settings "marketViews", the same shape as the old screener's)
function Market.SaveView(views, name, q)
  name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then
    return nil
  end
  local saved = {}
  for _, k in ipairs(Market.VIEW_FIELDS) do
    saved[k] = q[k]
  end
  saved.ascending = q.ascending or false
  for _, view in ipairs(views) do
    if view.name == name then
      view.q = saved
      return view
    end
  end
  views[#views + 1] = { name = name, q = saved }
  return views[#views]
end

function Market.ApplyView(view)
  local q = Market.NewQuery()
  for _, k in ipairs(Market.VIEW_FIELDS) do
    q[k] = view.q and view.q[k]
  end
  q.minQuality = q.minQuality or 1
  q.sortKey = q.sortKey or "score"
  q.ascending = view.q and view.q.ascending or false
  return q
end

-- ------------------------------------------------------------------------------------------------ columns

-- every column the screener can show; optional ones are off until switched on (Columns)
local function screenerColumns(days)
  return {
    { key = "name", label = L["Item"], width = 200, item = true },
    { key = "market", label = L["Market"], width = 86, format = "money" },
    { key = "avg", label = L["%dd avg"]:format(days), width = 86, format = "money", optional = true },
    { key = "vsAvg", label = L["vs %d-day avg"]:format(days), width = 80, format = "pct" },
    { key = "min", label = L["Lowest listing"], width = 86, format = "money", optional = true },
    { key = "change7", label = L["7d"], width = 62, format = "pct", optional = true },
    { key = "vol30", label = L["Volatility"], width = 70, format = "plainpct", optional = true },
    { key = "qty", label = L["Supply"], width = 60, format = "count" },
    { key = "soldPerDay", label = L["Sells/day"], width = 70, format = "rate" },
    { key = "hold", label = L["You hold"], width = 64 },
    { key = "signal", label = L["Signal"], width = 70, format = "signal" },
    { key = "score", label = L["Score"], width = 54 },
  }
end

-- the columns for a state of the screen: "screener", "alerts", "ah", "compact", "ahcompact". chosen: the Columns
-- choices (Settings "marketColumns": key -> on), for the screener. Returns the columns shown, and how many of the
-- screener's are hidden.
function Market.Columns(state, chosen, days)
  days = days or 7
  chosen = chosen or {}
  if state == "alerts" then
    return {
      { key = "name", label = L["Item"], width = 200, item = true },
      { key = "market", label = L["Market"], width = 86, format = "money" },
      { key = "vsAvg", label = L["vs %d-day avg"]:format(days), width = 80, format = "pct" },
      { key = "below", label = L["Below"], width = 80, format = "money" },
      { key = "above", label = L["Above"], width = 80, format = "money" },
      { key = "fired", label = L["Last fired"], width = 140 },
      { key = "hold", label = L["You hold"], width = 64 },
      { key = "signal", label = L["Signal"], width = 70, format = "signal" },
    },
      0
  elseif state == "ah" then
    return {
      { key = "name", label = L["Item"], width = 200, item = true },
      { key = "min", label = L["Lowest listing"], width = 90, format = "money" },
      { key = "onSale", label = L["On sale"], width = 60, format = "count" },
      { key = "market", label = L["Market"], width = 86, format = "money" },
      { key = "vsAvg", label = L["vs %d-day avg"]:format(days), width = 80, format = "pct" },
      { key = "signal", label = L["Signal"], width = 70, format = "signal" },
    },
      0
  elseif state == "ahcompact" then
    return {
      { key = "name", label = L["Item"], width = 180, item = true },
      { key = "min", label = L["Lowest listing"], width = 90, format = "money" },
      { key = "onSale", label = L["On sale"], width = 60, format = "count" },
      { key = "market", label = L["Market"], width = 86, format = "money" },
      { key = "signal", label = L["Signal"], width = 70, format = "signal" },
    },
      0
  elseif state == "compact" then
    return {
      { key = "name", label = L["Item"], width = 180, item = true },
      { key = "market", label = L["Market"], width = 86, format = "money" },
      { key = "vsAvg", label = L["vs avg"], width = 64, format = "pct" },
      { key = "soldPerDay", label = L["Sells/day"], width = 70, format = "rate" },
      { key = "signal", label = L["Signal"], width = 70, format = "signal" },
    },
      0
  end
  local out, hidden = {}, 0
  for _, col in ipairs(screenerColumns(days)) do
    local on = chosen[col.key]
    if on == nil then
      on = not col.optional
    end
    if on or col.item then
      out[#out + 1] = col
    else
      hidden = hidden + 1
    end
  end
  return out, hidden
end

-- the Columns menu's choices: every optional-or-not column but the item's, ticked when shown
function Market.ColumnChoices(chosen, days)
  local out = {}
  for _, col in ipairs(screenerColumns(days or 7)) do
    if not col.item then
      local on = (chosen or {})[col.key]
      if on == nil then
        on = not col.optional
      end
      out[#out + 1] = { key = col.key, label = col.label, on = on }
    end
  end
  return out
end

function Market.ColumnsLabel(hidden)
  return (hidden or 0) > 0 and L["Columns · %d hidden"]:format(hidden) or L["Columns"]
end

-- ------------------------------------------------------------------------------------------------ rows

local function held(f, key)
  local n = f.held and f.held[key]
  return n and n > 0 and count(n) or ""
end

-- the screener's rows: each summary with its key and item, what you hold and whether its data is old.
-- f: { today, held = { [key] = qty } }
function Market.ScreenerRows(list, f)
  f = f or {}
  local rows = {}
  for i, s in ipairs(list or {}) do
    local stale = f.today and s.day and f.today - s.day > Market.STALE_DAYS or nil
    local conf = ns.Analytics and ns.Analytics.Confidence and ns.Analytics.Confidence(s, f.today) or nil
    rows[i] = setmetatable(
      { key = s.itemID, item = s.itemID, hold = held(f, s.itemID), faded = stale, conf = conf },
      { __index = s }
    )
  end
  return rows
end

-- when an alert last fired, in words: "today 14:02 · below" (lit), "3 days ago · above", "never"
-- date(fmt, t) is the game's date; kind: "below" / "above" / nil
function Market.FiredText(at, kind, now, date)
  if not at then
    return { text = L["never"], color = "dim" }
  end
  local day = math.floor(at / 86400)
  local today = math.floor((now or at) / 86400)
  local text
  if day >= today then
    text = L["today %s"]:format(date and date("%H:%M", at) or "")
  elseif today - day == 1 then
    text = L["yesterday"]
  else
    text = L["%d days ago"]:format(today - day)
  end
  if kind == "below" then
    text = text .. " · " .. L["below"]
  elseif kind == "above" then
    text = text .. " · " .. L["above"]
  end
  return { text = text, color = day >= today and "warn" or "dim" }
end

-- Your alerts: the alerted items' summaries (MarketFilter.Apply with only = the alerts), with the alert's own columns.
-- alerts: Watch db.alerts; f: { fired = { [itemID] = { at, unread } }, now, date, held, today }. Items without a
-- price here yet get a row of their own. Newest fired first, never fired last. Returns rows and the lit row's key
-- (the newest fired one you haven't opened).
function Market.AlertRows(list, alerts, f)
  f = f or {}
  local rows, seen = {}, {}
  local function add(id, s)
    local a = alerts[id] or {}
    local fired = f.fired and f.fired[id]
    local st = a.state or {}
    local kind = st.below and "below" or st.above and "above" or nil
    local row = {
      key = id,
      item = id,
      market = s and s.market,
      vsAvg = s and s.vsAvg,
      below = a.below,
      above = a.above,
      fired = Market.FiredText(fired and fired.at, kind, f.now, f.date),
      firedAt = fired and fired.at or 0,
      unread = fired and fired.unread or nil,
      hold = held(f, id),
      signal = s and s.signal,
      faded = s and f.today and s.day and f.today - s.day > Market.STALE_DAYS or nil,
    }
    rows[#rows + 1] = row
    seen[id] = true
  end
  for _, s in ipairs(list or {}) do
    if alerts[s.itemID] then
      add(s.itemID, s)
    end
  end
  if not f.filtered then -- with a text or signal filter on, only what matched it
    for id in pairs(alerts) do
      if not seen[id] then
        add(id, nil)
      end
    end
  end
  table.sort(rows, function(a, b)
    if a.firedAt ~= b.firedAt then
      return a.firedAt > b.firedAt
    end
    return tostring(a.key) < tostring(b.key)
  end)
  local lit
  for _, r in ipairs(rows) do
    if r.unread then
      lit = r.key
      break
    end
  end
  return rows, lit
end

-- the newest alert notice per item: { [itemID] = { at, unread } } (notices newest first; isUnread(e) optional)
function Market.FiredFrom(notices, isUnread)
  local out = {}
  for _, e in ipairs(notices or {}) do
    if e.kind == "alert" and e.itemID and not out[e.itemID] then
      out[e.itemID] = { at = e.at, unread = isUnread and isUnread(e) or nil }
    end
  end
  return out
end

-- how many alerts fired today (the status line)
function Market.FiredToday(fired, now)
  local n, today = 0, math.floor((now or 0) / 86400)
  for _, e in pairs(fired or {}) do
    if e.at and math.floor(e.at / 86400) == today then
      n = n + 1
    end
  end
  return n
end

-- At the auction house: what the search found (AHBrowse.Rows: { key, qty, cheapest, market, signal }) with AME's
-- view beside it, narrowed by the screener's quality, price range, signal and category. info(key) -> { quality,
-- classID, subClassID }; items: the market index's summaries
function Market.AHRows(found, items, q, info, days)
  q = q or {}
  items = items or {}
  local avgKey = "avg" .. (days or 7)
  local rows = {}
  for _, r in ipairs(found or {}) do
    local s = items[r.key] or {}
    local i = info and info(r.key) or {}
    local ok = true
    if (q.minQuality or 0) > 0 and (i.quality or -1) < q.minQuality then
      ok = false
    elseif q.minPrice and (r.cheapest or 0) < q.minPrice then
      ok = false
    elseif q.maxPrice and (r.cheapest or math.huge) > q.maxPrice then
      ok = false
    elseif q.signal and s.signal ~= q.signal then
      ok = false
    elseif q.classID and i.classID ~= q.classID then
      ok = false
    elseif q.subClassID and i.subClassID ~= q.subClassID then
      ok = false
    elseif q.only and not q.only[r.key] then
      ok = false
    end
    if ok then
      local avg = s[avgKey] or s.avg7
      rows[#rows + 1] = {
        key = r.key,
        item = r.key,
        min = r.cheapest,
        onSale = r.qty,
        market = s.market or r.market,
        vsAvg = s.market and avg and avg > 0 and s.market / avg - 1 or nil,
        signal = s.signal or r.signal,
        soldPerDay = s.soldPerDay,
      }
    end
  end
  return rows
end

-- ------------------------------------------------------------------------------------------------ buying

-- buying qty climbs the listings, cheapest first: how many each gives, what it costs, how many they hold
function Market.Fill(listings, qty)
  if ns.AHShopping and ns.AHShopping.Fill then
    return ns.AHShopping.Fill(listings, qty)
  end
  local taken, cost, left = {}, 0, qty or 0
  for i, r in ipairs(listings or {}) do
    if left <= 0 then
      break
    end
    local n = math.min(left, r.qty)
    taken[i], cost, left = n, cost + n * r.price, left - n
  end
  return taken, cost, (qty or 0) - left
end

-- a listing's time left: "23 h", "40 min", the game's band, or ""
local BANDS = { [0] = L["under 30 min"], [1] = L["30 min-2 h"], [2] = L["2-12 h"], [3] = L["12-48 h"] }
function Market.TimeLeftText(seconds, band)
  if seconds then
    return seconds >= 3600 and L["%d h"]:format(math.floor(seconds / 3600))
      or L["%d min"]:format(math.max(1, math.floor(seconds / 60)))
  end
  return band and BANDS[band] or ""
end

-- the Buy card's listings for an item's book (AHSearch.results[key]): { key, each, qty, left, selected }, the rows
-- an order of qty takes from picked ("1 of 3": the last one partly). Returns them, the order's cost and how many
-- are on sale in all.
function Market.Listings(book, qty, now)
  local rows = book and book.rows or {}
  local taken, cost = Market.Fill(rows, qty or 1)
  local out, onSale = {}, 0
  for i, r in ipairs(rows) do
    onSale = onSale + (r.qty or 0)
    local left, band
    if ns.AHSearch and ns.AHSearch.TimeLeft then
      left, band = ns.AHSearch.TimeLeft(book, r, now)
    else
      left, band = r.timeLeft, r.band
    end
    local n = taken[i]
    out[i] = {
      key = i,
      each = r.price,
      qty = (n and n < r.qty) and L["%s of %s"]:format(count(n), count(r.qty)) or count(r.qty),
      left = { text = Market.TimeLeftText(left, band), color = "dim" },
      selected = n ~= nil or nil,
      mine = r.mine,
    }
  end
  return out, cost, onSale
end

-- ------------------------------------------------------------------------------------------------ lists

-- f: { shopping = { {name, missing, done} }, watch = { {name, count} }, guild = { {key, name, owner, count,
--      kind = "shop" | "watch"} }, star }. sel: the list shown ("shop:<i>" | "sg:<key>")
-- keys: "shop:<i>", "newshop", "watch:<i>", "newwatch", "sg:<key>", "wg:<key>", "guildlists"
function Market.ListSidebar(f, sel)
  local out = {}
  local function add(e)
    out[#out + 1] = e
  end
  add({ heading = true, label = L["Shopping lists"] })
  for i, l in ipairs(f.shopping or {}) do
    local key = "shop:" .. i
    add({
      key = key,
      label = l.name,
      count = l.done and L["done"] or count(l.missing or 0),
      tone = l.done and "good" or nil,
      selected = sel == key,
    })
  end
  add({ key = "newshop", label = "+ " .. L["New shopping list"], link = true })
  add({ heading = true, label = L["Watchlists"] })
  for i, l in ipairs(f.watch or {}) do
    add({ key = "watch:" .. i, label = (f.star and (f.star .. " ") or "") .. l.name, count = thousands(l.count or 0) })
  end
  add({ key = "newwatch", label = "+ " .. L["New watchlist"], link = true })
  add({ heading = true, label = L["From the guild"] })
  for _, g in ipairs(f.guild or {}) do
    local key = (g.kind == "watch" and "wg:" or "sg:") .. g.key
    add({
      key = key,
      label = g.name .. (g.owner and (" · " .. g.owner) or ""),
      count = thousands(g.count or 0),
      tone = "dim",
      selected = sel == key,
    })
  end
  add({ key = "guildlists", label = L["All guild lists"], link = true })
  return out
end

-- a list's rows (Shopping.Progress's rows): need, have, to buy, the price (market away, the lowest listing at the
-- auction house), the top price and what the rest costs. opts: { ah, results = AHSearch.results, onlyTop }
-- Returns rows and totals { missing, left (at the listings found), over (items over the top price) }.
function Market.ListRows(progress, opts)
  opts = opts or {}
  local results = opts.results or {}
  local rows, totals = {}, { missing = 0, left = 0, over = 0, searched = 0 }
  for i, r in ipairs(progress or {}) do
    local row = {
      key = r.itemID,
      item = r.itemID,
      need = r.need,
      have = r.held or r.have,
      covered = (r.held or r.have or 0) >= (r.need or 0) and (r.need or 0) > 0 or nil, -- drawn green
      max = r.max,
    }
    if r.missing <= 0 then
      row.tobuy = { text = L["done"], color = "good" }
      row.price = opts.ah and nil or r.market
    else
      totals.missing = totals.missing + 1
      row.tobuy = count(r.missing)
      if opts.ah then
        local book = results[r.itemID]
        local first = book and book.rows and book.rows[1]
        row.price = first and first.price
        if book then
          totals.searched = totals.searched + 1
        end
        local listings = {}
        for _, l in ipairs(book and book.rows or {}) do
          if not (opts.onlyTop and r.max and l.price > r.max) then
            listings[#listings + 1] = l
          end
        end
        if first and opts.onlyTop and r.max and first.price > r.max then
          row.tobuy = { text = L["%s · over your top price"]:format(count(r.missing)), color = "warn" }
          totals.over = totals.over + 1
        elseif #listings > 0 then
          local _, cost = Market.Fill(listings, r.missing)
          row.cost = cost
          totals.left = totals.left + cost
        end
      else
        row.price = r.market
        row.cost = r.cost
      end
    end
    row.under = type(row.price) == "number" and r.max and row.price <= r.max or nil -- at or under your top price: "*"
    rows[i] = row
  end
  return rows, totals
end

-- the next item to buy down the list: the first still short with listings (at or under its top price when onlyTop),
-- what the order takes and costs, and the one after it. rows: Shopping.Progress's rows; skip: keys passed over.
-- Returns { key, qty, cost, listings, max, allUnder, commodity } (or nil), and the next one's key.
function Market.NextBuy(rows, results, opts)
  opts = opts or {}
  local skip = opts.skip or {}
  local first, after
  for _, r in ipairs(rows or {}) do
    if r.missing > 0 and not skip[r.itemID] and not r.vendor then
      local book = results and results[r.itemID]
      local listings = {}
      for _, l in ipairs(book and book.rows or {}) do
        if not (opts.onlyTop and r.max and l.price > r.max) then
          listings[#listings + 1] = l
        end
      end
      if #listings > 0 then
        if first then
          after = r.itemID
          break
        end
        local want = book.commodity and r.missing or 1
        local taken, cost, got = Market.Fill(listings, want)
        local used = 0
        for _ in pairs(taken) do
          used = used + 1
        end
        first = {
          key = r.itemID,
          qty = got,
          cost = cost,
          listings = used,
          max = r.max,
          allUnder = r.max and listings[used] and listings[used].price <= r.max or false,
          commodity = book.commodity and true or false,
        }
      end
    end
  end
  return first, after
end

-- ------------------------------------------------------------------------------------------------ arbitrage

Market.HOUSES = { "Alliance", "Horde", "Neutral" }
Market.AGES = {
  { 1, L["Data up to 1 day"] },
  { 3, L["Data up to 3 days"] },
  { 7, L["Data up to 7 days"] },
  { 0, L["Data of any age"] },
}

function Market.AgeLabel(maxAge)
  for _, o in ipairs(Market.AGES) do
    if o[1] == (maxAge or 0) then
      return o[2]
    end
  end
  return Market.AGES[#Market.AGES][2]
end

function Market.AgeText(days)
  if not days or days <= 0 then
    return L["today"]
  elseif days == 1 then
    return L["1 day"]
  end
  return L["%d days"]:format(days)
end

function Market.ArbColumns(chosen)
  chosen = chosen or {}
  local all = {
    { key = "name", label = L["Item"], width = 200, item = true },
    { key = "buy", label = L["Buy"], width = 80, format = "money" },
    { key = "sell", label = L["Sell"], width = 80, format = "money" },
    { key = "net", label = L["Net"], width = 80, format = "signedMoney" },
    { key = "margin", label = L["Margin"], width = 60 },
    { key = "units", label = L["Units"], width = 70 },
    { key = "soldPerDay", label = L["Sells/day"], width = 64, format = "rate" },
    { key = "age", label = L["Data age"], width = 64 },
    { key = "search", label = "", width = 64, button = { label = L["Search"], action = "arbSearch" } },
  }
  local out, hidden = {}, 0
  for _, col in ipairs(all) do
    if col.item or col.button or chosen[col.key] ~= false then
      out[#out + 1] = col
    else
      hidden = hidden + 1
    end
  end
  return out, hidden, all
end

-- the routes (Arbitrage.Find's rows) as table rows. f: { atBuy (the Search button works there) }
function Market.ArbRows(routes, f)
  f = f or {}
  local rows = {}
  for i, e in ipairs(routes or {}) do
    rows[i] = {
      key = e.itemID,
      item = e.itemID,
      buy = e.buy,
      sell = e.sell,
      net = e.net or e.profit,
      margin = percent(e.margin or 0),
      units = L["%s of %s"]:format(e.units and count(e.units) or dim("?"), count(e.buyQty or 0)),
      soldPerDay = e.soldPerDay,
      age = Market.AgeText(e.age),
      search = f.atBuy and L["Search"] or false,
    }
  end
  return rows
end

-- the route's sums as key/value rows: buy, sells for, the cut, the deposit, you net
-- f: { buyHouse, sellHouse (labels), cutPct }
function Market.RouteCost(e, f)
  f = f or {}
  if not e then
    return {}
  end
  return {
    { label = L["Buy at the %s"]:format(f.buyHouse or ""), copper = e.buy },
    { label = L["Sells at the %s"]:format(f.sellHouse or ""), copper = e.sell },
    { label = L["%d%% cut"]:format(f.cutPct or 0), copper = -(e.fee or 0), signed = true },
    e.deposit and { label = L["Deposit if unsold"], copper = e.deposit } or { label = L["Deposit if unsold"], text = "—" },
    { label = L["You net"], copper = e.net or e.profit, signed = true, total = true },
  }
end

-- how fresh each side is, how fast it sells there, and how far the route goes. f: { buyData, sellData (text),
-- units (text) }
function Market.RouteData(e, f)
  f = f or {}
  if not e then
    return {}
  end
  return {
    { label = L["Buy-side data"], text = f.buyData or "—" },
    { label = L["Sell-side data"], text = f.sellData or "—" },
    { label = L["Sells/day there"], text = e.soldPerDay and ("~" .. count(e.soldPerDay)) or "—" },
    { label = L["Units"], text = f.units or "—" },
  }
end

function Market.RouteNote(e)
  if not e then
    return ""
  end
  local old = math.max(e.buyAge or 0, e.sellAge or 0)
  if old > Market.STALE_DAYS then
    return L["One side is %d days old: scan both auction houses before you buy."]:format(old)
  elseif (e.buyAge or 0) >= 1 then
    return L["One-day-old buy price: search it before you travel."]
  end
  return L["Search the buy house to see how many units still pay."]
end

-- an auction house's newest full scan from its raw log: { t, src } or nil
function Market.LastFull(raw)
  local full
  for _, e in ipairs(raw or {}) do
    if e.k == "full" and (not full or e.t > full.t) then
      full = e
    end
  end
  return full
end

-- ------------------------------------------------------------------------------------------------ status lines

-- f: { total, scanAgo (text), scanBy (nil: you) }
function Market.ScreenerStatus(f)
  local parts = { L["%s items"]:format(thousands(f.total or 0)) }
  if f.scanAgo then
    parts[#parts + 1] = f.scanBy and L["index from %s's full scan %s"]:format(f.scanBy, f.scanAgo)
      or L["index from your full scan %s"]:format(f.scanAgo)
  end
  if (f.unnamed or 0) > 0 then
    parts[#parts + 1] = L["%d items not searchable yet (names loading)"]:format(f.unnamed)
  end
  return table.concat(parts, " · ")
end

function Market.AlertStatus(n, firedToday)
  return L["%d alerts · %d fired today · checked against every scan, yours and your guild's"]:format(n, firedToday or 0)
end

function Market.AHStatus(house, found, searching, ago)
  if searching then
    return L["At the %s · searching..."]:format(house)
  end
  if not ago then
    return L["At the %s · search for an item, or pick a list"]:format(house)
  end
  return L["At the %s · %d found · searched %s"]:format(house, found or 0, ago)
end

-- a list's status line. totals: Shopping.Progress's; at: ListRows' totals (at the auction house)
function Market.ListStatus(totals, at, house)
  if not totals or (totals.items or 0) == 0 then
    return ""
  end
  if totals.done then
    return L["Everything on this list is covered."]
  end
  if at then
    return L["At the %s · %d of %d items still to buy · %s at the listings found, at or under your top prices"]:format(
      house or "",
      totals.missing,
      totals.items,
      money(at.left or 0)
    )
  end
  local s = L["%d of %d items still to buy: %s at market price"]:format(totals.missing, totals.items, money(totals.cost or 0))
  if (totals.unpriced or 0) > 0 then
    s = s .. " · " .. L["%d without a price yet"]:format(totals.unpriced)
  end
  return s .. " · " .. L["counts what your characters hold in bags and bank"]
end
