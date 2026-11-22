-- The shared tab layout ("shell slots"). Every tab lays itself out from the same pieces inside its content area:
--
--   header   (optional, fixed height)   item name, KPIs
--   toolbar  (optional, fixed height)   search, filters, ranges, modes
--   left     (optional, fixed width)    full-height scrolling sidebar (categories, lists)
--   main                                stretches both ways (chart, table)
--   right    (optional, fixed width)    full-height scrolling sidebar (verdict, details)
--   status   (optional)                 the tab's text in the window's footer (where the numbers come from)
--
-- Compact mode (window narrower than UI.COMPACT_W): sidebars leave the layout and main takes the width. The left one
-- is replaced by the tab's own control (e.g. a dropdown in the toolbar); the right one opens as a Details panel over
-- the right of main (slots:ToggleDetails()).
local _, ns = ...
local UI, W = ns.UI, ns.Widgets

local GAP = 8
UI.SLOT_GAP = GAP
-- one width for every tab's sidebars: menus on the left (Market, Settings, Guide), details on the right (Item,
-- Arbitrage). Left sidebars start under the toolbar, whose search box (when it has one) is as wide as them.
UI.SIDEBAR_W = 200
UI.SIDE_PANEL_W = 280

-- a sidebar: a frame with a scroll pane; add content to frame.content (inset 10 px by convention). plain: no panel
-- behind it (its content is cards, each with its own panel)
local function sidebar(parent, width, plain)
  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  if not plain then
    W.Skin(f, W.COLORS.panel)
  end
  f:SetWidth(width)
  f.pane = W.ScrollPane(f)
  f.content = f.pane.content
  return f
end
UI.Sidebar = sidebar

