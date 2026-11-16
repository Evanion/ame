--[[
LibAMEChart-1.0: time-series charts for World of Warcraft addons.
MIT licensed (see LICENSE in this folder). Part of Azeroth Mercantile Exchange, usable by any addon.

  local Chart = LibStub("LibAMEChart-1.0")
  local chart = Chart:New(parentFrame, {
    panes = { { axis = "price", weight = 3 }, { axis = "volume", weight = 1 } },
  })
  chart:SetSeries("market", { xs = times, ys = prices, kind = "area", axis = "price", color = { 0.3, 0.7, 1 } })
  chart:SetSeries("qty", { xs = times, ys = quantities, kind = "bars", axis = "volume", color = { 0.6, 0.6, 0.6 } })
  chart:SetAxisFormatter("price", function(v) return GetCoinTextureString(v) end)
  chart:SetHoverFormatter(function(chart, x, rows) return lines end) -- rows: { [seriesID] = { x, y, index } }
  chart:SetXRange(from, to)      -- optional; defaults to the data's extent
  chart.callbacks:RegisterCallback(owner, "RangeChanged", fn)   -- after zoom/pan, args: (event, chart, from, to)

Interaction: mouse wheel zooms around the cursor, drag pans, double-click resets, hovering shows a crosshair with
the nearest point of every series.

Series kinds: "line", "area" (line + translucent fill; trapezoid fill where Texture:SetVertexOffset exists), "bars".
Points are downsampled with LTTB to about one per 2 px, so large series stay cheap to draw. Regions are pooled and
reused between redraws.
]]

local MAJOR, MINOR = "LibAMEChart-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then
  return
end

local abs, ceil, floor, huge, log10, max, min =
  math.abs, math.ceil, math.floor, math.huge, math.log10 or function(x)
    return math.log(x) / math.log(10)
  end, math.max, math.min

---------------------------------------------------------------------------------------------------------------------
-- Math (pure; unit-tested outside the game)

local M = {}
lib.Math = M

function M.NiceStep(range, target)
  if range <= 0 then
    return 1
  end
  local raw = range / max(1, target)
  local mag = 10 ^ floor(log10(raw))
  local norm = raw / mag
  local nice
  if norm < 1.5 then
    nice = 1
  elseif norm < 3 then
    nice = 2
  elseif norm < 7 then
    nice = 5
  else
    nice = 10
  end
  return nice * mag
end

