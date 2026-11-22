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
  -- the charts' colours by what they show (data colours: they don't follow the theme)
  chart = {
    market = { 0.302, 0.851, 0.784, 1 }, -- the market price, and the Overview's index (#4dd9c8)
    lowest = { 0.498, 0.863, 0.541, 0.9 }, -- the cheapest listing (#7fdc8a)
    average = { 1, 0.8, 0.2, 1 }, -- the 7-day average (#ffcc33)
    fast = { 0.78, 0.55, 1, 1 }, -- MA 20
    supply = { 0.435, 0.455, 0.537, 1 }, -- units listed (#6f7489)
    vendor = { 0.85, 0.85, 0.85, 0.85 }, -- what a vendor pays
    bought = { 0.35, 0.65, 1, 1 }, -- your trades
    sold = { 1, 0.45, 0.85, 1 },
    bg = { 0.07, 0.08, 0.1, 1 }, -- behind the plot
    legendBg = { 0.06, 0.07, 0.09, 0.85 },
    legendBorder = { 1, 1, 1, 0.08 },
  },
}

-- Text colours by role ("RRGGBB"), and helpers for |c escapes (defined in Init.lua so chat lines can use them too)
W.HEX = ns.HEX

-- Colour-blind friendly palette (Settings): gains / buy in blue, losses / sell in orange (Okabe-Ito), so the two
-- never rely on red vs green. Applied to the text roles and the chart's up / down colours.
local PALETTES = {
  normal = { good = "4dd973", bad = "ff6159", up = { 0.3, 0.85, 0.45, 1 }, down = { 1, 0.38, 0.35, 1 } },
  colorBlind = { good = "56b4e9", bad = "e69f00", up = { 0.34, 0.71, 0.91, 1 }, down = { 0.9, 0.62, 0, 1 } },
}
W.PALETTES = PALETTES

-- WCAG contrast ratio of two "RRGGBB" colours (1 to 21; text needs 4.5, large text 3)
function W.Contrast(a, b)
  local function luminance(hex)
    local l = 0
    for i, weight in ipairs({ 0.2126, 0.7152, 0.0722 }) do
      local c = tonumber(hex:sub(i * 2 - 1, i * 2), 16) / 255
      c = c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
      l = l + weight * c
    end
    return l
  end
  local la, lb = luminance(a), luminance(b)
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05)
end
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

-- Selected buttons are a dark tint of the accent with the full accent as the border. Dark enough that a primary
-- button (the accent as bright as white text allows) still looks different next to one: gold can't get much
-- brighter than half strength behind white text, so selected stays well under that.
W.SELECTED_SHADE = 0.35

-- Primary buttons (a panel's main action) are filled with the accent, as bright as it can be with a white label
-- still readable on it: 5:1 at rest, and the hover a little lighter, still 4.5:1 (WCAG AA). Full-strength Horde red
-- behind white is about 3.9:1, so each theme's accent is darkened by just what it needs.
W.PRIMARY_CONTRAST, W.PRIMARY_HOVER_CONTRAST = 5, 4.5

local function hexOf(c)
  return W.Hex(c):sub(3)
end

-- the accent darkened until white text on it reaches `ratio`
function W.PrimaryShade(c, ratio)
  for step = 100, 0, -1 do
    local f = step / 100
    local shaded = { c[1] * f, c[2] * f, c[3] * f, 1 }
    if W.Contrast(hexOf(shaded), "ffffff") >= ratio then
      return shaded
    end
  end
  return { 0, 0, 0, 1 }
end

local function setAccent(c)
  W.COLORS.accent = { c[1], c[2], c[3], 1 }
  W.COLORS.selected = { c[1] * W.SELECTED_SHADE, c[2] * W.SELECTED_SHADE, c[3] * W.SELECTED_SHADE, 1 }
  W.COLORS.rowSelected = { c[1], c[2], c[3], 0.2 }
  W.COLORS.primary = W.PrimaryShade(c, W.PRIMARY_CONTRAST)
  W.COLORS.primaryHover = W.PrimaryShade(c, W.PRIMARY_HOVER_CONTRAST)
  W.TintMadeTag(c)
end

-- Source tags (where a material comes from, W.Tag): { fill, text } by kind. The AH in amber, made in the queue in a
-- tint of the theme's accent, the rest plain. What's in your bags gets no tag.
W.COLORS.tag = {
  other = { { 0.137, 0.153, 0.184, 1 }, { 0.81, 0.8, 0.78, 1 } },
  vendor = { { 0.137, 0.153, 0.184, 1 }, { 0.81, 0.8, 0.78, 1 } },
  ah = { { 0.227, 0.165, 0.102, 1 }, { 1, 0.8, 0.2, 1 } },
}
W.TAG_TINT, W.TAG_LIGHTEN = 0.25, 0.75
function W.TintMadeTag(c)
  W.COLORS.tag.made = {
    { c[1] * W.TAG_TINT, c[2] * W.TAG_TINT, c[3] * W.TAG_TINT, 1 },
    { c[1] + (1 - c[1]) * W.TAG_LIGHTEN, c[2] + (1 - c[2]) * W.TAG_LIGHTEN, c[3] + (1 - c[3]) * W.TAG_LIGHTEN, 1 },
  }
end
W.TintMadeTag(W.COLORS.accent)
W.tags = setmetatable({}, { __mode = "k" }) -- every W.Tag, for re-tinting "made" on a theme change

function W.SetTheme(house)
  local c = W.THEMES[house] or W.THEMES.Neutral
  W.theme = W.THEMES[house] and house or "Neutral" -- the applied theme
  setAccent(c)
  -- selected and primary buttons and ticked checkboxes take the new accent
  for b in pairs(W.buttons) do
    if b.selected or b.tone or b.primary then -- coloured choices redraw too (the palette may have changed)
      b:SetSelected(b.selected)
    end
  end
  for check in pairs(W.checks) do
    check:SetChecked(check.checked)
  end
  for list in pairs(W.sideLists) do
    list:Repaint()
  end
  for tag in pairs(W.tags) do
    if tag.kind == "made" then
      tag:Set(tag.value, tag.kind)
    end
  end
end

W.buttons = setmetatable({}, { __mode = "k" }) -- every W.Button, for re-tinting on a theme change
W.checks = setmetatable({}, { __mode = "k" }) -- every W.Check, likewise
W.sideLists = setmetatable({}, { __mode = "k" }) -- every UI.SideList (Shell.lua), for its selection's tint

-- "ffRRGGBB" for |c escapes
function W.Hex(c)
  local function byte(x)
    return math.floor(x * 255 + 0.5)
  end
  return ("ff%02x%02x%02x"):format(byte(c[1]), byte(c[2]), byte(c[3]))
end

-- until a theme is applied: the default accent's primary fill
W.COLORS.primary = W.PrimaryShade(W.COLORS.accent, W.PRIMARY_CONTRAST)
W.COLORS.primaryHover = W.PrimaryShade(W.COLORS.accent, W.PRIMARY_HOVER_CONTRAST)

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

-- a text role ("good", "dim", ...) or "RRGGBB" as a colour table
function W.RGB(color)
  local h = ns.HEX[color] or color
  return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255, 1 }
end

local WHITE = { 1, 1, 1, 1 }

-- flat button with hover and optional selected state; onClick(button).
-- opts.icon: a leading icon of that size (b.icon, a texture; the label moves right of it)
-- opts.color: the label's colour, a text role or "RRGGBB" (b:SetLabelColor to change it)
function W.Button(parent, label, width, height, onClick, opts)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(width or 60, height or 20)
  W.Skin(b, W.COLORS.panel)
  b.selected = false
  b.primary = false -- the panel's main action: W.Primary
  b.enabled = true
  W.buttons[b] = true
  b.tone = false -- coloured choices (signals): set by W.Segmented
  b.labelColor = opts and opts.color and W.RGB(opts.color) or false
  b.label = W.Text(b, "GameFontHighlightSmall", "CENTER")
  b.label:SetText(label)
  -- the label is AME's own font string (the button has none of the game's): its text goes there
  function b:SetText(text)
    self.label:SetText(text)
  end
  -- disabled looks it: faded, its label dimmed (the game's own state isn't drawn on AME's flat buttons)
  local setEnabled, enable, disable = b.SetEnabled, b.Enable, b.Disable
  local function look(self, on)
    self.enabled = on
    self:SetAlpha(on and 1 or 0.45)
    if self.label.SetTextColor then
      local c = W.COLORS.dim
      if on then
        c = self.labelColor or (self.primary and not self.selected and WHITE) or W.COLORS.text
      end
      self.label:SetTextColor(c[1], c[2], c[3], c[4])
    end
  end
  b.Look = look
  function b:SetLabelColor(color)
    self.labelColor = color and W.RGB(color) or false
    look(self, self.enabled)
  end
  function b:SetEnabled(on)
    on = on and true or false
    if setEnabled then
      setEnabled(self, on)
    end
    look(self, on)
  end
  function b:Enable()
    if enable then
      enable(self)
    end
    look(self, true)
  end
  function b:Disable()
    if disable then
      disable(self)
    end
    look(self, false)
  end
  function b:GetText()
    return self.label:GetText()
  end
  if opts and opts.icon then
    b.icon = b:CreateTexture(nil, "OVERLAY")
    b.icon:SetSize(opts.icon, opts.icon)
    b.icon:SetPoint("LEFT", 6, 0)
    b.label:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
  else
    b.label:SetPoint("CENTER")
  end
  if b.labelColor then
    look(b, true)
  end
  -- not selected: the panel colour, or for a primary button the accent fill; a little lighter under the mouse
  local function rest(self, hover)
    local c, bc
    if self.primary then
      c = hover and W.COLORS.primaryHover or W.COLORS.primary
      bc = c
    else
      c, bc = hover and W.COLORS.panelHover or W.COLORS.panel, W.COLORS.border
    end
    self:SetBackdropColor(c[1], c[2], c[3], c[4])
    self:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4])
  end
  b:SetScript("OnEnter", function(self)
    if not self.selected then
      rest(self, true)
    end
  end)
  b:SetScript("OnLeave", function(self)
    if not self.selected then
      rest(self, false)
    end
  end)
  b:SetScript("OnClick", function(self)
    if onClick then
      onClick(self)
    end
  end)
  function b:SetSelected(on)
    self.selected = on
    if self.primary and self.label.SetTextColor then
      look(self, self.enabled) -- white on the fill, the usual colour when selected
    end
    if self.tone then
      -- a coloured choice (a signal): its own label normally; selected, inverted - filled with its colour, dark text
      local text, fill = self.tone(on)
      self.label:SetText(text)
      if on and fill then
        self:SetBackdropColor(fill[1], fill[2], fill[3], 1)
        self:SetBackdropBorderColor(fill[1], fill[2], fill[3], 1)
        return
      end
    end
    if not on then
      rest(self, false)
      return
    end
    local c, bc = W.COLORS.selected, W.COLORS.accent
    self:SetBackdropColor(c[1], c[2], c[3], 1)
    self:SetBackdropBorderColor(bc[1], bc[2], bc[3], 1)
  end
  return b
