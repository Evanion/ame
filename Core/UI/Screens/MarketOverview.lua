-- Market > Overview (boards MarketOverview, MarketOverviewCompact): the whole auction house at a glance. The Market
-- screen owns the "market" screen and its mode switch; it draws this body for params.mode == "overview":
--
--   ns.ItemScreens.OverviewBody(app, params, opts) -> tree   (opts.toolbar = false: no "Change over" row, when the
--                                                             Market screen puts OverviewTools on its own toolbar)
--   ns.ItemScreens.OverviewTools(app, params) -> { item, ... } "Change over" and the period, for a toolbar row
--   ns.ItemScreens.OverviewActions                           its actions; also App.actions' fallbacks (prefixed)
--   ns.ItemScreens.OverviewStatus(app, params) -> text
--
-- params: period ("1" | "7" | "30"), chart ("index" | "value" | "auctions"). Wide: headline cards, the 30-day chart
-- with risers and fallers under it, categories and the largest items on the right. Narrow: four cards, a short chart
-- over the categories, in one column. Data from Core/Overview.lua (MarketStats.Summary).
local _, ns = ...
local L = ns.L

local Overview = ns.Overview

ns.ItemScreens = ns.ItemScreens or {}
local S = ns.ItemScreens

local function periodKey(params)
  return tostring(params.period or "7")
end

local function periodOptions()
  local out = {}
  for i, p in ipairs(Overview.PERIODS) do
    out[i] = { p[1], p[2] }
  end
  return out
end

function S.OverviewTools(app, params)
  local key = periodKey(params)
  if app.compact then
    local entries = {}
    for i, p in ipairs(Overview.PERIODS) do
      entries[i] = { key = p[1], label = p[2], checked = p[1] == key }
    end
    return {
      {
        id = "ov.period",
        type = "itemmenu",
        props = { label = Overview.PeriodLabel(Overview.PeriodDays(key)) .. " ▾", entries = entries, action = "overviewPeriod" },
      },
    }
  end
  return {
    { id = "ov.periodLabel", type = "text", props = { text = L["Change over"], color = "dim", size = 11 } },
    { id = "ov.period", type = "segmented", props = { options = periodOptions(), selected = key, action = "overviewPeriod" } },
  }
end

local MOVER_COLUMNS = {
  { key = "name", label = "", width = 140, item = true },
  { key = "market", label = "", width = 70, format = "money" },
  { key = "change", label = "", width = 70, format = "pct" },
}

local function heading(id, title, note)
  local text = ns.Kit.Color("heading", title) .. (note and ("  " .. ns.Kit.Color("dim", "· " .. note)) or "")
  return { id = id, type = "text", props = { text = text, font = "display", size = 15 }, meta = { h = 20 } }
end

local function moverBlock(id, title, note, source)
  return {
    id = id,
    type = "column",
    props = { gap = 4 },
    meta = { grow = 1 },
    children = {
      heading(id .. ".head", title, note),
      {
        id = id .. ".table",
        type = "table",
        props = { source = source, columns = MOVER_COLUMNS, bare = true, action = "overviewItem", empty = L["None yet"] },
        meta = { grow = 1 },
      },
    },
  }
end

