-- Market's Overview mode (boards MarketOverview, MarketOverviewCompact): the whole auction house at a glance, from
-- MarketStats.Summary. Pure functions turn the summary into widget props and table rows; Overview.Gather reads the
-- viewed market's index (built in the background: it says why when there's nothing yet).
--
--   Overview.Gather(app, period, onReady) -> summary | nil, why ("loading" | "empty" | "off" | "building" | "noscan")
--   Overview.Kpis(o, factor, compact) -> kpi props      Overview.Movers(list, period) -> rows
--   Overview.Categories(o, className) -> rows, max       Overview.Largest(top) -> rows
--   Overview.ChartData(o, mode) -> chart source          Overview.Message(why, house) -> text
local _, ns = ...
local L = ns.L

local Overview = {}
ns.Overview = Overview

local DAY = 86400
local floor = math.floor

Overview.PERIODS = { { "1", L["1 day"], 1 }, { "7", L["7 days"], 7 }, { "30", L["30 days"], 30 } }
Overview.CHARTS = { { "index", L["Price index"] }, { "value", L["Listed value"] }, { "auctions", L["Auctions"] } }
Overview.CHANGE_KEY = { [1] = "change1", [7] = "change7", [30] = "change30" }

local function W()
  return ns.Widgets
end

local function big(c)
  return W() and W().BigMoney and W().Plain(W().BigMoney(c or 0)) or tostring(c)
end

local function thousands(n)
  return W() and W().Thousands and W().Thousands(n or 0) or tostring(n)
end

function Overview.PeriodDays(key)
  for _, p in ipairs(Overview.PERIODS) do
    if p[1] == tostring(key) then
      return p[3]
    end
  end
  return 7
end

function Overview.PeriodLabel(days)
  for _, p in ipairs(Overview.PERIODS) do
    if p[3] == days then
      return p[2]
    end
  end
  return L["7 days"]
end

-- a change as the cards show it: "▲ 0.9%" good, "▼ 2.4%" bad, a flat one dim
function Overview.Delta(x)
  if not x then
    return nil, "dim"
  end
  local text = ("%.1f%%"):format(math.abs(x) * 100)
  if x > 0.0005 then
    return "▲ " .. text, "good"
  elseif x < -0.0005 then
    return "▼ " .. text, "bad"
  end
  return text, "dim"
end

-- the headline figures: price index, listed value, turnover, auctions, breadth (compact: the first four, no notes)
function Overview.Kpis(o, factor, compact)
  local out = {}
  local function add(label, value, change, note)
    local d, tone = Overview.Delta(change)
    out[#out + 1] = { label = label, value = value, delta = d, deltaTone = tone, note = not compact and note or nil }
  end
  add(
    compact and L["Price index"] or L["AME price index"],
    o.level and ("%.1f"):format(o.level) or "—",
    o.levelChange,
    L["%s steadily listed items · 30 days ago = 100"]:format(thousands(o.basket or 0))
  )
  add(
    L["Listed value"],
    big(o.value),
    o.valueChange,
    (factor and factor > 1) and L["each price capped at %d× its 30-day average"]:format(factor) or nil
  )
  out[#out + 1] = {
    label = compact and L["Turnover"] or L["Turnover (estimate)"],
    value = "~" .. big(o.turnover),
    delta = compact and L["/day"] or L["/ day"],
    deltaTone = "dim",
    note = not compact and L["supply leaving the AH × price"] or nil,
  }
  add(
    L["Auctions"],
    thousands(o.auctions),
    o.auctionsChange,
    L["%s items · %s units"]:format(thousands(o.items or 0), W() and W().Count(o.units or 0) or tostring(o.units))
  )
  if not compact then
    local moved = (o.up or 0) + (o.down or 0)
    out[#out + 1] = {
      label = L["Breadth"],
      value = moved > 0 and ("%d%%"):format(floor(100 * o.up / moved + 0.5)) or "—",
      delta = moved > 0 and (o.up >= o.down and L["rising"] or L["falling"]) or nil,
      deltaTone = "dim",
      note = L["%s up · %s down · %s Buy · %s Sell"]:format(
        thousands(o.up or 0),
        thousands(o.down or 0),
        thousands(o.buy or 0),
        thousands(o.sell or 0)
      ),
    }
  end
  return out
end

-- risers or fallers: item, market price, the change over the period (click opens the item)
function Overview.Movers(list, period)
  local key = Overview.CHANGE_KEY[period] or "change7"
  local rows = {}
  for i, s in ipairs(list or {}) do
    rows[i] = { key = "item:" .. tostring(s.itemID), item = s.itemID, name = s.itemID, market = s.market, change = s[key] }
  end
  return rows
end

-- categories by listed value: name, value, share (the bars full at the biggest share), the change, turnover
function Overview.Categories(o, className)
  local rows, max = {}, 0.01
  for i, c in ipairs(o.sectors or {}) do
    local other = c.classID == ns.MarketStats.OTHER
    rows[i] = {
      key = "class:" .. tostring(c.classID),
      classID = not other and c.classID or nil,
      name = other and L["Other"] or (className and className(c.classID)) or tostring(c.classID),
      value = big(c.value),
      share = c.share,
      change = c.change,
      turnover = c.turnover and ("~" .. big(c.turnover)) or "—",
    }
    max = math.max(max, c.share or 0)
  end
  return rows, max
end

-- the largest items by value: "18,400 ×", the item, the price each it's counted at, what that comes to (or, capped
-- at the outlier limit, what the listings would have come to)
function Overview.Largest(top)
  local rows = {}
  for i, t in ipairs(top or {}) do
    rows[i] = {
      key = "item:" .. tostring(t.id),
      item = t.id,
      count = { text = thousands(t.qty) .. " ×", color = "dim" },
      name = t.id,
      price = t.price,
      value = t.rawValue and { text = L["capped from %s"]:format(big(t.rawValue)), color = "dim" } or big(t.value),
    }
  end
  return rows