end

-- The main action of a panel (Post, Buy, Queue, Craft next, Search the AH): filled with the theme's accent and a
-- white label, as the designs show. Not the selected look (a dark tint with an accent border): that one says which
-- choice is picked. on = false makes it an ordinary button again (a panel whose main action changes).
function W.Primary(b, on)
  b.primary = on ~= false
  b:SetSelected(b.selected)
  b:Look(b.enabled)
  return b
end

-- A row of buttons where one is selected (tabs, ranges, filters, modes).
--   W.Segmented(parent, { { key, label }, ... }, {
--     height = 20, gap = 4,
--     width = 60,                 -- fixed button width; or
--     minWidth = 44,              -- at least this, wider for long labels (translations)
--     onSelect = function(key, button) end,
--     look = "primary",           -- the picked one filled with the accent (W.Primary), not the selected tint: the
--                                 -- window's tabs, where the open one is a place, not a choice among options
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
    b.tone = item[3] or false -- optional: function(selected) -> label, fill colour (W.SignalTone)
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
      if opts.look == "primary" then
        W.Primary(b, b.key == key)
      else
        b:SetSelected(b.key == key)
      end
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
-- text: a string, or a function(format) -> string for "tabs" / "csv" (the box then offers both)
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
    box.hint:SetPoint("RIGHT", -12, 0)
    box.hint:SetJustifyH("LEFT")
    box.formats = W.Segmented(box, { { "tabs", L["Spreadsheet"] }, { "csv", L["CSV"] } }, {
      minWidth = 60,
      onSelect = function(format)
        box.format = format
        box:Fill()
      end,
    })
    box.formats:SetPoint("TOPRIGHT", -12, -8)
    function box:Fill()
      local t = type(self.source) == "function" and self.source(self.format) or self.source
      self.hint:SetText(
        self.format == "csv" and L["Ctrl+C copies the selected text: comma-separated values."]
          or L["Ctrl+C copies the selected text; paste it into a spreadsheet. Tabs show as boxes here but paste as columns."]
      )
      self.edit:SetText(t or "")
      self.edit:SetFocus()
      self.edit:HighlightText()
    end
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -56)
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
  box.source = text
  box.format = box.format or "tabs"
  box.formats:SetShown(type(text) == "function")
  box.formats:Select(box.format, true)
  box:Show()
  box:Fill()
  return box
end

-- A one-time hint: a small callout above a frame, shown until "Got it" is clicked (remembered per account under
-- Settings "hintsSeen"). Returns the callout (nil when already seen).
-- Hints are information, not warnings: a calm blue-grey panel (never the faction accent, which is red for the Horde),
-- a "Tip" label, the text, and the button on its own line under it. They open below what they explain (opts.above:
-- above it), so they never cover the title bar.
W.HINT_BORDER = { 0.45, 0.62, 0.8, 0.55 }
W.HINT_BG = { 0.08, 0.1, 0.13, 0.97 }
W.HINT_WIDTH = 320

function W.Hint(anchor, key, text, opts)
  local seen = ns.Settings:Table("hintsSeen")
  if seen[key] then
    return nil
  end
  local tip = CreateFrame("Frame", nil, anchor, "BackdropTemplate")
  W.Skin(tip, W.HINT_BG, W.HINT_BORDER)
  tip:SetFrameStrata("DIALOG")
  tip:SetWidth(W.HINT_WIDTH)
  if opts and opts.above then
    tip:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 6)
  else
    tip:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
  end
  tip.label = W.Text(tip, "GameFontNormalSmall")
  tip.label:SetPoint("TOPLEFT", 10, -8)
  tip.label:SetText(W.Color("7fb2e6", L["Tip"]))
  tip.text = W.Text(tip, "GameFontHighlightSmall")
  tip.text:SetPoint("TOPLEFT", tip.label, "BOTTOMLEFT", 0, -4)
  tip.text:SetWidth(W.HINT_WIDTH - 20)
  tip.text:SetWordWrap(true)
  tip.text:SetSpacing(2)
  tip.text:SetText(text)
  tip.ok = W.Button(tip, L["Got it"], 64, 20, function()
    seen[key] = true
    tip:Hide()
  end)
  tip.ok:SetPoint("TOPRIGHT", tip.text, "BOTTOMRIGHT", 0, -8)
  -- tall enough for the label, the wrapped text and the button
  local function fit()
    tip:SetHeight(8 + 14 + 4 + (tip.text:GetStringHeight() or 24) + 8 + 20 + 8)
  end
  fit()
  tip:SetScript("OnShow", fit)
  tip.key = key
  return tip
