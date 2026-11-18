-- Settings tab: every AME setting, storage figures and data actions, as cards in three scrolling columns:
-- Window | Tooltips, Charts | Selling, Notifications, Data (Advanced adds Data quality). Basic shows what most
-- players change. Narrow windows stack the third column under the second.
local _, ns = ...
local L = ns.L

local W = ns.Widgets
local UI = ns.UI

local function ago(t)
  return W.Ago(t, GetServerTime())
end

---------------------------------------------------------------------------------------------------------------------
-- Settings

UI.SETTINGS_GAP = 10 -- between columns and cards

function UI:CreateSettingsView(parent, contentArea)
  local outer = contentArea(parent)
  local slots = UI.Slots(outer, { status = true })
  outer.slots = slots
  -- everything scrolls when the window is shorter than the tab's content
  local pane = W.ScrollPane(slots.main)
  local v = pane.content
  v.pane = pane
  self.settingsView = v
  local checks = {}
  v.checks = checks
  slots.status:SetText(L["Settings are saved per account  ·  sharing settings are on the Sync tab"])

  -- three columns of cards
  local cols, stacks = {}, {}
  for i = 1, 3 do
    cols[i] = CreateFrame("Frame", nil, v)
    cols[i]:SetHeight(1)
    stacks[i] = UI.Stack(cols[i], 0)
  end
  v.columns, v.stacks = cols, stacks
  function v:LayoutColumns()
    UI.Relayout(self, function()
      self:PlaceColumns()
      self.pane:Measure()
    end)
  end
  function v:PlaceColumns()
    local gap = UI.SETTINGS_GAP
    local narrow = UI.compact
    local n = narrow and 2 or 3
    local w = math.max(120, ((self:GetWidth() or 600) - gap * (n - 1)) / n)
    if self.FlowActions then
      self:FlowActions(w - 16)
    end
    for i = 1, 3 do
      cols[i]:SetWidth(w)
      cols[i]:SetHeight(math.max(1, stacks[i]:Height(w)))
      cols[i]:ClearAllPoints()
    end
    cols[1]:SetPoint("TOPLEFT", 0, 0)
    cols[2]:SetPoint("TOPLEFT", cols[1], "TOPRIGHT", gap, 0)
    if narrow then
      cols[3]:SetPoint("TOPLEFT", cols[2], "BOTTOMLEFT", 0, -gap)
    else
      cols[3]:SetPoint("TOPLEFT", cols[2], "TOPRIGHT", gap, 0)
    end
  end
  v:HookScript("OnSizeChanged", function()
    v:LayoutColumns()
  end)

  -- a card: its heading, then rows
  local function card(col, title, gap)
    local c = stacks[col]:Card(gap or UI.SETTINGS_GAP)
    c.stack:Heading(title, 0)
    return c, c.stack
  end
  local function check(st, label, key, onChange, indent)
    local row = st:Row(18, 6)
    local c = W.SettingCheck(row, label, key, indent or 0, -1, onChange)
    checks[#checks + 1] = c
    return c, row
  end
  -- "label ... control": the label on the left, the control right-aligned
  local function dropdown(st, label, width, options, onSelect, note)
    local row = st:Row(22, 6)
    local dd = W.Dropdown(row, width, options, onSelect, { neutral = true })
    dd:SetPoint("RIGHT", 0, 0)
    local text = W.Text(row, "GameFontHighlightSmall")
    text:SetPoint("LEFT", 0, 0)
    text:SetPoint("RIGHT", dd, "LEFT", -6, 0)
    text:SetText(note and (label .. "  " .. W.Dim(note)) or label)
    text:SetWordWrap(false)
    return dd, row
  end
  local function paragraph(st, text)
    local p = st:Text("GameFontDisableSmall", 4)
    p:SetSpacing(2)
    p:SetText(text)
    return p
  end

  -- column 1: Window
  local _, st = card(1, L["Window"], 0)
  local scales = {}
  for pct = 70, 120, 10 do
    scales[#scales + 1] = { pct / 100, ("%d%%"):format(pct) }
  end
  v.scale = dropdown(st, L["Scale"], 80, scales, function(value)
    ns.Settings:Set("windowScale", value)
    UI:ApplyPlacement()
  end, "(70-120%)")
  check(st, L["Dock next to the auction house when there's room"], "dockToAH", function()
    if UI.frame and UI.frame:IsShown() then
      UI:ApplyPlacement()
    end
  end)
  check(st, L["Open with the auction house"], "openWithAH")
  check(st, L["...and close with it"], "closeWithAH", nil, 20)
  check(st, L["Switch to the Item tab for what you put up for sale"], "sellSwitchesTab")
  local themes = {
    { "auto", L["Follow market"] },
    { "Horde", L["Horde red"] },
    { "Alliance", L["Alliance blue"] },
    { "Neutral", L["Goblin gold"] },
  }
  v.theme = dropdown(st, L["Colours"], 110, themes, function(value)
    ns.Settings:Set("theme", value)
    UI:ApplyTheme()
  end)
  v.colorBlind = check(st, L["Colour-blind friendly palette"], "colorBlind", function()
    W.ApplyPalette()
    UI:PaletteChanged()
  end)

  -- column 2: Tooltips, Charts
  _, st = card(2, L["Tooltips"], 0)
  local tooltipCheck = check(st, L["Show AME prices in item tooltips"], "tooltip")
  table.remove(checks)
  table.insert(checks, 1, tooltipCheck) -- checks[1]: the tooltip switch
  local avgs = {
    { 3, L["%d days"]:format(3) },
    { 7, L["%d days"]:format(7) },
    { 14, L["%d days"]:format(14) },
    { 30, L["%d days"]:format(30) },
  }
  v.avgDays = dropdown(st, L["Average period"], 90, avgs, function(value)
    -- one period everywhere: tooltips, the screener's average column and the item page
    ns.Settings:Set("tooltipAvgDays", value)
    local q = UI.mq
    if q and q.sortKey and q.sortKey:match("^avg%d+$") then
      q.sortKey = "avg" .. value
    end
    UI.list = nil
  end)
  check(st, L["Always show details (otherwise hold Shift)"], "tooltipDetail")

  _, st = card(2, L["Charts"])
  local styles = { { "line", L["Line"] }, { "candles", L["Candles"] } }
  v.style = dropdown(st, L["Style"], 100, styles, function(value)
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
  v.click = dropdown(st, L["Open charts with"], 110, clicks, function(value)
    ns.Settings:Set("clickModifier", value)
  end)
  paragraph(st, L["Off by default: loot addons use modified clicks. With AME open, Shift-click an item."])

  -- column 3: Selling, Notifications, Data (+ Data quality)
  _, st = card(3, L["Selling"], 0)
  local function cutInput(key, label)
    local row = st:Row(22, 6)
    local pct = W.Text(row, "GameFontHighlightSmall")
    pct:SetPoint("RIGHT", 0, 0)
    pct:SetText("%")
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
    input:SetPoint("RIGHT", pct, "LEFT", -4, 0)
    local text = W.Text(row, "GameFontHighlightSmall")
    text:SetPoint("LEFT", 0, 0)
    text:SetText(label)
    input.key = key
    return input
  end
  v.cutFaction = cutInput("cutFaction", L["Faction AH cut"])
  v.cutNeutral = cutInput("cutNeutral", L["Goblin AH cut"])
  local hours = {
    { 2, L["%d h"]:format(2) },
    { 8, L["%d h"]:format(8) },
    { 24, L["%d h"]:format(24) },
  }
  v.hours = dropdown(st, L["Listing length"], 80, hours, function(value)
    ns.Settings:Set("listingHours", value)
    ns.AME:InvalidateIndex() -- VENDOR signals depend on the deposit
    if UI.RenderArbitrage then
      UI:RenderArbitrage()
    end
  end)

  _, st = card(3, L["Notifications"])
  check(st, L["Announce recorded full scans"], "announceScans")
  check(st, L["Sound when an alert fires"], "alertSound")

  _, st = card(3, L["Data"])
  v.storage = st:Text("GameFontDisableSmall", 6)
  v.storage:SetSpacing(2)
  -- the data actions in one row, sized to their labels; what each does is on its tooltip
  local actions = st:Row(22, 8)
  v.actionsRow = actions
  local buttons = {}
  for _, a in ipairs({
    {
      L["Import from Auctionator"],
      L["If Auctionator is installed: imports its recent daily prices for days AME has no data for (faction AH)."],
      function()
        ns.AME:Backfill(true)
      end,
    },
    {
      L["Rebuild market data"],
      L["Recomputes the 30-day summaries behind the screener, tooltips and alerts."],
      function()
        ns.AME:RebuildIndex()
      end,
    },
    {
      L["Run self-test"],
      L["Checks every part of AME and offers a reload so the results are saved."],
      function()
        ns.SelfTest.Run(ns.AME)
      end,
    },
  }) do
    local b = W.Button(actions, a[1], 80, 22, a[3])
    b:SetWidth(math.ceil(b.label:GetStringWidth() or 60) + 16)
    buttons[#buttons + 1] = b
    W.Tooltip(b, function(tip)
      W.TipText(tip, a[1], a[2])
    end)
  end
  -- left to right, onto a new line when the next button doesn't fit the card
  function v:FlowActions(width)
    local x, y = 0, 0
    for _, b in ipairs(buttons) do
      local bw = b:GetWidth() or 80
      if x > 0 and x + bw > width then
        x, y = 0, y - 28
      end
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", actions, "TOPLEFT", x, y)
      x = x + bw + 6
    end
    actions:SetHeight(22 - y)
  end
  local minimapRow = st:Row(18, 8)
  v.minimap = W.Check(minimapRow, L["Show minimap button"], function(on)
    ns.Launcher:SetMinimap(on)
  end)
  v.minimap:SetPoint("TOPLEFT", 0, -1)

  local factors = {
    { false, L["Off"] },
    { 3, L["%dx off usual"]:format(3) },
    { 4, L["%dx off usual"]:format(4) },
    { 6, L["%dx off usual"]:format(6) },
    { 10, L["%dx off usual"]:format(10) },
  }
  local outlierRow
  v.outliers, outlierRow = dropdown(st, L["Ignore outrageous prices"], 110, factors, function(value)
    ns.Settings:Set("outlierFactor", value)
    ns.AME:InvalidateIndex()
    ns.AME:RebuildIndex()
    if UI.itemID and UI.current == "item" then
      UI:ShowItem(UI.itemID)
    end
  end)
  outlierRow:EnableMouse(true)
  W.Tooltip(outlierRow, function(tip)
    W.TipText(
      tip,
      L["Ignore outrageous prices"],
      L["Days where an item's price is this many times above (or below) its neighbouring days are left out of the screener, signals, alerts and charts - typically one listing at a 1000% markup in a thin market. Within a full scan, AME already ignores expensive listings: market price uses the cheapest part of the supply."]
    )
  end)

  v:SetScript("OnShow", function()
    UI:RefreshSettings()
  end)
  outer:HookScript("OnShow", function()
    UI:RefreshSettings()
  end)
  function outer:SetCompact()
    v:LayoutColumns()
    v.pane:Measure()
  end
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

  -- one line: this market's history, all markets' size, the last full scan
  local AME = ns.AME
  local parts = { L["Market: %s"]:format(ns.ShardLabel(AME:CurrentShard())) }
  if AME:HistoryLoaded() then
    local shards, bytes = 0, 0
    for _, data in pairs(AME.history.shards) do
      local _, b = ns.Store.Footprint(data)
      shards, bytes = shards + 1, bytes + b
    end
    local here = AME.history.shards[AME:CurrentShard()]
    local hereDays = ns.Store.Footprint(here)
    parts[#parts + 1] = L["this market: %d days, %d recent scans"]:format(hereDays, here and #(here.raw or {}) or 0)
    parts[#parts + 1] = L["all markets: %.0f KB"]:format(bytes / 1024)
  else
    parts[#parts + 1] = L["History not loaded yet."]
  end
  local f = AME_DB.stats.lastFull
  parts[#parts + 1] = f and L["last full scan %s"]:format(ago(f.at)) or L["No full scan recorded yet."]
  v.storage:SetText(table.concat(parts, "  ·  "))
  v:LayoutColumns()
  v.pane:Measure()
end
