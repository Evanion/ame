-- Settings tab: a side menu of sections (UI.SideList, like the Guide) and the chosen section's cards (UI.SettingsCard)
-- over the whole width, in columns on wide windows.
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
  v.sections = {}
  v.current = "general"
  slots.status:SetText(L["Settings are saved per account"])
  local sections = UI.SettingsSections()

  -- sidebar: the sections, a side menu (narrow windows: a dropdown on the toolbar)
  v.nav = UI.SideList(slots.left, {
    rows = #sections,
    onClick = function(e)
      UI:ShowSettingsSection(e.key)
    end,
  })
  function v:RenderNav()
    local entries = {}
    for k, sec in ipairs(sections) do
      entries[k] = { label = sec[2], key = sec[1], selected = sec[1] == self.current }
    end
    self.nav:SetEntries(entries)
  end
  for k, sec in ipairs(sections) do
    -- each section: a frame in the scroll pane holding a column of cards
    local frame = CreateFrame("Frame", nil, v)
    frame:SetPoint("TOPLEFT", 0, 0)
    frame:SetHeight(1)
    frame:SetShown(k == 1)
    v.sections[sec[1]] = { frame = frame, stack = UI.Stack(frame, 0) }
  end
  v:RenderNav()
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

  -- a card of setting rows (UI.SettingsCard); its setting checks join v.checks
  local function card(section, title, rows, gap)
    local c = UI.SettingsCard(v.sections[section].stack, title, rows, { gap = gap or UI.SETTINGS_GAP })
    for _, check in ipairs(c.checks) do
      checks[#checks + 1] = check
    end
    return c, c.controls
  end
  local function field(label, width, options, onSelect, note)
    return { field = label, note = note, dropdown = { width, options, onSelect } }
  end

  -- General: the window, notifications
  local scales = {}
  for pct = 70, 120, 10 do
    scales[#scales + 1] = { pct / 100, ("%d%%"):format(pct) }
  end
  local themes = {
    { "auto", L["Follow market"] },
    { "Horde", L["Horde red"] },
    { "Alliance", L["Alliance blue"] },
    { "Neutral", L["Goblin gold"] },
  }
  local _, ctl = card("general", L["Window"], {
    field(L["Scale"], 80, scales, function(value)
      ns.Settings:Set("windowScale", value)
      UI:ApplyPlacement()
    end, "(70-120%)"),
    {
      check = L["Dock next to the auction house when there's room"],
      key = "dockToAH",
      onChange = function()
        if UI.frame and UI.frame:IsShown() then
          UI:ApplyPlacement()
        end
      end,
    },
    { check = L["Open with the auction house"], key = "openWithAH" },
    { check = L["Switch to the Item tab for what you put up for sale"], key = "sellSwitchesTab" },
    field(L["Colours"], 110, themes, function(value)
      ns.Settings:Set("theme", value)
      UI:ApplyTheme()
    end),
    {
      check = L["Colour-blind friendly palette"],
      key = "colorBlind",
      onChange = function()
        W.ApplyPalette()
        UI:PaletteChanged()
      end,
    },
    {
      check = L["Show minimap button"],
      onChange = function(on)
        ns.Launcher:SetMinimap(on)
      end,
    },
  }, 0)
  v.scale, v.theme, v.colorBlind, v.minimap = ctl[1], ctl[5], ctl[6], ctl[7]
  _, ctl = card("general", L["Market overview"], {
    {
      check = L["Show the Market overview"],
      key = "marketOverview",
      onChange = function(on)
        UI:MarketOverviewChanged(on)
      end,
    },
    {
      text = L["Adds Overview next to Screener on the Market tab: a market index, a CPI, listed value, turnover and categories for the whole auction house. Market data takes a little longer to update while it's on."],
    },
  })
  v.overviewCheck = ctl[1]
  card("general", L["Notifications"], {
    { check = L["Announce recorded full scans"], key = "announceScans" },
    { check = L["Sound when an alert fires"], key = "alertSound" },
  })
  -- Other addons: what AME adds to them (Core/UI/Baganator.lua)
  local bag = ns.Baganator
  local function redrawBags()
    if bag then
      bag:SettingChanged(ns.Settings:Get("baganator") ~= false)
    end
  end
  _, ctl = card("general", L["Other addons"], {
    {
      check = L["Baganator: AME's corners and worth sort"],
      key = "baganator",
      onChange = function(on)
        if bag then
          bag:SettingChanged(on)
        end
      end,
    },
    { check = L["Tip corner: mark items to sell too"], key = "baganatorSellTip", indent = true, onChange = redrawBags },
    field(L["Value corner shows"], 130, {
      { "stack", L["The whole stack"] },
      { "each", L["One item"] },
    }, function(value)
      ns.Settings:Set("baganatorValue", value)
      redrawBags()
    end),
    field(L["Hide values under"], 130, {
      { 0, L["Show every value"] },
      { 100, W.Money(100) },
      { 1000, W.Money(1000) },
      { 10000, W.Money(10000) },
      { 100000, W.Money(100000) },
    }, function(value)
      ns.Settings:Set("baganatorMinValue", value)
      redrawBags()
    end),
    {
      text = L["Place the corners under Icons, and pick the worth sort as the sort, in Baganator's settings. The tip marks a slot; it never moves anything (junk is Baganator's own)."]
        .. " "
        .. (
          (bag and bag.Present()) and L["Turned off, Baganator lists them until a /reload, but they show nothing."]
          or W.Dim(L["Baganator isn't installed: nothing to do."])
        ),
    },
  })
  v.bagValue, v.bagMin = ctl[3], ctl[4]

  -- Tooltips & charts
  local avgs = {
    { 3, L["%d days"]:format(3) },
    { 7, L["%d days"]:format(7) },
    { 14, L["%d days"]:format(14) },
    { 30, L["%d days"]:format(30) },
  }
  _, ctl = card("display", L["Tooltips"], {
    { check = L["Show prices in item tooltips"], key = "tooltip" },
    field(L["Average period"], 90, avgs, function(value)
      -- one period everywhere: tooltips, the screener's average column and the item page
      ns.Settings:Set("tooltipAvgDays", value)
      local q = UI.mq
      if q and q.sortKey and q.sortKey:match("^avg%d+$") then
        q.sortKey = "avg" .. value
      end
      UI.list = nil
    end),
    { check = L["Always show details (otherwise hold Shift)"], key = "tooltipDetail" },
  }, 0)
  v.avgDays = ctl[2]
  for i, c in ipairs(checks) do
    if c.key == "tooltip" then
      table.remove(checks, i)
      table.insert(checks, 1, c) -- checks[1]: the tooltip switch
      break
    end
  end
  local styles = { { "line", L["Line"] }, { "candles", L["Candles"] } }
  local clicks = {
    { "none", L["Off"] },
    { "alt", L["Alt-click"] },
    { "altshift", L["Alt+Shift-click"] },
    { "ctrlalt", L["Ctrl+Alt-click"] },
  }
  _, ctl = card("display", L["Charts"], {
    field(L["Style"], 100, styles, function(value)
      ns.Settings:Set("chartStyle", value)
      if UI.series then
        UI:DrawItemChart()
      end
    end),
    field(L["Open charts with"], 110, clicks, function(value)
      ns.Settings:Set("clickModifier", value)
    end),
    {
      text = L["Off by default: loot addons use modified clicks. Without one, Shift-click an item while AME shows its Item tab."],
    },
  })
  v.style, v.click = ctl[1], ctl[2]

  -- items hidden from the lists (right-click a row to hide one)
  _, ctl = card("display", L["Hidden items"], {
    { text = "" },
    {
      buttons = {
        {
          L["Show them"],
          function()
            UI:ShowHidden()
          end,
          width = 100,
        },
        {
          L["Unhide all"],
          function()
            UI:UnhideAll()
            UI:RefreshSettings()
          end,
          width = 100,
        },
      },
    },
  })
  v.hiddenText, v.hiddenShow, v.hiddenUnhide = ctl[1], ctl[2].buttons[1], ctl[2].buttons[2]

  -- Selling: the cuts (a percent box, right-aligned like every field), the listing length
  local function cut(key, label)
    return {
      field = label,
      control = function(row)
        local box = CreateFrame("Frame", nil, row)
        box:SetSize(60, 22)
        local pct = W.Text(box, "GameFontHighlightSmall")
        pct:SetPoint("RIGHT", 0, 0)
        pct:SetText("%")
        local input = W.Input(box, {
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
        input.key = key
        box.input = input
        return box
      end,
    }
  end
  local hours = {
    { 2, L["%d h"]:format(2) },
    { 8, L["%d h"]:format(8) },
    { 24, L["%d h"]:format(24) },
  }
  _, ctl = card("selling", L["Selling"], {
    cut("cutFaction", L["Faction AH cut"]),
    cut("cutNeutral", L["Goblin AH cut"]),
    field(L["Listing length"], 80, hours, function(value)
      ns.Settings:Set("listingHours", value)
      ns.AME:InvalidateIndex() -- VENDOR signals depend on the deposit
      if UI.RenderArbitrage then
        UI:RenderArbitrage()
      end
    end),
  }, 0)
  v.cutFaction, v.cutNeutral, v.hours = ctl[1].input, ctl[2].input, ctl[3]

  local warns = { { 0, L["Off"] } }
  for _, pct in ipairs({ 5, 10, 20, 50 }) do
    warns[#warns + 1] = { pct, L["%d%% over"]:format(pct) }
  end
  _, ctl = card("selling", L["Buying"], {
    field(L["Warn when the price goes up"], 90, warns, function(value)
      ns.Settings:Set("buyWarnPct", value)
    end),
    {
      text = L["Buying in bulk on the Shopping tab: when the game's price for the order is this much over what the listings showed, AME says so and the button reads Confirm anyway."],
    },
  })
  v.buyWarn = ctl[1]

  -- Data: full scans, what AME holds, the data actions (wrapping when narrow; what each does is on its tooltip), the
  -- outlier filter
  local factors = {
    { false, L["Off"] },
    { 3, L["%dx off usual"]:format(3) },
    { 4, L["%dx off usual"]:format(4) },
    { 6, L["%dx off usual"]:format(6) },
    { 10, L["%dx off usual"]:format(10) },
  }
  local function action(label, tip, fn)
    return { label, fn, tip = { label, tip } }
  end
  local dataCard
  dataCard, ctl = card("data", L["Data"], {
    field(L["Full scans"], 170, {
      { "detailed", L["Detailed: every listing"] },
      { "fast", L["Fast: cheapest per item"] },
    }, function(value)
      ns.Settings:Set("scanMode", value)
      if ns.ScanButton then
        ns.ScanButton:Refresh()
      end
    end),
    {
      text = L["Detailed reads every listing - the most accurate prices - and the game allows one every 15 minutes. Fast reads only each item's cheapest listing, any time; its market prices come from how far above the cheapest each item usually sells, learned from detailed scans and searches. For the Full scan button and /ame scan."],
    },
    { text = "" },
    {
      buttons = {
        action(
          L["Import from Auctionator"],
          L["If Auctionator is installed: imports its recent daily prices for days AME has no data for (faction AH)."],
          function()
            ns.AME:Backfill(true)
          end
        ),
        action(
          L["Rebuild market data"],
          L["Recomputes the 30-day summaries behind the screener, tooltips and alerts."],
          function()
            ns.AME:RebuildIndex()
          end
        ),
        action(
          L["Run self-test"],
          L["Checks every part of AME and offers a reload so the results are saved."],
          function()
            ns.SelfTest.Run(ns.AME)
          end
        ),
      },
    },
    field(L["Ignore outrageous prices"], 110, factors, function(value)
      ns.Settings:Set("outlierFactor", value)
      ns.AME:InvalidateIndex()
      ns.AME:RebuildIndex()
      if UI.itemID and UI.current == "item" then
        UI:ShowItem(UI.itemID)
      end
    end),
  }, 0)
  v.scanMode, v.storage, v.actionsRow, v.outliers = ctl[1], ctl[3], ctl[4], ctl[5]
  -- the data actions onto as many lines as the card's width needs
  function v:FlowActions(width)
    self.actionsRow:Fit(width)
  end
  local outlierRow = dataCard.rowFrames[5]
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
  end
  v:RenderNav()
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
  v.bagValue:SetValue(ns.Settings:Get("baganatorValue"))
  v.bagMin:SetValue(ns.Settings:Get("baganatorMinValue"))
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