end

-- Removable filter chips in a row, then "Clear all": chips:Set({ { label, onRemove }, ... }). chips.count: shown.
function W.Chips(parent, onClearAll)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(20)
  row.pool = {}
  -- "Clear all" is an action written as text (the link colour), so it doesn't read as one more chip
  row.clear = CreateFrame("Button", nil, row)
  row.clear:SetHeight(18)
  row.clear.label = W.Text(row.clear, "GameFontHighlightSmall")
  row.clear.label:SetPoint("LEFT", 0, 0)
  row.clear.label:SetText(L["Clear all"])
  local link, white = W.RGB("link"), W.RGB("white")
  row.clear.label:SetTextColor(link[1], link[2], link[3], 1)
  row.clear:SetWidth(math.ceil(row.clear.label:GetStringWidth() or 50) + 4)
  row.clear:SetScript("OnEnter", function(self)
    self.label:SetTextColor(white[1], white[2], white[3], 1)
  end)
  row.clear:SetScript("OnLeave", function(self)
    self.label:SetTextColor(link[1], link[2], link[3], 1)
  end)
  row.clear:SetScript("OnClick", function()
    if onClearAll then
      onClearAll()
    end
  end)
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

-- A section heading in a tooltip ("DISENCHANTS INTO · 3 outcomes"): capitals in a quiet grey, the note dim after it.
-- The game's tooltip lines share one font, so capitals stand in for the design's small caps.
W.TIP_SECTION = "7f8594"
function W.TipSectionText(heading, note)
  local out = "|cff" .. W.TIP_SECTION .. tostring(heading or ""):upper() .. "|r"
  if note and note ~= "" then
    out = out .. W.Dim("  ·  " .. note)
  end
  return out
end
function W.TipSection(tip, heading, note)
  tip:AddLine(W.TipSectionText(heading, note))
end

-- an inline warning icon (the amber "!" of notices), sized to a tooltip or table line
W.WARN_ICON = "|TInterface\\DialogFrame\\UI-Dialog-Icon-AlertNew:12:12:0:0|t"

-- KPI card: a headline figure tile (Market Overview, Portfolio, Leveling, Sharing). A dim label, a large value, an
-- optional change after it, an optional rising / falling bar under it and an optional dim note at the bottom.
--   local c = W.KpiCard(parent, label, { term = "mxIndex" })
--   c:Set{ value = "104.2" | copper = 12000, copper2 = 9000, signed = true,
--          delta = "+0.9%", deltaKind = "up" | "down" | "mute", rise = 1200, fall = 800, note = "..." }
--   c:SetCompact(on): the narrow-window tile (a smaller value, tighter padding, no note)
-- copper is drawn with W.BigMoney (W.SignedMoney when signed); copper2 is a second amount after " / " (sold /
-- bought). deltaKind colours the change: up and down in the palette's gain / loss, mute dim (a count, "/day").
-- c.label and c.value are font strings; c.value:SetText still works for a value drawn by hand.
W.KPI_PAD, W.KPI_PAD_COMPACT = 6, 4
W.KPI_BAR_H = 5
W.KPI_DELTA = { up = "good", down = "bad", mute = "dim" }
function W.KpiCard(parent, label, opts)
  local c = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  W.Skin(c, W.COLORS.panel)
  c:SetSize(120, 42)
  c.compact, c.data = false, {}
  c.label = W.Text(c, "GameFontDisableSmall")
  c.label:SetText(label)
  c.label:SetWordWrap(false)
  c.label:SetPoint("RIGHT", -8, 0)
  c.value = W.Text(c, "GameFontHighlightLarge")
  c.value:SetWordWrap(false)
  c.value:SetPoint("TOPLEFT", c.label, "BOTTOMLEFT", 0, -3)
  c.delta = W.Text(c, "GameFontHighlightSmall")
  c.delta:SetPoint("BOTTOMLEFT", c.value, "BOTTOMRIGHT", 4, 1)
  c.delta:SetWordWrap(false)
  -- the breadth bar: rising on the left, falling on the right, each as wide as its share
  c.rise = c:CreateTexture(nil, "ARTWORK")
  c.rise:SetHeight(W.KPI_BAR_H)
  c.rise:SetPoint("TOPLEFT", c.value, "BOTTOMLEFT", 0, -3)
  c.fall = c:CreateTexture(nil, "ARTWORK")
  c.fall:SetHeight(W.KPI_BAR_H)
  c.fall:SetPoint("LEFT", c.rise, "RIGHT", 0, 0)
  c.note = W.Text(c, "GameFontDisableSmall")
  c.note:SetPoint("BOTTOMLEFT", 8, 5)
  c.note:SetPoint("RIGHT", -8, 0)
  c.note:SetWordWrap(false)
  c:EnableMouse(true)
  if opts and opts.term and ns.Help then
    ns.Help.Explain(c, opts.term)
  end

  function c:Layout()
    local pad = self.compact and W.KPI_PAD_COMPACT or W.KPI_PAD
    self.label:ClearAllPoints()
    self.label:SetPoint("TOPLEFT", 8, -pad)
    self.label:SetPoint("RIGHT", -8, 0)
    self.value:SetFontObject(self.compact and "GameFontHighlight" or "GameFontHighlightLarge")
    local d = self.data
    local bar = d.rise and d.fall and (d.rise + d.fall) > 0
    local width = (self:GetWidth() or 0) - 16
    if bar and width > 0 then
      local share = d.rise / (d.rise + d.fall)
      -- a zero-width texture draws full width, so an empty side is hidden instead
      self.rise:SetWidth(math.max(1, width * share))
      self.fall:SetWidth(math.max(1, width * (1 - share)))
      self.rise:SetShown(share > 0)
      self.fall:SetShown(share < 1)
      W.Fill(self.rise, W.COLORS.up)
      W.Fill(self.fall, W.COLORS.down)
      if share <= 0 then -- the fall bar starts at the left edge
        self.fall:ClearAllPoints()
        self.fall:SetPoint("TOPLEFT", self.value, "BOTTOMLEFT", 0, -3)
      else
        self.fall:ClearAllPoints()
        self.fall:SetPoint("LEFT", self.rise, "RIGHT", 0, 0)
      end
    else
      self.rise:Hide()
      self.fall:Hide()
    end
    self.note:SetShown(not self.compact and (self.note:GetText() or "") ~= "")
  end

  -- the height the card needs for what it shows (a row of cards takes the tallest)
  function c:NeededHeight()
    local pad = self.compact and W.KPI_PAD_COMPACT or W.KPI_PAD
    local h = 2 * pad + (self.label:GetStringHeight() or 10) + 3 + (self.value:GetStringHeight() or 16)
    if self.rise:IsShown() or self.fall:IsShown() then
      h = h + 3 + W.KPI_BAR_H
    end
    if self.note:IsShown() then
      h = h + 3 + (self.note:GetStringHeight() or 10)
    end
    return math.ceil(h)
  end

  function c:Set(t)
    t = t or {}
    self.data = t
    local value
    if t.copper ~= nil then
      value = t.signed and W.SignedMoney(t.copper) or W.BigMoney(t.copper)
      if t.copper2 ~= nil then
        value = value .. W.Dim(" / ") .. W.BigMoney(t.copper2)
      end
    else
      value = t.value ~= nil and tostring(t.value) or W.NONE
    end
    self.value:SetText(value)
    self.delta:SetText(t.delta or "")
    local tone = W.RGB(W.KPI_DELTA[t.deltaKind or "mute"] or "dim")
    self.delta:SetTextColor(tone[1], tone[2], tone[3], 1)
    self.delta:SetFontObject(t.deltaKind == "mute" and "GameFontDisableSmall" or "GameFontHighlightSmall")
    self.note:SetText(t.note or "")
    self:Layout()
  end

  function c:SetCompact(on)
    self.compact = on and true or false
    self:Layout()
  end

  c:SetScript("OnSizeChanged", function(self)
    self:Layout()
  end)
  c:Layout()
  return c
