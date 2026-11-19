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
--     selected = function(d) return bool end,       -- highlight the selected row
--     rowAlpha = function(d) return 0.5 end,        -- fade rows (stale data)
--     status = true,                                -- t.status: the status line at the bottom of parent
--   })
--   t:SetData(list); t:Render()
--   t:SetMessage("Loading...")                      -- centred over the rows (empty / loading); nil hides it
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
    return v and ("%.1f%%"):format(v * 100) or W.NONE
  end,
  rate = function(v)
    return W.Rate(v)
  end,
  count = function(v)
    return W.Count(v)
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
  t.rowH = rowH
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetPoint("TOPLEFT", 0, top)
  frame:SetPoint("RIGHT", 0, 0)
  if opts.fill then
    -- fills the parent down to its bottom (minus a status line): as many rows as fit, more as the window grows
    frame:SetPoint("BOTTOM", 0, opts.bottom or (opts.status and 20 or 0))
  else
    frame:SetHeight(20 + rowsN * rowH)
  end
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

  -- rows (made on demand: a table that fills its parent gets more as the window grows)
  function t:MakeRow(r)
    local row = CreateFrame("Button", nil, frame)
    row:SetHeight(rowH)
    row:SetPoint("TOPLEFT", 0, -20 - (r - 1) * rowH)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, r % 2 == 0 and 0.025 or 0)
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints()
    W.Fill(row.hl, W.COLORS.rowHover)
    if opts.selected then -- the selected row (e.g. the route in the sidebar)
      row.selTex = row:CreateTexture(nil, "BACKGROUND")
      row.selTex:SetAllPoints()
      W.Fill(row.selTex, W.COLORS.rowSelected)
      row.selTex:Hide()
    end
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
          end)
          row.star:SetScript("OnLeave", function(self)
            W.SetStar(self.tex, self.watched)
          end)
          W.Tooltip(row.star, function(tip, self)
            W.TipText(tip, self.watched and L["On a watchlist - click to change"] or L["Add to a watchlist"])
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
          row.conf = W.Text(row, "GameFontHighlightSmall", "LEFT")
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
    W.Tooltip(row, function(tip, self)
      if not self.data then
        return false
      end
      if self.itemID then
        W.SetItemTip(tip, self.itemID)
      end
      if opts.tooltip then
        opts.tooltip(tip, self.data)
      end
    end)
    t.rows[r] = row
    return row
  end
  for r = 1, rowsN do
    t:MakeRow(r)
  end
  t.visible = rowsN

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
  frame:SetScript("OnShow", function()
    if t.data then
      t:Render()
    end
  end)
  frame:SetScript("OnSizeChanged", function(_, width, height)
    if opts.fill then
      t:Fit(height)
    end
    t:Layout(width)
  end)
  t:Layout(frame:GetWidth())
  if opts.status then
    t.status = W.StatusLine(parent)
  end
  return t
end

-- A filling table's height changed: use as many rows as fit (making new ones as needed), hide the rest.
function DataTable:Fit(height)
  if type(height) ~= "number" or height <= 0 then
    return
  end
  self.fitHeight = height
  local n = math.max(1, math.floor((height - 20) / self.rowH))
  for r = #self.rows + 1, n do
    self:MakeRow(r)
  end
  self.visible = n
  for r, row in ipairs(self.rows) do
    if r > n then
      row:Hide()
    end
  end
  self.bar:SetHeight(n * self.rowH)
  self.layoutWidth = nil -- new rows need their cells placed
  if self.source then
    self:Render()
  end
end

-- a message centred over the rows (nothing to show, loading); nil hides it
function DataTable:SetMessage(text)
  if not self.message then
    self.message = W.Text(self.frame, "GameFontDisableSmall", "CENTER")
    self.message:SetPoint("LEFT", 20, -10) -- below the header
    self.message:SetPoint("RIGHT", -20, -10)
  end
  self.message:SetText(text or "")
  self.message:SetShown(text ~= nil)
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
  local avail = width - DataTable.BAR_SPACE - actionW
  -- Too narrow? First the flexible column gives up to 40% of its width (names truncate), then columns with a `drop`
  -- rank are hidden, highest rank first, until the rest fits.
  local flexCut = math.floor(opts.columns[flex].width * 0.4)
  local total = self.width - GAP
  local hidden, order = {}, {}
  local userHidden = self.userHidden or {}
  for c, col in ipairs(opts.columns) do
    if userHidden[col.key] and not col.item then -- switched off in the column chooser
      hidden[c] = true
      total = total - col.width - GAP
    elseif col.drop then
      order[#order + 1] = c
    end
  end
  table.sort(order, function(a, b)
    return opts.columns[a].drop > opts.columns[b].drop
  end)
  for _, c in ipairs(order) do
    if total - flexCut <= avail then
      break
    end
    hidden[c] = true
    total = total - opts.columns[c].width - GAP
  end
  self.hiddenColumns = hidden
  local rowW = math.max(total - flexCut, avail)
  local extra = rowW - total
  local widths, xs, x = {}, {}, 0
  for c, col in ipairs(opts.columns) do
    widths[c] = hidden[c] and 0 or col.width + (c == flex and extra or 0)
    xs[c] = x
    if not hidden[c] then
      x = x + widths[c] + GAP
    end
  end
  for c, h in ipairs(self.headers) do
    h:SetShown(not hidden[c])
    h:SetWidth(math.max(1, widths[c]))
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", xs[c], 0)
  end
  for _, row in ipairs(self.rows) do
    row:SetWidth(rowW)
    for c, col in ipairs(opts.columns) do
      local fs, cx = row.cells[c], xs[c]
      fs:ClearAllPoints()
      fs:SetShown(not hidden[c])
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
  local maxOffset = math.max(0, #(self.data or {}) - self.visible)
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
  local fallback = col.fallback and col.fallback(d) or (itemID and ("item:" .. itemID)) or ""
  return W.QualityText(quality, name or fallback)
end

function DataTable:Render()
  -- the size can change while the table is hidden (another tab or mode, the window closed) without a size event
  -- reaching it: check its height and width on every draw
  if self.opts.fill then
    local height = self.frame:GetHeight()
    if type(height) == "number" and height > 0 and height ~= self.fitHeight then
      self:Fit(height) -- draws again with the new row count
      return
    end
  end
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
  local n = self.visible
  local maxOffset = math.max(0, #list - n)
  -- show what fits, but keep the remembered position: a list that's briefly shorter (reloading, switching tabs)
  -- must not lose where you were scrolled to
  local offset = math.min(self:Offset(), maxOffset)
  self.syncing = true
  self.bar:SetMinMaxValues(0, maxOffset)
  self.bar:SetValue(offset)
  self.bar:SetShown(maxOffset > 0)
  self.syncing = false

  for r = 1, n do
    local row = self.rows[r]
    local d = list[offset + r]
    row.data = d
    row.itemID = d and opts.itemID and opts.itemID(d) or false
    row:SetShown(d ~= nil)
    row:SetAlpha(d and opts.rowAlpha and opts.rowAlpha(d) or 1)
    if opts.selected then
      row.selTex:SetShown(d ~= nil and opts.selected(d) or false)
    end
    if row.action then
      row.action:SetShown(d ~= nil and (not opts.action.shown or opts.action.shown(d)) or false)
      if d and opts.action.enabled then
        local on = opts.action.enabled(d) and true or false
        row.action:SetEnabled(on)
        row.action:SetAlpha(on and 1 or 0.4)
        row.action.usable = on
      end
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
          val = v ~= nil and tostring(v) or W.NONE
        end
        row.cells[c]:SetText(val or "")
        if col.item and row.conf then -- the confidence bars right after the (possibly cut) name
          local fs = row.cells[c]
          local w = math.min(fs:GetStringWidth() or 0, fs:GetWidth() or 0)
          row.conf:ClearAllPoints()
          row.conf:SetPoint("LEFT", fs, "LEFT", w + 5, 0)
        end
      end
    end
  end
end

-- the first visible index and how many rows fit (for status lines)
function DataTable:Window()
  return self:Offset(), self.visible
end

-- Columns switched off by the user (column chooser): a set of column keys. The item column always stays.
function DataTable:SetUserHidden(keys)
  self.userHidden = keys or {}
  self.layoutWidth = nil
  self:Layout(self.frame:GetWidth())
  if self.data then
    self:Render()
  end
end

-- how many columns are hidden now (switched off, or dropped because the table is narrow)
function DataTable:HiddenCount()
  local n = 0
  for _ in pairs(self.hiddenColumns or {}) do
    n = n + 1
  end
  return n
end

-- text without colour codes, textures or atlases (exports)
function DataTable.Plain(s)
  s = tostring(s or "")
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
  return s
end

-- a number for spreadsheets: gold with 4 decimals (copper exact), no thousands separators
local function gold(copper)
  return copper and ("%.4f"):format(copper / 10000) or ""
end
-- raw values for the formats that would otherwise export as display text
local EXPORT = {
  money = gold,
  count = function(v)
    return v and tostring(math.floor(v + 0.5)) or ""
  end,
  rate = function(v)
    return v and ("%.1f"):format(v) or ""
  end,
  pct = function(v)
    return v and ("%.1f%%"):format(v * 100) or ""
  end,
  plainpct = function(v)
    return v and ("%.1f%%"):format(v * 100) or ""
  end,
}

-- a CSV field: quoted when it holds the separator, a quote or a line break
local function csvField(s)
  if s:find('[,"\n]') then
    return '"' .. s:gsub('"', '""') .. '"'
  end
  return s
end

-- The whole list as text, header first, in the current sort: what's on screen, for copying out (WoW can't write
-- files). Columns you switched off are left out. format: "tabs" (default: pastes into spreadsheet columns) or "csv".
-- Money is gold as a plain number (header marked "(g)"), quantities and rates are plain numbers, so a spreadsheet
-- can sum and sort them. Columns can give their own raw value: col.export(d), or col.money = true for d[col.key].
function DataTable:ExportText(format)
  local opts, plain = self.opts, DataTable.Plain
  -- only columns you switched off are left out; ones dropped for lack of room are exported
  local hidden = {}
  for c, col in ipairs(opts.columns) do
    hidden[c] = (self.userHidden or {})[col.key] and not col.item or nil
  end
  local sep = format == "csv" and "," or "\t"
  local function cell(s)
    s = plain(s)
    if format == "csv" then
      return csvField(s)
    end
    return (s:gsub("[\t\n]", " "))
  end
  local header, lines = {}, {}
  for c, col in ipairs(opts.columns) do
    if not hidden[c] then
      local money = col.money or col.format == "money"
      header[#header + 1] = cell(label(col) .. (money and " (g)" or ""))
    end
  end
  lines[1] = table.concat(header, sep)
  for _, d in ipairs(self.data or {}) do
    local cells = {}
    for c, col in ipairs(opts.columns) do
      if not hidden[c] then
        local val
        if col.item then
          local id = opts.itemID and opts.itemID(d)
          val = (id and ns.ItemCache.Name(id)) or (col.fallback and col.fallback(d)) or (id and ("item:" .. id))
        elseif col.export or col.money then
          local raw
          if col.export then
            raw = col.export(d)
          else
            raw = d[col.key]
          end
          if col.money then
            val = type(raw) == "number" and gold(raw) or ""
          else
            val = raw
          end
        elseif col.format and EXPORT[col.format] then
          val = EXPORT[col.format](d[col.key])
        elseif col.text then
          val = col.text(d, self)
        elseif col.format then
          val = FORMATS[col.format](d[col.key])
        else
          val = d[col.key]
        end
        cells[#cells + 1] = cell(val == nil and "" or tostring(val))
      end
    end
    lines[#lines + 1] = table.concat(cells, sep)
  end
  return table.concat(lines, "\n")
end
