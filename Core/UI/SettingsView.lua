-- Settings tab: every AME setting, storage figures and data actions.
local _, ns = ...
local L = ns.L

local W = ns.Widgets
local UI = ns.UI
local heading, settingCheck = W.Heading, W.SettingCheck
local COL2 = UI.COLUMN2

local function ago(t)
  return W.Ago(t, GetServerTime())
end

---------------------------------------------------------------------------------------------------------------------
-- Settings

function UI:CreateSettingsView(parent, contentArea)
  local v = contentArea(parent)
  self.settingsView = v
  local checks = {}
  v.checks = checks

  heading(v, L["Display"], 0, 0)
  checks[#checks + 1] = settingCheck(v, L["Show AME prices in item tooltips"], "tooltip", 0, -24)
  local avgs = {
    { 3, L["%d days"]:format(3) },
    { 7, L["%d days"]:format(7) },
    { 14, L["%d days"]:format(14) },
    { 30, L["%d days"]:format(30) },
  }
  v.avgDays = W.Dropdown(v, 90, avgs, function(value)
    -- one period everywhere: tooltips, the screener's average column and the item page
    ns.Settings:Set("tooltipAvgDays", value)
    local q = UI.mq
    if q and q.sortKey and q.sortKey:match("^avg%d+$") then
      q.sortKey = "avg" .. value
    end
    UI.list = nil
  end, { neutral = true })
  W.Labeled(v, L["average period"], v.avgDays, nil, 90):SetPoint("TOPLEFT", 260, -26)
  checks[#checks + 1] =
    settingCheck(v, L["Always show full tooltip details (otherwise hold Shift)"], "tooltipDetail", 0, -48)

  local styles = { { "line", L["Line"] }, { "candles", L["Candles"] } }
  v.style = W.Dropdown(v, 120, styles, function(value)
    ns.Settings:Set("chartStyle", value)
    if UI.series then
      UI:DrawItemChart()
    end
  end, { neutral = true })
  W.Labeled(v, L["Chart style"], v.style, nil, 150):SetPoint("TOPLEFT", 0, -80)

  local clicks = {
    { "none", L["Off"] },
    { "alt", L["Alt-click"] },
    { "altshift", L["Alt+Shift-click"] },
    { "ctrlalt", L["Ctrl+Alt-click"] },
  }
  v.click = W.Dropdown(v, 120, clicks, function(value)
    ns.Settings:Set("clickModifier", value)
  end, { neutral = true })
  local clickLabel = W.Labeled(v, L["Open item charts with"], v.click, nil, 150)
  clickLabel:SetPoint("TOPLEFT", 0, -106)
  W.Paragraph(
    v,
    L["Off by default: loot and raid addons (e.g. Gargul, AHDB) use modified clicks on items and links. With the AME window open, Shift-click an item to chart it."]
  ):SetPoint("TOPLEFT", clickLabel, "BOTTOMLEFT", 0, -14)

  v.minimap = W.Check(v, L["Show minimap button"], function(on)
    ns.Launcher:SetMinimap(on)
  end)
  v.minimap:SetPoint("TOPLEFT", 0, -150)

  local themes = {
    { "auto", L["Follow market"] },
    { "Horde", L["Horde red"] },
    { "Alliance", L["Alliance blue"] },
    { "Neutral", L["Goblin gold"] },
  }
  v.theme = W.Dropdown(v, 110, themes, function(value)
    ns.Settings:Set("theme", value)
    UI:ApplyTheme()
  end, { neutral = true })
  W.Labeled(v, L["Window colours"], v.theme, nil, 90):SetPoint("TOPLEFT", 260, -152)

  heading(v, L["Notifications"], 0, -182)
  checks[#checks + 1] = settingCheck(v, L["Announce recorded full scans in chat"], "announceScans", 0, -204)
  checks[#checks + 1] = settingCheck(v, L["Play a sound when a watchlist alert fires"], "alertSound", 0, -226)
  checks[#checks + 1] = settingCheck(v, L["Open AME together with the auction house"], "openWithAH", 0, -248)
  checks[#checks + 1] = settingCheck(v, L["...and close it when the auction house closes"], "closeWithAH", 20, -270)
  checks[#checks + 1] =
    settingCheck(v, L["Switch to the Item tab when you put an item up for sale"], "sellSwitchesTab", 0, -292)

  heading(v, L["Data quality"], 0, -324)
  local factors = {
    { false, L["Off"] },
    { 3, L["%dx off usual"]:format(3) },
    { 4, L["%dx off usual"]:format(4) },
    { 6, L["%dx off usual"]:format(6) },
    { 10, L["%dx off usual"]:format(10) },
  }
  v.outliers = W.Dropdown(v, 120, factors, function(value)
    ns.Settings:Set("outlierFactor", value)
    ns.AME:InvalidateIndex()
    ns.AME:RebuildIndex()
    if UI.itemID and UI.current == "item" then
      UI:ShowItem(UI.itemID)
    end
  end, { neutral = true })
  W.Labeled(v, L["Ignore outrageous prices"], v.outliers, nil, 150):SetPoint("TOPLEFT", 0, -350)
  W.Paragraph(
    v,
    L["Days where an item's price is this many times above (or below) its neighbouring days are left out of the screener, signals, alerts and charts - typically one listing at a 1000% markup in a thin market. Within a full scan, AME already ignores expensive listings: market price uses the cheapest part of the supply."]
  ):SetPoint("TOPLEFT", 0, -372)

  -- data
  heading(v, L["Data"], COL2, 0)
  v.storage = W.Text(v, "GameFontHighlightSmall")
  v.storage:SetPoint("TOPLEFT", COL2, -24)
  v.storage:SetWidth(460)
  v.storage:SetSpacing(3)
  local actions = {
    {
      L["Import history from Auctionator"],
      L["If Auctionator is installed: imports its recent daily prices for days AME has no data for (faction AH)."],
      function()
        ns.AME:Backfill(true)
      end,
    },
    {
      L["Rebuild market index"],
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
  }
  -- each block below the previous one, so longer (translated) descriptions push the rest down instead of overlapping
  local last
  for _, a in ipairs(actions) do
    local b = W.Button(v, a[1], 190, 22, a[3])
    if last then
      b:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -10)
    else
      b:SetPoint("TOPLEFT", COL2, -110)
    end
    last = W.Paragraph(v, a[2])
    last:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -4)
  end
  local cutHeading = heading(v, L["Auction house cut"], COL2, 0)
  cutHeading:ClearAllPoints()
  cutHeading:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -16)
  local function cutInput(key, label, below)
    local input = W.Input(v, {
      width = 44,
      numeric = true,
      onChange = function(_, n, user)
        if user and n and n <= 100 then
          ns.Settings:Set(key, n)
          ns.AME:InvalidateIndexLater(nil, 2) -- VENDOR signals depend on the cut (rebuilt once typing settles)
        end
      end,
    })
    local row = W.Labeled(v, label, input, nil, 170)
    row:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -14) -- the 20 px input is centred on this label: keep rows apart
    input.row = row
    local pct = W.Text(v, "GameFontHighlightSmall")
    pct:SetPoint("LEFT", input, "RIGHT", 4, 0)
    pct:SetText("%")
    input.key = key
    return input
  end
  v.cutFaction = cutInput("cutFaction", L["Faction auction houses"], cutHeading)
  v.cutNeutral = cutInput("cutNeutral", L["Goblin auction houses"], v.cutFaction.row)
  local hours = {
    { 2, L["%d h listings"]:format(2) },
    { 8, L["%d h listings"]:format(8) },
    { 24, L["%d h listings"]:format(24) },
  }
  v.hours = W.Dropdown(v, 110, hours, function(value)
    ns.Settings:Set("listingHours", value)
    ns.AME:InvalidateIndex() -- VENDOR signals depend on the deposit
    if UI.RenderArbitrage then
      UI:RenderArbitrage()
    end
  end, { neutral = true })
  W.Labeled(v, L["Deposits for"], v.hours, nil, 80):SetPoint("TOPLEFT", v.cutFaction.row, "TOPLEFT", 250, 0)

  W.Paragraph(v, L["Sharing settings are on the Sync tab."]):SetPoint("TOPLEFT", v.cutNeutral.row, "BOTTOMLEFT", 0, -14)

  v:SetScript("OnShow", function()
    UI:RefreshSettings()
  end)
  return v
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
end