end

-- A row of KPI cards sharing the row's width: defs = { { label, term = "market" }, ... }.
-- opts: height = 42, gap = 6, width = the row's width until it has one (it follows OnSizeChanged).
-- Anchor the returned frame's left and right; its cards are row.cards. row:SetCompact(on) for every card.
function W.CardRow(parent, defs, opts)
  opts = opts or {}
  local h, gap = opts.height or 42, opts.gap or 6
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(h)
  row.cards = {}
  for i, d in ipairs(defs) do
    local c = W.KpiCard(row, d[1], { term = d.term })
    c:SetHeight(h)
    row.cards[i] = c
  end
  -- the shown cards share the width (a narrow window can leave one out: card:Hide(), then row:Relayout())
  local function layout(width)
    if type(width) ~= "number" or width <= 0 then
      return
    end
    local shown = {}
    for _, c in ipairs(row.cards) do
      if c:IsShown() then
        shown[#shown + 1] = c
      end
    end
    local n = math.max(1, #shown)
    local w = (width - gap * (n - 1)) / n
    for i, c in ipairs(shown) do
      c:SetWidth(w)
      c:ClearAllPoints()
      c:SetPoint("TOPLEFT", (i - 1) * (w + gap), 0)
      c:Layout()
    end
  end
  function row:Relayout()
    layout(self:GetWidth())
  end
  function row:SetCompact(on)
    for _, c in ipairs(self.cards) do
      c:SetCompact(on)
    end
  end
  -- taller cards have room for the rising / falling bar and the note
  function row:SetCardHeight(height)
    self:SetHeight(height)
    for _, c in ipairs(self.cards) do
      c:SetHeight(height)
    end
  end
  row:SetScript("OnSizeChanged", function(_, width)
    layout(width)
  end)
  layout(opts.width)
  return row
end

-- The default UI fonts lack glyphs like ▲ ▼ ▮, so use inline textures instead.
-- AME's own triangles (media/Signals): their art fills the image, so they sit centred on the text (the game's
-- arrow art sits high in its image), in gold.
W.ARROW_UP = " |TInterface\\AddOns\\AzerothMercantileExchange\\media\\Signals\\Up:9:9:0:0:32:32:0:32:0:32:255:209:0|t"
W.ARROW_DOWN =
  " |TInterface\\AddOns\\AzerothMercantileExchange\\media\\Signals\\Down:9:9:0:0:32:32:0:32:0:32:255:209:0|t"
-- pointing right: folded away, click to open (the game's own small arrow, as submenus have)
W.ARROW_RIGHT = " |TInterface\\ChatFrame\\ChatFrameExpandArrow:10:10:0:0|t"

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
-- text without colour codes (to recolour a value as a whole)
function W.Plain(s)
  return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
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

-- Whole-market amounts (listed value, turnover): 100,000 gold and up shortened to K / M / B ("486K g", "48.6M g",
-- "2.31M g"), so they fit a stat card; smaller amounts as W.Money(short). from: shorten from this many gold instead
-- (a table column shortens from 10,000 so its rows read alike).
function W.BigMoney(copper, from)
  if not copper then
    return W.NONE
  end
  local g = copper / 10000
  if g < (from or 100000) then
    return W.Money(copper, true)
  end
  local n, unit = g / 1000, "K"
  if g >= 1e9 then
    n, unit = g / 1e9, "B"
  elseif g >= 1e6 then
    n, unit = g / 1e6, "M"
  end
  local text = n < 10 and ("%.2f"):format(n) or n < 100 and ("%.1f"):format(n) or ("%d"):format(math.floor(n + 0.5))
  return "|cff" .. W.COIN_HEX.g .. text .. unit .. " g|r"
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
-- A gain or a loss: "+1g 20s" / "-35s", the sign in green / red. opts (all optional):
--   full = true   every unit (W.Money's long form; the default is short, for columns)
--   zero = "0"    what an amount under 1c shows (dimmed); default: signed as usual
--   tint = true   the whole amount in the sign's colour, not just the sign (Leveling's ledger)
function W.SignedMoney(v, opts)
  if not v then
    return W.NONE
  end
  opts = opts or {}
  if opts.zero and math.abs(v) < 1 then
    return W.Dim(opts.zero)
  end
  local tone, sign = v < 0 and "bad" or "good", v < 0 and "-" or "+"
  local m = W.Money(math.abs(v), not opts.full)
  if opts.tint then
    return W.Color(tone, sign .. W.Plain(m))
  end
  return W.Color(tone, sign) .. m
end

-- an auction house cut (0.05) as whole percent (5), for "the 5% cut"
function W.CutPct(cut)
  return math.floor((cut or 0) * 100 + 0.5)
end

-- an item's name, or "item:12345" while the client hasn't loaded it (plain text; W.ItemNameOrLoad also redraws)
function W.ItemLabel(key)
  return ns.ItemCache.Name(key) or ("item:" .. tostring(key))
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
  disenchant = { "disenchant", L["DE"] },
}
function W.Signal(signal)
  local s = SIGNALS[signal]
  return s and W.Color(s[1], s[2]) or W.NONE
end

-- Signals are never colour alone: an icon in front of the word (media/Signals, drawn by
-- scripts/make-signal-icons.lua): up triangle BUY, down triangle SELL, dot HOLD, pause WAIT, coin VENDOR, shard DE.
-- The white
-- icons take the signal's colour, so they follow the colour-blind palette too.
W.SIGNAL_ICON = { buy = "Up", sell = "Down", hold = "Dot", wait = "Pause", vendor = "Coin", disenchant = "Shard" }
W.SIGNAL_MEDIA = "Interface\\AddOns\\AzerothMercantileExchange\\media\\Signals\\"

-- an icon as inline text, tinted with a text role's colour ("good", "bad", ...), or with hex ("RRGGBB")
function W.SignalIcon(signal, size, hex)
  local s = SIGNALS[signal]
  if not s then
    return ""
  end
  hex = hex or ns.HEX[s[1]] or "ffffff"
  local r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
  size = size or 15 -- big enough to tell the dot (HOLD) from the coin (VENDOR)
  return ("|T%s%s:%d:%d:0:0:32:32:0:32:0:32:%d:%d:%d|t"):format(
    W.SIGNAL_MEDIA,
    W.SIGNAL_ICON[signal],
    size,
    size,
    r,
    g,
    b
  )
end

function W.SignalGlyph(signal)
  local s = SIGNALS[signal]
  return s and (W.SignalIcon(signal) .. " " .. W.Color(s[1], s[2])) or W.NONE
end

-- the plain form of a signal: icon and word in its tone (tooltips, text lines); the design's plain SignalBadge
W.SignalText = W.SignalGlyph

-- A signal as a selectable button (W.Segmented's item[3]): the coloured glyph normally; selected, inverted - the
-- button filled with the signal's colour and the icon and word in near-black (6:1 or better on every signal colour,
-- in both palettes). Worked out on each call, so it follows the colour-blind palette. short: the icon alone.
W.INVERTED_TEXT = "141414"
function W.SignalTone(signal, short)
  return function(selected)
    local s = SIGNALS[signal]
    if not (selected and s) then
      if short and s then
        return W.SignalIcon(signal)
      end
      return W.SignalGlyph(signal)
    end
    local hex = ns.HEX[s[1]] or "ffffff"
    local fill =
      { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 }
    local icon = W.SignalIcon(signal, nil, W.INVERTED_TEXT)
    if short then
      return icon, fill
    end
    return icon .. " " .. ns.Color(W.INVERTED_TEXT, s[2]), fill
  end
end

-- The Market's signal filter: one button per signal, the icon and word in its tone, the picked one inverted.
--   W.SignalFilter(parent, {
--     signals = { "all", "buy", "hold", "sell", "wait", "vendor", "disenchant" },  -- which, in order
--     short = false,                -- icons only (narrow windows); "All" stays a word
--     onSelect = function(key) end, minWidth = 40, height = 20,
--   })
-- Returns the W.Segmented: :Select(key, silent), .byKey, .buttons.
W.SIGNAL_ORDER = { "all", "buy", "hold", "sell", "wait", "vendor", "disenchant" }
function W.SignalFilter(parent, opts)
  opts = opts or {}
  local items = {}
  for _, key in ipairs(opts.signals or W.SIGNAL_ORDER) do
    if key == "all" then
      items[#items + 1] = { "all", L["All"] }
    elseif SIGNALS[key] then
      local tone = W.SignalTone(key, opts.short)
      items[#items + 1] = { key, (tone(false)), tone }
    end
  end
  return W.Segmented(parent, items, {
    minWidth = opts.minWidth or (opts.short and 28 or 40),
    height = opts.height or 20,
    onSelect = opts.onSelect,
  })
end

-- A signal badge's colours: the word a little lighter than the signal's tone, on a pill that is a dark tint of it,
-- darkened further where the word needs it to stay readable (4.5:1, WCAG AA). Worked out on each call, so it
-- follows the colour-blind palette. -> word "RRGGBB", pill colour table (nil for no signal)
W.BADGE_LIGHTEN, W.BADGE_TINT = 0.3, 0.3
function W.SignalBadgeColors(signal)
  local s = SIGNALS[signal]
  if not s then
    return nil
  end
  local c = W.RGB(ns.HEX[s[1]] or "ffffff")
  local word = {}
  for i = 1, 3 do
    word[i] = c[i] + (1 - c[i]) * W.BADGE_LIGHTEN
  end
  local wordHex = hexOf(word)
  for step = 100, 0, -5 do
    local f = W.BADGE_TINT * step / 100
    local pill = { c[1] * f, c[2] * f, c[3] * f, 1 }
    if W.Contrast(wordHex, hexOf(pill)) >= 4.5 then
      return wordHex, pill
    end
  end
  return wordHex, { 0, 0, 0, 1 }
end

-- A signal as a badge: the icon and word on a tinted pill (tables, the item card, the profession bar).
--   local badge = W.SignalBadge(parent); badge:SetSignal("buy")
-- No signal ("none", nil): a dim dash, no pill. badge:GetWidth() is what it takes.
function W.SignalBadge(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(14)
  f.pill = f:CreateTexture(nil, "BACKGROUND")
  f.pill:SetAllPoints()
  f.text = W.Text(f, "GameFontHighlightSmall", "CENTER")
  f.text:SetPoint("CENTER", 0, 0)
  f.text:SetWordWrap(false)
  f.signal = false
  function f:SetSignal(signal)
    self.signal = signal or false
    local wordHex, pill = W.SignalBadgeColors(signal)
    if not wordHex then
      self.pill:Hide()
      self.text:SetText(W.NONE)
    else
      self.pill:SetColorTexture(pill[1], pill[2], pill[3], 1)
      self.pill:Show()
      self.text:SetText(W.SignalIcon(signal, 10, wordHex) .. " " .. ns.Color(wordHex, SIGNALS[signal][2]))
    end
    self:SetWidth(math.ceil(self.text:GetStringWidth() or 0) + (wordHex and 10 or 0))
  end
  return f
end

-- A source tag: short text on a small tinted panel ("4 · bank", "AH", "made"), coloured by kind (W.COLORS.tag):
-- "other" (default), "vendor", "ah", "made" (follows the theme's accent).
--   local tag = W.Tag(parent); tag:Set("12 · AH", "ah"); tag:GetWidth()
function W.Tag(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(16)
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.text = W.Text(f, "GameFontHighlightSmall", "CENTER")
  f.text:SetPoint("CENTER", 0, 0)
  f.text:SetWordWrap(false)
  f.value, f.kind = "", "other"
  function f:Set(text, kind)
    self.value = text or ""
    self.kind = W.COLORS.tag[kind] and kind or "other"
    local c = W.COLORS.tag[self.kind]
    self.bg:SetColorTexture(c[1][1], c[1][2], c[1][3], c[1][4])
    self.text:SetText(self.value)
    self.text:SetTextColor(c[2][1], c[2][2], c[2][3], 1)
    self:SetWidth(math.ceil(self.text:GetStringWidth() or 0) + 12)
    self:SetShown(self.value ~= "")
  end
  W.tags[f] = true
  return f
end

-- item name/icon/quality colour; may be nil until the client has cached the item (call again after load)
-- An item's name (and icon) that shows the game's item tooltip on hover: an invisible frame over them, sized to
-- what's shown. first: the leftmost piece (the icon, or the name), text: the name's font string.
--   hover:SetItem(itemID) after setting the name; false hides it
-- It behaves as an item link: Shift-click (or another modified click) does what it does on a link in chat or your
-- bags (link it in chat, try it on, ...), a plain click opens the item in the AME window.
function W.ItemHover(parent, first, text)
  local f = CreateFrame("Button", nil, parent)
  f:SetPoint("TOPLEFT", first, "TOPLEFT", 0, 0)
  f:SetPoint("BOTTOM", first, "BOTTOM", 0, 0)
  f:EnableMouse(true)
  f.itemID = false
  f:SetScript("OnClick", function(self)
    W.ItemLinkClicked(self.itemID)
  end)
  function f:SetItem(itemID)
    self.itemID = itemID or false
    -- where the name starts (before the first layout pass: the icon's width and the usual 8 px gap)
    local left, right = first:GetLeft(), text:GetLeft()
    local offset = (left and right) and (right - left) or (first ~= text and (first:GetWidth() or 0) + 8 or 0)
    self:SetWidth(math.max(1, offset + (text:GetStringWidth() or 0)))
    self:SetShown(itemID and true or false)
  end
  W.Tooltip(f, function(tip, self)
    if not self.itemID then
      return false
    end
    W.SetItemTip(tip, self.itemID)
  end)
  return f
end

-- a click on an item name: modified, the game's own handling of an item link (chat, try on); plain, the AME window
function W.ItemLinkClicked(key)
  if not key then
    return
  end
  local link = ns.ItemCache.Link(key)
  local modified = IsModifiedClick and (IsModifiedClick("CHATLINK") or IsModifiedClick("DRESSUP"))
  if link and modified and HandleModifiedItemClick then
    HandleModifiedItemClick(link)
  elseif ns.UI and ns.UI.ShowItem then
    ns.UI:ShowItem(key)
  end
end

-- An item drawn as a link: [star] icon, the name in its quality colour, a dim count and confidence bars after it.
-- The whole of it is one hover and click region: the item's tooltip, and a click does what W.ItemLinkClicked does.
--   local link = W.ItemLink(parent, {
--     icon = 14,                        -- icon size; 0 for none
--     font = "GameFontHighlightSmall",  -- the name's font
--     star = false,                     -- a watchlist star in front (its own click: the watchlist menu)
--     top = false,                      -- the name level with the icon's top (a large icon, a line under the name)
--     maxWidth = nil,                   -- the name is cut short ("...") so the whole link fits this
--   })
--   link:SetItem(key, count, confidence)  -- count: a number or text; confidence: "high" / "medium" / "low"
--   link:SetFont(size, bold)               -- the name's size in px
--   link:GetWidth()                        -- what it takes, to put the next piece after it
-- link.name, .icon, .count, .conf are its parts; link.key the item. A name the client hasn't loaded yet shows as
-- "item:<id>" and fills in by itself (W.ItemNameOrLoad).
W.LINK_GAP = 6
function W.ItemLink(parent, opts)
  opts = opts or {}
  local f = CreateFrame("Button", nil, parent)
  local size = opts.icon or 14
  f.opts, f.key, f.iconSize, f.star = opts, false, size, false
  f.maxWidth = opts.maxWidth or false
  f:SetHeight(math.max(size, 16))
  local x = 0
  if opts.star then
    f.star = CreateFrame("Button", nil, f)
    f.star:SetSize(12, 12)
    f.star:SetPoint(opts.top and "TOPLEFT" or "LEFT", 0, 0)
    f.star.tex = f.star:CreateTexture(nil, "ARTWORK")
    f.star.tex:SetAllPoints()
    W.SetStar(f.star.tex, false)
    f.star:SetScript("OnClick", function(self)
      if f.key and ns.UI and ns.UI.StarClicked then
        ns.UI:StarClicked(self, f.key)
      end
    end)
    x = 14
  end
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(math.max(size, 1), math.max(size, 1))
  f.icon:SetPoint(opts.top and "TOPLEFT" or "LEFT", x, 0)
  f.icon:SetShown(size > 0)
  f.nameX = size > 0 and x + size + W.LINK_GAP or x
  f.name = W.Text(f, opts.font or "GameFontHighlightSmall")
  f.name:SetWordWrap(false)
  if opts.top then
    f.name:SetPoint("TOPLEFT", f.nameX, -1)
  else
    f.name:SetPoint("LEFT", f.nameX, 0)
  end
  f.count = W.Text(f, "GameFontDisableSmall")
  f.count:SetPoint("LEFT", f.name, "RIGHT", 4, 0)
  f.conf = W.Text(f, "GameFontHighlightSmall")
  f.conf:SetPoint("LEFT", f.count, "RIGHT", 4, 0)
  -- once the client has the name: draw it again
  f.redraw = function()
    if f.key then
      f:SetItem(f.key, f.countValue, f.confidence)
    end
  end

  function f:Layout()
    local countW = (self.count:GetText() or "") ~= "" and 4 + (self.count:GetStringWidth() or 0) or 0
    local confW = (self.conf:GetText() or "") ~= "" and 4 + 20 or 0
    local nameW = math.ceil(self.name:GetStringWidth() or 0)
    local room = self.maxWidth and math.max(20, self.maxWidth - self.nameX - countW - confW)
    if room and nameW > room then
      nameW = room
      self.name:SetWidth(room) -- cut short with "..."
    else
      self.name:SetWidth(0) -- as wide as the name
    end
    self:SetWidth(math.max(1, self.nameX + nameW + countW + confW))
  end

  function f:SetItem(key, count, confidence)
    self.key, self.countValue, self.confidence = key or false, count, confidence
    if not key then
      self:Hide()
      return
    end
    local name, _, quality, icon = W.ItemInfo(key)
    self.name:SetText(name and W.QualityText(quality, name) or W.ItemNameOrLoad(key, self.redraw))
    self.icon:SetTexture(icon or 134400)
    local c = type(count) == "number" and W.Thousands(count) or count
    self.count:SetText(c and c ~= "" and W.Dim(c) or "")
    self.conf:SetText(confidence and W.Confidence(confidence) or "")
    if self.star then
      local watched = ns.AME and ns.AME.watch and ns.AME.watch:Watched(key) or false
      W.SetStar(self.star.tex, watched)
    end
    self:Layout()
    self:Show()
  end

  function f:SetMaxWidth(w)
    self.maxWidth = w or false
    self:Layout()
  end

  -- The game's font has no bold weight: bold draws the name 2 px larger, as the game's own headings stand out.
  function f:SetFont(px, bold)
    local file, _, flags = self.name:GetFont()
    if file and px then
      self.name:SetFont(file, bold and px + 2 or px, flags)
    end
    self:Layout()
  end

  f:SetScript("OnClick", function(self)
    W.ItemLinkClicked(self.key)
  end)
  W.Tooltip(f, function(tip, self)
    if not self.key then
      return false
    end
    W.SetItemTip(tip, self.key)
  end)
  f:Hide()
  return f
end

-- Item links inside a line of text. W.LinkText(key, count, redraw) is the item's name as an |Hitem:...|h link in
-- its quality colour (no brackets: it reads as a name, not a chat message), a dim count after it. A frame that shows
-- such text needs W.EnableLinks(frame) for the hover and clicks. redraw runs once a name the client hadn't loaded
-- arrives (the text then says "item:<id>").
W.linkKeys = {} -- item string -> item key, for the clicks (a random-suffix variant's string isn't its key)
function W.LinkText(key, count, redraw)
  if not key then
    return W.NONE
  end
  local name, _, quality = W.ItemInfo(key)
  if not name then
    W.ItemNameOrLoad(key, redraw) -- starts watching for it
  end
  local s = ns.ItemString(key)
  W.linkKeys[s] = key
  local out = W.QualityText(quality, "|H" .. s .. "|h" .. (name or W.ItemLabel(key)) .. "|h")
  local c = type(count) == "number" and W.Thousands(count) or count
  if c and c ~= "" then
    out = out .. " " .. W.Dim(c)
  end
  return out
end

-- the item key behind a hyperlink's "item:..." part (nil for other links)
function W.LinkKey(link)
  if type(link) ~= "string" or not link:find("^item:") then
    return nil
  end
  return W.linkKeys[link] or tonumber(link:match("^item:(%d+)"))
end

-- Switch item links on in a frame's text (its font strings): hovering one shows the item's tooltip, a click does
-- what W.ItemLinkClicked does. Other links (the Guide's slash commands) are left to the frame's own scripts.
function W.EnableLinks(frame)
  if frame.SetHyperlinksEnabled then
    frame:SetHyperlinksEnabled(true)
  end
  frame:HookScript("OnHyperlinkEnter", function(self, link)
    local key = W.LinkKey(link)
    if key then
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
      W.SetItemTip(GameTooltip, key)
      GameTooltip:Show()
      self.linkTip = true
    end
  end)
  frame:HookScript("OnHyperlinkLeave", function(self)
    if self.linkTip then
      self.linkTip = false
      GameTooltip:Hide()
    end
  end)
  frame:HookScript("OnHyperlinkClick", function(_, link)
    local key = W.LinkKey(link)
    if key then
      W.ItemLinkClicked(key)
    end
  end)
  return frame
end

-- the game's item tooltip for an item key (a random-suffix variant shows its own stats)
function W.SetItemTip(tip, key)
  W.NudgeItemName(key)
  if ns.IsVariant(key) then
    local itemID, suffix = ns.SplitKey(key)
    -- the auction house's item key tooltip is the group's ("may vary in stats"): only when no link with the
    -- suffix's bonus is known
    if tip.SetItemKey and not ns.VariantString(key) then
      local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
      tip:SetItemKey(itemID, select(4, getInfo(itemID)) or 0, suffix) -- the auction house's own item key
    else
      tip:SetHyperlink(ns.ItemString(key))
    end
  else
    tip:SetItemByID(key)
  end
end

-- name, link, quality, icon of an item key; a variant has its own name and link, the rest is its base item's
function W.ItemInfo(key)
  local itemID = ns.BaseID(key)
  local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local name, link, quality, _, _, _, _, _, _, icon = getInfo(itemID)
  if not icon and C_Item and C_Item.GetItemIconByID then
    icon = C_Item.GetItemIconByID(itemID)
  end
  if name and ns.IsVariant(key) then
    name, link = ns.ItemCache.Name(key) or name, ns.ItemCache.Link(key) or link
  end
  return name, link, quality, icon
end

-- text in an item quality's colour (white without one)
function W.QualityText(quality, text)
  local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
  return (color and color.hex or "|cffffffff") .. text .. "|r"
end

-- An item's name in its quality colour; until the client has it, "item:<id>", and redraw() runs (debounced) once it
-- arrives. The load callback and the item data events don't always come (WoW Forever left Overview rows unnamed
-- while their tooltips loaded fine), so missing names are also checked every half second for a minute, asking the
-- client again every few seconds. Hovering the item (see SetItemTip) starts that minute over.
local redrawQueue = {}
local missing = {} -- [key] = { ticks = left, redraws = { [fn] = true } }
local redrawsOf = {} -- [key] = { [fn] = true }: who shows the key, kept after giving up for a later hover
local POLL, TICKS, ASK_EVERY = 0.5, 120, 10
local polling = false

local function queueRedraw(redraw)
  if redraw and not redrawQueue[redraw] then
    redrawQueue[redraw] = true
    C_Timer.After(0.2, function()
      redrawQueue[redraw] = nil
      redraw()
    end)
  end
end

local function ask(key)
  ns.ItemCache.Get(key)
  local request = C_Item and C_Item.RequestLoadItemDataByID
  if request then
    pcall(request, ns.BaseID(key))
  end
end

local function poll()
  polling = false
  for key, m in pairs(missing) do
    if W.ItemInfo(key) then
      missing[key] = nil
      for fn in pairs(m.redraws) do
        queueRedraw(fn)
      end
    else
      m.ticks = m.ticks - 1
      if m.ticks <= 0 then
        missing[key] = nil
      elseif m.ticks % ASK_EVERY == 0 then
        ask(key)
      end
    end
  end
  if next(missing) then
    polling = true
    C_Timer.After(POLL, poll)
  end
end

-- start (or restart) watching a key that has no name yet
local function watch(key)
  local m = missing[key]
  if m then
    m.ticks = TICKS
    return
  end
  local redraws = redrawsOf[key] or {}
  redrawsOf[key] = redraws
  missing[key] = { ticks = TICKS, redraws = redraws }
  ask(key)
  W.OnItemLoaded(key, function()
    for fn in pairs(redraws) do
      queueRedraw(fn)
    end
  end)
  if not polling then
    polling = true
    C_Timer.After(POLL, poll)
  end
end

function W.ItemNameOrLoad(key, redraw)
  local name, _, quality = W.ItemInfo(key)
  name = name or ns.ItemCache.Name(key)
  if not name and key then
    local redraws = redrawsOf[key] or {}
    redrawsOf[key] = redraws
    if redraw then
      redraws[redraw] = true
    end
    if not missing[key] then
      watch(key)
    end
  end
  return W.QualityText(quality, name or W.ItemLabel(key))
end

-- a tooltip is loading this key: if a list shows it unnamed, look again
function W.NudgeItemName(key)
  if key and redrawsOf[key] and next(redrawsOf[key]) and not W.ItemInfo(key) then
    watch(key)
  end
end

-- run fn once item data is cached
function W.OnItemLoaded(itemID, fn)
  if Item and Item.CreateFromItemID then
    local item = Item:CreateFromItemID(ns.BaseID(itemID))
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

-- money input with a hint ("min g"): "12" or "1.5" is gold, "9s 50c", "1g 20s", "150c" (ns.ParseMoney);
-- onChange(copper or nil, user). Text it can't read turns red (and counts as empty). box:SetCopper(c) fills it in.
function W.MoneyInput(parent, hint, onChange)
  local box
  box = W.Input(parent, {
    width = 64,
    hint = hint,
    onChange = function(text, _, user)
      local copper = ns.ParseMoney(text)
      local bad = copper == nil and text:find("%S") ~= nil
      box:SetTextColor(1, bad and 0.35 or 1, bad and 0.35 or 1)
      onChange(copper, user)
    end,
  })
  function box.SetCopper(self, copper)
    self:SetText(copper and ns.MoneyInputText(copper) or "")
  end
  box:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(L["Gold, or silver and copper too"], 1, 1, 1)
    GameTooltip:AddLine(L["12 or 12g is gold; 1.5 is 1g 50s; 9s 50c, 1g 20s and 150c work too."], nil, nil, nil, true)
    GameTooltip:Show()
  end)
  box:HookScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  return box
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

-- Shared popup menu: W.Menu(anchor, entries); entry = { text, checked = bool?, func = fn, disabled = bool? },
-- { separator = true }, { text, submenu = true, func } (a ▸ mark: it opens more choices), or { item = key }: the item
-- the menu is about, as a link (icon, quality colour, its tooltip; a click opens it, Shift-click links it).
-- One menu frame for the whole addon; closes on a pick or a click elsewhere.
local menu
-- opts.refresh: update a menu already open on this anchor instead of toggling it (live suggestions)
-- opts.cursor: open at the mouse pointer (a right-click menu) instead of under the anchor
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
  local ROW, SEP, width, top = 18, 9, 140, 3
  for i, e in ipairs(entries) do
    local it = menu.items[i]
    if not it then
      it = CreateFrame("Button", nil, menu)
      it.hl = it:CreateTexture(nil, "HIGHLIGHT")
      it.hl:SetAllPoints()
      W.Fill(it.hl, W.COLORS.rowHover)
      it.check = it:CreateTexture(nil, "ARTWORK")
      it.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
      it.check:SetSize(14, 14)
      it.check:SetPoint("LEFT", 2, 0)
      it.text = W.Text(it, "GameFontHighlightSmall")
      it.text:SetPoint("LEFT", 20, 0)
      -- a separator: a thin line across the middle of a short row
      it.rule = it:CreateTexture(nil, "ARTWORK")
      it.rule:SetHeight(1)
      it.rule:SetPoint("LEFT", 6, 0)
      it.rule:SetPoint("RIGHT", -6, 0)
      W.Fill(it.rule, W.COLORS.border)
      -- a submenu: a dim arrow on the right (the game's font has no triangle glyphs)
      it.arrow = it:CreateTexture(nil, "ARTWORK")
      it.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
      it.arrow:SetSize(10, 10)
      it.arrow:SetPoint("RIGHT", -4, 0)
      it.arrow:SetVertexColor(0.6, 0.62, 0.66, 1)
      -- an item's name heading the menu is a link like any other: its tooltip on hover
      it:SetScript("OnEnter", function(self)
        if self.itemKey then
          GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
          W.SetItemTip(GameTooltip, self.itemKey)
          GameTooltip:Show()
        end
      end)
      it:SetScript("OnLeave", function(self)
        if self.itemKey then
          GameTooltip:Hide()
        end
      end)
      menu.items[i] = it
    end
    -- { item = key }: the item's icon and name in its quality colour; a click does what a click on its link does
    it.itemKey = e.item or false
    local text = e.text
    if e.item then
      local name, _, quality, icon = W.ItemInfo(e.item)
      text = ("|T%s:14:14:0:0|t "):format(tostring(icon or 134400))
        .. W.QualityText(quality, name or W.ItemLabel(e.item))
    end
    -- { separator = true } is a line between groups; { text, submenu = true } opens more choices (its func)
    local sep = e.separator == true
    it:ClearAllPoints()
    it:SetPoint("TOPLEFT", 3, -top)
    it:SetPoint("RIGHT", -3, 0)
    it:SetHeight(sep and SEP or ROW)
    top = top + (sep and SEP or ROW)
    it.rule:SetShown(sep)
    it.hl:SetShown(not sep)
    it:EnableMouse(not sep)
    it.text:SetText(sep and "" or text)
    it.text:SetTextColor(e.disabled and 0.5 or 1, e.disabled and 0.5 or 1, e.disabled and 0.5 or 1)
    it.check:SetShown(not sep and e.checked == true)
    it.arrow:SetShown(not sep and e.submenu == true)
    it:SetScript("OnClick", function()
      if sep then
        return
      end
      menu:Hide()
      if e.item and not e.func then
        W.ItemLinkClicked(e.item)
      elseif e.func and not e.disabled then
        e.func()
      end
    end)
    it:Show()
    width = math.max(width, (it.text:GetStringWidth() or 0) + 34 + (e.submenu and 14 or 0))
    if e.item then -- no check mark to leave room for: the icon starts at the edge
      it.text:SetPoint("LEFT", 6, 0)
    else
      it.text:SetPoint("LEFT", 20, 0)
    end
  end
  for i = #entries + 1, #menu.items do
    menu.items[i]:Hide()
  end
  menu.anchor = anchor
  menu:SetSize(width, top + 3)
  menu:ClearAllPoints()
  local x, y
  if opts and opts.cursor and GetCursorPosition then
    x, y = GetCursorPosition()
  end
  if x and y then
    local scale = menu:GetEffectiveScale()
    menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + 2, y / scale - 2)
  else
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  end
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
  if perDay >= 1000 then
    return "~" .. W.Count(perDay) .. "/d" -- ~32k/d
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

-- A panel: the window's panel colour with the discreet grey border (lists, the Guide's article, the AH tabs'
-- panes). pad: also make panel.inner, a frame inset by that much, for the content.
function W.Panel(parent, pad)
  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  W.Skin(f, W.COLORS.panel)
  if pad then
    f.inner = CreateFrame("Frame", nil, f)
    f.inner:SetPoint("TOPLEFT", pad, -pad)
    f.inner:SetPoint("BOTTOMRIGHT", -pad, pad)
  end
  return f
end

-- A page heading: a gold title and a dim subtitle after it on the same line (the Crafting pages, the vendor panel,
-- the AH tabs' lists). Anchor the returned frame's left and right; :Set(title, subtitle).
function W.PageHeading(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(16)
  f.title = W.Text(f, "GameFontNormal")
  f.title:SetPoint("BOTTOMLEFT", 0, 2)
  f.title:SetWordWrap(false)
  f.subtitle = W.Text(f, "GameFontDisableSmall")
  -- the bottoms line up, so the smaller subtitle sits on the title's baseline
  f.subtitle:SetPoint("BOTTOMLEFT", f.title, "BOTTOMRIGHT", 8, 1)
  f.subtitle:SetPoint("RIGHT", f, "RIGHT", 0, 0)
  f.subtitle:SetWordWrap(false)
  function f:Set(title, subtitle)
    self.title:SetText(title or "")
    self.subtitle:SetText(subtitle or "")
    self.subtitle:SetShown((subtitle or "") ~= "")
  end
  return f
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
-- opts.fill: rows span the list's width (anchor the list's left and right); the list is only as tall as what it
-- shows (list:GetHeight() after SetItems), and the empty message wraps.
function W.RowList(parent, opts)
  local n, h, width = opts.rows or 5, opts.rowHeight or 20, opts.width or 460
  local list = CreateFrame("Frame", nil, parent)
  list:SetSize(width, n * h)
  list.rows = {}
  local defs = opts.buttons or {}
  for i = 1, n do
    local row = CreateFrame("Frame", nil, list)
    row:SetHeight(h)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * h)
    if opts.fill then
      row:SetPoint("RIGHT", list, "RIGHT", 0, 0)
    else
      row:SetWidth(width)
    end
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
      row.state:SetWordWrap(false)
      if right then
        row.state:SetPoint("RIGHT", right, "LEFT", -12, 0)
      else
        row.state:SetPoint("RIGHT", 0, 0)
      end
      if opts.fill then
        row.text:SetPoint("RIGHT", row.state, "LEFT", -8, 0) -- long names end in "..." before the state
      end
    elseif right then
      row.text:SetPoint("RIGHT", right, "LEFT", -6, 0)
    elseif opts.fill then
      row.text:SetPoint("RIGHT", 0, 0)
    end
    list.rows[i] = row
  end
  list.more = W.Text(list, "GameFontDisableSmall")
  list.more:SetPoint("TOPLEFT", 0, -n * h)
  if opts.fill then
    list.emptyText = W.Text(list, "GameFontDisableSmall")
    list.emptyText:SetPoint("TOPLEFT", 0, -3)
    list.emptyText:SetPoint("RIGHT", list, "RIGHT", 0, 0)
    list.emptyText:SetWordWrap(true)
    list.emptyText:SetJustifyV("TOP")
  end

  function list:SetItems(items, fill)
    for i, row in ipairs(self.rows) do
      local item = items[i]
      row.item, row.name = item or false, item and item.name or false
      local empty = i == 1 and #items == 0 and opts.empty and not self.emptyText
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
    -- only as tall as what's shown
    if self.emptyText then
      local none = #items == 0 and opts.empty
      self.emptyText:SetText(none and opts.empty or "")
      self.emptyText:SetShown(none and true or false)
      if none then
        self:SetHeight(math.max(h, (self.emptyText:GetStringHeight() or 12) + 6))
      else
        local shown = math.min(#items, n)
        self.more:ClearAllPoints()
        self.more:SetPoint("TOPLEFT", 0, -shown * h)
        self:SetHeight(shown * h + (#items > n and opts.more and 16 or 0))
      end
    end
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
  s:SetPoint("BOTTOMRIGHT", 0, 0)
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

-- how old something is, without "ago": "5 min", "2 h", "1 day", "3 days"
function W.Age(t, now)
  local d = math.max(0, now - (t or now))
  if d < 3600 then
    return L["%d min"]:format(math.max(1, math.floor(d / 60)))
  elseif d < 86400 then
    return L["%d h"]:format(math.floor(d / 3600))
  end
  local days = math.floor(d / 86400)
  return days == 1 and L["1 day"] or L["%d days"]:format(days)
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
