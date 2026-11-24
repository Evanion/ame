-- Settings, behind the cog (board Settings): the sections on the left (General, Tooltips & charts, Selling, Data, and
-- Sharing, which is the Guild tab's page), the picked section's cards on the right (the settingscard widget,
-- Core/UI/Parts/Settings.lua), scrolling when taller than the window. Every row reads and writes ns.Settings; what a
-- change does besides being saved is the same as the current Settings tab does (Core/UI/SettingsView.lua).
--
--   SettingsScreen.Get(key)                      a setting, with the defaults of the keys this screen adds
--   SettingsScreen.Cards(section, env) -> { { title, rows }, ... }   env: what the game says (see gatherEnv)
--   SettingsScreen.Apply(key, value) -> bool     save a change and do what it does
--   SettingsScreen.FontPath(which) -> path?      the picked LibSharedMedia font ("text" | "heading"), nil: AME's own
--   SettingsScreen.BarTexture() -> path?         the picked bar texture, nil: AME's flat one
local _, ns = ...
local L = ns.L

local App = ns.App

local S = {}
ns.SettingsScreen = S

-- keys this screen adds (Core/Settings.lua's DEFAULTS are shared: they belong there at the cut-over)
S.DEFAULTS = {
  ahMode = "ame", -- at the auction house: "ame" (AME's window takes over) | "game" (the game's window, AME beside it)
  professionMode = "ame", -- opening a profession: "ame" (the Crafting tab) | "game" (the game's window and a frame)
  queueTracker = true, -- the queue's missing reagents in the game's objectives tracker
  fontText = "", -- LibSharedMedia font names; "": AME's own
  fontHeading = "",
  barTexture = "", -- LibSharedMedia statusbar name; "": AME's flat bar
  notifySound = "", -- LibSharedMedia sound name; "": AME's default (Core/Sound.lua)
  soundRequest = true, -- the sound plays when a craft request arrives
  soundAuction = false, -- and when an auction sells or is undercut
  pendingMark = true, -- mark the minimap button and the data broker when something is waiting
}

S.SECTIONS = {
  { "general", L["General"] },
  { "display", L["Tooltips & charts"] },
  { "selling", L["Selling"] },
  { "data", L["Data"] },
  { "sharing", L["Sharing"] },
}

function S.Get(key)
  local v = ns.Settings and ns.Settings:Get(key)
  if v == nil then
    v = S.DEFAULTS[key]
  end
  return v
end

local function opt(value, label)
  return { value = value, label = label }
end

local function lsm()
  local stub = _G.LibStub
  return stub and stub("LibSharedMedia-3.0", true) or nil
end

-- a LibSharedMedia list, AME's own first
local function mediaOptions(kind, own)
  local out = { opt("", own) }
  local media = lsm()
  local ok, list = false, nil
  if media and media.List then
    ok, list = pcall(media.List, media, kind)
  end
  for _, name in ipairs(ok and type(list) == "table" and list or {}) do
    out[#out + 1] = opt(name, name)
  end
  return out
end

function S.FontPath(which)
  local name = S.Get(which == "heading" and "fontHeading" or "fontText")
  local media = lsm()
  if name and name ~= "" and media and media.Fetch then
    return media:Fetch("font", name, true)
  end
end

function S.BarTexture()
  local name = S.Get("barTexture")
  local media = lsm()
  if name and name ~= "" and media and media.Fetch then
    return media:Fetch("statusbar", name, true)
  end
end

-- ------------------------------------------------------------------------------------------------ the cards

local function check(label, key, extra)
  local r = { check = label, key = key, checked = S.Get(key) and true or false }
  for k, v in pairs(extra or {}) do
    r[k] = v
  end
  return r
end

local function field(label, key, options, extra)
  local r = { field = label, key = key, value = S.Get(key), options = options }
  for k, v in pairs(extra or {}) do
    r[k] = v
  end
  return r
end

local function general(env)
  local scales = {}
  for pct = 70, 120, 10 do
    scales[#scales + 1] = opt(pct / 100, ("%d%%"):format(pct))
  end
  local where = { opt("ame", L["The AME window"]), opt("game", L["The game's window"]) }
  local minimap = {
    check = L["Show minimap button"],
    key = "minimap",
    checked = env.minimapLib and not env.minimapHidden or false,
  }
  if not env.minimapLib then
    minimap.check = L["Show minimap button"] .. " " .. L["(needs LibDBIcon; included in releases)"]
    minimap.off = true
  end
  local sounds = {}
  for i, name in ipairs(env.sounds or {}) do
    sounds[i] = opt(name, name)
  end
  local bagOff = not S.Get("baganator")
  return {
    {
      title = L["Window"],
      rows = {
        field(L["Scale"], "windowScale", scales),
        field(L["At the auction house"], "ahMode", where),
        check(L["With the game's window: open AME beside it"], "openWithAH", { indent = true, off = S.Get("ahMode") ~= "game" }),
        field(L["Opening a profession"], "professionMode", where),
        check(L["Show the queue's missing reagents in the objectives tracker"], "queueTracker"),
        field(L["Colours"], "theme", {
          opt("auto", L["Follow market"]),
          opt("Horde", L["Horde red"]),
          opt("Alliance", L["Alliance blue"]),
          opt("Neutral", L["Goblin gold"]),
        }),
        check(L["Colour-blind friendly palette"], "colorBlind"),
        minimap,
      },
    },
    {
      title = L["Fonts and bars"],
      rows = {
        field(L["Text font"], "fontText", mediaOptions("font", L["Arial Narrow (AME)"])),
        field(L["Heading font"], "fontHeading", mediaOptions("font", L["Friz Quadrata (AME)"])),
        field(L["Bar texture"], "barTexture", mediaOptions("statusbar", L["Flat (AME)"])),
        {
          text = L["From LibSharedMedia: fonts and bar textures from your other addons' media packs are listed here too. Korean and Chinese text uses the game's own font."],
        },
      },
    },
    {
      title = L["Notifications"],
      rows = {
        { field = L["Sound"], key = "notifySound", value = env.sound, options = sounds },
        check(L["when a price alert fires"], "alertSound", { indent = true }),
        check(L["when a craft request arrives"], "soundRequest", { indent = true }),
        check(L["when an auction sells or is undercut"], "soundAuction", { indent = true }),
        check(L["Mark the minimap button and the data broker when something is waiting"], "pendingMark"),
        check(L["Announce recorded full scans in chat"], "announceScans"),
      },
    },
    {
      title = L["Other addons"],
      rows = {
        check(L["Baganator: AME's corners and worth sort"], "baganator"),
        check(L["Signal corner: show HOLD and WAIT too"], "baganatorAllSignals", { indent = true, off = bagOff }),
        check(L["Tip corner: mark items to sell too"], "baganatorSellTip", { indent = true, off = bagOff }),
        field(L["Value corner shows"], "baganatorValue", {
          opt("stack", L["The whole stack"]),
          opt("each", L["One item"]),
        }, { off = bagOff }),
        {
          text = L["Place the corners under Icons, and pick the worth sort as the sort, in Baganator's settings. The tip marks a slot; it never moves anything (junk is Baganator's own)."]
            .. " "
            .. (env.baganator and L["Turned off, Baganator lists them until a /reload, but they show nothing."] or L["Baganator isn't installed: nothing to do."]),
        },
      },
    },
  }
end

local function display(env)
  local days = {}
  for _, d in ipairs({ 3, 7, 14, 30 }) do
    days[#days + 1] = opt(d, L["%d days"]:format(d))
  end
  local hidden = env.hidden or 0
  return {
    {
      title = L["Tooltips"],
      rows = {
        check(L["Show prices in item tooltips"], "tooltip"),
        field(L["Average period"], "tooltipAvgDays", days),
        check(L["Always show details (otherwise hold Shift)"], "tooltipDetail"),
      },
    },
    {
      title = L["Charts"],
      rows = {
        field(L["Style"], "chartStyle", { opt("line", L["Line"]), opt("candles", L["Candles"]) }),
        field(L["Open charts with"], "clickModifier", {
          opt("none", L["Off"]),
          opt("alt", L["Alt-click"]),
          opt("altshift", L["Alt+Shift-click"]),
          opt("ctrlalt", L["Ctrl+Alt-click"]),
        }),
        {
          text = L["Off by default: loot addons use modified clicks. Without one, Shift-click an item while AME shows its Item tab."],
        },
      },
    },
    {
      title = L["Hidden items"],
      rows = {
        {
          text = hidden > 0
              and L["%d items are hidden from the Market, Arbitrage and Portfolio lists. AME still records their prices."]:format(hidden)
            or L["Nothing hidden. Right-click an item in the Market, Arbitrage or Portfolio list to hide it."],
        },
        {
          buttons = {
            { label = L["Show them"], action = "showHidden", off = hidden == 0 },
            { label = L["Unhide all"], action = "unhideAll", off = hidden == 0 },
          },
        },
      },
    },
  }
end

local function selling()
  local function cut(label, key)
    return { input = "", label = label, key = key, value = tostring(S.Get(key) or ""), suffix = "%", numeric = true, width = 44 }
  end
  local hours = {}
  for _, h in ipairs({ 2, 8, 24 }) do
    hours[#hours + 1] = opt(h, L["%d h"]:format(h))
  end
  local warns = { opt(0, L["Off"]) }
  for _, pct in ipairs({ 5, 10, 20, 50 }) do
    warns[#warns + 1] = opt(pct, L["%d%% over"]:format(pct))
  end
  return {
    {
      title = L["Selling"],
      rows = { cut(L["Faction AH cut"], "cutFaction"), cut(L["Goblin AH cut"], "cutNeutral"), field(L["Listing length"], "listingHours", hours) },
    },
    {
      title = L["Buying"],
      rows = {
        field(L["Warn when the price goes up"], "buyWarnPct", warns),
        {
          text = L["Buying in bulk: when the game's price for the order is this much over what the listings showed, AME says so and the button reads Confirm anyway."],
        },
      },
    },
  }
end

local function data(env)
  local factors = { opt(false, L["Off"]) }
  for _, x in ipairs({ 3, 4, 6, 10 }) do
    factors[#factors + 1] = opt(x, L["%dx off usual"]:format(x))
  end
  local rows = {
    field(L["Full scans"], "scanMode", {
      opt("detailed", L["Detailed: every listing"]),
      opt("fast", L["Fast: cheapest per item"]),
    }),
    {
      text = L["Detailed reads every listing - the most accurate prices - and the game allows one every 15 minutes. Fast reads only each item's cheapest listing, any time; its market prices come from how far above the cheapest each item usually sells, learned from detailed scans and searches. For the Full scan button and /ame scan."],
    },
  }
  if env.summary and env.summary ~= "" then
    rows[#rows + 1] = { text = env.summary }
  end
  rows[#rows + 1] = {
    buttons = {
      { label = L["Import from Auctionator"], action = "importAuctionator" },
      { label = L["Rebuild market data"], action = "rebuild" },
      { label = L["Run self-test"], action = "selftest" },
    },
  }
  rows[#rows + 1] = field(L["Ignore outrageous prices"], "outlierFactor", factors)
  rows[#rows + 1] = {
    text = L["Days where an item's price is this many times above (or below) its neighbouring days are left out of the screener, signals, alerts and charts - typically one listing at a 1000% markup in a thin market."],
  }
  return { { title = L["Data"], rows = rows } }
end

local function sharing()
  return {
    {
      title = L["Sharing"],
      rows = {
        { text = L["Sharing prices with your guild and trusted players is on the Guild tab."] },
        { buttons = { { label = L["Open Sharing"], action = "goSharing" } } },
      },
    },
  }
end

function S.Cards(section, env)
  env = env or {}
  if section == "display" then
    return display(env)
  elseif section == "selling" then
    return selling()
  elseif section == "data" then
    return data(env)
  elseif section == "sharing" then
    return sharing()
  end
  return general(env)
end

-- ------------------------------------------------------------------------------------------------ changes

local function try(fn, ...)
  if type(fn) == "function" then
    pcall(fn, ...)
  end
end

local function oldUI()
  return ns.UI
end

local function redrawBags()
  local bag = ns.Baganator
  if bag and bag.SettingChanged then
    pcall(bag.SettingChanged, bag, S.Get("baganator") ~= false)
  end
end

-- what a change does besides being saved (as Core/UI/SettingsView.lua does it)
S.EFFECTS = {
  windowScale = function(value)
    if ns.App and ns.App.frame and ns.App.frame.SetScale then
      ns.App.frame:SetScale(value)
    end
    local UI = oldUI()
    try(UI and UI.ApplyPlacement, UI)
  end,
  theme = function()
    local UI = oldUI()
    try(UI and UI.ApplyTheme, UI)
  end,
  colorBlind = function()
    local W = ns.Widgets
    try(W and W.ApplyPalette)
    local UI = oldUI()
    try(UI and UI.PaletteChanged, UI)
  end,
  baganator = function(on)
    local bag = ns.Baganator
    if bag and bag.SettingChanged then
      pcall(bag.SettingChanged, bag, on)
    end
  end,
  baganatorAllSignals = redrawBags,
  baganatorSellTip = redrawBags,
  baganatorValue = redrawBags,
  tooltipAvgDays = function(value)
    local UI = oldUI()
    if UI then
      local q = UI.mq
      if q and q.sortKey and tostring(q.sortKey):match("^avg%d+$") then
        q.sortKey = "avg" .. value
      end
      UI.list = nil
    end
  end,
  chartStyle = function()
    local UI = oldUI()
    if UI and UI.series then
      try(UI.DrawItemChart, UI)
    end
  end,
  cutFaction = function()
    local AME = ns.AME
    try(AME and AME.InvalidateIndexLater, AME, nil, 2)
  end,
  cutNeutral = function()
    local AME = ns.AME
    try(AME and AME.InvalidateIndexLater, AME, nil, 2)
  end,
  listingHours = function()
    local AME = ns.AME
    try(AME and AME.InvalidateIndex, AME)
    local UI = oldUI()
    try(UI and UI.RenderArbitrage, UI)
  end,
  scanMode = function()
    local B = ns.ScanButton
    try(B and B.Refresh, B)
  end,
  outlierFactor = function()
    local AME = ns.AME
    try(AME and AME.InvalidateIndex, AME)
    try(AME and AME.RebuildIndex, AME)
  end,
  notifySound = function(value)
    if ns.Sound then
      ns.Sound.Preview(value) -- picking one plays it
    end
  end,
  pendingMark = function()
    if ns.Pending then
      try(ns.Pending.Update)
    end
  end,
}

-- values a key accepts (a number box can be typed into)
local function clean(key, value)
  if key == "cutFaction" or key == "cutNeutral" then
    local n = tonumber(value)
    if not n or n < 0 or n > 100 then
      return nil
    end
    return n
  end
  if key == "notifySound" and value == (ns.Sound and ns.Sound.DEFAULT) then
    return ""
  end
  return value
end

function S.Apply(key, value)
  if type(key) ~= "string" then
    return false
  end
  if key == "minimap" then
    local Launcher = ns.Launcher
    if Launcher and Launcher.HasMinimapLibrary and Launcher:HasMinimapLibrary() then
      Launcher:SetMinimap(value and true or false)
      return true
    end
    return false
  end
  local v = clean(key, value)
  if v == nil and value ~= nil then
    return false
  end
  ns.Settings:Set(key, v)
  local effect = S.EFFECTS[key]
  if effect then
    pcall(effect, v)
  end
  return true
end

-- ------------------------------------------------------------------------------------------------ the screen

local function gatherEnv()
  local env = {}
  local Launcher = ns.Launcher
  env.minimapLib = Launcher and Launcher.HasMinimapLibrary and Launcher:HasMinimapLibrary() or false
  local mm = AME_DB and AME_DB.settings and AME_DB.settings.minimap
  env.minimapHidden = mm and mm.hide or false
  env.baganator = ns.Baganator and ns.Baganator.Present and ns.Baganator.Present() or false
  env.sounds = ns.Sound and ns.Sound.List() or {}
  env.sound = ns.Sound and ns.Sound.Chosen() or nil
  local watch = ns.AME and ns.AME.watch
  env.hidden = watch and watch.HiddenCount and watch:HiddenCount() or 0
  local UI = ns.UI
  if UI and UI.DataSummaryText then
    local ok, text = pcall(UI.DataSummaryText)
    env.summary = ok and text or nil
  end
  return env
end
S.GatherEnv = gatherEnv

local SIDEBAR_W = 190

local function build(app, params)
  local section = params.section or "general"
  local entries = {}
  for i, sec in ipairs(S.SECTIONS) do
    entries[i] = { key = sec[1], label = sec[2], selected = sec[1] == section }
  end
  local w = app.frame and app.frame:GetWidth() or App.W
  local cardW = math.min(560, math.max(300, (w or App.W) - 24 - SIDEBAR_W - 10 - 8))
  local cards = {}
  for i, c in ipairs(S.Cards(section, gatherEnv())) do
    cards[i] = {
      id = "settings.card" .. i,
      type = "settingscard",
      props = { title = c.title, rows = c.rows, width = cardW },
      meta = { w = cardW },
    }
  end
  return {
    id = "settings",
    type = "row",
    props = { gap = 10 },
    children = {
      { id = "settings.nav", type = "sidebar", props = { entries = entries, action = "section" }, meta = { w = SIDEBAR_W } },
      { id = "settings.cards", type = "scrollcolumn", props = { gap = 10 }, meta = { grow = 1 }, children = cards },
    },
  }
end

App.Screen("settings", {
  Build = build,
  Title = function()
    return L["Settings"]
  end,
  Status = function()
    return L["Settings are saved per account"]
  end,
  actions = {
    section = function(app, p)
      if not p or not p.key then
        return
      end
      if p.key == "sharing" and App.screens.sharing then
        app:Go("sharing")
      else
        app:Go("settings", { section = p.key }, true)
      end
    end,
    setting = function(app, p)
      if p and S.Apply(p.key, p.value) then
        app:Render()
      end
    end,
    showHidden = function(app)
      app:Go("market", { view = "hidden" })
    end,
    unhideAll = function(app)
      local watch = ns.AME and ns.AME.watch
      if watch and watch.UnhideAll then
        watch:UnhideAll()
      end
      local UI = ns.UI
      if UI and UI.SetHidden then
        pcall(UI.SetHidden, UI, nil, false)
      end
      app:Render()
    end,
    importAuctionator = function()
      local AME = ns.AME
      try(AME and AME.Backfill, AME, true)
    end,
    rebuild = function()
      local AME = ns.AME
      try(AME and AME.RebuildIndex, AME)
    end,
    selftest = function()
      if ns.SelfTest and ns.SelfTest.Run then
        pcall(ns.SelfTest.Run, ns.AME)
      end
    end,
    goSharing = function(app)
      app:Go(App.screens.sharing and "sharing" or app:TabScreen("guild"))
    end,
  },
})
