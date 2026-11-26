-- The chart widget (the canvas's Chart): LibAMEChart-1.0 drawn by the layout engine, fed by a data source. The
-- series never go in the layout: the view hands them to the renderer's context, and the chart reads them when drawn.
--
--   chart { source = "name",          -- ctx.sources[name]: a table, or a function returning one (below)
--           kind = "item" | "index" | "spark",
--           range?,                   -- "2D" ... "All" (item) or a number of days: the span shown (else the data's)
--           style? "line" | "candles",-- item only
--           legend?,                  -- item: draw the legend box (default true); index / spark: none
--           compact?,                 -- the narrow window: the legend folds into a "Legend" button
--           hidden?,                  -- { [layer key] = true }: legend layers switched off
--           action?,                  -- a legend row click: { key = layer }
--           hint?,                    -- a dim line in the corner ("Scroll to zoom ...")
--           format? }                 -- index: "level" | "money" | "count" (the y axis and hover)
--
-- Sources:
--   item:  { id?, points = { { x, market, min?, high?, qty?, avg? } }, intraday?, daily?, vendor?, from?, to?, now?,
--            trades = { { x, y, kind = "buy" | "sale" } }?, message? }   (Core/ItemPage.lua ChartData builds it)
--   index: { xs, ys, base? (a dashed level, 100), label?, message? }
--   spark: { xs, ys, avg? (aligned with xs), label?, format? ("money"), hourly? (the hover shows the hour) }
--
-- The item chart merges every series into one grid of time slots (Analytics.Slot), so candles, lines, the average
-- and supply sit at the same x and hovering a slot shows them all; zooming far enough changes the slot size.
local _, ns = ...
local L = ns.L

local Layout, Kit, W = ns.Layout, ns.Kit, ns.Widgets

local DAY = 86400
local Chart = {}
ns.ChartPart = Chart

Chart.SLOT_TARGET = 60
Chart.FAST = 20 -- MA 20: the average of the last 20 slots' closes
Chart.VENDOR_SHARE = 0.33 -- the vendor line is drawn when a vendor pays at least this share of the lowest price
Chart.LEGEND_ROW, Chart.LEGEND_SWATCH = 14, 12

local function lib()
  return LibStub and LibStub("LibAMEChart-1.0", true)
end

local function rgba(c, a)
  return { c[1], c[2], c[3], a or c[4] or 1 }
end

local function colors()
  local chart = W and W.COLORS and W.COLORS.chart or {}
  return {
    market = Kit.C("chartMarket"),
    lowest = Kit.C("chartLowest"),
    average = Kit.C("chartAverage"),
    fast = Kit.C("chartFast"),
    supply = Kit.C("chartSupply"),
    up = Kit.C("good"),
    down = Kit.C("bad"),
    vendor = chart.vendor or Kit.C("soft"),
    bought = chart.bought or Kit.C("link"),
    sold = chart.sold or Kit.C("q4"),
  }
end

local function source(ctx, name)
  local s = ctx and ctx.sources and ctx.sources[name]
  if type(s) == "function" then
    s = s()
  end
  return type(s) == "table" and s or {}
end

-- the days a range shows (nil: all)
local RANGE_DAYS = { ["2D"] = 2, ["7D"] = 7, ["30D"] = 30, ["90D"] = 90, ["1Y"] = 365 }
local function rangeDays(range)
  if type(range) == "number" then
    return range
  end
  return RANGE_DAYS[range]
end

-- a slot's length in words: "15 min", "6 h", "1 day", "3 days"
function Chart.SlotText(size)
  if size < 3600 then
    return L["%d min"]:format(size / 60)
  elseif size < DAY then
    return L["%d h"]:format(size / 3600)
  elseif size == DAY then
    return L["1 day"]
  end
  return L["%d days"]:format(math.floor(size / DAY + 0.5))
end

-- The slot size for the span on screen (the zoom, else the range, else all the points), never finer than the
-- points' own spacing: 15 minutes for scans, a day for daily history.
function Chart.SlotSize(data, view)
  local pts = data.points or {}
  if #pts == 0 then
    return DAY
  end
  local first, last = pts[1].x, pts[#pts].x
  local from, to = (view and view[1]) or data.from or first, (view and view[2]) or data.to or last
  from, to = math.max(from, first), math.min(to, last)
  return ns.Analytics.SlotSize(math.max(0, to - from), Chart.SLOT_TARGET, data.intraday and 15 * 60 or DAY)
end

-- Pure: the item chart's series and legend, from the source and the slot size.
-- -> { series = { { id, spec }, ... }, legend = { entry, ... }, slots, size, vendor }
--   legend entry: { color, label, kind = "line" | "dash" | "square" | "dot", key? } or { note = text }
function Chart.ItemSeries(data, size, style, hidden)
  hidden = hidden or {}
  local c = colors()
  local s = ns.Analytics.Slot(data.points or {}, size)
  local out, legend = {}, {}
  local function add(id, spec)
    if not hidden[id] then
      out[#out + 1] = { id, spec }
    end
  end
  local function present(ys)
    local oxs, oys = {}, {}
    for i, x in ipairs(s.xs) do
      if ys[i] then
        oxs[#oxs + 1], oys[#oys + 1] = x, ys[i]
      end
    end
    return oxs, oys
  end
  local qxs, qys = present(s.qty)
  add("qty", { xs = qxs, ys = qys, kind = "bars", axis = "volume", color = c.supply })
  if style == "candles" then
    add("candles", {
      kind = "candles",
      axis = "price",
      xs = s.xs,
      open = s.open,
      high = s.high,
      low = s.low,
      close = s.close,
      period = size,
      marker = true,
      color = c.up,
      upColor = c.up,
      downColor = c.down,
    })
    legend[#legend + 1] = { c.up, L["Up"], kind = "square" }
    legend[#legend + 1] = { c.down, L["Down"], kind = "square" }
    legend[#legend + 1] = { note = L["wick = cheapest listing"] }
  else
    add("market", { xs = s.xs, ys = s.market, kind = "area", axis = "price", color = c.market, marker = true })
    local lxs, lys = present(s.min)
    add("min", { xs = lxs, ys = lys, kind = "line", axis = "price", color = rgba(c.lowest, 0.9), width = 1.2 })
    legend[#legend + 1] = { c.market, L["Market"], kind = "line", key = "market" }
    legend[#legend + 1] = { c.lowest, L["Lowest"], kind = "line", key = "min" }
  end
  local axs, ays = present(s.avg)
  if #axs > 1 then
    add("sma", { xs = axs, ys = ays, kind = "line", axis = "price", color = rgba(c.average, 0.9), width = 1.5 })
    legend[#legend + 1] = { c.average, L["7-day average"], kind = "line", key = "sma" }
  end
  local fxs, fys = {}, {}
  for i = 2, #s.xs do
    fxs[#fxs + 1], fys[#fys + 1] = s.xs[i], ns.Analytics.SMA(s.close, math.min(Chart.FAST, i), i)
  end
  local span = Chart.FAST * size
  local fastLabel = L["MA %d (%s)"]:format(
    Chart.FAST,
    span < 3 * DAY and L["%d hours"]:format(span / 3600) or L["%d days"]:format(math.floor(span / DAY + 0.5))
  )
  if #fxs > 1 then
    add("fast", { xs = fxs, ys = fys, kind = "line", axis = "price", color = rgba(c.fast, 0.9), width = 1.3 })
    legend[#legend + 1] = { c.fast, fastLabel, kind = "line", key = "fast" }
  end
  -- what a vendor pays: a dashed level when it's near the prices; far below them the legend just says it
  local vendorLine
  local vendor = data.vendor
  if vendor and vendor > 0 and #s.xs > 0 then
    local lowest
    for i = 1, #s.xs do
      for _, y in ipairs({ s.low[i], s.market[i] }) do
        if y and y > 0 and (not lowest or y < lowest) then
          lowest = y
        end
      end
    end
    if lowest and vendor >= lowest * Chart.VENDOR_SHARE then
      vendorLine = vendor
      add("vendor", {
        xs = { s.xs[1], math.max(s.xs[#s.xs], (data.now or s.xs[#s.xs]) + DAY) },
        ys = { vendor, vendor },
        hover = false,
        kind = "line",
        axis = "price",
        color = c.vendor,
        width = 1.2,
        dash = { 6, 4 },
      })
      legend[#legend + 1] = { c.vendor, L["Vendor price"], kind = "dash", key = "vendor" }
    else
      legend[#legend + 1] = { note = L["Vendor price %s (below the chart)"]:format(W.Money(vendor, true)) }
    end
  end
  legend[#legend + 1] = { c.supply, L["Supply"], kind = "square", key = "qty" }
  local trades = data.trades
  if trades and #trades > 0 then
    local txs, tys, tcs = {}, {}, {}
    local bought, sold = false, false
    for i, t in ipairs(trades) do
      txs[i], tys[i] = t.x, t.y
      tcs[i] = t.kind == "buy" and c.bought or c.sold
      bought, sold = bought or t.kind == "buy", sold or t.kind ~= "buy"
    end
    add("trades", { xs = txs, ys = tys, colors = tcs, kind = "points", axis = "price", size = 8 })
    if bought then
      legend[#legend + 1] = { c.bought, L["You bought"], kind = "dot", key = "trades" }
    end
    if sold then
      legend[#legend + 1] = { c.sold, L["You sold"], kind = "dot", key = "trades" }
    end
  end
  legend[#legend + 1] = { note = L["(one point per %s)"]:format(Chart.SlotText(size)) }
  if data.intraday and data.daily then
    legend[#legend + 1] = { note = L["(older days: one point a day)"] }
  end
  return { series = out, legend = legend, slots = s, size = size, vendor = vendorLine, fastLabel = fastLabel }
end

-- ------------------------------------------------------------------------------------------------ the frames

local function money(v)
  return W.Money(v, true)
end

local function itemHover(f)
  return function(_, x, rows)
    local size = f.size or DAY
    local from, to = x - size / 2, x + size / 2
    local title
    if size < DAY then
      title = date("%a %b %d, %H:%M", from) .. " - " .. date("%H:%M", to)
    elseif size == DAY then
      title = date("%a %b %d, %Y", from)
    else
      title = date("%b %d", from) .. " - " .. date("%b %d, %Y", to - DAY)
    end
    local lines = { Kit.Color("white", title) }
    local s = f.slots
    if rows.candles and rows.candles.x == x and s then
      local i = rows.candles.index
      lines[#lines + 1] = { W.Dim(L["Open"]), money(s.open[i]) }
      lines[#lines + 1] = { W.Dim(L["High"]), money(s.high[i]) }
      lines[#lines + 1] = { W.Dim(L["Low (cheapest)"]), money(s.low[i]) }
      lines[#lines + 1] = { W.Dim(L["Close"]), money(s.close[i]) }
    end
    for _, r in ipairs({
      { "market", L["Market"] },
      { "min", L["Lowest"] },
      { "sma", L["7-day average"] },
      { "fast", f.fastLabel or "" },
    }) do
      local row = rows[r[1]]
      if row and row.x == x then
        lines[#lines + 1] = { W.Dim(r[2]), money(row.y) }
      end
    end
    if rows.qty and rows.qty.x == x then
      lines[#lines + 1] = { W.Dim(L["Supply"]), W.Count(rows.qty.y) }
    end
    if f.vendorLine then
      lines[#lines + 1] = { W.Dim(L["Vendor price"]), money(f.vendorLine) }
    end
    return lines
  end
end

local function indexFormat(format)
  if format == "money" then
    return function(v)
      return W.BigMoney and W.Plain and W.Plain(W.BigMoney(v)) or money(v)
    end
  elseif format == "count" then
    return function(v)
      return W.Count(v)
    end
  end
  return function(v)
    return ("%.1f"):format(v)
  end
end

-- one LibAMEChart per kind, made the first time that kind is drawn
local function chartFor(f, kind)
  f.charts = f.charts or {}
  local c = f.charts[kind]
  if c then
    return c
  end
  local L2 = lib()
  if not L2 then
    return nil
  end
  if kind == "item" then
    c = L2:New(f.plot, { panes = { { axis = "price", weight = 3 }, { axis = "volume", weight = 1 } } })
    c:SetAxisFormatter("price", money)
    c:SetAxisFormatter("volume", function(v)
      return W.Count(v)
    end)
    c:SetHoverFormatter(itemHover(f))
    if c.RegisterCallback then
      -- zooming far enough changes the slot size: merge the points into the new slots
      c.RegisterCallback(f, "RangeChanged", function(_, _, from, to)
        if f.data and Chart.SlotSize(f.data, { from, to }) ~= f.size then
          f.view = { from, to }
          Chart.Draw(f)
        end
      end)
    end
    c.frame:HookScript("OnEnter", function()
      f.hovering = true
      Chart.Legend(f)
    end)
    c.frame:HookScript("OnLeave", function()
      f.hovering = false
      Chart.Legend(f)
    end)
  elseif kind == "spark" then
    c =
      L2:New(f.plot, { panes = { { axis = "y", weight = 1 } }, padding = { left = 2, right = 2, top = 4, bottom = 4 } })
    c:SetAxisFormatter("y", function()
      return ""
    end)
    -- a spark with a label (Home's gold line) shows the point's figure on hover (its day, or hour when hourly); one
    -- without none
    c:SetHoverFormatter(function(_, x, rows)
      local data, row = f.data or {}, rows.y
      if not data.label or not row or row.x ~= x then
        return nil
      end
      local value = data.format == "money" and W.Money(row.y, true) or tostring(row.y)
      return {
        Kit.Color("white", date(data.hourly and "%a %b %d %H:%M" or "%a %b %d", x)),
        { W.Dim(data.label), value },
      }
    end)
  else
    c = L2:New(f.plot, { panes = { { axis = "y", weight = 1 } } })
    c:SetHoverFormatter(function(_, x, rows)
      local row = rows.y
      local lines = { Kit.Color("white", date("%a %b %d", x)) }
      if row and row.x == x then
        lines[#lines + 1] = { W.Dim(f.data and f.data.label or ""), f.format(row.y) }
      end
      return lines
    end)
  end
  c.frame:SetPoint("TOPLEFT", 4, -4)
  c.frame:SetPoint("BOTTOMRIGHT", -4, 4)
  f.charts[kind] = c
  return c
end

-- the legend box: one row per series (swatch, label), notes dim under the labels; a row click toggles its layer
local SWATCH = { line = { 12, 3 }, dash = { 5, 2 }, square = { 8, 8 }, dot = { 9, 9 } }
function Chart.Legend(f)
  local box, entries, p = f.legendBox, f.legend or {}, f.props or {}
  local show = p.kind == "item" and p.legend ~= false and #entries > 0
  local compact = p.compact and true or false
  f.legendToggle:SetShown(show and compact and not f.hovering)
  f.legendToggle.label:SetText(L["Legend"] .. (f.legendOpen and " ▾" or " ▸"))
  box:ClearAllPoints()
  if compact then
    box:SetPoint("TOPLEFT", f.legendToggle, "BOTTOMLEFT", 0, -4)
  else
    box:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -10)
  end
  box:SetShown(show and (not compact or f.legendOpen))
  box:SetAlpha(f.hovering and 0.25 or 1)
  if not show then
    return
  end
  local media = lib() and lib().MEDIA
  local hidden = p.hidden or {}
  local widest = 0
  for i, e in ipairs(entries) do
    local r = box.rows[i]
    if not r then
      r = CreateFrame("Button", nil, box)
      r:SetHeight(Chart.LEGEND_ROW)
      r:SetPoint("TOPLEFT", 4, -7 - (i - 1) * Chart.LEGEND_ROW)
      r:SetPoint("RIGHT", -4, 0)
      r.swatch = r:CreateTexture(nil, "OVERLAY")
      r.swatch:SetPoint("LEFT", 4, 0)
      r.swatch2 = r:CreateTexture(nil, "OVERLAY")
      r.swatch2:SetPoint("LEFT", 11, 0)
      r.text = Kit.Text(r, { size = 11 })
      r.text:SetPoint("LEFT", 4 + Chart.LEGEND_SWATCH + 6, 0)
      r:SetScript("OnClick", function(self)
        if self.key and f.props and f.props.action then
          f.ctx:Dispatch(f.props.action, { key = self.key })
        end
      end)
      box.rows[i] = r
    end
    r.key = e.key
    r:EnableMouse(e.key ~= nil)
    local on = not (e.key and hidden[e.key])
    r.swatch2:Hide()
    if e.note then
      r.swatch:Hide()
      r.text:SetText(W.Dim(e.note))
    else
      local c, kind = e[1], e.kind or "square"
      local size = SWATCH[kind] or SWATCH.square
      r.swatch:SetSize(size[1], size[2])
      if kind == "dot" and media then
        r.swatch:SetTexture(media .. "Dot")
        r.swatch:SetVertexColor(c[1], c[2], c[3], 1)
      else
        r.swatch:SetColorTexture(c[1], c[2], c[3], 1)
      end
      if kind == "dash" then
        r.swatch2:SetSize(size[1], size[2])
        r.swatch2:SetColorTexture(c[1], c[2], c[3], 1)
        r.swatch2:Show()
      end
      r.swatch:SetAlpha(on and 1 or 0.3)
      r.swatch2:SetAlpha(on and 1 or 0.3)
      r.swatch:Show()
      r.text:SetText(on and e[2] or W.Dim(e[2]))
    end
    r:Show()
    widest = math.max(widest, r.text:GetStringWidth() or 60)
  end
  for i = #entries + 1, #box.rows do
    box.rows[i]:Hide()
  end
  box:SetSize(8 + Chart.LEGEND_SWATCH + 6 + widest + 14, 14 + #entries * Chart.LEGEND_ROW)
end

-- draw the current props and source
function Chart.Draw(f)
  local p, data = f.props, f.data or {}
  for kind, c in pairs(f.charts or {}) do
    c.frame:SetShown(kind == p.kind)
  end
  local c = chartFor(f, p.kind)
  if not c then
    return
  end
  c.range = nil
  c:ClearSeries()
  f.legend = {}
  if p.kind == "item" then
    local pts = data.points or {}
    if #pts == 0 then
      c:SetMessage(
        data.message or L["No history for this item yet. Search for it at the auction house, or run a full scan."]
      )
      Chart.Legend(f)
      return
    end
    c:SetMessage(data.message)
    local size = Chart.SlotSize(data, f.view)
    local built = Chart.ItemSeries(data, size, p.style, p.hidden)
    f.size, f.slots, f.vendorLine, f.fastLabel = size, built.slots, built.vendor, built.fastLabel
    for _, s in ipairs(built.series) do
      c:SetSeries(s[1], s[2])
    end
    f.legend = built.legend
    local days = rangeDays(p.range)
    if f.view then
      c.range = { f.view[1], f.view[2] }
    elseif data.from then
      c.range = { data.from, data.to }
    elseif days then
      local now = data.now or (GetServerTime and GetServerTime()) or 0
      c.range = { now - days * DAY, now + DAY }
    end
    c:Refresh()
  else
    local xs, ys = data.xs or {}, data.ys or {}
    if #xs < 2 then
      c:SetMessage(data.message or L["Not enough days yet: the chart fills in with a full scan a day."])
      Chart.Legend(f)
      return
    end
    c:SetMessage(nil)
    if p.kind == "index" then
      f.format = indexFormat(p.format)
      c:SetAxisFormatter("y", f.format)
      if data.base then
        c:SetSeries("base", {
          xs = { xs[1], xs[#xs] },
          ys = { data.base, data.base },
          kind = "line",
          hover = false,
          color = Kit.C("controlLine"),
          width = 1,
          dash = { 4, 4 },
        })
      end
      c:SetSeries("y", { xs = xs, ys = ys, kind = "area", color = Kit.C("chartMarket"), marker = true })
    else
      c:SetSeries("y", { xs = xs, ys = ys, kind = "line", color = Kit.C(data.color or "chartMarket"), width = 2 })
      if data.avg then
        local axs, ays = {}, {}
        for i, x in ipairs(xs) do
          if data.avg[i] then
            axs[#axs + 1], ays[#ays + 1] = x, data.avg[i]
          end
        end
        c:SetSeries("avg", { xs = axs, ys = ays, kind = "line", color = Kit.C("chartAverage"), width = 1.5 })
      end
    end
    local days = rangeDays(p.range)
    if days then
      c:SetXRange(xs[#xs] - days * DAY, xs[#xs])
    end
  end
  Chart.Legend(f)
end

Layout.Register("chart", {
  props = {
    source = "string",
    kind = "string",
    range = "any?",
    style = "string?",
    legend = "boolean?",
    compact = "boolean?",
    hidden = "table?",
    action = "string?",
    hint = "string?",
    format = "string?",
    bare = "boolean?", -- inside a card: no box of its own (the card is the frame)
  },
  create = function(parent, ctx)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f.ctx = ctx
    local bg = W and W.COLORS and W.COLORS.chart and W.COLORS.chart.bg
    Kit.Box(f, bg or "bg", "line")
    f.plot = CreateFrame("Frame", nil, f)
    f.plot:SetAllPoints()
    f.legendBox = CreateFrame("Frame", nil, f, "BackdropTemplate")
    local cc = W and W.COLORS and W.COLORS.chart or {}
    Kit.Box(f.legendBox, cc.legendBg or "panel", cc.legendBorder or "line")
    f.legendBox:SetFrameLevel((f:GetFrameLevel() or 1) + 5)
    f.legendBox:EnableMouse(true)
    f.legendBox.rows = {}
    f.legendToggle = Kit.Button(f)
    f.legendToggle:SetSize(76, 20)
    f.legendToggle:SetPoint("TOPLEFT", 8, -8)
    f.legendToggle:SetFrameLevel((f:GetFrameLevel() or 1) + 5)
    f.legendToggle:SetScript("OnClick", function()
      f.legendOpen = not f.legendOpen
      Chart.Legend(f)
    end)
    f.hint = Kit.Text(f, { size = 11, color = "dim", justify = "RIGHT" })
    f.hint:SetPoint("BOTTOMRIGHT", -70, 24)
    f.hint:SetAlpha(0.7)
    return f
  end,
  update = function(f, p, ctx)
    -- other data (its id: the item and range), kind or range drops the zoom; a redraw of the same keeps it
    local data = source(ctx, p.source)
    local id = data.id or data
    if f.dataId ~= id or (f.props and (f.props.kind ~= p.kind or f.props.range ~= p.range)) then
      f.view = nil
    end
    f.dataId = id
    f.props, f.data, f.ctx = p, data, ctx
    if f.bare ~= (p.bare and true or false) then
      f.bare = p.bare and true or false
      if f.bare then
        Kit.Box(f, { 0, 0, 0, 0 }, false)
      else
        local bg = W and W.COLORS and W.COLORS.chart and W.COLORS.chart.bg
        Kit.Box(f, bg or "bg", "line")
      end
    end
    f.hint:SetText(p.hint or "")
    f.hint:SetShown(p.hint ~= nil and not p.compact)
    Chart.Draw(f)
  end,
  size = function()
    return 0, 0
  end,
})