-- tick values within [lo, hi]
function M.NiceTicks(lo, hi, target)
  if hi <= lo then
    return { lo }, 1
  end
  local step = M.NiceStep(hi - lo, target)
  local ticks = {}
  local v = ceil(lo / step) * step
  while v <= hi + step * 1e-9 do
    ticks[#ticks + 1] = v
    v = v + step
  end
  return ticks, step
end

local HOUR, DAY = 3600, 86400
local TIME_STEPS = {
  { 1 * HOUR, "hour" },
  { 2 * HOUR, "hour" },
  { 3 * HOUR, "hour" },
  { 6 * HOUR, "hour" },
  { 12 * HOUR, "hour" },
  { 1 * DAY, "day" },
  { 2 * DAY, "day" },
  { 7 * DAY, "week" },
  { 14 * DAY, "week" },
  { 30 * DAY, "month" },
  { 91 * DAY, "month" },
  { 365 * DAY, "year" },
}

-- ticks aligned to UTC multiples of a "nice" duration: { { t =, unit = "hour"|"day"|"week"|"month"|"year" }, ... }
function M.TimeTicks(from, to, target)
  local span = to - from
  local step, unit = TIME_STEPS[#TIME_STEPS][1], TIME_STEPS[#TIME_STEPS][2]
  for _, s in ipairs(TIME_STEPS) do
    if span / s[1] <= target then
      step, unit = s[1], s[2]
      break
    end
  end
  local ticks = {}
  local t = ceil(from / step) * step
  while t <= to do
    ticks[#ticks + 1] = { t = t, unit = unit }
    t = t + step
  end
  return ticks, step
end

function M.Nearest(xs, x)
  local n = #xs
  if n == 0 then
    return nil
  end
  local lo, hi = 1, n
  while lo < hi do
    local mid = floor((lo + hi) / 2)
    if xs[mid] < x then
      lo = mid + 1
    else
      hi = mid
    end
  end
  if lo > 1 and abs(xs[lo - 1] - x) <= abs(xs[lo] - x) then
    return lo - 1
  end
  return lo
end

-- Largest-Triangle-Three-Buckets downsampling: returns indices to keep (always first and last).
function M.LTTB(xs, ys, threshold)
  local n = #xs
  if threshold >= n or threshold < 3 then
    local all = {}
    for i = 1, n do
      all[i] = i
    end
    return all
  end
  local out = { 1 }
  local every = (n - 2) / (threshold - 2)
  local a = 1
  for i = 0, threshold - 3 do
    local avgStart = floor((i + 1) * every) + 2
    local avgEnd = min(floor((i + 2) * every) + 2, n + 1)
    local ax, ay, count = 0, 0, 0
    for j = avgStart, avgEnd - 1 do
      ax, ay, count = ax + xs[j], ay + ys[j], count + 1
    end
    if count > 0 then
      ax, ay = ax / count, ay / count
    else
      ax, ay = xs[n], ys[n]
    end
    local rangeStart = floor(i * every) + 2
    local rangeEnd = floor((i + 1) * every) + 2
    local best, bestArea = rangeStart, -1
    for j = rangeStart, min(rangeEnd - 1, n - 1) do
      local area = abs((xs[a] - ax) * (ys[j] - ys[a]) - (xs[a] - xs[j]) * (ay - ys[a]))
      if area > bestArea then
        best, bestArea = j, area
      end
    end
    out[#out + 1] = best
    a = best
  end
  out[#out + 1] = n
  return out
end

-- zoom [from, to] by factor (< 1 zooms in) around anchor, clamped to [limitFrom, limitTo], span >= minSpan
function M.Zoom(from, to, anchor, factor, limitFrom, limitTo, minSpan)
  local span = (to - from) * factor
  span = max(span, minSpan or 0)
  span = min(span, limitTo - limitFrom)
  local frac = (to > from) and (anchor - from) / (to - from) or 0.5
  local a = anchor - frac * span
  local b = a + span
  if a < limitFrom then
    a, b = limitFrom, limitFrom + span
  end
  if b > limitTo then
    a, b = limitTo - span, limitTo
  end
  return a, b
end

function M.Pan(from, to, delta, limitFrom, limitTo)
  local span = to - from
  local a = min(max(from + delta, limitFrom), limitTo - span)
  return a, a + span
end

-- y extent of points with x in [x0, x1]; pad is a fraction of the range added on both sides
function M.Extent(xs, ys, x0, x1, pad)
  local lo, hi = huge, -huge
  for i = 1, #xs do
    local x = xs[i]
    if x >= x0 and x <= x1 then
      local y = ys[i]
      if y < lo then
        lo = y
      end
      if y > hi then
        hi = y
      end
    end
  end
  if lo == huge then
    return nil, nil
  end
  local range = hi - lo
  if range == 0 then
    range = abs(hi) > 0 and abs(hi) or 1
  end
  return lo - range * (pad or 0), hi + range * (pad or 0)
end

---------------------------------------------------------------------------------------------------------------------
-- Rendering (WoW only)

local Chart = {}
Chart.__index = Chart
lib.ChartMixin = Chart

-- The library ships media/Line.tga (soft alpha edges = antialiased lines). It may be embedded in any addon, so find
-- its folder from the load stack. Without it, lines fall back to solid (aliased) colour textures.
local LINE_TEXTURE
do
  local stack = debugstack and debugstack(1, 2, 0) or ""
  local dir = stack:match("(Interface[\\/][Aa]dd[Oo]ns[\\/].-)[\\/]LibAMEChart%-1%.0%.lua")
  if dir then
    LINE_TEXTURE = dir:gsub("/", "\\") .. "\\media\\Line"
  end
end
lib.LINE_TEXTURE = LINE_TEXTURE

local DEFAULTS = {
  lineTexture = LINE_TEXTURE, -- false for solid lines
  lineSoftness = 2, -- soft lines are drawn this much thicker so the solid core keeps the requested width
  upColor = { 0.3, 0.85, 0.45, 1 },
  downColor = { 1, 0.38, 0.35, 1 },
  padding = { left = 8, right = 64, top = 8, bottom = 18 }, -- right side holds the y-axis labels
  paneGap = 6,
  gridColor = { 1, 1, 1, 0.06 },
  axisTextColor = { 0.75, 0.75, 0.75, 1 },
  crosshairColor = { 1, 1, 1, 0.35 },
  lineWidth = 2,
  areaAlpha = 0.18,
  pixelsPerPoint = 2,
  targetYTicks = 4,
  targetXTicks = 6,
  minSpan = 2 * 3600,
  font = "GameFontHighlightSmall",
}

local function pool(chart, kind)
  local p = chart.pools[kind]
  if not p then
    p = { used = 0, items = {} }
    chart.pools[kind] = p
  end
  p.used = p.used + 1
  local r = p.items[p.used]
  if not r then
    if kind == "line" then
      r = chart.canvas:CreateLine(nil, "ARTWORK")
    elseif kind == "text" then
      r = chart.canvas:CreateFontString(nil, "OVERLAY", chart.opts.font)
    elseif kind == "fill" then
      r = chart.canvas:CreateTexture(nil, "BORDER")
    else
      r = chart.canvas:CreateTexture(nil, "BACKGROUND")
    end
    p.items[p.used] = r
  elseif r.SetVertexOffset and kind == "fill" then
    -- area fills bend their top corners into trapezoids; a reused texture must start rectangular again
    for corner = 1, 4 do
      r:SetVertexOffset(corner, 0, 0)
    end
  end
  r:Show()
  return r
end

local function releaseAll(chart)
  for _, p in pairs(chart.pools) do
    for i = 1, #p.items do
      p.items[i]:Hide()
      if p.items[i].ClearAllPoints then
        p.items[i]:ClearAllPoints()
      end
    end
    p.used = 0
  end
end

local function copyDefaults(opts)
  local o = {}
  for k, v in pairs(DEFAULTS) do
    o[k] = v
  end
  for k, v in pairs(opts or {}) do
    o[k] = v
  end
  o.panes = o.panes or { { axis = "default", weight = 1 } }
  return o
end

function lib:New(parent, opts)
  local frame = CreateFrame("Button", nil, parent)
  local chart = setmetatable({
    frame = frame,
    opts = copyDefaults(opts),
    series = {},
    order = {},
    pools = {},
    formatters = {},
    range = nil, -- user/zoom range { from, to }
    callbacks = nil,
  }, Chart)
  if LibStub("CallbackHandler-1.0", true) then
    chart.callbacks = LibStub("CallbackHandler-1.0"):New(chart)
  end
  chart.canvas = CreateFrame("Frame", nil, frame)
  chart.canvas:SetAllPoints(frame)
  chart:SetupInteraction()
  frame:SetScript("OnSizeChanged", function()
    chart:Refresh()
  end)
  return chart
end

function Chart:SetSeries(id, s)
  if not self.series[id] then
    self.order[#self.order + 1] = id
  end
  s.axis = s.axis or self.opts.panes[1].axis
  s.kind = s.kind or "line"
  s.color = s.color or { 0.3, 0.7, 1, 1 }
  if s.kind == "candles" then
    -- candles: xs plus open/high/low/close arrays; hover and extent helpers read close as the series value
    assert(s.open and s.high and s.low and s.close, "candles need open, high, low and close")
    s.ys = s.ys or s.close
  end
  self.series[id] = s
  self:Refresh()
end

function Chart:ClearSeries()
  self.series, self.order = {}, {}
  self:Refresh()
end

function Chart:SetAxisFormatter(axis, fn)
  self.formatters[axis] = fn
  self:Refresh()
end

function Chart:SetTimeFormatter(fn)
  self.timeFormatter = fn
  self:Refresh()
end

function Chart:SetHoverFormatter(fn)
  self.hoverFormatter = fn
end

function Chart:SetMessage(text)
  if not self.message then
    self.message = self.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.message:SetPoint("CENTER")
  end
  self.message:SetText(text or "")
  self.message:SetShown(text ~= nil)
end

-- full data extent across all series
function Chart:DataExtent()
  local lo, hi = huge, -huge
  for _, s in pairs(self.series) do
    local xs = s.xs
    if xs and #xs > 0 then
      lo, hi = min(lo, xs[1]), max(hi, xs[#xs])
    end
  end
  if lo == huge then
    return nil
  end
  if hi == lo then
    hi = lo + DAY
    lo = lo - DAY
  end
  return lo, hi
end

function Chart:SetXRange(from, to)
  self.range = from and { from, to } or nil
  self:Refresh()
end

function Chart:GetXRange()
  local lo, hi = self:DataExtent()
  if not lo then
    return nil
  end
  if self.range then
    return max(lo, self.range[1]), min(hi, self.range[2])
  end
  return lo, hi
end

-- pane rectangles in canvas coordinates (origin bottom-left)
function Chart:Layout()
  local o = self.opts
  local w, h = self.frame:GetWidth(), self.frame:GetHeight()
  local plotW = max(1, w - o.padding.left - o.padding.right)
  local plotH = max(1, h - o.padding.top - o.padding.bottom)
  local totalWeight = 0
  for _, p in ipairs(o.panes) do
    totalWeight = totalWeight + (p.weight or 1)
  end
  local gaps = o.paneGap * (#o.panes - 1)
  local avail = max(1, plotH - gaps)
  local panes = {}
  local top = h - o.padding.top
  for _, p in ipairs(o.panes) do
    local ph = avail * (p.weight or 1) / totalWeight
    panes[p.axis] = { x = o.padding.left, y = top - ph, w = plotW, h = ph }
    top = top - ph - o.paneGap
  end
  return panes, plotW
end

local function colorOf(c, alpha)
  return c[1], c[2], c[3], alpha or c[4] or 1
end

function Chart:Refresh()
  if not self.frame:IsVisible() and not self.forceRender then
    self.dirty = true
    return
  end
  self.dirty = false
  releaseAll(self)
  local from, to = self:GetXRange()
  if not from then
    return
  end
  local o = self.opts
  local panes, plotW = self:Layout()
  self.view = { from = from, to = to, panes = panes, plotW = plotW }
  local function sx(x)
    return o.padding.left + (x - from) / (to - from) * plotW
  end
  self.view.sx = sx

  -- y extents per axis (bars start at zero)
  local extents = {}
  for _, id in ipairs(self.order) do
    local s = self.series[id]
    if s.xs and #s.xs > 0 then
      local lo, hi
      if s.kind == "candles" then
        local l1, h1 = M.Extent(s.xs, s.low, from, to, 0.08)
        local l2, h2 = M.Extent(s.xs, s.high, from, to, 0.08)
        if l1 and l2 then
          lo, hi = min(l1, l2), max(h1, h2)
        end
      else
        lo, hi = M.Extent(s.xs, s.ys, from, to, s.kind == "bars" and 0 or 0.08)
      end
      if lo then
        if s.kind == "bars" then
          lo = 0
        end
        local e = extents[s.axis]
        if not e then
          extents[s.axis] = { lo, hi }
        else
          e[1], e[2] = min(e[1], lo), max(e[2], hi)
        end
      end
    end
  end
  self.view.extents = extents

  -- grid + y labels
  for axis, pane in pairs(panes) do
    local e = extents[axis]
    if e then
      local ticks = M.NiceTicks(e[1], e[2], pane.h < 80 and 2 or o.targetYTicks)
      local fmt = self.formatters[axis] or tostring
      for _, v in ipairs(ticks) do
        local y = pane.y + (v - e[1]) / (e[2] - e[1]) * pane.h
        if y >= pane.y and y <= pane.y + pane.h then
          local g = pool(self, "grid")
          g:SetColorTexture(colorOf(o.gridColor))
          g:SetPoint("BOTTOMLEFT", self.canvas, "BOTTOMLEFT", pane.x, y)
          g:SetSize(pane.w, 1)
          local t = pool(self, "text")
          t:SetText(fmt(v))
          t:SetTextColor(colorOf(o.axisTextColor))
          t:SetPoint("LEFT", self.canvas, "BOTTOMLEFT", pane.x + pane.w + 4, y)
        end
      end
    end
  end

  -- x labels (under the last pane)
  local lastPane = panes[o.panes[#o.panes].axis]
  local tfmt = self.timeFormatter or function(t, unit)
    return date(unit == "hour" and "%H:%M" or "%b %d", t)
  end
  for _, tick in ipairs((M.TimeTicks(from, to, o.targetXTicks))) do
    local x = sx(tick.t)
    local t = pool(self, "text")
    t:SetText(tfmt(tick.t, tick.unit))
    t:SetTextColor(colorOf(o.axisTextColor))
    t:SetPoint("TOP", self.canvas, "BOTTOMLEFT", x, lastPane.y - 3)
    for _, pane in pairs(panes) do
      local g = pool(self, "grid")
      g:SetColorTexture(colorOf(o.gridColor))
      g:SetPoint("BOTTOMLEFT", self.canvas, "BOTTOMLEFT", x, pane.y)
      g:SetSize(1, pane.h)
    end
  end

  -- series
  local maxPoints = max(3, floor(plotW / o.pixelsPerPoint))
  for _, id in ipairs(self.order) do
    local s = self.series[id]
    local pane, e = panes[s.axis], extents[s.axis]
    if pane and e and s.xs and #s.xs > 0 then
      self:DrawSeries(s, pane, e, from, to, sx, maxPoints)
    end
  end
  self:UpdateHover()
end

function Chart:DrawSeries(s, pane, e, from, to, sx, maxPoints)
  local o = self.opts
  local function sy(y)
    return pane.y + (y - e[1]) / (e[2] - e[1]) * pane.h
  end
  if s.kind == "candles" then
    self:DrawCandles(s, pane, from, to, sx, sy)
    return
  end
  -- visible slice (+1 point either side so lines reach the edges)
  local xs, ys = s.xs, s.ys
  local first, last = 1, #xs
  while first < last and xs[first + 1] < from do
    first = first + 1
  end
  while last > first and xs[last - 1] > to do
    last = last - 1
  end
  local vx, vy = {}, {}
  for i = first, last do
    vx[#vx + 1], vy[#vy + 1] = xs[i], ys[i]
  end
  local keep = M.LTTB(vx, vy, maxPoints)
  local px, py = {}, {}
  local left, right = pane.x, pane.x + pane.w
  for k, i in ipairs(keep) do
    px[k], py[k] = min(max(sx(vx[i]), left), right), sy(vy[i])
  end

  local r, g, b, a = colorOf(s.color)
  if s.kind == "bars" then
    local bw = max(1, min(12, pane.w / max(1, #px) * 0.7))
    for k = 1, #px do
      local t = pool(self, "fill")
      t:SetColorTexture(r, g, b, (a or 1) * 0.7)
      t:SetPoint("BOTTOM", self.canvas, "BOTTOMLEFT", px[k], pane.y)
      t:SetSize(bw, max(1, py[k] - pane.y))
    end
    return
  end

  if s.kind == "area" then
    for k = 1, #px - 1 do
      local x1, x2, y1, y2 = px[k], px[k + 1], py[k], py[k + 1]
      if x2 > x1 then
        local t = pool(self, "fill")
        t:SetColorTexture(r, g, b, o.areaAlpha)
        local top = max(y1, y2)
        t:SetPoint("BOTTOMLEFT", self.canvas, "BOTTOMLEFT", x1, pane.y)
        t:SetSize(x2 - x1, max(1, top - pane.y))
        if t.SetVertexOffset then
          -- trapezoid: pull the lower top corner down (1 = UPPER_LEFT, 3 = UPPER_RIGHT)
          t:SetVertexOffset(1, 0, y1 < top and -(top - y1) or 0)
          t:SetVertexOffset(3, 0, y2 < top and -(top - y2) or 0)
        end
      end
    end
  end

  local width = s.width or o.lineWidth
  for k = 1, #px - 1 do
    local line = pool(self, "line")
    if o.lineTexture then
      line:SetTexture(o.lineTexture)
      line:SetVertexColor(r, g, b, a or 1)
      line:SetThickness(width * o.lineSoftness)
    else
      line:SetColorTexture(r, g, b, a or 1)
      line:SetThickness(width)
    end
    line:SetStartPoint("BOTTOMLEFT", self.canvas, px[k], py[k])
    line:SetEndPoint("BOTTOMLEFT", self.canvas, px[k + 1], py[k + 1])
  end
  if #px == 1 then
    local dot = pool(self, "fill")
    dot:SetColorTexture(r, g, b, a or 1)
    dot:SetPoint("CENTER", self.canvas, "BOTTOMLEFT", px[1], py[1])
    dot:SetSize(5, 5)
  end
end

-- Candlesticks: a 1px wick from low to high and a body from open to close, coloured by direction. The caller decides
-- the candle period (s.period, in x units, sets the body width; otherwise the spacing of visible candles does).
function Chart:DrawCandles(s, pane, from, to, sx, sy)
  local o = self.opts
  local xs = s.xs
  local visible = {}
  for i = 1, #xs do
    if xs[i] >= from and xs[i] <= to then
      visible[#visible + 1] = i
    end
  end
  if #visible == 0 then
    return
  end
  local slot = s.period and (s.period / (to - from) * pane.w) or (pane.w / #visible)
  local bw = max(1, min(18, floor(slot * 0.7)))
  local left, right = pane.x, pane.x + pane.w
  for _, i in ipairs(visible) do
    local x = sx(xs[i])
    if x >= left and x <= right then
      local op, cl = s.open[i], s.close[i]
      local up = cl >= op
      local r, g, b, a = colorOf(up and (s.upColor or o.upColor) or (s.downColor or o.downColor))
      local wick = pool(self, "fill")
      wick:SetColorTexture(r, g, b, (a or 1) * 0.8)
      local yl, yh = sy(s.low[i]), sy(s.high[i])
      wick:SetPoint("BOTTOM", self.canvas, "BOTTOMLEFT", floor(x) + 0.5, yl)
      wick:SetSize(1, max(1, yh - yl))
      local body = pool(self, "fill")
      body:SetColorTexture(r, g, b, a or 1)
      local y1, y2 = sy(min(op, cl)), sy(max(op, cl))
      body:SetPoint("BOTTOM", self.canvas, "BOTTOMLEFT", floor(x) + 0.5, y1)
      body:SetSize(bw, max(1, y2 - y1))
    end
  end
end

---------------------------------------------------------------------------------------------------------------------
-- interaction: hover crosshair, wheel zoom, drag pan, double-click reset

function Chart:CursorX()
  local scale = self.frame:GetEffectiveScale()
  local cx = GetCursorPosition() / scale
  return cx - self.frame:GetLeft()
end

function Chart:XAt(px)
  local v = self.view
  if not v then
    return nil
  end
  return v.from + (px - self.opts.padding.left) / v.plotW * (v.to - v.from)
end

function Chart:SetupInteraction()
  local f = self.frame
  f:EnableMouse(true)
  f:EnableMouseWheel(true)
  f:RegisterForClicks("LeftButtonUp")

  self.cross = self.canvas:CreateTexture(nil, "OVERLAY")
  self.cross:SetColorTexture(colorOf(self.opts.crosshairColor))
  self.cross:Hide()
  self.dots = {}
  self.label = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
  if self.label.SetBackdrop then
    self.label:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8x8",
      edgeFile = "Interface\\Buttons\\WHITE8x8",
      edgeSize = 1,
    })
    self.label:SetBackdropColor(0.05, 0.05, 0.07, 0.92)
    self.label:SetBackdropBorderColor(1, 1, 1, 0.15)
  end
  self.label:SetFrameLevel(f:GetFrameLevel() + 5)
  self.label.text = self.label:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  self.label.text:SetPoint("TOPLEFT", 6, -5)
  self.label.text:SetJustifyH("LEFT")
  self.label:Hide()

  f:SetScript("OnEnter", function()
    self.hovering = true
  end)
  f:SetScript("OnLeave", function()
    self.hovering = false
    self.dragging = nil
    self:UpdateHover()
  end)
  f:SetScript("OnMouseWheel", function(_, delta)
    local lo, hi = self:DataExtent()
    local from, to = self:GetXRange()
    if not lo then
      return
    end
    local anchor = self:XAt(self:CursorX()) or (from + to) / 2
    local a, b = M.Zoom(from, to, anchor, delta > 0 and 0.8 or 1.25, lo, hi, self.opts.minSpan)
    self:SetUserRange(a, b)
  end)
  f:SetScript("OnMouseDown", function()
    local from, to = self:GetXRange()
    if from then
      self.dragging = { px = self:CursorX(), from = from, to = to }
    end
  end)
  f:SetScript("OnMouseUp", function()
    self.dragging = nil
  end)
  f:SetScript("OnDoubleClick", function()
    self:SetUserRange(nil)
  end)
  f:SetScript("OnShow", function()
    if self.dirty then
      self:Refresh()
    end
  end)
  f:SetScript("OnUpdate", function()
    if self.dragging then
      local d = self.dragging
      local lo, hi = self:DataExtent()
      local v = self.view
      if lo and v then
        local dx = (self:CursorX() - d.px) / v.plotW * (d.to - d.from)
        local a, b = M.Pan(d.from, d.to, -dx, lo, hi)
        if not self.range or abs(a - self.range[1]) > 1 then
          self:SetUserRange(a, b)
        end
      end
    end
    if self.hovering then
      self:UpdateHover()
    end
  end)
end

function Chart:SetUserRange(a, b)
  self.range = a and { a, b } or nil
  self:Refresh()
  if self.callbacks then
    local from, to = self:GetXRange()
    self.callbacks:Fire("RangeChanged", self, from, to)
  end
end

function Chart:UpdateHover()
  local v = self.view
  if not (self.hovering and v) then
    self.cross:Hide()
    self.label:Hide()
    for _, d in pairs(self.dots) do
      d:Hide()
    end
    return
  end
  local px = self:CursorX()
  local x = self:XAt(px)
  local rows, snapX = {}, nil
  for _, id in ipairs(self.order) do
    local s = self.series[id]
    local i = s.xs and M.Nearest(s.xs, x)
    if i then
      rows[id] = { x = s.xs[i], y = s.ys[i], index = i }
      if not snapX or abs(s.xs[i] - x) < abs(snapX - x) then
        snapX = s.xs[i]
      end
    end
  end
  if not snapX then
    return
  end
  local cx = v.sx(snapX)
  local top, bottom = -huge, huge
  for _, pane in pairs(v.panes) do
    top, bottom = max(top, pane.y + pane.h), min(bottom, pane.y)
  end
  self.cross:ClearAllPoints()
  self.cross:SetPoint("BOTTOMLEFT", self.canvas, "BOTTOMLEFT", cx, bottom)
  self.cross:SetSize(1, top - bottom)
  self.cross:Show()

  for id, row in pairs(rows) do
    local s = self.series[id]
    local pane, e = v.panes[s.axis], v.extents[s.axis]
    local dot = self.dots[id]
    if not dot then
      dot = self.canvas:CreateTexture(nil, "OVERLAY")
      dot:SetTexture("Interface\\COMMON\\Indicator-Gray")
      self.dots[id] = dot
    end
    if pane and e and s.kind ~= "bars" and row.x == snapX then
      dot:SetVertexColor(colorOf(s.color))
      dot:ClearAllPoints()
      dot:SetPoint("CENTER", self.canvas, "BOTTOMLEFT", cx, pane.y + (row.y - e[1]) / (e[2] - e[1]) * pane.h)
      dot:SetSize(10, 10)
      dot:Show()
    else
      dot:Hide()
    end
  end

  local lines = self.hoverFormatter and self.hoverFormatter(self, snapX, rows)
  if lines and #lines > 0 then
    self.label.text:SetText(table.concat(lines, "\n"))
    local w = self.label.text:GetStringWidth() + 12
    local h = self.label.text:GetStringHeight() + 10
    self.label:SetSize(w, h)
    self.label:ClearAllPoints()
    local side = cx + w + 16 > self.frame:GetWidth() and -(w + 12) or 12
    self.label:SetPoint("TOPLEFT", self.frame, "BOTTOMLEFT", cx + side, top)
    self.label:Show()
  else
    self.label:Hide()
  end
end
