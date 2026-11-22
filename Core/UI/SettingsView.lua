-- Settings tab: a sidebar of sections (like the Guide) and the chosen section's cards over the whole width, in
-- columns on wide windows.
-- Sections: General (window, notifications), Tooltips & charts, Selling, Sharing (guild and trusted players, built
-- by SyncView), Data. Narrow windows pick the section from a dropdown instead of the sidebar.
local _, ns = ...
local L = ns.L

local W = ns.Widgets
local UI = ns.UI

local function kb(bytes)
  return bytes >= 1024 * 1024 and ("%.1f MB"):format(bytes / 1024 / 1024) or ("%.0f KB"):format(bytes / 1024)
end

local function count(t)
  local n = 0
  for _ in pairs(t or {}) do
    n = n + 1
  end
  return n
end

local function ago(t)
  return W.Ago(t, GetServerTime())
end

---------------------------------------------------------------------------------------------------------------------
-- Settings

UI.SETTINGS_GAP = 10 -- between cards
UI.SETTINGS_COLUMN = 380 -- a column of cards is at least this wide: wider windows get two, then three
UI.SETTINGS_COLUMNS = 3

function UI.SettingsSections()
  return {
    { "general", L["General"] },
    { "display", L["Tooltips & charts"] },
    { "selling", L["Selling"] },
    { "sharing", L["Sharing"] },
    { "data", L["Data"] },
  }
end

