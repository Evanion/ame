-- DataTable: the one list component behind the Market screener, Arbitrage and Portfolio tables. Register columns,
-- feed rows; it handles the header (sort arrows, hover explanations), a fixed pool of rows, wheel scrolling and a
-- scrollbar, optional watchlist star / item icon / confidence bars / action button per row, and item names that
-- fill in by themselves when the client finishes loading them.
--
--   local t = ns.DataTable.New(parent, {
--     columns = {
--       { key = "name", label = "Item", width = 190, item = true },        -- icon + quality-coloured name
--       { key = "market", label = "Market", width = 86, format = "money" },
--       { key = "x", label = function() return "dynamic" end, width = 60, text = function(d) return ... end },
--     },
--     rows = 17, top = -28,                         -- header y inside parent
--     itemID = function(d) return d.itemID end,     -- rows are items (icon, tooltip, click opens the chart)
--     star = true, confidence = function(d) return "high" end,
--     action = { label = "Search", width = 56, shown = function(d) end, onClick = function(d) end },
--     sort = { key = "score", ascending = false },  -- initial / current sort (arrow in the header)
--     onSort = function(key) end,                   -- only when the owner sorts (e.g. sorting tied to filters);
--                                                   -- otherwise the table sorts its rows itself on header clicks
--     offset = { get = fn, set = fn },              -- optional: owner keeps the scroll position
--     onClick = function(d, button) end, tooltip = function(tip, d) end,
--   })
--   t:SetData(list); t:Render()
local _, ns = ...
local L = ns.L

local W = ns.Widgets

local DataTable = {}
DataTable.__index = DataTable
ns.DataTable = DataTable

local GAP = 8
local STAR_W, ICON_W, NAME_X = 16, 18, 40

local FORMATS = {
  money = function(v)
    return W.Money(v, true)
  end,
  pct = function(v)
    return W.Percent(v)
  end,
  plainpct = function(v)
    return v and ("%.1f%%"):format(v * 100) or "|cff777777-|r"
  end,
  rate = function(v)
    return W.Rate(v)
  end,
  signal = function(v)
    return W.Signal(v)
  end,
}

local function label(col)
  return type(col.label) == "function" and col.label() or col.label or ""
end

-- the data key a column sorts by (false: not sortable); item columns sort by item name ("__name")
local function sortKey(col)
  if col.sortKey == false then
    return nil
  end
  if type(col.sortKey) == "function" then
    return col.sortKey()
  end
  return col.sortKey or (col.item and "__name") or col.key
end

