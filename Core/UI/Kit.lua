-- The redesign's look in game: colours from Core/UI/Tokens.lua (the same values the design canvas uses), the
-- market's accent and the shades derived from it, the two fonts, and the skins the new widgets share (a panel, a
-- control, the warm chrome of the title bar and status row). Widgets draw with this, never with literal colours.
--
--   Kit.C("panel") -> { r, g, b, 1 }       a token colour (0-1)
--   Kit.Hex("dim") -> "9a9fa8"              for |c escapes
--   Kit.SetTheme("horde" | "alliance" | "goblin"), Kit.SetFaction("horde" | "alliance")
--   Kit.Accent(), Kit.Selected(), Kit.Primary(), Kit.Row()   the accent and its shades
--   Kit.Box(frame, fill, line)              a flat box: a token fill and a 1 px line (or false for none)
--   Kit.Text(parent, opts)                  a font string: opts.font "ui" | "display", opts.size, opts.color, opts.justify
--   Kit.SetFont(fs, font, size)             change one
--   Kit.Chrome(frame)                       the warm gradient of the title bar and status row
local _, ns = ...

local T = ns.Tokens
local Kit = { listeners = {} }
ns.Kit = Kit

local cache = {}
local function parse(hex)
  hex = hex:gsub("#", "")
  return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, 1 }
end

function Kit.C(name)
  local c = cache[name]
  if not c then
    local hex = T.color[name] or (type(name) == "string" and name:match("^#?%x%x%x%x%x%x$") and name)
    c = parse(hex or "#ff00ff")
    cache[name] = c
  end
  return c
end

function Kit.Hex(name)
  local c = type(name) == "table" and name or Kit.C(name)
  return ("%02x%02x%02x"):format(c[1] * 255 + 0.5, c[2] * 255 + 0.5, c[3] * 255 + 0.5)
end

-- text in a token's colour
function Kit.Color(name, text)
  return "|cff" .. Kit.Hex(name) .. tostring(text) .. "|r"
end

-- ------------------------------------------------------------------------------------------------ theme

local function byKey(list, key)
  for _, v in ipairs(list) do
    if v.key == key then
      return v
    end
  end
  return list[1]
end

local function lin(v)
  return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
end
local function luminance(c)
  return 0.2126 * lin(c[1]) + 0.7152 * lin(c[2]) + 0.0722 * lin(c[3])
end

-- the accent darkened until white text on it reaches the contrast (as scripts/design-tokens.lua does)
local function primaryShade(c, ratio)
  for step = 100, 0, -1 do
    local s = { c[1] * step / 100, c[2] * step / 100, c[3] * step / 100, 1 }
    if 1.05 / (luminance(s) + 0.05) >= ratio then
      return s
    end
  end
  return { 0, 0, 0, 1 }
end

Kit.theme, Kit.faction = "horde", "horde"
local accent, selected, primary, row, factionColor

local function rebuild()
  local a = byKey(T.themes, Kit.theme).accent
  accent = { a[1] / 255, a[2] / 255, a[3] / 255, 1 }
  local s = T.selectedShade
  selected = { accent[1] * s, accent[2] * s, accent[3] * s, 1 }
  primary = primaryShade(accent, T.primaryContrast)
  row = { accent[1], accent[2], accent[3], T.rowAlpha }
  local f = byKey(T.factions, Kit.faction).color
  factionColor = { f[1] / 255, f[2] / 255, f[3] / 255, 1 }
end
rebuild()

function Kit.Accent()
  return accent
end
function Kit.Selected()
  return selected
end
function Kit.Primary()
  return primary
end
function Kit.Row()
  return row
end
function Kit.Faction()
  return factionColor
end

-- the market being viewed sets the accent; listeners (open widgets) redraw
function Kit.SetTheme(key)
  key = tostring(key or "horde"):lower()
  if key == Kit.theme then
    return
  end
  Kit.theme = key
  rebuild()
  for fn in pairs(Kit.listeners) do
    fn()
  end
end

