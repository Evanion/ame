-- Small flat-style widget helpers shared by AME windows.
local _, ns = ...
local L = ns.L

local W = {}
ns.Widgets = W

W.COLORS = {
  bg = { 0.055, 0.06, 0.075, 0.96 },
  panel = { 0.09, 0.1, 0.12, 1 },
  border = { 1, 1, 1, 0.1 },
  accent = { 0.2, 0.8, 1, 1 },
  text = { 0.9, 0.9, 0.9, 1 },
  dim = { 0.6, 0.62, 0.66, 1 },
  up = { 0.3, 0.85, 0.45, 1 },
  down = { 1, 0.38, 0.35, 1 },
  panelHover = { 0.14, 0.15, 0.18, 1 }, -- buttons and inputs under the mouse
  rowHover = { 1, 1, 1, 0.08 }, -- list, menu and sidebar rows under the mouse
  rowSelected = { 0.2, 0.8, 1, 0.2 }, -- the picked row (accent; follows the theme)
  selected = { 0.2, 0.8, 1, 0.18 },
}

-- Text colours by role ("RRGGBB"), and helpers for |c escapes (defined in Init.lua so chat lines can use them too)
W.HEX = ns.HEX

-- Colour-blind friendly palette (Settings): gains / buy in blue, losses / sell in orange (Okabe-Ito), so the two
-- never rely on red vs green. Applied to the text roles and the chart's up / down colours.
local PALETTES = {
  normal = { good = "4dd973", bad = "ff6159", up = { 0.3, 0.85, 0.45, 1 }, down = { 1, 0.38, 0.35, 1 } },
  colorBlind = { good = "56b4e9", bad = "e69f00", up = { 0.34, 0.71, 0.91, 1 }, down = { 0.9, 0.62, 0, 1 } },
}
function W.ApplyPalette()
  local p = PALETTES[ns.Settings and ns.Settings:Get("colorBlind") and "colorBlind" or "normal"]
  ns.HEX.good, ns.HEX.bad = p.good, p.bad
  W.COLORS.up, W.COLORS.down = p.up, p.down
end
W.Color = ns.Color
function W.Dim(text)
  return ns.Color("dim", text)
end
W.NONE = ns.Color("none", "-") -- a missing value

-- fill a texture with a colour table
function W.Fill(tex, c)
  tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
end

-- Faction themes for window chrome (title, selected buttons, panel glow). Data colours in charts stay fixed.
W.THEMES = {
  Alliance = { 0.25, 0.56, 1 },
  Horde = { 0.93, 0.25, 0.2 },
  Neutral = { 1, 0.73, 0.22 }, -- goblin auction houses
}

function W.SetTheme(house)
  local c = W.THEMES[house] or W.THEMES.Neutral
  W.theme = W.THEMES[house] and house or "Neutral" -- the applied theme
  W.COLORS.accent = { c[1], c[2], c[3], 1 }
  W.COLORS.selected = { c[1], c[2], c[3], 0.22 }
  W.COLORS.rowSelected = { c[1], c[2], c[3], 0.2 }
  -- selected buttons and ticked checkboxes take the new accent
  for b in pairs(W.buttons) do
    if b.selected then
      b:SetSelected(true)
    end
  end
  for check in pairs(W.checks) do
    check:SetChecked(check.checked)
  end
end

W.buttons = setmetatable({}, { __mode = "k" }) -- every W.Button, for re-tinting on a theme change
W.checks = setmetatable({}, { __mode = "k" }) -- every W.Check, likewise

-- "ffRRGGBB" for |c escapes
function W.Hex(c)
  local function byte(x)
    return math.floor(x * 255 + 0.5)
  end
  return ("ff%02x%02x%02x"):format(byte(c[1]), byte(c[2]), byte(c[3]))
end

local FLAT = {
  bgFile = "Interface\\Buttons\\WHITE8x8",
  edgeFile = "Interface\\Buttons\\WHITE8x8",
  edgeSize = 1,
}

function W.Skin(frame, color, border)
  if not frame.SetBackdrop then
    Mixin(frame, BackdropTemplateMixin)
  end
  frame:SetBackdrop(FLAT)
  local c, b = color or W.COLORS.bg, border or W.COLORS.border
  frame:SetBackdropColor(c[1], c[2], c[3], c[4])
  frame:SetBackdropBorderColor(b[1], b[2], b[3], b[4])
end

function W.Text(parent, font, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  fs:SetJustifyH(justify or "LEFT")
  return fs
end

-- flat button with hover and optional selected state; onClick(button).
-- opts.icon: a leading icon of that size (b.icon, a texture; the label moves right of it)
function W.Button(parent, label, width, height, onClick, opts)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(width or 60, height or 20)
  W.Skin(b, W.COLORS.panel)
  b.selected = false
  W.buttons[b] = true
  b.label = W.Text(b, "GameFontHighlightSmall", "CENTER")
  b.label:SetText(label)
  if opts and opts.icon then
    b.icon = b:CreateTexture(nil, "OVERLAY")
    b.icon:SetSize(opts.icon, opts.icon)
    b.icon:SetPoint("LEFT", 6, 0)
    b.label:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
  else
    b.label:SetPoint("CENTER")
  end
  b:SetScript("OnEnter", function(self)
    if not self.selected then
      local c = W.COLORS.panelHover
      self:SetBackdropColor(c[1], c[2], c[3], c[4])
    end
  end)
  b:SetScript("OnLeave", function(self)
    if not self.selected then
      local c = W.COLORS.panel
      self:SetBackdropColor(c[1], c[2], c[3], c[4])
    end
  end)
  b:SetScript("OnClick", function(self)
    if onClick then
      onClick(self)
    end
  end)
  function b:SetSelected(on)
    self.selected = on
    local c = on and W.COLORS.selected or W.COLORS.panel
    self:SetBackdropColor(c[1], c[2], c[3], on and 1 or c[4])
    local bc = on and W.COLORS.accent or W.COLORS.border
    self:SetBackdropBorderColor(bc[1], bc[2], bc[3], on and 0.6 or bc[4])
  end
  return b
end

-- A row of buttons where one is selected (tabs, ranges, filters, modes).
--   W.Segmented(parent, { { key, label }, ... }, {
--     height = 20, gap = 4,
--     width = 60,                 -- fixed button width; or
--     minWidth = 44,              -- at least this, wider for long labels (translations)
--     onSelect = function(key, button) end,
--   })
-- Returns a frame sized to the row (anchor it as one piece) with :Select(key, silent), :Selected(), .buttons (in
-- order) and .byKey; each button has .key. Clicking selects and calls onSelect.
function W.Segmented(parent, items, opts)
  opts = opts or {}
  local h, gap = opts.height or 20, opts.gap or 4
  local seg = CreateFrame("Frame", nil, parent)
  seg.buttons, seg.byKey, seg.selected = {}, {}, false
  local x = 0
  for i, item in ipairs(items) do
    local b = W.Button(seg, item[2], opts.width or 60, h, function(self)
      seg:Select(self.key)
    end)
    b.key = item[1]
    local w = opts.width
    if not w then
      local textW = b.label:GetStringWidth() or 0
      w = math.max(opts.minWidth or 0, math.ceil(textW) + 16)
      b:SetWidth(w)
    end
    b:SetPoint("LEFT", x, 0)
    x = x + w + gap
    seg.buttons[i], seg.byKey[b.key] = b, b
  end
  seg:SetSize(math.max(0, x - gap), h)

  function seg:Select(key, silent)
    self.selected = key
    for _, b in ipairs(self.buttons) do
      b:SetSelected(b.key == key)
    end
    if not silent and opts.onSelect then
      opts.onSelect(key, self.byKey[key])
    end
  end

  function seg:Selected()
    return self.selected
  end
  return seg
end

-- Hover tooltip: build(tip, frame) fills GameTooltip (return false to show nothing). Hooks OnEnter / OnLeave, so the
-- frame's own hover scripts keep working. anchor: "ANCHOR_RIGHT" by default.
function W.Tooltip(frame, build, anchor)
  frame:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
    if build(GameTooltip, self) == false then
      GameTooltip:Hide()
      return
    end
    GameTooltip:Show()
  end)
  frame:HookScript("OnLeave", function()
    GameTooltip:Hide()
  end)
