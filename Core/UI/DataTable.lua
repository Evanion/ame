-- DataTable: the one list component behind the Market screener, Arbitrage and Portfolio tables. Register columns,
-- feed rows; it handles the header (sort arrows, hover explanations), a fixed pool of rows, wheel scrolling and a
-- scrollbar, optional watchlist star / item icon / confidence bars / action button per row, and item names that
-- fill in by themselves when the client finishes loading them.
--
--   local t = ns.DataTable.New(parent, {
--     columns = {
--       { key = "name", label = "Item", width = 190, item = true },        -- icon + quality-coloured name
--         (suffix = function(d) return "  x5" end: text after the name)
--       { key = "market", label = "Market", width = 86, format = "money" },
--       { key = "x", label = function() return "dynamic" end, width = 60, text = function(d) return ... end },
--       { key = "made", label = "Makes", width = 150, item = function(d) return d.product end },
--         (a second item in the row: its own icon, hover and modified click; a plain click is the row's)
--       { key = "net", label = "Net", width = 70, format = "signedMoney" },   -- "+1g 20s" / "-35s"
--       { key = "share", label = "Share", width = 110, format = "share", max = 0.4 }, -- bar (full at max) and %
--       { key = "signal", label = "Signal", width = 64, format = "signal" },  -- a SignalBadge (W.SignalBadge)
--       { key = "from", label = "From", width = 80, format = "tag" },   -- a W.Tag: d.from = { text =, kind = "ah" }
--                                                                        -- (or plain text: kind "other")
--       { key = "buy", label = "", width = 50, button = { label = "Buy" or function(d) end,
--           variant = function(d) return "primary" end, onClick = function(d) end, shown = fn, enabled = fn } },
--     },
--     bare = true,                                  -- no header row (small lists in panels)
--     note = "Faded rows...",                       -- a dim wrapped line under the rows (t:SetNote to change it)
--     shiftClick = true,                            -- the owner's onClick uses Shift itself (search the AH) while
--                                                   -- no chat box is open; otherwise a modified click on an item
--                                                   -- row links the item, as a link in chat does
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
  signedMoney = function(v)
    return W.SignedMoney(v)
  end,
  tag = function(v) -- a tag's text (the cell draws a W.Tag)
    return type(v) == "table" and (v.text or "") or v and tostring(v) or ""
  end,
  share = function(v) -- the percent beside the bar
    return v and ("%d%%"):format(math.floor(v * 100 + 0.5)) or W.NONE
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

-- The row's own item (opts.itemID: star, confidence, the row's tooltip) is the column with item = true; a column
-- with item = function(d) shows another item in the row, with its own icon and hover.
local function mainItem(col)
  return col.item == true
end
local function linkItem(col)
  return type(col.item) == "function"
end

-- the data key a column sorts by (false: not sortable); item columns sort by item name ("__name", "__name:<key>")
local function sortKey(col)
  if col.sortKey == false or col.button then
    return nil
  end
  if type(col.sortKey) == "function" then
    return col.sortKey()
  end
  return col.sortKey or (mainItem(col) and "__name") or (linkItem(col) and "__name:" .. col.key) or col.key
end

local SHARE_W = 64 -- a share cell's bar track

-- items, bars and badges read from the left, numbers from the right
local LEFT_FORMATS = { share = true, signal = true, tag = true }
local function leftAligned(col)
  return col.item or col.align == "LEFT" or LEFT_FORMATS[col.format] or false
end

-- a modified click on an item: the game's handling of a link (chat, try on). Shift-click is the owner's while it
-- has a Shift-click of its own (shiftClick) and no chat box is open to take the link.
local function linksItem(opts)
  if not (IsModifiedClick and (IsModifiedClick("CHATLINK") or IsModifiedClick("DRESSUP"))) then
    return false
  end
  if opts.shiftClick and IsModifiedClick("CHATLINK") then
    local chat = _G.ChatEdit_GetActiveWindow and _G.ChatEdit_GetActiveWindow()
    return chat and true or false
  end
  return true
end
DataTable.LinksItem = linksItem

function DataTable.New(parent, opts)
  local t = setmetatable({ opts = opts, data = {}, headers = {}, rows = {}, pending = {}, ownOffset = 0 }, DataTable)
  t.sort = opts.sort or {}
  local rowsN, rowH, top = opts.rows or 17, opts.rowHeight or 22, opts.top or 0
  t.rowH = rowH
  t.headH = opts.bare and 0 or 20 -- a bare table has no header row
  t.rowsN = rowsN
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetPoint("TOPLEFT", 0, top)
  frame:SetPoint("RIGHT", 0, 0)
  if opts.fill then
    -- fills the parent down to its bottom (minus a status line): as many rows as fit, more as the window grows
    frame:SetPoint("BOTTOM", 0, opts.bottom or (opts.status and 20 or 0))
  else
    frame:SetHeight(t.headH + rowsN * rowH)
  end
  t.frame = frame

  -- header
  local x = 0
  for _, col in ipairs(opts.columns) do
    local h = CreateFrame("Button", nil, frame)
    h:SetHeight(18) -- width and position: t:Layout()
    h:SetShown(not opts.bare)
    local left = leftAligned(col)
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
    row:SetPoint("TOPLEFT", 0, -t.headH - (r - 1) * rowH)
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
    row.links, row.shares, row.buttons, row.badges, row.tags = {}, {}, {}, {}, {} -- by column: their parts
    for c, col in ipairs(opts.columns) do
      local left = leftAligned(col)
      local fs = W.Text(row, "GameFontHighlightSmall", left and "LEFT" or "RIGHT")
      fs:SetWordWrap(false)
      fs:SetHeight(rowH) -- width and position (and of the star, icon, confidence bars): t:Layout()
      if linkItem(col) then
        -- another item in the row: its icon, and a region over icon and name for its tooltip and modified click
        local link = CreateFrame("Button", nil, row)
        link:SetHeight(rowH)
        link:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        link.icon = row:CreateTexture(nil, "ARTWORK")
        link.icon:SetSize(ICON_W, ICON_W)
        link.key = false
        link:SetScript("OnClick", function(self, button)
          if self.key and linksItem({}) then
            W.ItemLinkClicked(self.key)
            return
          end
          local click = row:GetScript("OnClick")
          if click then
            click(row, button) -- a plain click is the row's (select it)
          end
        end)
        W.Tooltip(link, function(tip, self)
          if not self.key then
            return false
          end
          W.SetItemTip(tip, self.key)
        end)
        row.links[c] = link
      elseif col.format == "share" then
        local track = row:CreateTexture(nil, "ARTWORK")
        track:SetSize(SHARE_W, 6)
        W.Fill(track, W.COLORS.panelHover)
        local bar = row:CreateTexture(nil, "ARTWORK", nil, 1)
        bar:SetHeight(6)
        bar:SetPoint("LEFT", track, "LEFT", 0, 0)
        row.shares[c] = { track = track, bar = bar }
      elseif col.format == "signal" then
        row.badges[c] = W.SignalBadge(row)
      elseif col.format == "tag" then
        row.tags[c] = W.Tag(row)
      elseif col.button then
        local def = col.button
        local b = W.Button(row, "", col.width, rowH - 4, function()
          if row.data and def.onClick then
            def.onClick(row.data, row)
          end
        end)
        b:Hide()
        row.buttons[c] = b
      end
      if mainItem(col) then
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
      -- right-click on an item row: what you can do with the item (opts.itemMenu = { hide = true } adds Hide)
      if button == "RightButton" and self.itemID and opts.itemMenu and ns.UI.ItemMenu then
        ns.UI:ItemMenu(self, self.itemID, opts.itemMenu)
        return
      end
      -- a modified click on an item row links the item (chat, try on), as a link in chat would
      if self.itemID and button ~= "RightButton" and linksItem(opts) then
        W.ItemLinkClicked(self.itemID)
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
  bar:SetPoint("TOPRIGHT", 0, -t.headH) -- inside the table's right edge, never past the window
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
  if opts.note then
    t:SetNote(opts.note)
  end
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
  local n = math.max(1, math.floor((height - self.headH - self:NoteSpace()) / self.rowH))
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
    self.message:SetPoint("LEFT", 20, -self.headH / 2) -- below the header
    self.message:SetPoint("RIGHT", -20, -self.headH / 2)
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
DataTable.MIN_FLEX = 60 -- the flexible column (the item names) never narrower than this

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
    if userHidden[col.key] and not mainItem(col) then -- switched off in the column chooser
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
  -- the flexible column takes up the difference: wider when there's room; when nothing more can be dropped, it
  -- keeps giving way (down to DataTable.MIN_FLEX) rather than the row running past the table's edge
  local extra = math.max(avail - total, DataTable.MIN_FLEX - opts.columns[flex].width)
  local rowW = total + extra
  local widths, xs, x = {}, {}, 0
  for c, col in ipairs(opts.columns) do
    widths[c] = hidden[c] and 0 or col.width + (c == flex and extra or 0)
    xs[c] = x
    if not hidden[c] then
      x = x + widths[c] + GAP
    end
  end
  for c, h in ipairs(self.headers) do
    h:SetShown(not hidden[c] and not opts.bare)
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
      if mainItem(col) then
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
      elseif row.links[c] then
        local link = row.links[c]
        fs:SetSize(math.max(1, widths[c] - ICON_W - 4), rowH)
        fs:SetPoint("LEFT", cx + ICON_W + 4, 0)
        link.icon:ClearAllPoints()
        link.icon:SetPoint("LEFT", cx, 0)
        link:ClearAllPoints()
        link:SetPoint("LEFT", cx, 0) -- its width follows the name: Render
      elseif row.shares[c] then
        local s = row.shares[c]
        s.track:ClearAllPoints()
        s.track:SetPoint("LEFT", cx, 0)
        fs:SetSize(math.max(1, widths[c] - SHARE_W - 6), rowH)
        fs:SetPoint("LEFT", cx + SHARE_W + 6, 0)
      elseif row.badges[c] or row.tags[c] then
        local part = row.badges[c] or row.tags[c]
        part:ClearAllPoints()
        part:SetPoint("LEFT", cx, 0)
        fs:SetSize(1, rowH)
        fs:SetPoint("LEFT", cx, 0)
      elseif row.buttons[c] then
        local b = row.buttons[c]
        b:SetWidth(math.max(1, widths[c]))
        b:ClearAllPoints()
        b:SetPoint("LEFT", cx, 0)
        fs:SetSize(1, rowH)
        fs:SetPoint("LEFT", cx, 0)
      else
        fs:SetSize(widths[c], rowH)
        fs:SetPoint("LEFT", cx, 0)
      end
    end
  end
  -- a wrapped note takes more lines when the table gets narrower: make room for it again
  local space = self:NoteSpace()
  if space ~= (self.noteSpace or 0) then
    self.noteSpace = space
    self:Resize()
  end
end

-- A dim note under the rows, wrapped to the table's width, inside its frame; nil removes it. A filling table gives
-- it the room of the rows it needs; a fixed one grows by it.
function DataTable:SetNote(text)
  if not self.note then
    self.note = W.Text(self.frame, "GameFontDisableSmall", "LEFT")
    self.note:SetWordWrap(true)
    self.note:SetPoint("BOTTOMLEFT", 8, 4)
    self.note:SetPoint("BOTTOMRIGHT", -8 - DataTable.BAR_SPACE, 4)
  end
  self.note:SetText(text or "")
  self.note:SetShown(text ~= nil and text ~= "")
  self.noteSpace = self:NoteSpace()
  self:Resize()
end

-- the height the note takes under the rows (0 without one)
function DataTable:NoteSpace()
  if not (self.note and self.note:IsShown()) then
    return 0
  end
  return math.ceil(self.note:GetStringHeight() or 12) + 8
end

-- after the note changed: a fixed table's height, or a filling table's row count (on its next draw)
function DataTable:Resize()
  if self.opts.fill then
    self.fitHeight = nil
    if self.source then
      self:Render()
    end
  else
    self.frame:SetHeight(self.headH + self.rowsN * self.rowH + self:NoteSpace())
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
  elseif key:find("^__name:") then -- another item column, by its item's name
    local colKey = key:sub(8)
    for _, col in ipairs(self.opts.columns) do
      if col.key == colKey and linkItem(col) then
        local id = col.item(d)
        v = id and (W.ItemInfo(id) or W.ItemLabel(id)) or nil
      end
    end
  else
    v = d[key]
  end
  if type(v) == "table" then -- a tag cell's { text, kind }
    v = v.text
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

local function itemCell(t, iconTex, col, d, itemID)
  local name, _, quality, icon = W.ItemInfo(itemID or 0)
  if itemID and not name then
    t:RenderWhenLoaded(itemID)
    -- the load callback doesn't always come (WoW Forever): also look again until the name arrives, and when the
    -- row is hovered
    t.redraw = t.redraw or function()
      t:Render()
    end
    W.ItemNameOrLoad(itemID, t.redraw)
  end
  iconTex:SetTexture(icon or 134400)
  iconTex:SetShown(itemID ~= nil)
  local fallback = col.fallback and col.fallback(d) or (itemID and ("item:" .. itemID)) or ""
  return W.QualityText(quality, name or fallback) .. (col.suffix and col.suffix(d) or "")
end

-- a share cell: the bar over its track (full at col.max, 40% by default), in the accent
local function shareCell(s, col, v, shown)
  s.track:SetShown(shown)
  local f = v and math.max(0, math.min(1, v / (col.max or 0.4))) or 0
  s.bar:SetWidth(math.max(1, f * SHARE_W))
  W.Fill(s.bar, W.COLORS.accent)
  s.bar:SetShown(shown and f > 0)
  s.width = f * SHARE_W
end

-- a button cell: its label and look for this row (variant "primary", "selected" or normal)
local function buttonCell(b, def, d, shown)
  shown = shown and (not def.shown or def.shown(d)) and true or false
  b:SetShown(shown)
  if not shown then
    return
  end
  b:SetText(type(def.label) == "function" and def.label(d) or def.label or "")
  local variant = def.variant and def.variant(d)
  W.Primary(b, variant == "primary")
  b:SetSelected(variant == "selected")
  b:SetEnabled(not def.enabled or def.enabled(d) and true or false)
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
      local hidden = self.hiddenColumns or {}
      for c, col in ipairs(opts.columns) do
        local val
        if mainItem(col) then
          val = itemCell(self, row.icon, col, d, row.itemID or nil)
        elseif linkItem(col) then
          local link, key = row.links[c], col.item(d)
          link.key = key or false
          val = itemCell(self, link.icon, col, d, key)
          link.icon:SetShown(key ~= nil and not hidden[c])
        elseif row.shares[c] then
          shareCell(row.shares[c], col, d[col.key], not hidden[c])
          val = FORMATS.share(d[col.key])
        elseif row.badges[c] then
          local badge = row.badges[c]
          badge:SetSignal(d[col.key])
          badge:SetShown(not hidden[c])
          val = ""
        elseif row.tags[c] then
          local tag, v = row.tags[c], d[col.key]
          if type(v) == "table" then
            tag:Set(v.text, v.kind)
          else
            tag:Set(v and tostring(v) or "", "other")
          end
          tag:SetShown(tag:IsShown() and not hidden[c])
          val = ""
        elseif row.buttons[c] then
          buttonCell(row.buttons[c], col.button, d, not hidden[c])
          val = ""
        elseif col.text then
          val = col.text(d, self)
        elseif col.format then
          val = FORMATS[col.format](d[col.key])
        else
          local v = d[col.key]
          val = v ~= nil and tostring(v) or W.NONE
        end
        row.cells[c]:SetText(val or "")
        local link = row.links[c]
        if link then -- the hover region over the icon and the (possibly cut) name
          local fs = row.cells[c]
          local w = math.min(fs:GetStringWidth() or 0, fs:GetWidth() or 0)
          link:SetWidth(ICON_W + 4 + math.max(1, w))
          link:SetShown(link.key and not hidden[c] and true or false)
        end
        if mainItem(col) and row.conf then -- the confidence bars right after the (possibly cut) name
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
  signedMoney = gold,
  share = function(v)
    return v and ("%.1f%%"):format(v * 100) or ""
  end,
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
    hidden[c] = (col.button or (self.userHidden or {})[col.key] and not mainItem(col)) and true or nil
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
      local money = col.money or col.format == "money" or col.format == "signedMoney"
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
          local id
          if linkItem(col) then
            id = col.item(d)
          else
            id = opts.itemID and opts.itemID(d)
          end
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