function UI:CreateSettingsView(parent, contentArea)
  local outer = contentArea(parent)
  local slots = UI.Slots(outer, { toolbar = 22, left = UI.SIDEBAR_W, status = true })
  outer.slots = slots
  -- the chosen section scrolls when the window is shorter than it
  local pane = W.ScrollPane(slots.main)
  local v = pane.content
  v.pane = pane
  v.slots = slots
  self.settingsView = v
  local checks = {}
  v.checks = checks
  v.sections, v.links = {}, {}
  v.current = "general"
  slots.status:SetText(L["Settings are saved per account"])
  local sections = UI.SettingsSections()

  -- sidebar: the sections (narrow windows: a dropdown on the toolbar)
  local list = slots.left.content
  for k, sec in ipairs(sections) do
    local b = CreateFrame("Button", nil, list)
    b:SetHeight(20)
    b:SetPoint("TOPLEFT", 4, -8 - (k - 1) * 22)
    b:SetPoint("RIGHT", list, "RIGHT", -4, 0)
    b.sel = b:CreateTexture(nil, "BACKGROUND")
    b.sel:SetAllPoints()
    W.Fill(b.sel, W.COLORS.rowSelected)
    b.sel:SetShown(k == 1)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    W.Fill(b.hl, W.COLORS.rowHover)
    b.text = W.Text(b, "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", 8, 0)
    b.text:SetPoint("RIGHT", -4, 0)
    b.text:SetWordWrap(false)
    b.text:SetText(sec[2])
    b:SetScript("OnClick", function()
      UI:ShowSettingsSection(sec[1])
    end)
    v.links[sec[1]] = b
    -- each section: a frame in the scroll pane holding a column of cards
    local frame = CreateFrame("Frame", nil, v)
    frame:SetPoint("TOPLEFT", 0, 0)
    frame:SetHeight(1)
    frame:SetShown(k == 1)
    v.sections[sec[1]] = { frame = frame, stack = UI.Stack(frame, 0) }
  end
  v.pick = W.Dropdown(slots.toolbar, 180, sections, function(key)
    if key then
      UI:ShowSettingsSection(key)
    end
  end, { neutral = true })
  v.pick:SetPoint("LEFT", 0, 0)
  -- wide: the toolbar row names the section, over its cards (the sidebar starts under it, as on every tab)
  v.title = W.Text(slots.toolbar, "GameFontNormal")
  v.title:SetPoint("LEFT", UI.SIDEBAR_W + UI.SLOT_GAP, 0)
  v.title:SetText(sections[1][2])
  v.names = {}
  for _, sec in ipairs(sections) do
    v.names[sec[1]] = sec[2]
  end

  -- the shown section's width and height (cards measure their wrapped text at this width)
  function v:PlaceSection()
    local sec = self.sections[self.current]
    local w = math.max(200, self:GetWidth() or 200)
    sec.frame:SetWidth(w)
    if self.current == "data" and self.FlowActions then
      self:FlowActions(w - 16)
    end
    local h = sec.measure and sec.measure(w)
      or sec.stack:Flow(w, UI.SETTINGS_COLUMN, UI.SETTINGS_GAP, UI.SETTINGS_COLUMNS)
    sec.frame:SetHeight(math.max(1, h))
  end
  function v:LayoutColumns()
    UI.Relayout(self, function()
      self:PlaceSection()
      self.pane:Measure()
    end)
  end
  v:HookScript("OnSizeChanged", function()
    v:LayoutColumns()
  end)

  -- a card: its heading, then rows
  local function card(section, title, gap)
    local c = v.sections[section].stack:Card(gap or UI.SETTINGS_GAP)
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

  -- General: the window, notifications
  local _, st = card("general", L["Window"], 0)
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
  local minimapRow = st:Row(18, 6)
  v.minimap = W.Check(minimapRow, L["Show minimap button"], function(on)
    ns.Launcher:SetMinimap(on)
  end)
  v.minimap:SetPoint("TOPLEFT", 0, -1)
  _, st = card("general", L["Market overview"])
  v.overviewCheck = check(st, L["Show the Market overview"], "marketOverview", function(on)
    UI:MarketOverviewChanged(on)
  end)
  paragraph(
    st,
    L["Adds Overview next to Screener on the Market tab: a market index, a CPI, listed value, turnover and categories for the whole auction house. Market data takes a little longer to update while it's on."]
  )
  if ns.CraftingData:Installed() then -- without its data addon, Crafting isn't offered at all
    _, st = card("general", L["Crafting"])
    v.craftingCheck = check(st, L["Show the Crafting tab"], "crafting", function(on)
      UI:CraftingChanged(on)
    end)
    paragraph(
      st,
      L["What your characters' professions earn at today's prices: top earners, selling materials raw or refined, and recipes on the auction house worth buying. Open each profession once so AME knows your recipes. Needs the AME Crafting Data addon."]
    )
  end
  _, st = card("general", L["Notifications"])
  check(st, L["Announce recorded full scans"], "announceScans")
  check(st, L["Sound when an alert fires"], "alertSound")

  -- Tooltips & charts
  _, st = card("display", L["Tooltips"], 0)
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
  _, st = card("display", L["Charts"])
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
  paragraph(
    st,
    L["Off by default: loot addons use modified clicks. Without one, Shift-click an item while AME shows its Item tab."]
  )

  -- Selling
  -- items hidden from the lists (right-click a row to hide one)
  _, st = card("display", L["Hidden items"])
  v.hiddenText = paragraph(st, "")
  local hiddenRow = st:Row(22, 8)
  v.hiddenShow = W.Button(hiddenRow, L["Show them"], 100, 22, function()
    UI:ShowHidden()
  end)
  v.hiddenShow:SetPoint("LEFT")
  v.hiddenUnhide = W.Button(hiddenRow, L["Unhide all"], 100, 22, function()
    UI:UnhideAll()
    UI:RefreshSettings()
  end)
  v.hiddenUnhide:SetPoint("LEFT", v.hiddenShow, "RIGHT", 6, 0)

  _, st = card("selling", L["Selling"], 0)
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

  -- Data
  _, st = card("selling", L["Buying"])
  local warns = { { 0, L["Off"] } }
  for _, pct in ipairs({ 5, 10, 20, 50 }) do
    warns[#warns + 1] = { pct, L["%d%% over"]:format(pct) }
  end
  v.buyWarn = dropdown(st, L["Warn when the price goes up"], 90, warns, function(value)
    ns.Settings:Set("buyWarnPct", value)
  end)
  paragraph(
    st,
    L["Buying in bulk on the Shopping tab: when the game's price for the order is this much over what the listings showed, AME says so and the button reads Confirm anyway."]
  )

  _, st = card("data", L["Data"], 0)
  v.scanMode = dropdown(st, L["Full scans"], 170, {
    { "detailed", L["Detailed: every listing"] },
    { "fast", L["Fast: cheapest per item"] },
  }, function(value)
    ns.Settings:Set("scanMode", value)
    if ns.ScanButton then
      ns.ScanButton:Refresh()
    end
  end)
  paragraph(
    st,
    L["Detailed reads every listing - the most accurate prices - and the game allows one every 15 minutes. Fast reads only each item's cheapest listing, any time; its market prices come from how far above the cheapest each item usually sells, learned from detailed scans and searches. For the Full scan button and /ame scan."]
  )
  v.storage = st:Text("GameFontDisableSmall", 6)
  v.storage:SetSpacing(2)
  -- the data actions in a row, sized to their labels (wrapping when narrow); what each does is on its tooltip
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

  -- Sharing: guild and trusted players (SyncView builds it into its section)
  local sharing = v.sections.sharing
  local syncView = self:CreateSyncSection(sharing.frame, {
    pane = pane,
    status = slots.status,
    relayout = function()
      v:LayoutColumns()
    end,
  })
  sharing.measure = function(w)
    return syncView:Measure(w)
  end

  v:SetScript("OnShow", function()
    UI:RefreshSettings()
  end)
  outer:HookScript("OnShow", function()
    UI:RefreshSettings()
  end)
  function outer:SetCompact(on)
    slots:SetCompact(on)
    v.pick:SetShown(on)
    v.title:SetShown(not on)
    v:LayoutColumns()
  end
  outer:SetCompact(slots.compact)
  return outer
end

-- show one section (highlighted in the sidebar, picked in the narrow dropdown)
function UI:ShowSettingsSection(key)
  local v = self.settingsView
  if not (v and v.sections[key]) then
    return
  end
  v.current = key
  for k, sec in pairs(v.sections) do
    sec.frame:SetShown(k == key)
    v.links[k].sel:SetShown(k == key)
  end
  v.pick:SetValue(key)
  v.title:SetText(v.names[key])
  v.pane:SetScroll(0)
  self:RefreshSettings()
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
  v.pick:SetValue(v.current)
  for _, c in ipairs(v.checks) do
    c:SetChecked(ns.Settings:Get(c.key))
  end
  v.style:SetValue(ns.Settings:Get("chartStyle"))
  v.click:SetValue(ns.Settings:Get("clickModifier"))
  v.outliers:SetValue(ns.Settings:Get("outlierFactor"))
  v.avgDays:SetValue(ns.Settings:Get("tooltipAvgDays"))
  v.theme:SetValue(ns.Settings:Get("theme"))
  v.scanMode:SetValue(ns.Settings:Get("scanMode"))
  v.scale:SetValue(ns.Settings:Get("windowScale"))
  v.cutFaction:SetText(tostring(ns.Settings:Get("cutFaction")))
  v.cutNeutral:SetText(tostring(ns.Settings:Get("cutNeutral")))
  v.hours:SetValue(ns.Settings:Get("listingHours"))
  v.buyWarn:SetValue(ns.Settings:Get("buyWarnPct"))
  local hidden = ns.AME.watch and ns.AME.watch:HiddenCount() or 0
  v.hiddenText:SetText(
    hidden > 0
        and L["%d items are hidden from the Market, Arbitrage and Portfolio lists. AME still records their prices."]:format(
          hidden
        )
      or L["Nothing hidden. Right-click an item in the Market, Arbitrage or Portfolio list to hide it."]
  )
  for _, b in ipairs({ v.hiddenShow, v.hiddenUnhide }) do
    b:SetEnabled(hidden > 0)
    b:SetAlpha(hidden > 0 and 1 or 0.4)
  end
  local hasIcon = ns.Launcher:HasMinimapLibrary()
  v.minimap:SetChecked(hasIcon and not AME_DB.settings.minimap.hide)
  v.minimap.label:SetText(
    hasIcon and L["Show minimap button"]
      or L["Show minimap button"] .. " " .. W.Dim(L["(needs LibDBIcon; included in releases)"])
  )

  v.storage:SetText(UI.DataSummaryText())

  -- the footer: Sharing says whether sync is on; the other sections, where settings are kept
  if v.current == "sharing" then
    self:RefreshSync()
  else
    v.slots.status:SetText(L["Settings are saved per account"])
  end
  v:LayoutColumns()
end

-- Settings, Data: what AME holds, one paragraph per market (the one you're on first), then the totals
function UI.DataSummaryText()
  local AME = ns.AME
  local lines = {}
  if not AME:HistoryLoaded() then
    lines[#lines + 1] = L["History not loaded yet."]
  else
    local now, me = GetServerTime(), UnitName("player")
    local here = AME:CurrentShard()
    local shards = {}
    for shard in pairs(AME.history.shards) do
      shards[#shards + 1] = shard
    end
    table.sort(shards, function(a, b)
      if (a == here) ~= (b == here) then
        return a == here
      end
      return tostring(a) < tostring(b)
    end)
    local total = 0
    for _, shard in ipairs(shards) do
      local sum = ns.Store.Summary(AME.history.shards[shard], now, me)
      total = total + sum.bytes
      local head = W.Color("white", ns.ShardLabel(shard)) .. (shard == here and W.Dim(" " .. L["(this market)"]) or "")
      local parts = {}
      if sum.from then
        parts[#parts + 1] = L["history from %s (%d days by day, %d weeks by week)"]:format(
          date("%b %d, %Y", sum.from * 86400),
          sum.days,
          sum.weeks
        )
      else
        parts[#parts + 1] = L["no daily history yet"]
      end
      parts[#parts + 1] = L["hourly prices for %d of the last %d hours"]:format(sum.hours, sum.hoursOf)
      parts[#parts + 1] = L["%d full scans and %d searches kept in full (%d yours, %d from others)"]:format(
        sum.full,
        sum.partial,
        sum.mine,
        sum.full + sum.partial - sum.mine
      )
      if sum.newest then
        parts[#parts + 1] = L["newest full scan %s"]:format(ago(sum.newest))
      end
      local index = AME.indexes and AME.indexes[shard]
      if index and index.count then
        parts[#parts + 1] = L["%s items"]:format(W.Thousands(index.count))
      end
      local outcomes = count(AME_DB.sellThrough and AME_DB.sellThrough[shard])
      if outcomes > 0 then
        parts[#parts + 1] = L["your listing outcomes for %s items"]:format(W.Thousands(outcomes))
      end
      parts[#parts + 1] = kb(sum.bytes)
      lines[#lines + 1] = head .. "\n" .. table.concat(parts, "  ·  ")
    end
    lines[#lines + 1] = L["All markets: %s of price history."]:format(kb(total))
  end
  local ledger = AME.ledger and AME.ledger.db and AME.ledger.db.entries
  local f = AME_DB.stats.lastFull
  lines[#lines + 1] = table.concat({
    L["Ledger: %s entries"]:format(W.Thousands(ledger and #ledger or 0)),
    f and L["last full scan %s"]:format(ago(f.at)) or L["No full scan recorded yet."],
  }, "  ·  ")
  return table.concat(lines, "\n\n")
end
