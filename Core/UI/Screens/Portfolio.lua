-- Portfolio (board Portfolio): what you hold, the ledger, who you trade with. Views Positions, Ledger, Customers,
-- Suppliers here; Auctions and (at the auction house) Sell are screens of their own (Auctions.lua, Sell.lua) behind
-- the same segmented control. Scope (all characters on this market / this one), range, Export CSV; five KPI cards
-- and the view's table. The rows come from Core/PortfolioPage.lua.
local _, ns = ...
local L = ns.L

local App, P = ns.App, ns.PortfolioPage

P.CACHE = 2 -- seconds a gather is reused (Build and Status in one draw, a burst of events)

local function clock()
  return GetTime and GetTime() or os.time()
end

-- the facts for a scope and range, gathered at most every P.CACHE seconds
function P.Facts(scope, range, fresh)
  local key = tostring(scope) .. "|" .. tostring(range)
  local c = P.cached
  if not fresh and c and c.key == key and clock() - c.at < P.CACHE then
    return c.facts
  end
  if ns.Trading and ns.Trading.ScanBags then
    pcall(ns.Trading.ScanBags, ns.Trading)
  end
  local f = P.Gather(scope, range)
  P.cached = { key = key, at = clock(), facts = f }
  return f
end

-- undercut auctions, as the Auctions screen counts them
function P.Undercut(f)
  local books = ns.AHSearch and ns.AHSearch.results or {}
  local _, sum = P.AuctionRows(f.auctions, books, { me = UnitName and UnitName("player"), scanMin = P.ScanMin() })
  return sum.undercut
end

local function params(p)
  p.view = p.view or "positions"
  p.scope = p.scope or "all"
  p.range = p.range or "7"
  return p
end

-- the views control, shared by Portfolio, Sell and Auctions: the segmented control, or a menu in the narrow window
function P.ViewControl(app, id, selected)
  local views = P.Views(app:AtAH())
  if app.compact then
    local label = selected
    for _, v in ipairs(views) do
      if v[1] == selected then
        label = v[2]
      end
    end
    return {
      id = id,
      type = "menubutton",
      props = { label = label, options = views, selected = selected, action = "view" },
    }
  end
  return { id = id, type = "segmented", props = { options = views, selected = selected, action = "view" } }
end

-- a view picked: Sell and Auctions are their own screens
function P.GoView(app, key)
  if key == "sell" then
    app:Go("sell")
  elseif key == "auctions" then
    app:Go("auctions")
  else
    local id, cur = app:Current()
    if id == "portfolio" then
      app:Go("portfolio", { view = key, scope = cur.scope, range = cur.range })
    else
      app:Go("portfolio", { view = key })
    end
  end
end

local NOTES = {
  positions = L["Click a row to open the item. Where: bags, bank, mail and auctions, across your characters on this market."],
  ledger = L["Sales and purchases, from auction mail. Click a row to open the item."],
  customers = L["The players who bought from you, from auction mail."],
  suppliers = L["The players you bought from, from auction mail."],
}

local EMPTY = {
  positions = L["Nothing held with a market price yet."],
  ledger = L["No sales or purchases in this range yet."],
  customers = L["No customers named in this range."],
  suppliers = L["No suppliers named in this range."],
}

function P.Rows(view, f)
  if view == "ledger" then
    return P.LedgerRows(f)
  elseif view == "customers" then
    return P.CounterpartyRows(f.customers)
  elseif view == "suppliers" then
    return P.CounterpartyRows(f.suppliers)
  end
  return P.PositionRows(f)
end

local function body(app, p)
  p = params(p)
  local f = P.Facts(p.scope, p.range)
  local rows = P.Rows(p.view, f)
  app:Source("portfolio.rows", rows)
  local kpis = {}
  for i, k in ipairs(P.Kpis(f, P.RangeLabel(p.range), P.Undercut(f))) do
    kpis[i] = { id = "pf.kpi" .. i, type = "kpi", props = k }
  end
  local scope, range
  if app.compact then
    scope = {
      id = "pf.scope",
      type = "menubutton",
      props = {
        label = P.SCOPES[p.scope == "char" and 2 or 1][2],
        options = P.SCOPES,
        selected = p.scope,
        action = "scope",
      },
    }
    range = {
      id = "pf.range",
      type = "menubutton",
      props = { label = P.RangeLabel(p.range), options = P.RANGES, selected = p.range, action = "range" },
    }
  else
    scope =
      { id = "pf.scope", type = "segmented", props = { options = P.SCOPES, selected = p.scope, action = "scope" } }
    range =
      { id = "pf.range", type = "segmented", props = { options = P.RANGES, selected = p.range, action = "range" } }
  end
  return {
    id = "portfolio",
    type = "column",
    props = { gap = 8 },
    children = {
      {
        id = "pf.bar",
        type = "row",
        props = { gap = 6, align = "center" },
        meta = { h = 24 },
        children = {
          P.ViewControl(app, "pf.views", p.view),
          { id = "pf.barGap", type = "spacer", meta = { grow = 1 } },
          scope,
          { id = "pf.barGap2", type = "spacer", meta = { w = 8 } },
          range,
          {
            id = "pf.export",
            type = "button",
            props = { label = L["Export CSV"], action = "export" },
            meta = { w = 80 },
          },
        },
      },
      { id = "pf.kpis", type = "grid", props = { cols = 5, gap = 8, rowH = 52 }, meta = { h = 52 }, children = kpis },
      {
        id = "pf.table",
        type = "table",
        props = {
          source = "portfolio.rows",
          columns = P.Columns(p.view),
          sort = P.SORT[p.view],
          action = "openRow",
          note = NOTES[p.view],
          empty = EMPTY[p.view],
          flex = (p.view == "customers" or p.view == "suppliers") and "player" or nil,
        },
        meta = { grow = 1 },
      },
    },
  }
end

local VIEW_TITLE =
  { positions = L["Positions"], ledger = L["Ledger"], customers = L["Customers"], suppliers = L["Suppliers"] }

App.Screen("portfolio", {
  tab = "portfolio",
  Build = body,
  Title = function(_, p)
    return VIEW_TITLE[p.view or "positions"] or L["Portfolio"]
  end,
  Status = function(_app, p)
    p = params(p)
    local f = P.Facts(p.scope, p.range)
    return P.Status(p.view, f, P.Rows(p.view, f))
  end,
  actions = {
    view = function(app, pl)
      P.GoView(app, pl.key)
    end,
    scope = function(app, pl)
      app:Set({ scope = pl.key })
    end,
    range = function(app, pl)
      app:Set({ range = pl.key })
    end,
    openRow = function(app, pl)
      if pl.item then
        app:Go("item", { item = pl.item })
      end
    end,
    export = function(app)
      local _, p = app:Current()
      local fr = app.renderer and app.renderer:Frame("pf.table")
      local dt = fr and fr.dt
      if dt and ns.Widgets and ns.Widgets.ExportBox then
        ns.Widgets.ExportBox(L["Export: %s"]:format(VIEW_TITLE[p.view or "positions"] or ""), function(format)
          return dt:ExportText(format or "csv")
        end)
      end
    end,
  },
})