function DataTable.New(parent, opts)
  local t = setmetatable({ opts = opts, data = {}, headers = {}, rows = {}, pending = {}, ownOffset = 0 }, DataTable)
  t.sort = opts.sort or {}
  local rowsN, rowH, top = opts.rows or 17, opts.rowHeight or 22, opts.top or 0
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetPoint("TOPLEFT", 0, top)
  frame:SetPoint("RIGHT", 0, 0)
  frame:SetHeight(20 + rowsN * rowH)
  t.frame = frame

  -- header
  local x = 0
  for _, col in ipairs(opts.columns) do
    local h = CreateFrame("Button", nil, frame)
    h:SetHeight(18) -- width and position: t:Layout()
    local left = col.item or col.align == "LEFT"
    h.text = W.Text(h, "GameFontNormalSmall", left and "LEFT" or "RIGHT")
    h.text:SetAllPoints()
    if col.term and ns.Help then
      ns.Help.Explain(h, col.term)
    end
    h:SetScript("OnClick", function()
      local key = sortKey(col)
      if not key then
        return
      end
      if t.sort.key == key then
        t.sort.ascending = not t.sort.ascending
      else
        t.sort.key, t.sort.ascending = key, col.ascendingFirst or false
      end
      if opts.onSort then
        opts.onSort(t.sort.key, t.sort.ascending)
      else
        t:Resort()
        t:Render()
      end
    end)
    h.col = col
    x = x + col.width + GAP
    t.headers[#t.headers + 1] = h
  end
  t.width = x -- the columns' own widths; the table fills its parent and gives the rest to the flexible column

  -- rows
  for r = 1, rowsN do
    local row = CreateFrame("Button", nil, frame)
    row:SetHeight(rowH)
    row:SetPoint("TOPLEFT", 0, -20 - (r - 1) * rowH)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, r % 2 == 0 and 0.025 or 0)
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 1, 1, 0.06)
    row.cells = {}
    row.star, row.icon, row.conf, row.action = false, false, false, false -- optional parts, set below
    for c, col in ipairs(opts.columns) do
      local left = col.item or col.align == "LEFT"
      local fs = W.Text(row, "GameFontHighlightSmall", left and "LEFT" or "RIGHT")
      fs:SetWordWrap(false)
      fs:SetHeight(rowH) -- width and position (and of the star, icon, confidence bars): t:Layout()
      if col.item then
        if opts.star then
          row.star = CreateFrame("Button", nil, row)
          row.star:SetSize(STAR_W, STAR_W)
          row.star.tex = row.star:CreateTexture(nil, "ARTWORK")
          row.star.tex:SetAllPoints()
          W.SetStar(row.star.tex, false)
          row.star:SetScript("OnEnter", function(self)
            W.SetStar(self.tex, self.watched, true)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(
              self.watched and L["On a watchlist - click to change"] or L["Add to a watchlist"],
              1,
              1,
              1
            )
            GameTooltip:Show()
          end)
          row.star:SetScript("OnLeave", function(self)
            W.SetStar(self.tex, self.watched)
            GameTooltip:Hide()
          end)
          row.star:SetScript("OnClick", function(self)
            if row.itemID and ns.UI.StarClicked then
              ns.UI:StarClicked(self, row.itemID)
            end
          end)
        end
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ICON_W, ICON_W)
        if opts.confidence then
          row.conf = W.Text(row, "GameFontHighlightSmall", "RIGHT")
          row.conf:SetSize(20, rowH)
        end
      end
      row.cells[c] = fs
    end
    if opts.action then
      local a = opts.action
      row.action = W.Button(row, a.label, a.width or 56, rowH - 4, function()
        if row.data then
          a.onClick(row.data)
        end
      end)
      row.action:SetPoint("LEFT", row, "RIGHT", 4, 0)
      row.action:Hide()
    end
    row:SetScript("OnClick", function(self, button)
      if not self.data then
        return
      end
      if opts.onClick then
        opts.onClick(self.data, button)
      elseif self.itemID then
        ns.UI:ShowItem(self.itemID)
      end
    end)
    row:SetScript("OnEnter", function(self)
      if not self.data then
        return
      end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if self.itemID then
        GameTooltip:SetItemByID(self.itemID)
      end
      if opts.tooltip then
        opts.tooltip(GameTooltip, self.data)
      end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
    t.rows[r] = row
  end

  -- scrollbar (only shown when there's more than fits)
  local bar = CreateFrame("Slider", nil, frame, "BackdropTemplate")
  bar:SetOrientation("VERTICAL")
  bar:SetPoint("TOPRIGHT", 0, -20) -- inside the table's right edge, never past the window
  bar:SetSize(8, rowsN * rowH)
  W.Skin(bar, W.COLORS.panel)
  bar.thumb = bar:CreateTexture(nil, "OVERLAY")
  bar.thumb:SetColorTexture(1, 1, 1, 0.25)
  bar.thumb:SetSize(8, 40)
  bar:SetThumbTexture(bar.thumb)
  bar:SetMinMaxValues(0, 0)
  bar:SetValueStep(1)
  bar:SetObeyStepOnDrag(true)
  bar:SetScript("OnValueChanged", function(_, value)
    if t.syncing then
      return
    end
    t:SetOffset(math.floor(value + 0.5))
    t:Render()
  end)
  t.bar = bar

  frame:EnableMouseWheel(true)
  frame:SetScript("OnMouseWheel", function(_, delta)
    t:Scroll(delta)
  end)
  frame:SetScript("OnSizeChanged", function(_, width)
    t:Layout(width)
  end)
  t:Layout(frame:GetWidth())
  return t
end

-- the column that takes the width left over: opts.flex (a column key), else the item column, else the first
local function flexIndex(opts)
  for c, col in ipairs(opts.columns) do
    if opts.flex and col.key == opts.flex then
      return c
    end
  end
  for c, col in ipairs(opts.columns) do
    if col.item then
      return c
    end
  end
  return 1
end

DataTable.BAR_SPACE = 14 -- scrollbar (8) and a gap before it

-- Fit the columns to the table's width: rows span it up to the action button and scrollbar, and the flexible
-- column grows to fill what the fixed columns leave (and gives up some of its own when the table is too narrow).
function DataTable:Layout(width)
  local opts, rowH = self.opts, self.opts.rowHeight or 22
  if type(width) ~= "number" or width <= 0 then
    return
  end
  self.layoutWidth = width
  local actionW = opts.action and ((opts.action.width or 56) + 8) or 0
  local flex = flexIndex(opts)
  -- when space is short the flexible column gives up to 40% of its width (names truncate) before anything overflows
  local minW = self.width - GAP - math.floor(opts.columns[flex].width * 0.4)
  local rowW = math.max(minW, width - DataTable.BAR_SPACE - actionW)
  local extra = rowW - (self.width - GAP)
  local widths, xs, x = {}, {}, 0
  for c, col in ipairs(opts.columns) do
    widths[c] = col.width + (c == flex and extra or 0)
    xs[c] = x
    x = x + widths[c] + GAP
  end
  for c, h in ipairs(self.headers) do
    h:SetWidth(widths[c])
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", xs[c], 0)
  end
  for _, row in ipairs(self.rows) do
    row:SetWidth(rowW)
    for c, col in ipairs(opts.columns) do
      local fs, cx = row.cells[c], xs[c]
      fs:ClearAllPoints()
      if col.item then
        local nameX = opts.star and NAME_X or (ICON_W + 4)
        local trailing = opts.confidence and 22 or 0
        fs:SetSize(widths[c] - nameX - trailing, rowH)
        fs:SetPoint("LEFT", cx + nameX, 0)
        if row.star then
          row.star:ClearAllPoints()
          row.star:SetPoint("LEFT", cx, 0)
        end
        row.icon:ClearAllPoints()
        row.icon:SetPoint("LEFT", cx + (opts.star and STAR_W + 2 or 0), 0)
        if row.conf then
          row.conf:ClearAllPoints()
          row.conf:SetPoint("LEFT", cx + widths[c] - 20, 0)
        end
      else
        fs:SetSize(widths[c], rowH)
        fs:SetPoint("LEFT", cx, 0)
      end
    end
  end
end

function DataTable:Offset()
  local o = self.opts.offset
  return o and (o.get() or 0) or self.ownOffset
end

function DataTable:SetOffset(n)
  local o = self.opts.offset
  if o then
    o.set(n)
  else
    self.ownOffset = n
  end
end

function DataTable:Scroll(delta)
  local maxOffset = math.max(0, #(self.data or {}) - #self.rows)
  self:SetOffset(math.max(0, math.min(self:Offset(), maxOffset) - delta * 3))
  self:Render()
end

-- Rows to show. Unless the owner sorts (onSort), the table keeps a sorted copy and re-sorts on header clicks.
function DataTable:SetData(list)
  self.source = list or {}
  self:Resort()
end

-- a row's value for a sort key: the item's name for "__name", lower-cased text, numbers as they are
function DataTable:SortValue(d, key)
  local v
  if key == "__name" then
    local id = self.opts.itemID and self.opts.itemID(d)
    v = id and W.ItemInfo(id) or d.name
  else
    v = d[key]
  end
  if type(v) == "string" then
    return v:lower()
  elseif type(v) == "boolean" then
    return v and 1 or 0
  end
  return v
end

function DataTable:Resort()
  local src = self.source or {}
  if self.opts.onSort or not self.sort.key then
    self.data = src
    return
  end
  local data = {}
  for i, d in ipairs(src) do
    data[i] = d
  end
  local key, asc = self.sort.key, self.sort.ascending
  local cache = {}
  local function value(d)
    local v = cache[d]
    if v == nil then
      v = self:SortValue(d, key)
      cache[d] = v == nil and false or v
    end
    return v ~= false and v or nil
  end
  table.sort(data, function(a, b)
    local x, y = value(a), value(b)
    if x == nil or y == nil or type(x) ~= type(y) then
      if x == nil and y ~= nil then
        return false -- empty values last, either direction
      elseif y == nil and x ~= nil then
        return true
      end
      return tostring(a) < tostring(b)
    end
    if x == y then
      return tostring(a) < tostring(b)
    end
    if asc then
      return x < y
    end
    return x > y
  end)
  self.data = data
end

function DataTable:SetShown(shown)
  self.frame:SetShown(shown)
end

-- re-render once the client has loaded an item's name (batched)
function DataTable:RenderWhenLoaded(itemID)
  if self.pending[itemID] then
    return
  end
  self.pending[itemID] = true
  W.OnItemLoaded(itemID, function()
    self.pending[itemID] = nil
    if not self.queued then
      self.queued = true
      C_Timer.After(0.05, function()
        self.queued = false
        self:Render()
      end)
    end
  end)
end

local function itemCell(t, row, col, d, itemID)
  local name, _, quality, icon = W.ItemInfo(itemID or 0)
  if itemID and not name then
    t:RenderWhenLoaded(itemID)
  end
  row.icon:SetTexture(icon or 134400)
  row.icon:SetShown(itemID ~= nil)
  local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
  local fallback = col.fallback and col.fallback(d) or (itemID and ("item:" .. itemID)) or ""
  return (color and color.hex or "|cffffffff") .. (name or fallback) .. "|r"
end

function DataTable:Render()
  local width = self.frame:GetWidth()
  if width ~= self.layoutWidth then -- laid out before the window had a size, or resized since
    self:Layout(width)
  end
  local opts = self.opts
  for _, h in ipairs(self.headers) do
    local key = sortKey(h.col)
    local arrow = (key and self.sort.key == key) and (self.sort.ascending and W.ARROW_UP or W.ARROW_DOWN) or ""
    h.text:SetText(label(h.col) .. arrow)
  end
  local list = self.data
  local n = #self.rows
  local maxOffset = math.max(0, #list - n)
  -- show what fits, but keep the remembered position: a list that's briefly shorter (reloading, switching tabs)
  -- must not lose where you were scrolled to
  local offset = math.min(self:Offset(), maxOffset)
  self.syncing = true
  self.bar:SetMinMaxValues(0, maxOffset)
  self.bar:SetValue(offset)
  self.bar:SetShown(maxOffset > 0)
  self.syncing = false

  for r, row in ipairs(self.rows) do
    local d = list[offset + r]
    row.data = d
    row.itemID = d and opts.itemID and opts.itemID(d) or false
    row:SetShown(d ~= nil)
    if row.action then
      row.action:SetShown(d ~= nil and (not opts.action.shown or opts.action.shown(d)) or false)
    end
    if d then
      if row.star then
        local watched = ns.AME.watch and row.itemID and ns.AME.watch:Watched(row.itemID) or false
        row.star.watched = watched
        W.SetStar(row.star.tex, watched)
      end
      if row.conf then
        row.conf:SetText(W.Confidence(opts.confidence(d)))
      end
      for c, col in ipairs(opts.columns) do
        local val
        if col.item then
          val = itemCell(self, row, col, d, row.itemID or nil)
        elseif col.text then
          val = col.text(d, self)
        elseif col.format then
          val = FORMATS[col.format](d[col.key])
        else
          local v = d[col.key]
          val = v ~= nil and tostring(v) or "|cff777777-|r"
        end
        row.cells[c]:SetText(val or "")
      end
    end
  end
end

-- the first visible index and how many rows fit (for status lines)
function DataTable:Window()
  return self:Offset(), #self.rows
end