local function categoryTable(id, compact, period, meta)
  local cols = {
    { key = "name", label = L["Category"], width = 100, align = "LEFT" },
    { key = "value", label = L["Value"], width = 64 },
    { key = "share", label = L["Share"], width = 100, format = "share" },
    { key = "change", label = Overview.PeriodLabel(period), width = 56, format = "pct" },
  }
  if not compact then
    cols[#cols + 1] = { key = "turnover", label = L["Turnover"], width = 64 }
  end
  return {
    id = id,
    type = "table",
    props = {
      source = "overview.categories",
      columns = cols,
      flex = "name",
      action = "overviewCategory",
      note = compact and L["Narrow window: one column. Widen it for breadth, risers and fallers, and the largest items."]
        or L["Click a category to open it in the screener."],
    },
    meta = meta or { grow = 1 },
  }
end

local function chartPanel(params, compact)
  local mode = params.chart or "index"
  local top
  if compact then
    top = { heading("ov.chart.head", L["Price index, 30 days"]) }
  else
    top = {
      heading("ov.chart.head", L["Last 30 days"]),
      { id = "ov.chart.gap", type = "spacer", meta = { grow = 1 } },
      {
        id = "ov.chart.mode",
        type = "segmented",
        props = { options = Overview.CHARTS, selected = mode, action = "overviewChart" },
      },
    }
  end
  return {
    id = "ov.chartcard",
    type = "card",
    props = { pad = 8, gap = 4 },
    meta = compact and { h = 120 } or { grow = 1 }, -- wide: the chart takes the room the movers leave
    children = {
      { id = "ov.chart.top", type = "row", props = { gap = 6, align = "center" }, meta = { h = 24 }, children = top },
      {
        id = "ov.chart",
        type = "chart",
        props = { source = "overview.chart", kind = "index", range = 30, format = Overview.ChartData(nil, compact and "index" or mode).format },
        meta = { grow = 1 },
      },
    },
  }
end

local function kpiRow(o, compact)
  local kpis = Overview.Kpis(o, ns.Settings and ns.Settings:Get("outlierFactor"), compact)
  local kids = {}
  for i, k in ipairs(kpis) do
    kids[i] = { id = "ov.kpi" .. i, type = "kpi", props = k }
  end
  local h = compact and 44 or 72
  return { id = "ov.kpis", type = "grid", props = { cols = #kids, gap = compact and 6 or 8, rowH = h }, meta = { h = h }, children = kids }
end

-- the body under the mode switch
function S.OverviewBody(app, params, opts)
  params, opts = params or {}, opts or {}
  local compact = app.compact and true or false
  local period = Overview.PeriodDays(periodKey(params))
  local o, why = Overview.Gather(app, period, function()
    app:Redraw()
  end)
  S.overview = o
  local kids = {}
  if opts.toolbar ~= false then
    local tools = { { id = "ov.tools.gap", type = "spacer", meta = { grow = 1 } } }
    for _, t in ipairs(S.OverviewTools(app, params)) do
      tools[#tools + 1] = t
    end
    kids[#kids + 1] = { id = "ov.tools", type = "row", props = { gap = 6, align = "center" }, meta = { h = 24 }, children = tools }
  end
  if not o then
    local house = ns.HOUSE_LABEL and ns.HOUSE_LABEL[app:House()] or app:House()
    kids[#kids + 1] = {
      id = "ov.message",
      type = "text",
      props = { text = Overview.Message(why, house), color = "dim", wrap = true, justify = "CENTER" },
      meta = { h = 60 },
    }
    app:Source("overview.chart", { xs = {}, ys = {} })
    app:Source("overview.categories", {})
    return { id = "ov", type = "column", props = { gap = 8 }, children = kids }
  end
  local className = function(id)
    return ns.ItemCache.ClassName(id)
  end
  local cats, max = Overview.Categories(o, className)
  app:Source("overview.categories", cats)
  app:Source("overview.chart", Overview.ChartData(o, compact and "index" or (params.chart or "index")))
  kids[#kids + 1] = kpiRow(o, compact)
  if compact then
    kids[#kids + 1] = chartPanel(params, true)
    kids[#kids + 1] = categoryTable("ov.categories", true, period)
    S.categoryMax = max
    return { id = "ov", type = "column", props = { gap = 6 }, children = kids }
  end
  app:Source("overview.risers", Overview.Movers(o.risers, period))
  app:Source("overview.fallers", Overview.Movers(o.fallers, period))
  local largest = Overview.Largest(o.top)
  app:Source("overview.largest", largest)
  local note = L["%s, steadily listed items"]:format(Overview.PeriodLabel(period))
  kids[#kids + 1] = {
    id = "ov.main",
    type = "row",
    props = { gap = 10 },
    meta = { grow = 1 },
    children = {
      {
        id = "ov.left",
        type = "column",
        props = { gap = 8 },
        meta = { grow = 1 },
        children = {
          chartPanel(params, false),
          {
            id = "ov.movers",
            type = "row",
            props = { gap = 8 },
            meta = { h = 24 + 5 * 22 + 6 }, -- at the bottom, as tall as their five rows
            children = {
              moverBlock("ov.risers", L["Biggest risers"], note, "overview.risers"),
              moverBlock("ov.fallers", L["Biggest fallers"], note, "overview.fallers"),
            },
          },
        },
      },
      {
        id = "ov.right",
        type = "column",
        props = { gap = 8 },
        meta = { w = 400 },
        children = {
          heading("ov.categories.head", L["Categories"], L["by listed value"]),
          -- the categories take the room and scroll when it runs short; the largest items show all their rows
          categoryTable("ov.categories", false, period),
          heading("ov.largest.head", L["Largest by value"], L["what the total leans on"]),
          {
            id = "ov.largest",
            type = "table",
            props = {
              source = "overview.largest",
              bare = true,
              action = "overviewItem",
              flex = "name",
              columns = {
                { key = "count", label = "", width = 64 },
                { key = "name", label = "", width = 150, item = true },
                { key = "price", label = "", width = 80, format = "money" },
                { key = "value", label = "", width = 100 },
              },
            },
            meta = { h = math.max(1, #largest) * 22 + 4 },
          },
        },
      },
    },
  }
  S.categoryMax = max
  return { id = "ov", type = "column", props = { gap = 8 }, children = kids }
end

function S.OverviewStatus(app)
  return Overview.Status(S.overview, app.compact, GetServerTime and GetServerTime() or 0)
end

S.OverviewActions = {
  overviewPeriod = function(app, p)
    app:Set({ period = tostring(p.key) })
  end,
  overviewChart = function(app, p)
    app:Set({ chart = p.key })
  end,
  -- a category opens in the screener
  overviewCategory = function(app, p)
    local classID = tonumber(tostring(p.key or ""):match("^class:(%-?%d+)$"))
    if classID and classID ~= ns.MarketStats.OTHER then
      app:Go("market", { mode = "screener", classID = classID })
    end
  end,
  overviewItem = function(app, p)
    local key = p.item or tonumber(tostring(p.key or ""):match("(%d+)$"))
    if key then
      app:Go("item", { item = key })
    end
  end,
}

-- the Market screen may list these among its own actions; until then they answer from App's fallbacks
for name, fn in pairs(S.OverviewActions) do
  if ns.App and ns.App.actions and not ns.App.actions[name] then
    ns.App.actions[name] = fn
  end
end
