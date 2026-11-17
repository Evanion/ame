-- Settings tab: every AME setting, storage figures and data actions.
local _, ns = ...
local L = ns.L

local W = ns.Widgets
local UI = ns.UI
local heading, note, settingCheck = W.Heading, W.Note, W.SettingCheck
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
  local avgLabel = W.Text(v, "GameFontHighlightSmall")
  avgLabel:SetPoint("TOPLEFT", 260, -26)
  avgLabel:SetText(L["average period"])
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
  v.avgDays:SetPoint("TOPLEFT", 340, -22)
  checks[#checks + 1] =
    settingCheck(v, L["Always show full tooltip details (otherwise hold Shift)"], "tooltipDetail", 0, -48)

  local styleLabel = W.Text(v, "GameFontHighlightSmall")
  styleLabel:SetPoint("TOPLEFT", 0, -80)
  styleLabel:SetText(L["Chart style"])
  local styles = { { "line", L["Line"] }, { "candles", L["Candles"] } }
  v.style = W.Dropdown(v, 120, styles, function(value)
    ns.Settings:Set("chartStyle", value)
    if UI.series then
      UI:DrawItemChart()
    end
  end, { neutral = true })
  v.style:SetPoint("TOPLEFT", 150, -76)

  local clickLabel = W.Text(v, "GameFontHighlightSmall")
  clickLabel:SetPoint("TOPLEFT", 0, -106)
  clickLabel:SetText(L["Open item charts with"])
  local clicks = { { "alt", L["Alt-click"] }, { "altshift", L["Alt+Shift-click"] }, { "none", L["Off"] } }
  v.click = W.Dropdown(v, 120, clicks, function(value)
    ns.Settings:Set("clickModifier", value)
  end, { neutral = true })
  v.click:SetPoint("TOPLEFT", 150, -102)
  note(v, clickLabel, L["Change this if another addon (e.g. AHDB) also uses Alt-click on items."], 440):SetPoint(
    "TOPLEFT",
    clickLabel,
    "BOTTOMLEFT",
    0,
    -14
  )

  v.minimap = W.Check(v, L["Show minimap button"], function(on)
    ns.Launcher:SetMinimap(on)
  end)
  v.minimap:SetPoint("TOPLEFT", 0, -150)

  local themeLabel = W.Text(v, "GameFontHighlightSmall")
  themeLabel:SetPoint("TOPLEFT", 260, -152)
  themeLabel:SetText(L["Window colours"])
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
  v.theme:SetPoint("TOPLEFT", 350, -148)

  heading(v, L["Notifications"], 0, -182)
  checks[#checks + 1] = settingCheck(v, L["Announce recorded full scans in chat"], "announceScans", 0, -204)
  checks[#checks + 1] = settingCheck(v, L["Play a sound when a watchlist alert fires"], "alertSound", 0, -226)

  heading(v, L["Data quality"], 0, -258)
  local outlierLabel = W.Text(v, "GameFontHighlightSmall")
  outlierLabel:SetPoint("TOPLEFT", 0, -284)
  outlierLabel:SetText(L["Ignore outrageous prices"])
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
  v.outliers:SetPoint("TOPLEFT", 150, -280)
  local why = W.Text(v, "GameFontDisableSmall")
  why:SetPoint("TOPLEFT", 0, -306)
  why:SetWidth(440)
  why:SetSpacing(2)
  why:SetText(
    L["Days where an item's price is this many times above (or below) its neighbouring days are left out of the screener, signals, alerts and charts - typically one listing at a 1000% markup in a thin market. Within a full scan, AME already ignores expensive listings: market price uses the cheapest part of the supply."]
  )

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
  for i, a in ipairs(actions) do
    local b = W.Button(v, a[1], 190, 22, a[3])
    b:SetPoint("TOPLEFT", COL2, -110 - (i - 1) * 46)
    local t = W.Text(v, "GameFontDisableSmall")
    t:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -4)
    t:SetWidth(440)
    t:SetText(a[2])
  end
  heading(v, L["Auction house cut"], COL2, -258)
  local function cutInput(key, label, y)
    local t = W.Text(v, "GameFontHighlightSmall")
    t:SetPoint("TOPLEFT", COL2, y)
    t:SetText(label)
    local input = W.Input(v, {
      width = 44,
      numeric = true,
      onChange = function(_, n, user)
        if user and n and n <= 100 then
          ns.Settings:Set(key, n)
        end
      end,
    })
    input:SetPoint("TOPLEFT", COL2 + 170, y + 4)
    local pct = W.Text(v, "GameFontHighlightSmall")
    pct:SetPoint("LEFT", input, "RIGHT", 4, 0)
    pct:SetText("%")
    input.key = key
    return input
  end
  v.cutFaction = cutInput("cutFaction", L["Faction auction houses"], -284)
  v.cutNeutral = cutInput("cutNeutral", L["Goblin auction houses"], -310)
  local hoursLabel = W.Text(v, "GameFontHighlightSmall")
  hoursLabel:SetPoint("TOPLEFT", COL2 + 250, -284)
  hoursLabel:SetText(L["Deposits for"])
  local hours = {
    { 2, L["%d h listings"]:format(2) },
    { 8, L["%d h listings"]:format(8) },
    { 24, L["%d h listings"]:format(24) },
  }
  v.hours = W.Dropdown(v, 110, hours, function(value)
    ns.Settings:Set("listingHours", value)
    if UI.RenderArbitrage then
      UI:RenderArbitrage()
    end
  end, { neutral = true })
  v.hours:SetPoint("TOPLEFT", COL2 + 330, -280)

  local more = W.Text(v, "GameFontDisableSmall")
  more:SetPoint("TOPLEFT", COL2, -340)
  more:SetWidth(440)
  more:SetText(L["Sharing settings are on the Sync tab. These options are also in the game's AddOns settings."])

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
