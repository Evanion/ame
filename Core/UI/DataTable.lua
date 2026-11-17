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
--     sort = { key = "score", ascending = false },  -- current sort (arrow in the header)
--     onSort = function(key) end,                   -- header clicked; owner re-sorts and calls SetData
--     localSort = true,                             -- or let the table sort by d[key]
--     offset = { get = fn, set = fn },              -- optional: owner keeps the scroll position
--     onClick = function(d, button) end, tooltip = function(tip, d) end,
--   })
--   t:SetData(list); t:Render()
local _, ns = ...

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

-- the data key a column sorts by (false: not sortable)
local function sortKey(col)
  if col.sortKey == false then
    return nil
  end
  if type(col.sortKey) == "function" then
    return col.sortKey()
  end
  return col.sortKey or col.key
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
    h:SetSize(col.width, 18)
    h:SetPoint("TOPLEFT", x, 0)
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
        t:Render()
      end
    end)
    h.col = col
    x = x + col.width + GAP
    t.headers[#t.headers + 1] = h
  end
  t.width = x

  -- rows
  for r = 1, rowsN do
    local row = CreateFrame("Button", nil, frame)
    row:SetSize(x, rowH)
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
    local cx = 0
    for c, col in ipairs(opts.columns) do
      local left = col.item or col.align == "LEFT"
      local fs = W.Text(row, "GameFontHighlightSmall", left and "LEFT" or "RIGHT")
      fs:SetWordWrap(false)
      if col.item then
        local nameX = opts.star and NAME_X or (ICON_W + 4)
        local trailing = opts.confidence and 22 or 0
        fs:SetSize(col.width - nameX - trailing, rowH)
        fs:SetPoint("LEFT", cx + nameX, 0)
        if opts.star then
          row.star = CreateFrame("Button", nil, row)
          row.star:SetSize(STAR_W, STAR_W)
          row.star:SetPoint("LEFT", cx, 0)
          row.star.tex = row.star:CreateTexture(nil, "ARTWORK")
          row.star.tex:SetAllPoints()
          W.SetStar(row.star.tex, false)
          row.star:SetScript("OnEnter", function(self)
            W.SetStar(self.tex, self.watched, true)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.watched and "On a watchlist - click to change" or "Add to a watchlist", 1, 1, 1)
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
        row.icon:SetPoint("LEFT", cx + (opts.star and STAR_W + 2 or 0), 0)
        if opts.confidence then
          row.conf = W.Text(row, "GameFontHighlightSmall", "RIGHT")
          row.conf:SetSize(20, rowH)
          row.conf:SetPoint("LEFT", cx + col.width - 20, 0)
        end
      else
        fs:SetSize(col.width, rowH)
        fs:SetPoint("LEFT", cx, 0)
      end
      row.cells[c] = fs
      cx = cx + col.width + GAP
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
  bar:SetPoint("TOPLEFT", x - 2 + (opts.action and ((opts.action.width or 56) + 8) or 0), -20)
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
  return t
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
  self:SetOffset(math.max(0, self:Offset() - delta * 3))
  self:Render()
end

function DataTable:SetData(list)
  self.data = list or {}
  if self.opts.localSort and self.sort.key then
    local key, asc = self.sort.key, self.sort.ascending
    table.sort(self.data, function(a, b)
      local x, y = a[key], b[key]
      if x == y or x == nil or y == nil then
        if x == nil and y ~= nil then
          return false
        elseif y == nil and x ~= nil then
          return true
        end
        return (a.itemID or 0) < (b.itemID or 0)
      end
      if asc then
        return x < y
      end
      return x > y
    end)
  end
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
  local opts = self.opts
  for _, h in ipairs(self.headers) do
    local key = sortKey(h.col)
    local arrow = (key and self.sort.key == key) and (self.sort.ascending and W.ARROW_UP or W.ARROW_DOWN) or ""
    h.text:SetText(label(h.col) .. arrow)
  end
  local list = self.data
  local n = #self.rows
  local maxOffset = math.max(0, #list - n)
  local offset = math.min(self:Offset(), maxOffset)
  self:SetOffset(offset)
  self.syncing = true
  self.bar:SetMinMaxValues(0, maxOffset)
  self.bar:SetValue(offset)
  self.bar:SetShown(maxOffset > 0)
  self.syncing = false

  for r, row in ipairs(self.rows) do
    local d = list[offset + r]
    row.data = d
    row.itemID = d and opts.itemID and opts.itemID(d) or nil
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
          val = itemCell(self, row, col, d, row.itemID)
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
