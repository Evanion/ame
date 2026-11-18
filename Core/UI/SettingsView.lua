-- Settings tab: every AME setting, storage figures and data actions, in two scrolling columns of sections.
-- Basic shows what most players change; Advanced adds data quality and diagnostics.
local _, ns = ...
local L = ns.L

local W = ns.Widgets
local UI = ns.UI

local function ago(t)
  return W.Ago(t, GetServerTime())
end

---------------------------------------------------------------------------------------------------------------------
-- Settings

local LABEL_W = 150 -- label column of "label: control" rows

function UI:CreateSettingsView(parent, contentArea)
  local outer = contentArea(parent)
  local slots = UI.Slots(outer, { toolbar = 22, status = true })
  outer.slots = slots
  -- everything scrolls when the window is shorter than the tab's content
  local pane = W.ScrollPane(slots.main)
  local v = pane.content
  v.pane = pane
  self.settingsView = v
  local checks = {}
  v.checks = checks
  v.advanced = {} -- shown in Advanced mode only (the last sections of the right column)

  -- Basic | Advanced
  v.level = W.Segmented(slots.toolbar, { { "basic", L["Basic"] }, { "advanced", L["Advanced"] } }, {
    minWidth = 70,
    onSelect = function(key)
      ns.Settings:Set("settingsLevel", key)
      UI:RefreshSettings()
    end,
  })
  v.level:SetPoint("LEFT", 0, 0)
  v.levelHint = W.Text(slots.toolbar, "GameFontDisableSmall")
  v.levelHint:SetPoint("LEFT", v.level, "RIGHT", 10, 0)
  v.levelHint:SetText(L["Advanced adds data quality and diagnostics."])
  slots.status:SetText(L["Settings are saved per account. Sharing settings are on the Sync tab."])

  -- two columns, each a stack of sections
  local left = CreateFrame("Frame", nil, v)
  left:SetPoint("TOPLEFT", 0, 0)
  left:SetPoint("RIGHT", v, "CENTER", -8, 0)
  left:SetHeight(1)
  local right = CreateFrame("Frame", nil, v)
  right:SetPoint("TOPLEFT", v, "TOP", 8, 0)
  right:SetPoint("RIGHT", v, "RIGHT", 0, 0)
  right:SetHeight(1)
  local L1, L2 = UI.Stack(left), UI.Stack(right)

  local function check(st, label, key, onChange, indent)
    local row = st:Row(18, 6)
    local c = W.SettingCheck(row, label, key, indent or 0, -1, onChange)
    checks[#checks + 1] = c
    return c, row
  end
  local function dropdown(st, label, width, options, onSelect)
    local row = st:Row(22, 6)
    local dd = W.Dropdown(row, width, options, onSelect, { neutral = true })
    W.Labeled(row, label, dd, nil, LABEL_W):SetPoint("LEFT", 0, 0)
    return dd, row
  end
  local function paragraph(st, text)
    local p = st:Text("GameFontDisableSmall", 4)
    p:SetSpacing(2)
    p:SetText(text)
    return p
  end

  -- left: Window, Tooltips, Charts
  L1:Heading(L["Window"], 0)
  local scales = {}
  for pct = 70, 120, 10 do
    scales[#scales + 1] = { pct / 100, ("%d%%"):format(pct) }
  end
  v.scale = dropdown(L1, L["Window scale"], 110, scales, function(value)
    ns.Settings:Set("windowScale", value)
    UI:ApplyPlacement()
  end)
  check(L1, L["Dock AME beside the auction house when there's room"], "dockToAH", function()
    if UI.frame and UI.frame:IsShown() then
      UI:ApplyPlacement()
    end
  end)
  check(L1, L["Open AME together with the auction house"], "openWithAH")
  check(L1, L["...and close it when the auction house closes"], "closeWithAH", nil, 20)
  check(L1, L["Switch to the Item tab when you put an item up for sale"], "sellSwitchesTab")
  local themes = {
    { "auto", L["Follow market"] },
    { "Horde", L["Horde red"] },
    { "Alliance", L["Alliance blue"] },
    { "Neutral", L["Goblin gold"] },
  }
  v.theme = dropdown(L1, L["Window colours"], 110, themes, function(value)
    ns.Settings:Set("theme", value)
    UI:ApplyTheme()
  end)
  v.colorBlind = check(L1, L["Colour-blind friendly palette (blue / orange)"], "colorBlind", function()
    W.ApplyPalette()
    UI:PaletteChanged()
  end)
  local minimapRow = L1:Row(18, 6)
  v.minimap = W.Check(minimapRow, L["Show minimap button"], function(on)
    ns.Launcher:SetMinimap(on)
  end)
  v.minimap:SetPoint("TOPLEFT", 0, -1)

  L1:Heading(L["Tooltips"])
  local tooltipCheck = check(L1, L["Show AME prices in item tooltips"], "tooltip")
  table.remove(checks)
  table.insert(checks, 1, tooltipCheck) -- checks[1]: the tooltip switch
  local avgs = {
    { 3, L["%d days"]:format(3) },
    { 7, L["%d days"]:format(7) },
    { 14, L["%d days"]:format(14) },
    { 30, L["%d days"]:format(30) },
  }
  v.avgDays = dropdown(L1, L["average period"], 90, avgs, function(value)
    -- one period everywhere: tooltips, the screener's average column and the item page
    ns.Settings:Set("tooltipAvgDays", value)
    local q = UI.mq
    if q and q.sortKey and q.sortKey:match("^avg%d+$") then
      q.sortKey = "avg" .. value
    end
    UI.list = nil
  end)
  check(L1, L["Always show full tooltip details (otherwise hold Shift)"], "tooltipDetail")

  L1:Heading(L["Charts"])
  local styles = { { "line", L["Line"] }, { "candles", L["Candles"] } }
  v.style = dropdown(L1, L["Chart style"], 120, styles, function(value)
    ns.Settings:Set("chartStyle", value)
    if UI.series then
      UI:DrawItemChart()
    end
  end)
  local clicks = {
    { "none", L["Off"] },
    { "alt", L["Alt-click"] },
    { "altshift", L["Alt+Shift-click"] },
    { "ctrlalt", L["Ctrl+Alt-click"] },
  }
  v.click = dropdown(L1, L["Open item charts with"], 120, clicks, function(value)
    ns.Settings:Set("clickModifier", value)
  end)
  paragraph(
    L1,
    L["Off by default: loot and raid addons (e.g. Gargul, AHDB) use modified clicks on items and links. With the AME window open, Shift-click an item to chart it."]
  )

  -- right: Selling, Notifications, Data; Advanced: Data quality, Diagnostics
  L2:Heading(L["Selling"], 0)
  local function cutInput(key, label)
    local row = L2:Row(22, 6)
    local input = W.Input(row, {
      width = 44,
      numeric = true,
      onChange = function(_, n, user)
        if user and n and n <= 100 then
          ns.Settings:Set(key, n)
          ns.AME:InvalidateIndexLater(nil, 2) -- VENDOR signals depend on the cut (rebuilt once typing settles)
        end
      end,
    })
    W.Labeled(row, label, input, nil, LABEL_W):SetPoint("LEFT", 0, 0)
    local pct = W.Text(row, "GameFontHighlightSmall")
    pct:SetPoint("LEFT", input, "RIGHT", 4, 0)
    pct:SetText("%")
    input.key = key
    return input
  end
  v.cutFaction = cutInput("cutFaction", L["Faction auction houses"])
  v.cutNeutral = cutInput("cutNeutral", L["Goblin auction houses"])
  local hours = {
    { 2, L["%d h listings"]:format(2) },
    { 8, L["%d h listings"]:format(8) },
    { 24, L["%d h listings"]:format(24) },
  }
  v.hours = dropdown(L2, L["Deposits for"], 110, hours, function(value)
    ns.Settings:Set("listingHours", value)
    ns.AME:InvalidateIndex() -- VENDOR signals depend on the deposit
    if UI.RenderArbitrage then
      UI:RenderArbitrage()
    end
  end)

  L2:Heading(L["Notifications"])
  check(L2, L["Announce recorded full scans in chat"], "announceScans")
  check(L2, L["Play a sound when a watchlist alert fires"], "alertSound")

  L2:Heading(L["Data"])
  v.storage = L2:Text("GameFontHighlightSmall", 6)
  v.storage:SetSpacing(3)
  local function action(st, label, text, fn, list)
    local row = st:Row(22, 8)
    local b = W.Button(row, label, 190, 22, fn)
    b:SetPoint("LEFT")
    local p = paragraph(st, text)
    if list then
      list[#list + 1] = row
      list[#list + 1] = p
    end
    return b
  end
  action(
    L2,
    L["Import history from Auctionator"],
    L["If Auctionator is installed: imports its recent daily prices for days AME has no data for (faction AH)."],
    function()
      ns.AME:Backfill(true)
    end
  )

  local adv = v.advanced
  adv[#adv + 1] = L2:Heading(L["Data quality"])
  local factors = {
    { false, L["Off"] },
    { 3, L["%dx off usual"]:format(3) },
    { 4, L["%dx off usual"]:format(4) },
    { 6, L["%dx off usual"]:format(6) },
    { 10, L["%dx off usual"]:format(10) },
  }
  local outlierRow
  v.outliers, outlierRow = dropdown(L2, L["Ignore outrageous prices"], 120, factors, function(value)
    ns.Settings:Set("outlierFactor", value)
    ns.AME:InvalidateIndex()
    ns.AME:RebuildIndex()
    if UI.itemID and UI.current == "item" then
      UI:ShowItem(UI.itemID)
    end
  end)
  adv[#adv + 1] = outlierRow
  adv[#adv + 1] = paragraph(
    L2,
    L["Days where an item's price is this many times above (or below) its neighbouring days are left out of the screener, signals, alerts and charts - typically one listing at a 1000% markup in a thin market. Within a full scan, AME already ignores expensive listings: market price uses the cheapest part of the supply."]
  )
  adv[#adv + 1] = L2:Heading(L["Diagnostics"])
  action(
    L2,
    L["Rebuild market index"],
    L["Recomputes the 30-day summaries behind the screener, tooltips and alerts."],
    function()
      ns.AME:RebuildIndex()
    end,
    adv
  )
  action(L2, L["Run self-test"], L["Checks every part of AME and offers a reload so the results are saved."], function()
    ns.SelfTest.Run(ns.AME)
  end, adv)

  v:SetScript("OnShow", function()
    UI:RefreshSettings()
  end)
  outer:HookScript("OnShow", function()
    UI:RefreshSettings()
  end)
  return outer
end

-- the colour-blind palette changed: redraw what's coloured
function UI:PaletteChanged()
  if not self.frame then
    return
  end
  self:ApplyTheme()
  if self.series and self.DrawItemChart then
    self:DrawItemChart()
  end
end

function UI:RefreshSettings()
  local v = self.settingsView
  if not (v and v:IsShown()) then
    return
  end
  local advanced = ns.Settings:Get("settingsLevel") == "advanced"
  v.level:Select(advanced and "advanced" or "basic", true)
  for _, obj in ipairs(v.advanced) do
    obj:SetShown(advanced)
  end
  for _, c in ipairs(v.checks) do
    c:SetChecked(ns.Settings:Get(c.key))
  end
  v.style:SetValue(ns.Settings:Get("chartStyle"))
  v.click:SetValue(ns.Settings:Get("clickModifier"))
  v.outliers:SetValue(ns.Settings:Get("outlierFactor"))
  v.avgDays:SetValue(ns.Settings:Get("tooltipAvgDays"))
  v.theme:SetValue(ns.Settings:Get("theme"))
  v.scale:SetValue(ns.Settings:Get("windowScale"))
  v.cutFaction:SetText(tostring(ns.Settings:Get("cutFaction")))
  v.cutNeutral:SetText(tostring(ns.Settings:Get("cutNeutral")))
  v.hours:SetValue(ns.Settings:Get("listingHours"))
  local hasIcon = ns.Launcher:HasMinimapLibrary()
  v.minimap:SetChecked(hasIcon and not AME_DB.settings.minimap.hide)
  v.minimap.label:SetText(
    hasIcon and L["Show minimap button"]
      or L["Show minimap button"] .. " " .. W.Dim(L["(needs LibDBIcon; included in releases)"])
  )

  local AME = ns.AME
  local lines = { L["Market: %s"]:format(W.Color("white", ns.ShardLabel(AME:CurrentShard()))) }
  if AME:HistoryLoaded() then
    local shards, bytes = 0, 0
    for _, data in pairs(AME.history.shards) do
      local _, b = ns.Store.Footprint(data)
      shards, bytes = shards + 1, bytes + b
    end
    local here = AME.history.shards[AME:CurrentShard()]
    local hereDays = ns.Store.Footprint(here)
    lines[#lines + 1] = L["This market: %d days of history, %d recent scans kept in full"]:format(
      hereDays,
      here and #(here.raw or {}) or 0
    )
    lines[#lines + 1] = L["All markets: %d, %.0f KB of compressed daily history"]:format(shards, bytes / 1024)
  else
    lines[#lines + 1] = L["History not loaded yet."]
  end
  local f = AME_DB.stats.lastFull
  lines[#lines + 1] = f and L["Last full scan: %d items, %s"]:format(f.items, ago(f.at))
    or L["No full scan recorded yet."]
  v.storage:SetText(table.concat(lines, "\n"))
  v.pane:Measure()
end