end

-- A box with text to copy (exports: WoW can't write files). The text is selected; Ctrl+C copies it.
function W.ExportBox(title, text)
  local box = W.exportBox
  if not box then
    box = CreateFrame("Frame", "AMEExportBox", UIParent, "BackdropTemplate")
    box:SetSize(560, 360)
    box:SetPoint("CENTER")
    box:SetFrameStrata("DIALOG")
    box:EnableMouse(true)
    box:SetMovable(true)
    box:RegisterForDrag("LeftButton")
    box:SetScript("OnDragStart", box.StartMoving)
    box:SetScript("OnDragStop", box.StopMovingOrSizing)
    W.Skin(box)
    box.title = W.Text(box, "GameFontNormal")
    box.title:SetPoint("TOPLEFT", 12, -10)
    box.hint = W.Text(box, "GameFontDisableSmall")
    box.hint:SetPoint("TOPLEFT", box.title, "BOTTOMLEFT", 0, -4)
    box.hint:SetText(L["Ctrl+C copies the selected text; paste it into a spreadsheet."])
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -44)
    scroll:SetPoint("BOTTOMRIGHT", -32, 40)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetFontObject("ChatFontSmall")
    edit:SetWidth(500)
    edit:SetAutoFocus(false)
    edit:SetScript("OnEscapePressed", function()
      box:Hide()
    end)
    scroll:SetScrollChild(edit)
    box.edit = edit
    local close = W.Button(box, L["Close"], 80, 22, function()
      box:Hide()
    end)
    close:SetPoint("BOTTOMRIGHT", -12, 10)
    tinsert(UISpecialFrames, "AMEExportBox")
    W.exportBox = box
  end
  box.title:SetText(title)
  box.edit:SetText(text or "")
  box:Show()
  box.edit:SetFocus()
  box.edit:HighlightText()
  return box
end

-- A one-time hint: a small callout above a frame, shown until "Got it" is clicked (remembered per account under
-- Settings "hintsSeen"). Returns the callout (nil when already seen).
function W.Hint(anchor, key, text)
  local seen = ns.Settings:Table("hintsSeen")
  if seen[key] then
    return nil
  end
  local tip = CreateFrame("Frame", nil, anchor, "BackdropTemplate")
  W.Skin(tip, { 0.1, 0.12, 0.16, 0.97 }, W.COLORS.accent)
  tip:SetFrameStrata("DIALOG")
  tip:SetSize(300, 64)
  tip:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 6)
  tip.text = W.Text(tip, "GameFontHighlightSmall")
  tip.text:SetPoint("TOPLEFT", 10, -8)
  tip.text:SetPoint("RIGHT", -10, 0)
  tip.text:SetWordWrap(true)
  tip.text:SetText(text)
  tip.ok = W.Button(tip, L["Got it"], 60, 18, function()
    seen[key] = true
    tip:Hide()
  end)
  tip.ok:SetPoint("BOTTOMRIGHT", -8, 6)
  tip.key = key
  return tip
end

