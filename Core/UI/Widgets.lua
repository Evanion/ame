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
  hover = { 1, 1, 1, 0.06 },
  selected = { 0.2, 0.8, 1, 0.18 },
}

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
end

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

-- flat button with hover and optional selected state; onClick(button)
function W.Button(parent, label, width, height, onClick)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(width or 60, height or 20)
  W.Skin(b, W.COLORS.panel)
  b.label = W.Text(b, "GameFontHighlightSmall", "CENTER")
  b.label:SetPoint("CENTER")
  b.label:SetText(label)
  b:SetScript("OnEnter", function(self)
    if not self.selected then
      self:SetBackdropColor(0.14, 0.15, 0.18, 1)
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

-- The default UI fonts lack glyphs like ▲ ▼ ▮, so use inline textures instead.
W.ARROW_UP = " |TInterface\\Buttons\\Arrow-Up-Up:12:12:0:-2|t"
W.ARROW_DOWN = " |TInterface\\Buttons\\Arrow-Down-Up:12:12:0:2|t"

-- small tinted colour square for legends
function W.Swatch(r, g, b)
  return ("|TInterface\\Buttons\\WHITE8x8:8:8:0:0:8:8:0:8:0:8:%d:%d:%d|t"):format(r * 255, g * 255, b * 255)
end

-- compact money: "1,234g 56s" / "56s 7c" / "7c", with coloured unit letters
local function commas(n)
  local s = tostring(n)
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end

function W.Money(copper, short)
  if not copper then
    return "|cff777777-|r"
  end
  copper = math.floor(copper + 0.5)
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  local G, S, C = "|cffffd100g|r", "|cffc7c7cfs|r", "|cffeda55fc|r"
  -- short (narrow columns): whole gold from 100g up, rounded; below that silver still matters (2g 98s, not 2g).
  -- Zero lower units are left out: "18s", not "18s 0c".
  if g >= 1000 or (short and g >= 100) then
    return commas(math.floor(copper / 10000 + 0.5)) .. G
  elseif g > 0 then
    if s == 0 then
      return commas(g) .. G
    end
    return ("%s%s %d%s"):format(commas(g), G, s, S)
  elseif s > 0 then
    if c == 0 then
      return ("%d%s"):format(s, S)
    end
    return ("%d%s %d%s"):format(s, S, c, C)
  end
  return ("%d%s"):format(c, C)
end

function W.Percent(x, decimals)
  if not x then
    return "|cff777777-|r"
  end
  local c = x > 0.0005 and W.COLORS.up or x < -0.0005 and W.COLORS.down or W.COLORS.dim
  return ("|cff%02x%02x%02x%+." .. (decimals or 1) .. "f%%|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, x * 100)
end

function W.Signal(signal)
  if signal == "buy" then
    return "|cff4dd973" .. L["BUY"] .. "|r"
  elseif signal == "sell" then
    return "|cffff6159" .. L["SELL"] .. "|r"
  elseif signal == "hold" then
    return "|cffffcc33" .. L["HOLD"] .. "|r"
  elseif signal == "wait" then
    return "|cff8fa3b8" .. L["WAIT"] .. "|r"
  end
  return "|cff777777-|r"
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
-- The button shows the current choice and is highlighted when a non-default (index > 1) option is picked.
function W.Dropdown(parent, width, options, onSelect)
  local b = W.Button(parent, "", width, 20)
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
        it.hl:SetColorTexture(1, 1, 1, 0.08)
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
    local a = W.COLORS.accent
    for i, it in ipairs(self.items) do
      if i > #options then
        break
      end
      it.sel:SetColorTexture(a[1], a[2], a[3], i == b.index and 0.2 or 0)
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

  function b:SetOptions(newOptions)
    options = newOptions
    self.values = newOptions
    build()
  end

  -- select the option whose value is `value` (first option if none)
  function b:SetValue(value)
    for i, o in ipairs(options) do
      if o[1] == value then
        return self:SetIndex(i)
      end
    end
    self:SetIndex(1)
  end

  function b:SetIndex(i)
    self.index = i
    self.label:SetText(options[i] and text(options[i]) or "")
    self:SetSelected(not self.neutral and i ~= (self.defaultIndex or 1))
  end
  b.menu = menu
  b:SetIndex(1)
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
function W.Input(parent)
  local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
  W.Skin(box, W.COLORS.panel)
  box:SetFontObject("GameFontHighlightSmall")
  box:SetTextInsets(6, 6, 0, 0)
  box:SetAutoFocus(false)
  box:SetHeight(20)
  box:HookScript("OnEditFocusGained", function(self)
    local a = W.COLORS.accent
    self:SetBackdropBorderColor(a[1], a[2], a[3], 0.7)
  end)
  box:HookScript("OnEditFocusLost", function(self)
    local b = W.COLORS.border
    self:SetBackdropBorderColor(b[1], b[2], b[3], b[4])
  end)
  box:HookScript("OnEnter", function(self)
    if not self:HasFocus() then
      self:SetBackdropColor(0.14, 0.15, 0.18, 1)
    end
  end)
  box:HookScript("OnLeave", function(self)
    local c = W.COLORS.panel
    self:SetBackdropColor(c[1], c[2], c[3], c[4])
  end)
  box:SetScript("OnEscapePressed", box.ClearFocus)
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
      it.hl:SetColorTexture(1, 1, 1, 0.08)
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
  b.mark = b:CreateTexture(nil, "OVERLAY")
  b.mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
  b.mark:SetPoint("CENTER")
  b.mark:SetSize(16, 16)
  b.label = W.Text(b, "GameFontHighlightSmall")
  b.label:SetPoint("LEFT", b, "RIGHT", 5, 0)
  b.label:SetText(label)
  function b:SetChecked(on)
    self.checked = on and true or false
    self.mark:SetShown(self.checked)
    local a = self.checked and W.COLORS.accent or W.COLORS.border
    self.box:SetBackdropBorderColor(a[1], a[2], a[3], self.checked and 0.8 or a[4])
  end
  b:SetScript("OnClick", function(self)
    self:SetChecked(not self.checked)
    if onToggle then
      onToggle(self.checked)
    end
  end)
  b:SetChecked(false)
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
    return "|cff777777-|r"
  end
  if perDay >= 10 or perDay < 0.05 then -- "~0/d", not "~0.0/d": nothing measurably sells
    return ("~%d/d"):format(math.floor(perDay + 0.5))
  end
  return ("~%.1f/d"):format(perDay)
end

-- section heading at a position in a panel
function W.Heading(parent, text, x, y)
  local h = W.Text(parent, "GameFontNormal")
  h:SetPoint("TOPLEFT", x, y)
  h:SetText(text)
  return h
end

-- explanatory paragraph under an anchor
function W.Note(parent, anchor, text, width)
  local t = W.Text(parent, "GameFontDisableSmall")
  t:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
  t:SetWidth(width or 440)
  t:SetSpacing(2)
  t:SetText(text)
  return t
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
  return ("%s |cff999999(%s)|r"):format(W.Money(choice.price), W.Hours(choice.hours))
end

-- the whole suggestion on one line
function W.PostAdvice(advice)
  if not advice then
    return "|cff999999" .. L["Posting price: not enough data on this item yet."] .. "|r"
  end
  local parts = {
    W.Confidence(advice.confidence) .. " |cffffd100" .. L["Post at"] .. "|r",
    L["Quick %s"]:format(W.PostChoice(advice.quick)),
    L["Normal %s"]:format(W.PostChoice(advice.normal)),
    L["Patient %s"]:format(W.PostChoice(advice.patient)),
    L["%d ahead"]:format(advice.normal.ahead),
  }
  local text = table.concat(parts, "   ")
  if advice.hold then
    text = text .. "   |cffff6159" .. L["unlikely to sell soon: consider holding"] .. "|r"
  elseif advice.cheap then
    text = text .. "   |cffffcc00" .. L["well below its usual price"] .. "|r"
  end
  return text
end

-- data confidence as three small bars (textures, not font glyphs): high = 3 green, medium = 2 amber, low = 1 red
local CONFIDENCE = {
  high = { 3, { 0.3, 0.85, 0.45 } },
  medium = { 2, { 1, 0.8, 0.2 } },
  low = { 1, { 1, 0.38, 0.35 } },
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