end

-- the 30-day chart: the price index (100 marked), listed value or auctions, by day
function Overview.ChartData(o, mode)
  local s = o and o.series or {}
  local days, ys, format, label = s.levelDays, s.level, "level", L["Price index"]
  if mode == "value" then
    days, ys, format, label = s.days, s.value, "money", L["Listed value"]
  elseif mode == "auctions" then
    days, ys, format, label = s.days, s.auctions, "count", L["Auctions"]
  end
  local xs = {}
  for i, d in ipairs(days or {}) do
    xs[i] = d * DAY
  end
  return {
    id = "overview:" .. tostring(mode) .. ":" .. #xs,
    xs = xs,
    ys = ys or {},
    base = mode ~= "value" and mode ~= "auctions" and 100 or nil,
    label = label,
    format = format,
  }
end

function Overview.Message(why, house)
  if why == "empty" then
    return L["No price history for the %s yet: scan there (any character on this account counts)."]:format(house)
  elseif why == "noscan" then
    return L["No full scan of the %s in the last 30 days. Market totals need one: run a full scan there (any scanner)."]:format(house)
  elseif why == "off" then
    return L["The Overview needs market statistics, which are off: switch on the market overview in Settings."]
  elseif why == "building" then
    return L["Building market statistics..."]
  end
  return L["Loading history..."]
end

-- "Totals from your full scan 2 h ago · index from 30 days of history · days without a full scan are left out"
function Overview.Status(o, compact, now)
  if not o then
    return ""
  end
  local when = o.day and (W() and W().DaysAgo and W().DaysAgo(o.day, floor((now or 0) / DAY)) or date and date("%b %d", o.day * DAY))
  if compact then
    return L["Totals from the full scan of %s"]:format(when or "")
  end
  return L["Totals from the full scan of %s"]:format(when or "")
    .. " · "
    .. L["index from %d days of history"]:format(#(o.series and o.series.levelDays or {}))
    .. " · "
    .. L["days without a full scan are left out"]
end

local function itemClass(id)
  return ns.ItemCache.Get(id).classID
end

-- the summary for the viewed market and period (nil and why when there's none yet)
function Overview.Gather(app, period, onReady)
  local AME = ns.AME
  if not (AME and AME.MarketRealmName) then
    return nil, "loading"
  end
  local shard = app:Shard()
  local index = AME.CachedIndex and AME:CachedIndex(shard)
  if not index then
    if AME.HistoryLoaded and AME:HistoryLoaded() and AME.HasData and not AME:HasData(shard) then
      return nil, "empty"
    end
    if AME.HistoryLoaded and not AME:HistoryLoaded() then
      if AME.LoadHistory then
        pcall(AME.LoadHistory, AME)
      end
    elseif AME.IndexFor and Overview.loading ~= shard then
      Overview.loading = shard
      pcall(AME.IndexFor, AME, shard, function()
        Overview.loading = nil
        if onReady then
          onReady()
        end
      end)
    end
    return nil, "loading"
  end
  if not index.stats and not ns.Settings:Get("marketOverview") then
    return nil, "off" -- market statistics are built only with the Overview switched on (Settings)
  end
  if not index.stats then
    -- built while the Overview was off, or saved by an older version: rebuilt with statistics
    if AME.RefreshIndex and Overview.building ~= shard then
      Overview.building = shard
      pcall(AME.RefreshIndex, AME, shard)
    end
    return nil, "building"
  end
  Overview.building = nil
  local hide = AME.watch and AME.watch:Hidden() or nil
  local ok, o = pcall(ns.MarketStats.Summary, index, period, itemClass, hide, ns.Settings:Get("outlierFactor"))
  if not ok or not o then
    return nil, "noscan"
  end
  return o
end
