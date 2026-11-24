-- AME's colours and fonts: the one source for the redesign ("hybrid" look: flat dark content, game-flavoured chrome).
-- The addon loads it (ns.Tokens, read by Core/UI/Kit.lua); scripts/design-tokens.lua turns it into
-- docs/ux/design/tokens.css for the design canvas, so the boards and the game draw from the same values.
local _, ns = ...
local T = {
  -- faction accents (window chrome only; data colours never follow the theme). Horde is the default.
  themes = {
    { key = "horde", name = "Horde", accent = { 237, 64, 51 } },
    { key = "alliance", name = "Alliance", accent = { 64, 143, 255 } },
    { key = "goblin", name = "Goblin", accent = { 255, 186, 56 } },
  },
  -- your own faction's colour: "Azeroth" in the title is always in it, whichever market's theme the chrome wears
  -- (a Horde player looking at the goblin AH: red "Azeroth", gold accent)
  factions = {
    { key = "horde", name = "Horde", color = { 237, 64, 51 } },
    { key = "alliance", name = "Alliance", color = { 64, 143, 255 } },
  },
  -- shades derived from the accent, as the addon derives them
  selectedShade = 0.35, -- a selected control: the accent this dark
  primaryContrast = 5, -- a primary button: the accent darkened until white text on it reaches this (WCAG)
  rowAlpha = 0.2, -- the picked row: the accent this strong over the panel

  color = {
    -- surfaces
    bg = "#0f1014", -- the window, behind the panels
    panel = "#15171c", -- cards, tables, sidebars
    control = "#1d2027", -- buttons, inputs, pills
    chromeTop = "#241e15", -- the title bar and status row: warm, game-flavoured
    chromeBottom = "#16130e",
    -- lines
    line = "#262930", -- panel borders
    lineSoft = "#1e2127", -- between rows
    controlLine = "#3a3d44",
    frame = "#5a4a2e", -- the window's own frame: bronze
    frameLit = "#6b5a3a", -- the title bar's edge, a card's top edge
    primaryLine = "#b89a5a", -- the gilt edge of a primary button
    -- text
    text = "#e6e4df",
    soft = "#cfcdc7", -- button labels, quieter lines
    dim = "#9a9fa8", -- secondary text
    heading = "#ffd100", -- headings and the title: the game's gold
    tab = "#c9b68c", -- tabs at rest: parchment
    white = "#ffffff",
    -- meaning (data colours)
    good = "#4dd973", -- gains, BUY
    bad = "#ff6159", -- losses, SELL, undercut
    warn = "#ffcc33", -- HOLD, alerts
    gold = "#ffd100", -- the gold unit
    wait = "#8fa3b8",
    vendor = "#c8a272",
    disenchant = "#b49cff",
    link = "#8bb8ff",
    badge = "#e0442f", -- the unread count
    -- item quality, as the game colours names (rare and epic lightened to read on dark)
    q0 = "#9d9d9d",
    q1 = "#ffffff",
    q2 = "#1eff00",
    q3 = "#3d9bff",
    q4 = "#b866ff",
    q5 = "#ff8000",
    -- charts
    chartMarket = "#4dd9c8",
    chartLowest = "#7fdc8a",
    chartAverage = "#ffcc33",
    chartFast = "#c78cff",
    chartSupply = "#6f7489",
  },

  font = {
    ui = "Inter, system-ui, sans-serif", -- in game: the UI font the client ships
    display = "Marcellus, Georgia, serif", -- headings and tabs; in game: Friz Quadrata, the game's own
  },
}
if type(ns) == "table" then
  ns.Tokens = T
end
return T