-- A side menu (Market's categories and lists, Settings' sections, the Guide's articles, Crafting's pages): one line
-- per entry, as many lines as the sidebar is tall, paging with the mouse wheel.
--   local list = UI.SideList(sidebar, { onClick = function(entry, button, line) end })
--   list:SetEntries({ { heading = "Watchlists", note = "3" },
--     { label, count, note, selected, kind = "link" | "dim" | "done", indent = 1, key }, ... })
-- Lines are gold; kind "link" is an action written as text ("+ New list"), "dim" a quieter line (a subclass), "done"
-- a finished one (its count in green). The selected line is tinted with the theme's accent and its text turns white.
-- note: dim text after the label (a guild list's owner). indent: steps of 10 px in. A count that is a number gets
-- thousands separators. Headings don't click.
-- The lines are sidebar.lines (and list.lines), each with .text, .count, .sel and .entry.
UI.SIDE_LINE_H = 19
UI.SIDE_INDENT = 10
local SIDE_PAD = 4

function UI.SideList(side, opts)
  opts = opts or {}
  local lineH = opts.lineHeight or UI.SIDE_LINE_H
  local list = { sidebar = side, lines = {}, entries = {}, offset = 0, rows = opts.rows or 1, opts = opts }
  side.lines = list.lines
  if side.pane then
    side.pane:Hide() -- the list pages itself, so a long one needs no scroll bar
  end

  local function line(i)
    local b = CreateFrame("Button", nil, side)
    b:SetHeight(lineH)
    b:SetPoint("TOPLEFT", SIDE_PAD, -SIDE_PAD - (i - 1) * lineH)
    b:SetPoint("RIGHT", side, "RIGHT", -SIDE_PAD, 0)
    b.sel = b:CreateTexture(nil, "BACKGROUND")
    b.sel:SetAllPoints()
    W.Fill(b.sel, W.COLORS.rowSelected)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    W.Fill(b.hl, W.COLORS.rowHover)
    b.text = W.Text(b, "GameFontNormalSmall")
    b.text:SetPoint("LEFT", 6, 0)
    b.text:SetPoint("RIGHT", -38, 0)
    b.text:SetWordWrap(false)
    b.count = W.Text(b, "GameFontDisableSmall", "RIGHT")
    b.count:SetPoint("RIGHT", -4, 0)
    b.entry = false
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, button)
      local e = self.entry
      if e and not e.heading and opts.onClick then
        opts.onClick(e, button, self)
      end
    end)
    list.lines[i] = b
    return b
  end
  for i = 1, list.rows do
    line(i)
  end

  local function paint(b, e)
    b.entry = e or false
    if not e then
      b:Hide()
      return
    end
    b:Show()
    b:EnableMouse(not e.heading)
    b.hl:SetShown(not e.heading)
    b.sel:SetShown(e.selected and not e.heading or false)
    local x = 6 + UI.SIDE_INDENT * (e.indent or 0)
    b.text:ClearAllPoints()
    b.text:SetPoint("LEFT", x, 0)
    b.text:SetPoint("RIGHT", -38, 0)
    local label = e.heading or e.label or ""
    if e.note and e.note ~= "" then
      label = label .. "  " .. W.Dim(e.note)
    end
    b.text:SetText(label)
    -- every line gets its colour set, so a reused line never keeps the one its last entry had
    local font, color = "GameFontNormalSmall", "gold"
    if e.heading then
      font, color = "GameFontDisableSmall", "dim"
    elseif e.selected then
      font, color = "GameFontHighlightSmall", "white"
    elseif e.kind == "link" then
      font, color = "GameFontHighlightSmall", "link"
    elseif e.kind == "dim" then
      font, color = "GameFontHighlightSmall", "soft"
    end
    b.text:SetFontObject(font)
    local c = W.RGB(color)
    b.text:SetTextColor(c[1], c[2], c[3], 1)
    local count = e.count
    if type(count) == "number" then
      count = W.Thousands(count)
    end
    b.count:SetText(count and (e.kind == "done" and W.Color("good", count) or tostring(count)) or "")
  end

  function list:Render()
    self.offset = math.max(0, math.min(self.offset, #self.entries - self.rows))
    for i, b in ipairs(self.lines) do
      paint(b, i <= self.rows and self.entries[self.offset + i] or nil)
    end
  end

  -- entries: the whole list; the lines show the part that fits from the current offset
  function list:SetEntries(entries)
    self.entries = entries or {}
    self:Render()
  end

  -- page by n lines (positive: down the list)
  function list:Scroll(n)
    self.offset = self.offset + n
    self:Render()
  end

  -- the selection's tint follows the theme (W.SetTheme calls this)
  function list:Repaint()
    for _, b in ipairs(self.lines) do
      W.Fill(b.sel, W.COLORS.rowSelected)
    end
  end

  -- as many lines as the side's height holds
  function list:Fit(h)
    local n = math.max(1, math.floor(((h or 0) - 2 * SIDE_PAD) / lineH))
    for i = #self.lines + 1, n do
      line(i)
    end
    self.rows = n
    self:Render()
  end
  side:HookScript("OnSizeChanged", function(_, _, h)
    list:Fit(h)
  end)
  side:EnableMouseWheel(true)
  side:SetScript("OnMouseWheel", function(_, delta)
    list:Scroll(-delta * 2)
  end)
  W.sideLists[list] = true
  return list
end

-- A vertical stack in a sidebar: each piece goes under the previous one, spanning the width (10 px margins).
--   stack:Heading(text) -> font string      stack:Text(font) -> wrapping font string
--   stack:Pair(label, term) -> row with .label (dim, left) and .value (right); term: hover explanation (Help)
--   stack:Row(height) -> an empty frame for custom controls
--   stack:Card(gap) -> a panel (its own stack: card.stack) that sizes itself to what's in it (card:Fit())
--   stack:Height(width) -> the height of everything stacked so far (margins included). With the stack's width,
--     wrapping texts are given their width first, so they measure right away (not one layout pass late)
-- pad: the margin around the stack (10 by default; 0 for a column of cards)
function UI.Stack(content, pad)
  pad = pad or 10
  local st = { items = {} }
  local last
  local function add(obj, gap, fixedWidth)
    gap = last and (gap or 4) or 0
    if last then
      obj:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -gap)
    else
      obj:SetPoint("TOPLEFT", content, "TOPLEFT", pad, -pad)
    end
    if not fixedWidth then
      obj:SetPoint("RIGHT", content, "RIGHT", -pad, 0)
    end
    last = obj
    st.items[#st.items + 1] = { obj, gap }
    return obj
  end
  function st:Height(width)
    local h = 2 * pad
    local inner = width and math.max(1, width - 2 * pad)
    for _, it in ipairs(self.items) do
      local obj = it[1]
      if obj.card then
        obj:Fit(inner)
      end
      local oh
      if obj.GetStringHeight then
        if inner and obj.wraps then
          obj:SetWidth(inner) -- wrapped text measures at its real width now
        end
        local text = obj:GetText()
        oh = (text and text ~= "") and (obj:GetStringHeight() or 12) or 0
      else
        oh = obj:GetHeight() or 0
      end
      h = h + it[2] + oh
    end
    return h
  end
  -- A stack of cards, laid out over the whole width: in columns at least minWidth wide (up to maxColumns), each card
  -- in the shortest column so far, in order; one column when there's no room for two. Returns the height.
  function st:Flow(width, minWidth, gap, maxColumns)
    local inner = math.max(1, width - 2 * pad)
    local n = math.min(maxColumns or 2, #self.items, math.floor((inner + gap) / (minWidth + gap)))
    n = math.max(1, n)
    if n == 1 then
      if self.flowed then -- back to the plain stack's anchors
        self.flowed = nil
        local prev
        for _, it in ipairs(self.items) do
          local obj = it[1]
          obj:ClearAllPoints()
          if prev then
            obj:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -it[2])
          else
            obj:SetPoint("TOPLEFT", content, "TOPLEFT", pad, -pad)
          end
          obj:SetPoint("RIGHT", content, "RIGHT", -pad, 0)
          prev = obj
        end
      end
      return self:Height(width)
    end
    self.flowed = true
    local cw = math.floor((inner - (n - 1) * gap) / n)
    local heights = {}
    for c = 1, n do
      heights[c] = 0
    end
    for _, it in ipairs(self.items) do
      local obj = it[1]
      local col = 1
      for c = 2, n do
        if heights[c] < heights[col] then
          col = c
        end
      end
      if obj.card then
        obj:Fit(cw)
      end
      local y = heights[col] > 0 and heights[col] + gap or 0
      obj:ClearAllPoints()
      obj:SetPoint("TOPLEFT", content, "TOPLEFT", pad + (col - 1) * (cw + gap), -(pad + y))
      obj:SetWidth(cw)
      heights[col] = y + (obj:GetHeight() or 0)
    end
    return 2 * pad + math.max(unpack(heights))
  end
  function st:Card(gap)
    local card = add(CreateFrame("Frame", nil, content, "BackdropTemplate"), gap or 8)
    W.Skin(card, W.COLORS.panel)
    card.card = true
    card.stack = UI.Stack(card, 8)
    card.SetContent = UI.SetCardContent
    card.parts, card.redraw, card.fitWidth = false, false, false -- set by SetContent
    function card:Fit(width)
      if self.parts then
        UI.LayoutCardContent(self, width)
      else
        self:SetHeight(self.stack:Height(width))
      end
    end
    return card
  end
  function st:Heading(text, gap)
    local h = add(W.Text(content, "GameFontNormal"), gap or 14)
    h:SetText(text)
    return h
  end
  -- wrapping text: an explicit width (from Height(width)), so its height is known as soon as it's measured
  function st:Text(font, gap)
    local t = add(W.Text(content, font or "GameFontHighlightSmall"), gap, true)
    t:SetWordWrap(true)
    t:SetJustifyV("TOP")
    t:SetWidth(200)
    t.wraps = true
    return t
  end
  function st:Pair(label, term, gap)
    local row = add(CreateFrame("Frame", nil, content), gap or 3)
    row:SetHeight(16)
    row.label = W.Text(row, "GameFontDisableSmall")
    row.label:SetPoint("LEFT", 0, 0)
    row.label:SetText(label)
    row.value = W.Text(row, "GameFontHighlightSmall", "RIGHT")
    row.value:SetPoint("RIGHT", 0, 0)
    row.value:SetPoint("LEFT", row.label, "RIGHT", 6, 0)
    row.value:SetWordWrap(false)
    if term and ns.Help then
      row:EnableMouse(true)
      ns.Help.Explain(row, term)
    end
    return row
  end
  function st:Row(height, gap)
    local row = add(CreateFrame("Frame", nil, content), gap)
    row:SetHeight(height)
    return row
  end
  return st
end

-- Card content: card:SetContent(c) draws a whole label / value card from a table, so views describe a card instead
-- of building and re-filling its pieces by hand. Every piece is optional:
--   title, titleColor (a text role or "RRGGBB"; white by default)   or   item, count: the title as an item link
--   subtitle: a dim line under the title           note: a dim wrapped line under the rows
--   rows = { { label, copper | text, signed, color, total, big, term, item, count, hidden }, ... }
--     copper: money (W.Money, or W.SignedMoney with every unit when signed); text: any text, in color if given
--     total: a rule above and a brighter, larger line (a sum); big: a headline value
--     term: the label explains itself on hover (Help); item (+ count): an item link before the label
--     hidden: left out, taking no room (so a card can keep a row's place in its list)
-- The pieces are made on the first call and reused on every later one: card.rows[i] keeps its .label and .value
-- font strings, so callers and specs can read them. A card uses SetContent or its stack, not both.
local CARD_PAD = 8
local CARD_ROW_H, CARD_BIG_H, CARD_TOTAL_PAD = 16, 22, 4
local CARD_FONTS = {
  plain = { "GameFontDisableSmall", "GameFontHighlightSmall" },
  total = { "GameFontHighlight", "GameFontHighlight" },
  big = { "GameFontHighlight", "GameFontHighlightLarge" },
}

local function cardRow(card)
  local row = CreateFrame("Frame", nil, card)
  row.rule = row:CreateTexture(nil, "ARTWORK")
  row.rule:SetHeight(1)
  row.rule:SetPoint("TOPLEFT", 0, 0)
  row.rule:SetPoint("TOPRIGHT", 0, 0)
  W.Fill(row.rule, W.COLORS.border)
  -- label and value share a bottom line, so a big value and its small label sit on one baseline
  row.label = W.Text(row, "GameFontDisableSmall")
  row.label:SetPoint("BOTTOMLEFT", 0, 2)
  row.label:SetWordWrap(false)
  row.value = W.Text(row, "GameFontHighlightSmall", "RIGHT")
  row.value:SetPoint("BOTTOMRIGHT", 0, 2)
  row.value:SetPoint("LEFT", row.label, "RIGHT", 6, 0)
  row.value:SetWordWrap(false)
  W.EnableLinks(row) -- the label's item link
  if ns.Help then
    ns.Help.Explain(row, function(self)
      return self.term
    end)
  end
  return row
end

local function cardParts(card)
  local p = { rows = {} }
  p.title = W.Text(card, "GameFontHighlightLarge")
  p.title:SetWordWrap(false)
  p.title.wraps = false
  p.item = W.ItemLink(card, { icon = 16 })
  p.item:SetFont(14, true)
  p.subtitle = W.Text(card, "GameFontDisableSmall")
  p.subtitle:SetWordWrap(true)
  p.subtitle:SetJustifyV("TOP")
  p.subtitle.wraps = true
  p.note = W.Text(card, "GameFontDisableSmall")
  p.note:SetWordWrap(true)
  p.note:SetJustifyV("TOP")
  p.note.wraps = true
  card.parts, card.rows = p, p.rows
  return p
end

local function cardValue(r)
  if r.copper ~= nil then
    return r.signed and W.SignedMoney(r.copper, { full = true }) or W.Money(r.copper)
  end
  if r.text == nil then
    return ""
  end
  return r.color and W.Color(r.color, r.text) or tostring(r.text)
end

function UI.SetCardContent(card, c)
  c = c or {}
  card.contentData = c
  local p = card.parts or cardParts(card)
  -- an item name the client hasn't loaded yet comes back through this
  card.redraw = card.redraw or function()
    card:SetContent(card.contentData)
  end
  if c.item then
    p.item:SetItem(c.item, c.count)
    p.title:SetText("")
  else
    p.item:SetItem(false)
    p.title:SetText(c.title or "")
    local tc = c.titleColor and W.RGB(c.titleColor) or W.COLORS.text
    p.title:SetTextColor(tc[1], tc[2], tc[3], 1)
  end
  p.subtitle:SetText(c.subtitle or "")
  p.note:SetText(c.note or "")
  local n = 0
  for _, r in ipairs(c.rows or {}) do
    if not r.hidden then
      n = n + 1
      local row = p.rows[n] or cardRow(card)
      p.rows[n] = row
      local kind = r.total and "total" or r.big and "big" or "plain"
      row.kind = kind
      row.label:SetFontObject(CARD_FONTS[kind][1])
      row.value:SetFontObject(CARD_FONTS[kind][2])
      local label = r.label or ""
      if r.item then
        label = W.LinkText(r.item, r.count, card.redraw) .. (label ~= "" and " " .. label or "")
      end
      row.label:SetText(label)
      row.value:SetText(cardValue(r))
      row.rule:SetShown(kind == "total")
      row:SetHeight((kind == "big" and CARD_BIG_H or CARD_ROW_H) + (kind == "total" and CARD_TOTAL_PAD or 0))
      row.term = r.term or false
      row:EnableMouse((row.term or r.item) and true or false)
      row:Show()
    end
  end
  for i = n + 1, #p.rows do
    p.rows[i]:Hide()
  end
  p.shownRows = n
  card:Fit(card.fitWidth)
end

-- Lays the content out from the top and sizes the card to it; pieces with nothing to show take no room.
-- width: the card's width (wrapped lines measure at it), or the last one given.
function UI.LayoutCardContent(card, width)
  local p = card.parts
  width = width or card.fitWidth
  card.fitWidth = width
  local inner = width and math.max(1, width - 2 * CARD_PAD)
  local y, gap = CARD_PAD, 0
  local function place(obj, h, before)
    y = y + (gap > 0 and (before or 2) or 0)
    obj:ClearAllPoints()
    obj:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -y)
    if obj ~= p.item then
      obj:SetPoint("RIGHT", card, "RIGHT", -CARD_PAD, 0)
    end
    y, gap = y + h, 1
  end
  local function text(fs, before)
    local t = fs:GetText()
    if not t or t == "" then
      fs:Hide()
      return
    end
    fs:Show()
    if inner and fs.wraps then
      fs:SetWidth(inner) -- wrapped text measures at its real width now
    end
    place(fs, fs:GetStringHeight() or 12, before)
  end
  text(p.title)
  if p.item:IsShown() then
    place(p.item, p.item:GetHeight() or 16)
  end
  text(p.subtitle)
  for i = 1, p.shownRows or 0 do
    local row = p.rows[i]
    place(row, row:GetHeight() or CARD_ROW_H, i == 1 and 4 or 0)
  end
  text(p.note, 4)
  card:SetHeight(y + CARD_PAD)
end

-- Re-measure after the game lays text out: fn() now, and once more on the next frame (wrapped text only gets its
-- real height at its new width after a layout pass). Repeated calls in one frame share the second pass.
function UI.Relayout(owner, fn)
  fn()
  if owner.relayoutPending then
    return
  end
  owner.relayoutPending = true
  C_Timer.After(0, function()
    owner.relayoutPending = false
    fn()
  end)
end

-- v: the tab's content area. opts = { header = h, toolbar = h, chips = h, left = w, right = w, status = true,
--   fullLeft = true: the left sidebar runs from the top, with header / toolbar / chips beside it }
-- Returns slots: .header .toolbar .chips .main (frames), .left .right (sidebar frames; put things in .content),
-- .status (a font string), :SetCompact(on), :ToggleDetails(), :Layout(), .compact, .details
function UI.Slots(v, opts)
  local s = { opts = opts, compact = UI.compact or false, details = false }
  local y = 0
  local bars = {}
  local function bar(h)
    local f = CreateFrame("Frame", nil, v)
    f:SetHeight(h)
    bars[#bars + 1] = { frame = f, h = h }
    y = y - h - GAP
    return f
  end
  if opts.header and not opts.headerBelow then
    s.header = bar(opts.header)
  end
  if opts.toolbar then
    s.toolbar = bar(opts.toolbar)
  end
  if opts.header and opts.headerBelow then -- under the toolbar
    s.header = bar(opts.header)
  end
  if opts.chips then
    s.chips = bar(opts.chips)
  end
  s.top = y
  s.bottom = 0
  if opts.status then
    -- the footer belongs to the window (it stays put, sidebars end above it): the tab only sets its text
    s.status = { text = "" }
    function s.status:SetText(text)
      self.text = text or ""
      UI:UpdateFooter()
    end
    function s.status:GetText()
      return self.text
    end
  end
  if opts.left then
    s.left = sidebar(v, opts.left)
  end
  if opts.right then
    s.right = sidebar(v, opts.right, opts.rightCards)
  end
  s.main = CreateFrame("Frame", nil, v)

  function s:Layout()
    local compact = self.compact
    local l = (self.left and not compact) and (opts.left + GAP) or 0
    local r = (self.right and not compact) and (opts.right + GAP) or 0
    local top = 0
    for _, b in ipairs(bars) do
      b.frame:ClearAllPoints()
      b.frame:SetShown(not b.hidden)
      if not b.hidden then
        b.frame:SetPoint("TOPLEFT", opts.fullLeft and l or 0, top)
        b.frame:SetPoint("TOPRIGHT", 0, top)
        top = top - b.h - GAP
      end
    end
    self.top = top
    self.main:ClearAllPoints()
    self.main:SetPoint("TOPLEFT", l, self.top)
    self.main:SetPoint("BOTTOMRIGHT", -r, self.bottom)
    if self.left then
      self.left:ClearAllPoints()
      self.left:SetPoint("TOPLEFT", 0, opts.fullLeft and 0 or self.top)
      self.left:SetPoint("BOTTOMLEFT", 0, self.bottom)
      self.left:SetShown(not compact)
    end
    if self.right then
      self.right:ClearAllPoints()
      self.right:SetPoint("TOPRIGHT", 0, self.top)
      self.right:SetPoint("BOTTOMRIGHT", 0, self.bottom)
      -- compact: a panel over main, raised above it, shown on demand
      self.right:SetFrameLevel((self.main:GetFrameLevel() or 1) + (compact and 20 or 0))
      self.right:SetShown(not compact or self.details)
    end
  end

  -- hide or show a bar (header / toolbar / chips); main and the sidebars move up or down with it
  function s:ShowBar(frame, on)
    for _, b in ipairs(bars) do
      if b.frame == frame then
        b.hidden = not on
      end
    end
    self:Layout()
  end

  function s:SetCompact(on)
    self.compact = on and true or false
    self.details = false
    self:Layout()
  end

  function s:ToggleDetails(on)
    if on == nil then
      on = not self.details
    end
    self.details = on
    self:Layout()
  end

  s:Layout()
  return s
end
