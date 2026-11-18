-- The shared tab layout ("shell slots"). Every tab lays itself out from the same pieces inside its content area:
--
--   header   (optional, fixed height)   item name, KPIs
--   toolbar  (optional, fixed height)   search, filters, ranges, modes
--   left     (optional, fixed width)    full-height scrolling sidebar (categories, lists)
--   main                                stretches both ways (chart, table)
--   right    (optional, fixed width)    full-height scrolling sidebar (verdict, details)
--   status   (optional)                 one line at the bottom, left of the version
--
-- Compact mode (window narrower than UI.COMPACT_W): sidebars leave the layout and main takes the width. The left one
-- is replaced by the tab's own control (e.g. a dropdown in the toolbar); the right one opens as a Details panel over
-- the right of main (slots:ToggleDetails()).
local _, ns = ...
local UI, W = ns.UI, ns.Widgets

local GAP = 8
UI.SLOT_GAP = GAP

-- a sidebar: a skinned frame with a scroll pane; add content to frame.content (inset 10 px by convention)
local function sidebar(parent, width)
  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  W.Skin(f, W.COLORS.panel)
  f:SetWidth(width)
  f.pane = W.ScrollPane(f)
  f.content = f.pane.content
  return f
end
UI.Sidebar = sidebar

-- A vertical stack in a sidebar: each piece goes under the previous one, spanning the width (10 px margins).
--   stack:Heading(text) -> font string      stack:Text(font) -> wrapping font string
--   stack:Pair(label, term) -> row with .label (dim, left) and .value (right); term: hover explanation (Help)
--   stack:Row(height) -> an empty frame for custom controls
function UI.Stack(content)
  local st = {}
  local last
  local function add(obj, gap)
    if last then
      obj:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -(gap or 4))
    else
      obj:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -10)
    end
    obj:SetPoint("RIGHT", content, "RIGHT", -10, 0)
    last = obj
    return obj
  end
  function st:Heading(text, gap)
    local h = add(W.Text(content, "GameFontNormal"), gap or 14)
    h:SetText(text)
    return h
  end
  function st:Text(font, gap)
    local t = add(W.Text(content, font or "GameFontHighlightSmall"), gap)
    t:SetWordWrap(true)
    t:SetJustifyV("TOP")
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

-- v: the tab's content area. opts = { header = h, toolbar = h, left = w, right = w, status = true }
-- Returns slots: .header .toolbar .main (frames), .left .right (sidebar frames; put things in .content),
-- .status (a font string), :SetCompact(on), :ToggleDetails(), :Layout(), .compact, .details
function UI.Slots(v, opts)
  local s = { opts = opts, compact = UI.compact or false, details = false }
  local y = 0
  local function bar(h)
    local f = CreateFrame("Frame", nil, v)
    f:SetPoint("TOPLEFT", 0, y)
    f:SetPoint("TOPRIGHT", 0, y)
    f:SetHeight(h)
    y = y - h - GAP
    return f
  end
  if opts.header then
    s.header = bar(opts.header)
  end
  if opts.toolbar then
    s.toolbar = bar(opts.toolbar)
  end
  s.top = y
  s.bottom = 0
  if opts.status then
    s.status = W.Text(v, "GameFontDisableSmall")
    s.status:SetPoint("BOTTOMLEFT", 0, 2)
    s.status:SetPoint("BOTTOMRIGHT", -UI.FOOTER_SPACE, 2)
    s.status:SetWordWrap(false)
    s.bottom = 20
  end
  if opts.left then
    s.left = sidebar(v, opts.left)
  end
  if opts.right then
    s.right = sidebar(v, opts.right)
  end
  s.main = CreateFrame("Frame", nil, v)

  function s:Layout()
    local compact = self.compact
    local l = (self.left and not compact) and (opts.left + GAP) or 0
    local r = (self.right and not compact) and (opts.right + GAP) or 0
    self.main:ClearAllPoints()
    self.main:SetPoint("TOPLEFT", l, self.top)
    self.main:SetPoint("BOTTOMRIGHT", -r, self.bottom)
    if self.left then
      self.left:ClearAllPoints()
      self.left:SetPoint("TOPLEFT", 0, self.top)
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