-- Removable filter chips in a row, then "Clear all": chips:Set({ { label, onRemove }, ... }). chips.count: shown.
function W.Chips(parent, onClearAll)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(20)
  row.pool = {}
  row.clear = W.Button(row, L["Clear all"], 64, 18, onClearAll)
  function row:Set(list)
    local x = 0
    for i, chip in ipairs(list) do
      local b = self.pool[i]
      if not b then
        b = W.Button(self, "", 60, 18, function(btn)
          if btn.onRemove then
            btn.onRemove()
          end
        end)
        self.pool[i] = b
      end
      b.onRemove = chip[2]
      b.label:SetText(chip[1] .. "  " .. W.Dim("x"))
      local w = math.ceil(b.label:GetStringWidth() or 40) + 16
      b:SetWidth(w)
      b:ClearAllPoints()
      b:SetPoint("LEFT", x, 0)
      b:Show()
      x = x + w + 4
    end
    for i = #list + 1, #self.pool do
      self.pool[i]:Hide()
    end
    self.count = #list
    self.clear:SetShown(#list > 0)
    self.clear:ClearAllPoints()
    self.clear:SetPoint("LEFT", x + 4, 0)
  end
  row:Set({})
  return row
end

-- A one-line font string that may be cut short: hovering it shows the full text when it doesn't fit.
function W.Truncated(fs)
  fs:SetWordWrap(false)
  local hover = CreateFrame("Frame", nil, fs:GetParent())
  hover:SetAllPoints(fs)
  hover:EnableMouse(true)
  W.Tooltip(hover, function(tip)
    if (fs:GetStringWidth() or 0) <= (fs:GetWidth() or 0) then
      return false -- fits: nothing to add
    end
    tip:SetText(fs:GetText() or "", 1, 1, 1, 1, true)
  end)
  return hover
end

W.TIP_LABEL = { 0.8, 0.8, 0.8 } -- left side of label / value tooltip lines (values are white)

-- a tooltip's white title and a wrapped explanation under it
function W.TipText(tip, title, text)
  tip:SetText(title, 1, 1, 1)
  if text then
    tip:AddLine(text, nil, nil, nil, true)
  end
end

-- a label / value line in a tooltip
function W.TipPair(tip, label, value)
  local c = W.TIP_LABEL
  tip:AddDoubleLine(label, value, c[1], c[2], c[3], 1, 1, 1)
end

-- Stat card: a small panel with a dim label over a value (c.label, c.value). opts.term: hover explanation (Help).
function W.StatCard(parent, label, opts)
  local c = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  W.Skin(c, W.COLORS.panel)
  c:SetSize(120, 42)
  c.label = W.Text(c, "GameFontDisableSmall")
  c.label:SetPoint("TOPLEFT", 8, -6)
  c.label:SetText(label)
  c.value = W.Text(c, "GameFontHighlight")
  c.value:SetPoint("BOTTOMLEFT", 8, 7)
  c:EnableMouse(true)
  if opts and opts.term and ns.Help then
    ns.Help.Explain(c, opts.term)
  end
  return c
end

-- A row of stat cards sharing the row's width: defs = { { label, term = "market" }, ... }.
-- opts: height = 42, gap = 6, width = the row's width until it has one (it follows OnSizeChanged).
-- Anchor the returned frame's left and right; its cards are row.cards.
function W.CardRow(parent, defs, opts)
  opts = opts or {}
  local h, gap = opts.height or 42, opts.gap or 6
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(h)
  row.cards = {}
  for i, d in ipairs(defs) do
    local c = W.StatCard(row, d[1], { term = d.term })
    c:SetHeight(h)
    row.cards[i] = c
  end
  local function layout(width)
    if type(width) ~= "number" or width <= 0 then
      return
    end
    local n = #row.cards
    local w = (width - gap * (n - 1)) / n
    for i, c in ipairs(row.cards) do
      c:SetWidth(w)
      c:ClearAllPoints()
      c:SetPoint("TOPLEFT", (i - 1) * (w + gap), 0)
    end
  end
  row:SetScript("OnSizeChanged", function(_, width)
    layout(width)
  end)
  layout(opts.width)
  return row
end

-- The default UI fonts lack glyphs like ▲ ▼ ▮, so use inline textures instead.
W.ARROW_UP = " |TInterface\\Buttons\\Arrow-Up-Up:12:12:0:-2|t"
W.ARROW_DOWN = " |TInterface\\Buttons\\Arrow-Down-Up:12:12:0:2|t"

-- small tinted colour square for legends: W.Swatch(r, g, b) or W.Swatch(colorTable)
function W.Swatch(r, g, b)
  if type(r) == "table" then
    r, g, b = r[1], r[2], r[3]
  end
  return ("|TInterface\\Buttons\\WHITE8x8:8:8:0:0:8:8:0:8:0:8:%d:%d:%d|t"):format(r * 255, g * 255, b * 255)
end

-- compact money: "1,234g 56s" / "56s 7c" / "7c", with coloured unit letters
local function commas(n)
  local s = tostring(n)
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end
-- a whole number with thousands separators: 12345 -> "12,345"
function W.Thousands(n)
  return commas(math.floor((n or 0) + 0.5))
end

-- Money: each unit in its coin's colour, number and letter together ("12g" gold, "34s" silver, "5c" copper), so
-- amounts read at a glance. Every gold amount in AME goes through here.
W.COIN_HEX = { g = "ffd100", s = "c7c7cf", c = "eda55f" }
local function coin(n, unit)
  return "|cff" .. W.COIN_HEX[unit] .. n .. unit .. "|r"
end

function W.Money(copper, short)
  if not copper then
    return W.NONE
  end
  copper = math.floor(copper + 0.5)
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  -- short (narrow columns): whole gold from 100g up, rounded; below that silver still matters (2g 98s, not 2g).
  -- Zero lower units are left out: "18s", not "18s 0c".
  if g >= 1000 or (short and g >= 100) then
    return coin(commas(math.floor(copper / 10000 + 0.5)), "g")
  elseif g > 0 then
    if s == 0 then
      return coin(commas(g), "g")
    end
    return coin(commas(g), "g") .. " " .. coin(s, "s")
  elseif s > 0 then
    if c == 0 then
      return coin(s, "s")
    end
    return coin(s, "s") .. " " .. coin(c, "c")
  end
  return coin(c, "c")
end

-- Quantities, abbreviated when large: 950, 1k, 4.5k, 12k, 1.2M (exact numbers stay in exports and tooltips' detail)
function W.Count(n)
  if not n then
    return W.NONE
  end
  n = math.floor(n + 0.5)
  local a = math.abs(n)
  local out
  if a < 1000 then
    return tostring(n)
  elseif a < 10000 then
    out = ("%.1fk"):format(n / 1000)
  elseif a < 1000000 then
    out = ("%dk"):format(math.floor(n / 1000 + 0.5))
  else
    out = ("%.1fM"):format(n / 1000000)
  end
  return (out:gsub("%.0([kM])", "%1"))
end

-- profit / loss: green "+12g", red "-3g 5s", "-" for nothing
function W.SignedMoney(v)
  if not v then
    return W.NONE
  end
  if v < 0 then
    return W.Color("bad", "-") .. W.Money(-v, true)
  end
  return W.Color("good", "+") .. W.Money(v, true)
end

function W.Percent(x, decimals)
  if not x then
    return W.NONE
  end
  local c = x > 0.0005 and W.COLORS.up or x < -0.0005 and W.COLORS.down or W.COLORS.dim
  return ("|cff%02x%02x%02x%+." .. (decimals or 1) .. "f%%|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, x * 100)
end

local SIGNALS = {
  buy = { "good", L["BUY"] },
  sell = { "bad", L["SELL"] },
  hold = { "hold", L["HOLD"] },
  wait = { "wait", L["WAIT"] },
  vendor = { "vendor", L["VENDOR"] },
}
function W.Signal(signal)
  local s = SIGNALS[signal]
  return s and W.Color(s[1], s[2]) or W.NONE
end

-- signals are never colour alone: a glyph in front of the word (plain characters every game font has)
W.SIGNAL_GLYPH = { buy = "+", sell = "-", hold = "=", wait = "~", vendor = "$" }
function W.SignalGlyph(signal)
  local s = SIGNALS[signal]
  return s and W.Color(s[1], W.SIGNAL_GLYPH[signal] .. " " .. s[2]) or W.NONE
end

-- item name/icon/quality colour; may be nil until the client has cached the item (call again after load)
function W.ItemInfo(itemID)
  local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local name, link, quality, _, _, _, _, _, _, icon = getInfo(itemID)
  if not icon and C_Item and C_Item.GetItemIconByID then
    icon = C_Item.GetItemIconByID(itemID)
  end
  return name, link, quality, icon
end

-- text in an item quality's colour (white without one)
function W.QualityText(quality, text)
  local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
  return (color and color.hex or "|cffffffff") .. text .. "|r"
end

-- run fn once item data is cached
function W.OnItemLoaded(itemID, fn)
  if Item and Item.CreateFromItemID then
    local item = Item:CreateFromItemID(itemID)
    if item and not item:IsItemEmpty() then
      item:ContinueOnItemLoad(fn)
      return
    end
  end
  fn()
end

-- gradient across a texture; orientation "VERTICAL" (from = bottom) or "HORIZONTAL" (from = left)
function W.Gradient(t, orientation, from, to)
  t:SetColorTexture(1, 1, 1, 1)
  if CreateColor and t.SetGradient then
    local ok = pcall(t.SetGradient, t, orientation, CreateColor(unpack(from)), CreateColor(unpack(to)))
    if ok then
      return
    end
  end
  if t.SetGradientAlpha then
    t:SetGradientAlpha(orientation, from[1], from[2], from[3], from[4], to[1], to[2], to[3], to[4])
  else
    t:SetColorTexture(to[1], to[2], to[3], (from[4] + to[4]) / 2)
  end
end

-- soft inner glow along a frame's edges (fades inward) plus a faint top highlight; recolour with W.TintInnerGlow
function W.InnerGlow(frame, color, size)
  size = size or 18
  local function tex()
    local t = frame:CreateTexture(nil, "BORDER")
    return t
  end
  local top, bottom, left, right = tex(), tex(), tex(), tex()
  top:SetPoint("TOPLEFT", 1, -1)
  top:SetPoint("TOPRIGHT", -1, -1)
  top:SetHeight(size)
  bottom:SetPoint("BOTTOMLEFT", 1, 1)
  bottom:SetPoint("BOTTOMRIGHT", -1, 1)
  bottom:SetHeight(size)
  left:SetPoint("TOPLEFT", 1, -1)
  left:SetPoint("BOTTOMLEFT", 1, 1)
  left:SetWidth(size)
  right:SetPoint("TOPRIGHT", -1, -1)
  right:SetPoint("BOTTOMRIGHT", -1, 1)
  right:SetWidth(size)
  frame.glowEdges = { top = top, bottom = bottom, left = left, right = right }
  W.TintInnerGlow(frame, color)
  local hl = frame:CreateTexture(nil, "BORDER", nil, 1)
  hl:SetPoint("TOPLEFT", 1, -1)
  hl:SetPoint("TOPRIGHT", -1, -1)
  hl:SetHeight(1)
  hl:SetColorTexture(1, 1, 1, 0.08)
end

function W.TintInnerGlow(frame, color)
  local e = frame.glowEdges
  if not e then
    return
  end
  local c = color or W.COLORS.accent
  local edge, clear = { c[1], c[2], c[3], 0.1 }, { c[1], c[2], c[3], 0 }
  W.Gradient(e.top, "VERTICAL", clear, edge)
  W.Gradient(e.bottom, "VERTICAL", edge, clear)
  W.Gradient(e.left, "HORIZONTAL", edge, clear)
  W.Gradient(e.right, "HORIZONTAL", clear, edge)
end

-- Flat dropdown selector. options = { { value, label, colorHex? }, ... }; onSelect(value, option).
-- The button shows the current choice and is highlighted when another option than the default is picked (a filter
-- that is on). opts: neutral = never highlighted (a plain choice), default = the default option's value (first
-- option otherwise; also the initial choice). Set the choice with b:SetValue(value); b:Reset() goes back to the
-- default; b.values is the option list.
function W.Dropdown(parent, width, options, onSelect, opts)
  opts = opts or {}
  local b = W.Button(parent, "", width, 20)
  b.neutral = opts.neutral or false
  b.values = options
  b.label:ClearAllPoints()
  b.label:SetPoint("LEFT", 8, 0)
  b.label:SetPoint("RIGHT", -18, 0)
  b.label:SetJustifyH("LEFT")
  b.arrow = b:CreateTexture(nil, "OVERLAY")
  b.arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
  b.arrow:SetSize(12, 12)
  b.arrow:SetPoint("RIGHT", -4, -2)

  local function text(o)
    return o[3] and ("|c%s%s|r"):format(o[3], o[2]) or o[2]
  end

  local ROW = 18
  local menu = CreateFrame("Frame", nil, b, "BackdropTemplate")
  W.Skin(menu, W.COLORS.bg)
  menu:SetFrameStrata("DIALOG")
  menu:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
  menu:Hide()
  menu.items = {}

  -- (re)build the option rows; options can change later via b:SetOptions
  local function build()
    for i, o in ipairs(options) do
      local it = menu.items[i]
      if not it then
        it = CreateFrame("Button", nil, menu)
        it:SetSize(width - 6, ROW)
        it:SetPoint("TOPLEFT", 3, -3 - (i - 1) * ROW)
        it.hl = it:CreateTexture(nil, "HIGHLIGHT")
        it.hl:SetAllPoints()
        W.Fill(it.hl, W.COLORS.rowHover)
        it.sel = it:CreateTexture(nil, "BACKGROUND")
        it.sel:SetAllPoints()
        it.text = W.Text(it, "GameFontHighlightSmall")
        it.text:SetPoint("LEFT", 6, 0)
        menu.items[i] = it
      end
      it.text:SetText(text(o))
      it:SetScript("OnClick", function()
        b:SetIndex(i)
        menu:Hide()
        onSelect(o[1], o)
      end)
      it:Show()
    end
    for i = #options + 1, #menu.items do
      menu.items[i]:Hide()
    end
    menu:SetSize(width, #options * ROW + 6)
  end
  build()
  -- close when clicking anywhere else
  menu:SetScript("OnShow", function(self)
    local a = W.COLORS.rowSelected
    for i, it in ipairs(self.items) do
      if i > #options then
        break
      end
      it.sel:SetColorTexture(a[1], a[2], a[3], i == b.index and a[4] or 0)
    end
    pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN")
  end)
  menu:SetScript("OnHide", function(self)
    pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN")
  end)
  menu:SetScript("OnEvent", function(self)
    if not self:IsMouseOver() and not b:IsMouseOver() then
      self:Hide()
    end
  end)
  b:SetScript("OnClick", function()
    menu:SetShown(not menu:IsShown())
  end)

  -- index of the option whose value is `value` (nil if none)
  local function find(value)
    for i, o in ipairs(options) do
      if o[1] == value then
        return i
      end
    end
  end

  function b:SetOptions(newOptions)
    options = newOptions
    self.values = newOptions
    self.defaultIndex = opts.default ~= nil and find(opts.default) or 1
    build()
  end

  -- select the option whose value is `value` (first option if none)
  function b:SetValue(value)
    self:SetIndex(find(value) or 1)
  end

  -- back to the default option
  function b:Reset()
    self:SetIndex(self.defaultIndex)
  end

  function b:SetIndex(i)
    self.index = i
    self.label:SetText(options[i] and text(options[i]) or "")
    self:SetSelected(not self.neutral and i ~= self.defaultIndex)
  end
  b.menu = menu
  b.defaultIndex = opts.default ~= nil and find(opts.default) or 1
  b:Reset()
  return b
end

-- Flat close button: an X drawn from two rotated bars; dim, red on hover. onClick defaults to hiding the parent.
function W.CloseButton(parent, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(22, 22)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.bg:SetColorTexture(1, 1, 1, 0)
  b.bars = {}
  for i, angle in ipairs({ math.pi / 4, -math.pi / 4 }) do
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(1, 1, 1, 1)
    t:SetSize(12, 1.5)
    t:SetPoint("CENTER")
    t:SetRotation(angle)
    t:SetVertexColor(0.65, 0.67, 0.7, 1)
    b.bars[i] = t
  end
  b:SetScript("OnEnter", function(self)
    self.bg:SetColorTexture(1, 0.3, 0.25, 0.18)
    for _, t in ipairs(self.bars) do
      t:SetVertexColor(1, 0.45, 0.4, 1)
    end
  end)
  b:SetScript("OnLeave", function(self)
    self.bg:SetColorTexture(1, 1, 1, 0)
    for _, t in ipairs(self.bars) do
      t:SetVertexColor(0.65, 0.67, 0.7, 1)
    end
  end)
  b:SetScript("OnClick", function()
    if onClick then
      onClick()
    else
      parent:Hide()
    end
  end)
  return b
end

-- Flat text input matching the buttons: panel background, padded text, accent border while focused.
--   W.Input(parent, {
--     width = 120, height = 20,
--     hint = "Search...",                  -- dim placeholder while empty (box:SetHint to change it)
--     numeric = true,
--     onChange = function(text, value, user) end, -- value = tonumber(text); user = typed (not SetText)
--     onEnter = function(box) end,         -- Enter (default: drop focus)
--     clearOnEscape = true,                -- Escape empties the box (it always drops focus)
--     onEscape = function(box) end,        -- after that
--   })
-- The input owns OnTextChanged / OnEnterPressed / OnEscapePressed; set behaviour through opts, not SetScript.
function W.Input(parent, opts)
  opts = opts or {}
  local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
  W.Skin(box, W.COLORS.panel)
  box:SetFontObject("GameFontHighlightSmall")
  box:SetTextInsets(6, 6, 0, 0)
  box:SetAutoFocus(false)
  if opts.width then
    box:SetWidth(opts.width)
  end
  box:SetHeight(opts.height or 20)
  if opts.numeric then
    box:SetNumeric(true)
  end
  box.hint = false
  box.SetHint = W.InputHint
  if opts.hint then
    box:SetHint(opts.hint)
  end
  box:HookScript("OnEditFocusGained", function(self)
    local a, c = W.COLORS.accent, W.COLORS.panel
    self:SetBackdropBorderColor(a[1], a[2], a[3], 0.7)
    self:SetBackdropColor(c[1], c[2], c[3], c[4])
  end)
  box:HookScript("OnEditFocusLost", function(self)
    local b = W.COLORS.border
    self:SetBackdropBorderColor(b[1], b[2], b[3], b[4])
  end)
  box:HookScript("OnEnter", function(self)
    if not self:HasFocus() then
      local c = W.COLORS.panelHover
      self:SetBackdropColor(c[1], c[2], c[3], c[4])
    end
  end)
  box:HookScript("OnLeave", function(self)
    if not self:HasFocus() then
      local c = W.COLORS.panel
      self:SetBackdropColor(c[1], c[2], c[3], c[4])
    end
  end)
  box:SetScript("OnTextChanged", function(self, user)
    local text = self:GetText() or ""
    if self.hint then
      self.hint:SetShown(text == "")
    end
    if opts.onChange then
      opts.onChange(text, tonumber(text), user)
    end
  end)
  box:SetScript("OnEnterPressed", function(self)
    if opts.onEnter then
      opts.onEnter(self)
    else
      self:ClearFocus()
    end
  end)
  box:SetScript("OnEscapePressed", function(self)
    if opts.clearOnEscape then
      self:SetText("")
    end
    self:ClearFocus()
    if opts.onEscape then
      opts.onEscape(self)
    end
  end)
  return box
end

-- placeholder text shown while an input is empty (clipped to the box: translations run longer)
function W.InputHint(box, text)
  if not box.hint then
    box.hint = W.Text(box, "GameFontDisableSmall")
    box.hint:SetPoint("LEFT", 6, 0)
    box.hint:SetPoint("RIGHT", -6, 0)
    box.hint:SetWordWrap(false)
  end
  box.hint:SetText(text)
  box.hint:SetShown((box:GetText() or "") == "")
end

-- whole-gold input with a hint ("min g"); onChange(gold or nil, user)
function W.GoldInput(parent, hint, onChange)
  return W.Input(parent, {
    width = 64,
    numeric = true,
    hint = hint,
    onChange = function(_, value, user)
      onChange(value, user)
    end,
  })
end

W.STAR = "Interface\\Common\\FavoritesIcon"

-- Watchlist star: the auction house's own favourite star (atlas) when the client has it, else a file texture.
-- Empty stars stay clearly visible (not just a faint ghost) and light up on hover.
local FAV_ON, FAV_OFF = "auctionhouse-icon-favorite", "auctionhouse-icon-favorite-off"
local function hasAtlas(name)
  return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

function W.SetStar(tex, on, hot)
  if hasAtlas(FAV_ON) then
    local off = hasAtlas(FAV_OFF)
    tex:SetAtlas(on and FAV_ON or (off and FAV_OFF or FAV_ON))
    tex:SetDesaturated(not on and not off)
    tex:SetAlpha(on and 1 or (hot and 1 or 0.6))
  else
    tex:SetTexture(W.STAR)
    tex:SetDesaturated(not on)
    tex:SetAlpha(on and 1 or (hot and 0.9 or 0.45))
  end
end

-- inline star for text (sidebar list names)
function W.StarInline(size)
  size = size or 12
  if hasAtlas(FAV_ON) then
    return ("|A:%s:%d:%d|a"):format(FAV_ON, size, size)
  end
  return ("|T%s:%d:%d|t"):format(W.STAR, size, size)
end

-- Shared popup menu: W.Menu(anchor, entries); entry = { text, checked = bool?, func = fn, disabled = bool? }.
-- One menu frame for the whole addon; closes on a pick or a click elsewhere.
local menu
-- opts.refresh: update a menu already open on this anchor instead of toggling it (live suggestions)
function W.Menu(anchor, entries, opts)
  if not menu then
    menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    W.Skin(menu, W.COLORS.bg)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu.items = {}
    menu:SetScript("OnShow", function(self)
      pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN")
    end)
    menu:SetScript("OnHide", function(self)
      pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN")
    end)
    menu:SetScript("OnEvent", function(self)
      if not self:IsMouseOver() and not (self.anchor and self.anchor:IsMouseOver()) then
        self:Hide()
      end
    end)
    -- the menu lives on the whole screen: close it when what opened it goes away (another tab, the window closed)
    menu:SetScript("OnUpdate", function(self)
      local a = self.anchor
      if not (a and a.IsVisible and a:IsVisible()) then
        self:Hide()
      end
    end)
    W.menu = menu
  end
  if menu:IsShown() and menu.anchor == anchor and not (opts and opts.refresh) then
    menu:Hide()
    return menu
  end
  local ROW, width = 18, 140
  for i, e in ipairs(entries) do
    local it = menu.items[i]
    if not it then
      it = CreateFrame("Button", nil, menu)
      it:SetHeight(ROW)
      it:SetPoint("TOPLEFT", 3, -3 - (i - 1) * ROW)
      it:SetPoint("RIGHT", -3, 0)
      it.hl = it:CreateTexture(nil, "HIGHLIGHT")
      it.hl:SetAllPoints()
      W.Fill(it.hl, W.COLORS.rowHover)
      it.check = it:CreateTexture(nil, "ARTWORK")
      it.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
      it.check:SetSize(14, 14)
      it.check:SetPoint("LEFT", 2, 0)
      it.text = W.Text(it, "GameFontHighlightSmall")
      it.text:SetPoint("LEFT", 20, 0)
      menu.items[i] = it
    end
    it.text:SetText(e.text)
    it.text:SetTextColor(e.disabled and 0.5 or 1, e.disabled and 0.5 or 1, e.disabled and 0.5 or 1)
    it.check:SetShown(e.checked == true)
    it:SetScript("OnClick", function()
      menu:Hide()
      if e.func and not e.disabled then
        e.func()
      end
    end)
    it:Show()
    width = math.max(width, (it.text:GetStringWidth() or 0) + 34)
  end
  for i = #entries + 1, #menu.items do
    menu.items[i]:Hide()
  end
  menu.anchor = anchor
  menu:SetSize(width, #entries * ROW + 6)
  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  menu:Show()
  return menu
end

-- Flat checkbox with a label; onToggle(checked)
function W.Check(parent, label, onToggle)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(16, 16)
  b.box = CreateFrame("Frame", nil, b, "BackdropTemplate")
  b.box:SetAllPoints()
  W.Skin(b.box, W.COLORS.panel)
  -- ticked: an accent-coloured square inside the box
  -- on the box frame: a child frame draws over its parent's own textures, so a mark on the button would be hidden
  b.mark = b.box:CreateTexture(nil, "OVERLAY")
  b.mark:SetPoint("TOPLEFT", 4, -4)
  b.mark:SetPoint("BOTTOMRIGHT", -4, 4)
  b.label = W.Text(b, "GameFontHighlightSmall")
  b.label:SetPoint("LEFT", b, "RIGHT", 5, 0)
  b.label:SetText(label)
  function b:SetChecked(on)
    self.checked = on and true or false
    self.mark:SetShown(self.checked)
    local accent = W.COLORS.accent
    self.mark:SetColorTexture(accent[1], accent[2], accent[3], 1)
    local a = self.checked and accent or W.COLORS.border
    self.box:SetBackdropBorderColor(a[1], a[2], a[3], self.checked and 0.8 or a[4])
  end
  b:SetScript("OnClick", function(self)
    self:SetChecked(not self.checked)
    if onToggle then
      onToggle(self.checked)
    end
  end)
  b:SetChecked(false)
  W.checks[b] = true
  return b
end

-- close the shared menu if it's open on this anchor (or any anchor when nil)
function W.HideMenu(anchor)
  local m = W.menu
  if m and m:IsShown() and (anchor == nil or m.anchor == anchor) then
    m:Hide()
  end
end

-- estimated units sold per day: "~350/d", "~4.5/d", "-"
function W.Rate(perDay)
  if not perDay then
    return W.NONE
  end
  if perDay >= 10 or perDay < 0.05 then -- "~0/d", not "~0.0/d": nothing measurably sells
    return ("~%d/d"):format(math.floor(perDay + 0.5))
  end
  return ("~%.1f/d"):format(perDay)
end

-- A scrolling area that fills its parent. Put the content in pane.content (as wide as the pane); its height is
-- measured from what's in it when shown or resized (pane:Measure() after changing it). The mouse wheel scrolls, and a
-- thin bar shows where you are when the content is taller than the pane.
function W.ScrollPane(parent)
  local pane = CreateFrame("ScrollFrame", nil, parent)
  pane:SetAllPoints()
  local content = CreateFrame("Frame", nil, pane)
  content:SetSize(1, 1)
  pane:SetScrollChild(content)
  pane.content = content
  local bar = pane:CreateTexture(nil, "OVERLAY")
  bar:SetColorTexture(1, 1, 1, 0.25)
  bar:SetWidth(4)
  bar:Hide()

  function pane:Range()
    return math.max(0, (content:GetHeight() or 0) - (self:GetHeight() or 0))
  end

  function pane:SetScroll(y)
    local max, viewH = self:Range(), self:GetHeight() or 0
    y = math.max(0, math.min(max, y or 0))
    self:SetVerticalScroll(y)
    bar:SetShown(max > 0)
    if max > 0 then
      local h = math.max(20, viewH * viewH / (viewH + max))
      bar:SetHeight(h)
      bar:ClearAllPoints()
      bar:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -(viewH - h) * y / max)
    end
  end

  -- the content's height: down to the lowest shown child or text, plus a margin
  function pane:Measure()
    local top = content:GetTop()
    if not top then
      return
    end
    local bottom = top
    -- shown children and texts, and theirs (columns hold sections), a few levels down
    local function scan(frame, depth)
      for _, list in ipairs({ { frame:GetChildren() }, { frame:GetRegions() } }) do
        for _, obj in ipairs(list) do
          if obj.IsShown and obj:IsShown() then
            local b = obj.GetBottom and obj:GetBottom()
            if type(b) == "number" and b < bottom then
              bottom = b
            end
            if depth > 1 and obj.GetChildren then
              scan(obj, depth - 1)
            end
          end
        end
      end
    end
    scan(content, 3)
    content:SetHeight(math.max(1, top - bottom + 12))
    self:SetScroll(self:GetVerticalScroll() or 0)
  end

  pane:SetScript("OnSizeChanged", function(self, w)
    content:SetWidth(math.max(1, (w or 0) - 8))
    self:Measure()
  end)
  pane:SetScript("OnShow", function(self)
    self:Measure()
  end)
  pane:EnableMouseWheel(true)
  pane:SetScript("OnMouseWheel", function(self, delta)
    self:SetScroll((self:GetVerticalScroll() or 0) - delta * 40)
  end)
  return pane
end

-- section heading at a position in a panel
function W.Heading(parent, text, x, y)
  local h = W.Text(parent, "GameFontNormal")
  h:SetPoint("TOPLEFT", x, y)
  h:SetText(text)
  return h
end

-- A short fixed list of text rows with buttons on the right (people, requests). Anchor the returned frame.
--   local list = W.RowList(parent, {
--     rows = 5, rowHeight = 20, width = 460,
--     buttons = { { key = "block", label = "Block", width = 50, onClick = function(item, row) end,
--                   shown = function(item) return true end }, ... },   -- left to right; key = "remove",
--                                                                       -- close = true: a small X instead
--     state = true,       -- row.state: dim right-aligned text before the buttons
--     empty = "No one",   -- dim text in the first row when the list is empty (else nothing shows)
--     more = "+ %d more", -- a line under the rows when items don't fit
--   })
--   list:SetItems(items, function(row, item) row.text:SetText(item.name) end)
-- list.rows[i] has .text, .item, .name (item.name) and each button under its key.
function W.RowList(parent, opts)
  local n, h, width = opts.rows or 5, opts.rowHeight or 20, opts.width or 460
  local list = CreateFrame("Frame", nil, parent)
  list:SetSize(width, n * h)
  list.rows = {}
  local defs = opts.buttons or {}
  for i = 1, n do
    local row = CreateFrame("Frame", nil, list)
    row:SetSize(width, h)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * h)
    row.item, row.name, row.state = false, false, false
    row.buttons = {}
    local right -- the leftmost button so far (buttons are placed right to left)
    for k = #defs, 1, -1 do
      local d = defs[k]
      local function click()
        if row.item then
          d.onClick(row.item, row)
        end
      end
      local b
      if d.close then
        b = W.CloseButton(row, click)
        b:SetSize(18, 18)
      else
        b = W.Button(row, d.label, d.width or 60, 18, click)
      end
      if right then
        b:SetPoint("RIGHT", right, "LEFT", -6, 0)
      else
        b:SetPoint("RIGHT", 0, 0)
      end
      right = b
      row[d.key], row.buttons[k] = b, b
    end
    row.text = W.Text(row, "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 0, 0)
    row.text:SetWordWrap(false)
    if opts.state then
      row.state = W.Text(row, "GameFontDisableSmall", "RIGHT")
      if right then
        row.state:SetPoint("RIGHT", right, "LEFT", -12, 0)
      else
        row.state:SetPoint("RIGHT", 0, 0)
      end
    elseif right then
      row.text:SetPoint("RIGHT", right, "LEFT", -6, 0)
    end
    list.rows[i] = row
  end
  list.more = W.Text(list, "GameFontDisableSmall")
  list.more:SetPoint("TOPLEFT", 0, -n * h)

  function list:SetItems(items, fill)
    for i, row in ipairs(self.rows) do
      local item = items[i]
      row.item, row.name = item or false, item and item.name or false
      local empty = i == 1 and #items == 0 and opts.empty
      row:SetShown(item ~= nil or empty and true or false)
      for k, d in ipairs(defs) do
        row.buttons[k]:SetShown(item ~= nil and (not d.shown or d.shown(item)))
      end
      if row.state then
        row.state:SetText("")
      end
      if item then
        fill(row, item)
      elseif empty then
        row.text:SetText(W.Dim(opts.empty))
      end
    end
    self.more:SetText(opts.more and #items > n and opts.more:format(#items - n) or "")
  end
  return list
end

-- Popups (StaticPopup). The dialog is registered under id on first use; arg fills a %s in text, data is handed
-- back to onAccept.
local function popup(id, text, accept, extra)
  local d = StaticPopupDialogs[id]
  if not d then
    d = {
      text = text,
      button1 = accept,
      button2 = CANCEL or L["Cancel"],
      OnAccept = function(dialog, data)
        StaticPopupDialogs[id].accepted(dialog, data)
      end,
      timeout = 0,
      whileDead = true,
      hideOnEscape = true,
      preferredIndex = 3,
    }
    for k, v in pairs(extra or {}) do
      d[k] = v
    end
    StaticPopupDialogs[id] = d
  end
  return d
end

-- yes / no: onAccept(data)
function W.Confirm(id, text, accept, onAccept, arg, data)
  popup(id, text, accept or ACCEPT or L["Accept"]).accepted = function(_, d)
    onAccept(d)
  end
  StaticPopup_Show(id, arg, nil, data)
end

-- ask for a line of text: onAccept(text, data) on Accept or Enter
function W.Prompt(id, text, onAccept, data)
  popup(id, text, ACCEPT or L["Accept"], {
    hasEditBox = true,
    EditBoxOnEnterPressed = function(box)
      local dialog = box:GetParent()
      StaticPopupDialogs[id].OnAccept(dialog, dialog.data)
      dialog:Hide()
    end,
  }).accepted = function(
    dialog,
    d
  )
    local box = dialog and (dialog.editBox or dialog.EditBox)
    onAccept(box and box:GetText(), d)
  end
  StaticPopup_Show(id, nil, nil, data)
end

-- The status line along the bottom of a tab (counts, hints); join its parts with W.SEP.
W.SEP = "  ·  "
function W.StatusLine(parent)
  local s = W.Text(parent, "GameFontDisableSmall", "LEFT")
  s:SetPoint("BOTTOMLEFT", 0, 0)
  s:SetPoint("BOTTOMRIGHT", -(ns.UI and ns.UI.FOOTER_SPACE or 0), 0) -- the version sits at the right end
  s:SetWordWrap(false)
  return s
end

-- explanatory paragraph: dim, wrapped at width (440 by default); position it yourself
function W.Paragraph(parent, text, width)
  local t = W.Text(parent, "GameFontDisableSmall")
  t:SetWidth(width or 440)
  t:SetSpacing(2)
  t:SetText(text)
  return t
end

-- explanatory paragraph under an anchor
function W.Note(parent, anchor, text, width)
  local t = W.Paragraph(parent, text, width)
  t:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
  return t
end

-- A label before a control (dropdown, input): returns the label; position the label and the control follows,
-- gap px after the text, or at labelWidth from the label's start (controls line up across rows).
function W.Labeled(parent, text, control, gap, labelWidth)
  local label = W.Text(parent, "GameFontHighlightSmall")
  label:SetText(text)
  control:ClearAllPoints()
  if labelWidth then
    control:SetPoint("LEFT", label, "LEFT", labelWidth, 0)
  else
    control:SetPoint("LEFT", label, "RIGHT", gap or 6, 0)
  end
  return label
end

-- a check bound to a setting
function W.SettingCheck(parent, label, key, x, y, onChange)
  local c = W.Check(parent, label, function(on)
    ns.Settings:Set(key, on)
    if onChange then
      onChange(on)
    end
  end)
  c:SetPoint("TOPLEFT", x, y)
  c.key = key
  return c
end

-- how long ago a server time was: "just now", "5 min ago", "3 h ago", "2 days ago"; "never" without one
function W.Ago(t, now)
  if not t then
    return L["never"]
  end
  local d = math.max(0, now - t)
  if d < 60 then
    return L["just now"]
  elseif d < 3600 then
    return L["%d min ago"]:format(d / 60)
  elseif d < 86400 then
    return L["%d h ago"]:format(d / 3600)
  end
  return L["%d days ago"]:format(d / 86400)
end

-- how long ago a day number was: "today", "yesterday", "3 days ago" (nil without both days)
function W.DaysAgo(day, today)
  if not (day and today) then
    return nil
  end
  local d = today - day
  if d <= 0 then
    return L["today"]
  elseif d == 1 then
    return L["yesterday"]
  end
  return L["%d days ago"]:format(d)
end

-- expected time to sell: "<1h", "~5h", "~2 days", "a week+"
function W.Hours(h)
  if not h then
    return L["a week+"]
  elseif h < 1 then
    return L["<1h"]
  elseif h < 36 then
    return L["~%dh"]:format(math.floor(h + 0.5))
  end
  return L["~%d days"]:format(math.floor(h / 24 + 0.5))
end

-- one posting suggestion (Pricing.Suggest's quick / normal / patient): "12s 5c (~3h)"
function W.PostChoice(choice)
  return W.Money(choice.price) .. " " .. W.Dim("(" .. W.Hours(choice.hours) .. ")")
end

-- the whole suggestion on one line
function W.PostAdvice(advice)
  if not advice then
    return W.Dim(L["Posting price: not enough data on this item yet."])
  end
  local head = W.Confidence(advice.confidence) .. " " .. W.Color("gold", L["Post at"])
  local parts
  if advice.quick.price == advice.patient.price then
    -- one price fits all three: say why instead of repeating it
    parts = { head, W.PostChoice(advice.normal) }
    if advice.normal.ahead == 0 and (advice.book and #advice.book.prices or 0) > 0 then
      parts[#parts + 1] = W.Dim(L["more is listed than sells in one listing time: only the lowest price sells soon"])
    end
  else
    parts = {
      head,
      L["Quick %s"]:format(W.PostChoice(advice.quick)),
      L["Normal %s"]:format(W.PostChoice(advice.normal)),
      L["Patient %s"]:format(W.PostChoice(advice.patient)),
      L["%d ahead"]:format(advice.normal.ahead),
    }
  end
  local text = table.concat(parts, "   ")
  if advice.hold then
    text = text .. "   " .. W.Color("bad", L["unlikely to sell soon: consider holding"])
  elseif advice.cheap then
    text = text .. "   " .. W.Color("warn", L["well below its usual price"])
  end
  return text
end

-- data confidence as three small bars (textures, not font glyphs): high = 3 green, medium = 2 amber, low = 1 red
local CONFIDENCE = {
  high = { 3, W.COLORS.up },
  medium = { 2, { 1, 0.8, 0.2 } },
  low = { 1, W.COLORS.down },
}
function W.Confidence(level)
  local c = CONFIDENCE[level] or CONFIDENCE.low
  local out = {}
  for i = 1, 3 do
    local col = i <= c[1] and c[2] or { 0.35, 0.35, 0.38 }
    out[i] = ("|TInterface\\Buttons\\WHITE8x8:%d:3:0:0:8:8:0:8:0:8:%d:%d:%d|t"):format(
      4 + i * 2,
      col[1] * 255,
      col[2] * 255,
      col[3] * 255
    )
  end
  return table.concat(out, " ")
end