function Kit.SetFaction(key)
  Kit.faction = tostring(key or "horde"):lower() == "alliance" and "alliance" or "horde"
  rebuild()
end

-- fn() runs when the theme changes (a widget that draws the accent)
function Kit.OnTheme(fn)
  Kit.listeners[fn] = true
end

-- ------------------------------------------------------------------------------------------------ fonts

-- The UI font is the client's own narrow face; headings and tabs use the game's display font. Korean and Chinese
-- clients keep the game's own font for both (theirs has the glyphs). LibSharedMedia picks come in Settings.
Kit.FONTS = { ui = "Fonts\\ARIALN.TTF", display = "Fonts\\FRIZQT__.TTF" }

local function localeFont()
  local loc = GetLocale and GetLocale() or "enUS"
  if loc == "koKR" or loc == "zhCN" or loc == "zhTW" then
    return _G.STANDARD_TEXT_FONT
  end
end

function Kit.FontPath(font)
  return localeFont() or Kit.FONTS[font or "ui"] or Kit.FONTS.ui
end

function Kit.SetFont(fs, font, size)
  if fs.SetFont then
    fs:SetFont(Kit.FontPath(font), size or 12, "")
  end
  fs.kitFont, fs.kitSize = font or "ui", size or 12
end

function Kit.SetColor(fs, color)
  local c = type(color) == "table" and color or Kit.C(color or "text")
  fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

function Kit.Text(parent, opts)
  opts = opts or {}
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  Kit.SetFont(fs, opts.font, opts.size)
  Kit.SetColor(fs, opts.color or "text")
  fs:SetJustifyH(opts.justify or "LEFT")
  if fs.SetWordWrap then
    fs:SetWordWrap(opts.wrap and true or false)
  end
  return fs
end

-- ------------------------------------------------------------------------------------------------ skins

local WHITE = "Interface\\Buttons\\WHITE8x8"
local EDGE = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 }

local function rgba(c)
  c = type(c) == "table" and c or Kit.C(c)
  return c[1], c[2], c[3], c[4] or 1
end

-- a flat box: fill and line are token names or colours; line false: no border
function Kit.Box(frame, fill, line)
  if frame.SetBackdrop then
    frame:SetBackdrop(EDGE)
    frame:SetBackdropColor(rgba(fill or "panel"))
    if line == false then
      frame:SetBackdropBorderColor(0, 0, 0, 0)
    else
      frame:SetBackdropBorderColor(rgba(line or "line"))
    end
  end
  frame.kitFill, frame.kitLine = fill, line
end

-- a texture in a colour
function Kit.Fill(tex, color)
  tex:SetColorTexture(rgba(color))
end

-- the warm gradient of the title bar and status row (top to bottom)
function Kit.Chrome(frame)
  local tex = frame.kitChrome or frame:CreateTexture(nil, "BACKGROUND")
  frame.kitChrome = tex
  tex:SetAllPoints()
  tex:SetTexture(WHITE)
  local top, bottom = Kit.C("chromeTop"), Kit.C("chromeBottom")
  if tex.SetGradient and CreateColor then
    tex:SetGradient("VERTICAL", CreateColor(rgba(bottom)), CreateColor(rgba(top)))
  else
    tex:SetColorTexture(rgba(top))
  end
  return tex
end

-- a thin line inside a frame: side "TOP" | "BOTTOM" | "LEFT" | "RIGHT"
function Kit.Line(frame, side, color, thickness)
  local tex = frame:CreateTexture(nil, "BORDER")
  Kit.Fill(tex, color or "line")
  thickness = thickness or 1
  if side == "TOP" or side == "BOTTOM" then
    tex:SetPoint(side .. "LEFT")
    tex:SetPoint(side .. "RIGHT")
    tex:SetHeight(thickness)
  else
    tex:SetPoint("TOP" .. side)
    tex:SetPoint("BOTTOM" .. side)
    tex:SetWidth(thickness)
  end
  return tex
end

Kit.WHITE = WHITE
