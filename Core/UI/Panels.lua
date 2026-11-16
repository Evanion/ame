-- Sync and Settings tabs of the main window.
local ADDON, ns = ...

local W = ns.Widgets
local UI = ns.UI

local function ago(t)
  if not t then
    return "never"
  end
  local d = math.max(0, GetServerTime() - t)
  if d < 60 then
    return "just now"
  elseif d < 3600 then
    return ("%d min ago"):format(d / 60)
  elseif d < 86400 then
    return ("%d h ago"):format(d / 3600)
  end
  return ("%d days ago"):format(d / 86400)
end
UI.Ago = ago

local function heading(parent, text, x, y)
  local h = W.Text(parent, "GameFontNormal")
  h:SetPoint("TOPLEFT", x, y)
  h:SetText(text)
  return h
end

local function note(parent, anchor, text, width)
  local t = W.Text(parent, "GameFontDisableSmall")
  t:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
  t:SetWidth(width or 440)
  t:SetSpacing(2)
  t:SetText(text)
  return t
end

-- a check bound to a setting
local function settingCheck(parent, label, key, x, y, onChange)
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

---------------------------------------------------------------------------------------------------------------------
-- Sync

local MAX_TRUSTED, MAX_PENDING, MAX_PEERS, MAX_BLOCKED = 9, 3, 5, 3
local COL2 = 490

function UI:CreateSyncView(parent, contentArea)
  local v = contentArea(parent)
  self.syncView = v
  local svc = ns.SyncService

  heading(v, "Sharing", 0, 0)
  v.guild = settingCheck(v, "Share full scans with my guild (members running AME)", "syncGuild", 0, -24)
  v.trusted = settingCheck(v, "Share with trusted players (below)", "syncTrusted", 0, -46)
  local alts = W.Text(v, "GameFontDisableSmall")
  alts:SetPoint("TOPLEFT", 0, -72)
  alts:SetWidth(450)
  alts:SetSpacing(2)
  alts:SetText(
    "Your alts on this Battle.net account already share everything: AME's history is saved account-wide. "
      .. "Trust players to swap scans with friends, or with your own characters on other accounts. Only your "
      .. "market and auction house are shared, and scans that disagree wildly with your prices are rejected."
  )

  heading(v, "Activity", 0, -128)
  v.activity = W.Text(v, "GameFontHighlightSmall")
  v.activity:SetPoint("TOPLEFT", 0, -150)
  v.activity:SetWidth(450)
  v.activity:SetSpacing(3)

  heading(v, "Recently heard from", 0, -236)
  v.peers = {}
  for i = 1, MAX_PEERS do
    local row = CreateFrame("Frame", nil, v)
    row:SetSize(460, 18)
    row:SetPoint("TOPLEFT", 0, -258 - (i - 1) * 20)
    row.text = W.Text(row, "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 0, 0)
    row.text:SetWidth(390)
    row.block = W.Button(row, "Block", 50, 16, function()
      svc:Block(row.name)
      UI:RefreshSync()
    end)
    row.block:SetPoint("RIGHT", 0, 0)
    v.peers[i] = row
  end

  heading(v, "Blocked", 0, -364)
  v.guildBlocked = W.Text(v, "GameFontDisableSmall")
  v.guildBlocked:SetPoint("TOPLEFT", 0, -384)
  v.guildBlocked:SetWidth(460)
  v.blocked = {}
  for i = 1, MAX_BLOCKED do
    local row = CreateFrame("Frame", nil, v)
    row:SetSize(460, 18)
    row:SetPoint("TOPLEFT", 0, -400 - (i - 1) * 18)
    row.text = W.Text(row, "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 0, 0)
    row.unblock = W.Button(row, "Unblock", 60, 16, function()
      svc:Unblock(row.name)
      UI:RefreshSync()
    end)
    row.unblock:SetPoint("RIGHT", 0, 0)
    v.blocked[i] = row
  end

  -- trusted players
  heading(v, "Trusted players", COL2, 0)
  local input = W.Input(v)
  input:SetSize(240, 20)
  input:SetPoint("TOPLEFT", COL2, -24)
  input.hint = W.Text(input, "GameFontDisableSmall")
  input.hint:SetPoint("LEFT", 6, 0)
  input.hint:SetText("Character name, e.g. First Last")
  local function add()
    local e, why = svc:AddTrusted(input:GetText())
    if e then
      input:SetText("")
      v.addStatus:SetText(("Asked %s to share. They'll see a request in their Sync tab."):format(e.name))
    else
      v.addStatus:SetText("|cffff6159" .. tostring(why) .. "|r")
    end
    input:ClearFocus()
    UI:RefreshSync()
  end
  input:SetScript("OnTextChanged", function(self)
    self.hint:SetShown(self:GetText() == "")
  end)
  input:SetScript("OnEnterPressed", add)
  v.input = input
  local addButton = W.Button(v, "Add", 60, 20, add)
  addButton:SetPoint("LEFT", input, "RIGHT", 6, 0)
  v.addStatus = W.Text(v, "GameFontDisableSmall")
  v.addStatus:SetPoint("TOPLEFT", COL2, -48)
  v.addStatus:SetWidth(460)

  v.pendingHead = heading(v, "Requests", COL2, -70)
  v.pending = {}
  for i = 1, MAX_PENDING do
    local row = CreateFrame("Frame", nil, v)
    row:SetSize(460, 20)
    row:SetPoint("TOPLEFT", COL2, -92 - (i - 1) * 22)
    row.text = W.Text(row, "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 0, 0)
    row.approve = W.Button(row, "Approve", 64, 18, function()
      svc:Approve(row.name)
      UI:RefreshSync()
    end)
    row.approve:SetPoint("RIGHT", -126, 0)
    row.decline = W.Button(row, "Decline", 64, 18, function()
      svc:Decline(row.name)
      UI:RefreshSync()
    end)
    row.decline:SetPoint("RIGHT", -56, 0)
    row.block = W.Button(row, "Block", 50, 18, function()
      svc:Block(row.name)
      UI:RefreshSync()
    end)
    row.block:SetPoint("RIGHT", 0, 0)
    v.pending[i] = row
  end

  v.trustedHead = heading(v, "Trusted", COL2, -164)
  v.trustedRows = {}
  for i = 1, MAX_TRUSTED do
    local row = CreateFrame("Frame", nil, v)
    row:SetSize(460, 20)
    row:SetPoint("TOPLEFT", COL2, -186 - (i - 1) * 22)
    row.text = W.Text(row, "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 0, 0)
    row.state = W.Text(row, "GameFontDisableSmall", "RIGHT")
    row.state:SetPoint("RIGHT", -30, 0)
    row.remove = W.CloseButton(row, function()
      svc:RemoveTrusted(row.name)
      UI:RefreshSync()
    end)
    row.remove:SetSize(18, 18)
    row.remove:SetPoint("RIGHT", 0, 0)
    v.trustedRows[i] = row
  end
  v.trustedEmpty = W.Text(v, "GameFontDisableSmall")
  v.trustedEmpty:SetPoint("TOPLEFT", COL2, -186)
  v.trustedEmpty:SetText("Nobody yet. Add a friend above - they need AME too, and must approve.")
  v.trustedMore = W.Text(v, "GameFontDisableSmall")
  v.trustedMore:SetPoint("TOPLEFT", COL2, -186 - MAX_TRUSTED * 22)

  v:SetScript("OnShow", function()
    UI:RefreshSync()
  end)
  svc.onChange = function()
    UI:RefreshSync()
  end
  return v
end

function UI:RefreshSync()
  local v = self.syncView
  if not (v and v:IsShown()) then
    return
  end
  local svc = ns.SyncService
  v.guild:SetChecked(ns.Settings:Get("syncGuild"))
  v.trusted:SetChecked(ns.Settings:Get("syncTrusted"))

  local s = AME_DB.stats
  local lines = {}
  if not svc.enabled then
    lines[1] = "|cffff6159Sync is unavailable: the AceComm library didn't load.|r"
  else
    local guild = IsInGuild and IsInGuild()
    lines[#lines + 1] = ("Guild: %s"):format(
      not ns.Settings:Get("syncGuild") and "off" or guild and "|cff4dd973on|r" or "on, but you're not in a guild"
    )
    lines[#lines + 1] = ("Announced %d times, served %d scans, received %d, rejected %d"):format(
      s.syncAnnounced or 0,
      s.syncServed or 0,
      s.syncReceived or 0,
      s.syncRejected or 0
    )
    local last = s.lastSyncReceived
    lines[#lines + 1] = last and ("Last received: %d items from %s, %s"):format(last.items, last.from, ago(last.at))
      or "Nothing received yet - scans arrive when someone you share with runs a full scan."
    if s.lastSyncRejection then
      lines[#lines + 1] = "|cffffcc00Last rejected:|r " .. s.lastSyncRejection
    end
  end
  v.activity:SetText(table.concat(lines, "\n"))

  local peers = svc.trust and svc.trust:PeerList() or {}
  for i, row in ipairs(v.peers) do
    local p = peers[i]
    row.name = p and p.name
    row.block:SetShown(p ~= nil and not svc.trust:IsBlocked(p.name))
    if p then
      local blocked = svc.trust:IsBlocked(p.name)
      row.text:SetText(
        ("%s  |cff999999via %s, %s%s%s|r"):format(
          p.name,
          p.via == "GUILD" and "guild" or "whisper",
          ago(p.at),
          (p.received or 0) > 0 and (", %d scans received"):format(p.received) or "",
          blocked and ", |cffff6159blocked|r" or ""
        )
      )
    else
      row.text:SetText(i == 1 and "|cff999999No one yet.|r" or "")
    end
  end

  local guildList = {}
  for _, name in pairs(svc.trust and svc.trust.guildBlocked or {}) do
    guildList[#guildList + 1] = name
  end
  table.sort(guildList)
  v.guildBlocked:SetText(
    #guildList > 0 and ("By your guild officers: |cffffffff%s|r"):format(table.concat(guildList, ", "))
      or 'Guild officers can block players for everyone: add a line "AME block: Name, Name" to the guild info.'
  )
  local blocked = svc.trust and svc.trust:BlockedList() or {}
  for i, row in ipairs(v.blocked) do
    local b = blocked[i]
    row:SetShown(b ~= nil or (i == 1 and #blocked == 0))
    row.name = b and b.name
    row.unblock:SetShown(b ~= nil)
    if b then
      row.text:SetText(("%s  |cff999999blocked %s|r"):format(b.name, ago(b.at)))
    else
      row.text:SetText("|cff999999You haven't blocked anyone.|r")
    end
  end

  local pending = svc.trust and svc.trust:PendingList() or {}
  v.pendingHead:SetShown(#pending > 0)
  for i, row in ipairs(v.pending) do
    local p = pending[i]
    row:SetShown(p ~= nil)
    if p then
      row.name = p.name
      row.text:SetText(("%s  |cff999999wants to share, %s|r"):format(p.name, ago(p.at)))
    end
  end

  local trusted = svc.trust and svc.trust:TrustedList() or {}
  local top = #pending > 0 and (-92 - math.min(#pending, MAX_PENDING) * 22 - 10) or -70
  v.trustedHead:ClearAllPoints()
  v.trustedHead:SetPoint("TOPLEFT", COL2, top)
  v.trustedHead:SetText(("Trusted (%d)"):format(#trusted))
  v.trustedEmpty:ClearAllPoints()
  v.trustedEmpty:SetPoint("TOPLEFT", COL2, top - 22)
  v.trustedEmpty:SetShown(#trusted == 0)
  for i, row in ipairs(v.trustedRows) do
    local e = trusted[i]
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", COL2, top - 22 - (i - 1) * 22)
    row:SetShown(e ~= nil)
    if e then
      row.name = e.name
      row.text:SetText(e.name)
      local heard = svc.trust:LastHeard(e.name)
      row.state:SetText(
        e.mutual
            and ("|cff4dd973sharing|r  |cff999999%s|r"):format(heard and ("heard " .. ago(heard)) or "not heard yet")
          or "|cff999999waiting for them to approve|r"
      )
    end
  end
  v.trustedMore:ClearAllPoints()
  v.trustedMore:SetPoint("TOPLEFT", COL2, top - 22 - MAX_TRUSTED * 22)
  v.trustedMore:SetText(#trusted > MAX_TRUSTED and ("+ %d more"):format(#trusted - MAX_TRUSTED) or "")
end

---------------------------------------------------------------------------------------------------------------------
-- Settings

function UI:CreateSettingsView(parent, contentArea)
  local v = contentArea(parent)
  self.settingsView = v
  local checks = {}
  v.checks = checks

  heading(v, "Display", 0, 0)
  checks[#checks + 1] = settingCheck(v, "Show AME prices in item tooltips", "tooltip", 0, -24)
  local avgLabel = W.Text(v, "GameFontHighlightSmall")
  avgLabel:SetPoint("TOPLEFT", 260, -26)
  avgLabel:SetText("average over")
  local avgs = { { 3, "3 days" }, { 7, "7 days" }, { 14, "14 days" }, { 30, "30 days" } }
  v.avgDays = W.Dropdown(v, 90, avgs, function(value)
    ns.Settings:Set("tooltipAvgDays", value)
  end)
  v.avgDays:SetPoint("TOPLEFT", 340, -22)
  v.avgDays.values = avgs
  v.avgDays.neutral = true
  checks[#checks + 1] =
    settingCheck(v, "Always show full tooltip details (otherwise hold Shift)", "tooltipDetail", 0, -48)

  local styleLabel = W.Text(v, "GameFontHighlightSmall")
  styleLabel:SetPoint("TOPLEFT", 0, -80)
  styleLabel:SetText("Chart style")
  local styles = { { "line", "Line" }, { "candles", "Candles" } }
  v.style = W.Dropdown(v, 120, styles, function(value)
    ns.Settings:Set("chartStyle", value)
    if UI.series then
      UI:DrawItemChart()
    end
  end)
  v.style:SetPoint("TOPLEFT", 150, -76)
  v.style.values = styles
  v.style.neutral = true

  local clickLabel = W.Text(v, "GameFontHighlightSmall")
  clickLabel:SetPoint("TOPLEFT", 0, -106)
  clickLabel:SetText("Open item charts with")
  local clicks = { { "alt", "Alt-click" }, { "altshift", "Alt+Shift-click" }, { "none", "Off" } }
  v.click = W.Dropdown(v, 120, clicks, function(value)
    ns.Settings:Set("clickModifier", value)
  end)
  v.click:SetPoint("TOPLEFT", 150, -102)
  v.click.values = clicks
  v.click.neutral = true
  note(v, clickLabel, "Change this if another addon (e.g. AHDB) also uses Alt-click on items.", 440):SetPoint(
    "TOPLEFT",
    clickLabel,
    "BOTTOMLEFT",
    0,
    -14
  )

  v.minimap = W.Check(v, "Show minimap button", function(on)
    ns.Settings:SetMinimap(on)
  end)
  v.minimap:SetPoint("TOPLEFT", 0, -150)

  heading(v, "Notifications", 0, -182)
  checks[#checks + 1] = settingCheck(v, "Announce recorded full scans in chat", "announceScans", 0, -204)
  checks[#checks + 1] = settingCheck(v, "Play a sound when a watchlist alert fires", "alertSound", 0, -226)

  heading(v, "Data quality", 0, -258)
  local outlierLabel = W.Text(v, "GameFontHighlightSmall")
  outlierLabel:SetPoint("TOPLEFT", 0, -284)
  outlierLabel:SetText("Ignore outrageous prices")
  local factors = {
    { false, "Off" },
    { 3, "3x off usual" },
    { 4, "4x off usual" },
    { 6, "6x off usual" },
    { 10, "10x off usual" },
  }
  v.outliers = W.Dropdown(v, 120, factors, function(value)
    ns.Settings:Set("outlierFactor", value)
    ns.AME:InvalidateIndex()
    ns.AME:RebuildIndex()
    if UI.itemID and UI.current == "item" then
      UI:ShowItem(UI.itemID)
    end
  end)
  v.outliers:SetPoint("TOPLEFT", 150, -280)
  v.outliers.values = factors
  v.outliers.neutral = true
  local why = W.Text(v, "GameFontDisableSmall")
  why:SetPoint("TOPLEFT", 0, -306)
  why:SetWidth(440)
  why:SetSpacing(2)
  why:SetText(
    "Days where an item's price is this many times above (or below) its neighbouring days are left out of "
      .. "the screener, signals, alerts and charts - typically one listing at a 1000% markup in a thin market. "
      .. "Within a full scan, AME already ignores expensive listings: market price uses the cheapest part of the "
      .. "supply."
  )

  -- data
  heading(v, "Data", COL2, 0)
  v.storage = W.Text(v, "GameFontHighlightSmall")
  v.storage:SetPoint("TOPLEFT", COL2, -24)
  v.storage:SetWidth(460)
  v.storage:SetSpacing(3)
  local actions = {
    {
      "Re-import Auctionator history",
      "Imports Auctionator's recent daily prices for this auction house again (fills gaps only).",
      function()
        ns.AME:Backfill(true)
      end,
    },
    {
      "Rebuild market index",
      "Recomputes the 30-day summaries behind the screener, tooltips and alerts.",
      function()
        ns.AME:RebuildIndex()
      end,
    },
    {
      "Run self-test",
      "Checks every part of AME and offers a reload so the results are saved.",
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
  heading(v, "Auction house cut", COL2, -258)
  local function cutInput(key, label, y)
    local t = W.Text(v, "GameFontHighlightSmall")
    t:SetPoint("TOPLEFT", COL2, y)
    t:SetText(label)
    local input = W.Input(v)
    input:SetSize(44, 20)
    input:SetNumeric(true)
    input:SetPoint("TOPLEFT", COL2 + 170, y + 4)
    input:SetScript("OnTextChanged", function(self, user)
      local n = tonumber(self:GetText())
      if user and n and n <= 100 then
        ns.Settings:Set(key, n)
      end
    end)
    input:SetScript("OnEnterPressed", input.ClearFocus)
    local pct = W.Text(v, "GameFontHighlightSmall")
    pct:SetPoint("LEFT", input, "RIGHT", 4, 0)
    pct:SetText("%")
    input.key = key
    return input
  end
  v.cutFaction = cutInput("cutFaction", "Faction auction houses", -284)
  v.cutNeutral = cutInput("cutNeutral", "Goblin auction houses", -310)
  local hoursLabel = W.Text(v, "GameFontHighlightSmall")
  hoursLabel:SetPoint("TOPLEFT", COL2 + 250, -284)
  hoursLabel:SetText("Deposits for")
  local hours = { { 2, "2 h listings" }, { 8, "8 h listings" }, { 24, "24 h listings" } }
  v.hours = W.Dropdown(v, 110, hours, function(value)
    ns.Settings:Set("listingHours", value)
    if UI.RenderArbitrage then
      UI:RenderArbitrage()
    end
  end)
  v.hours.neutral = true
  v.hours.values = hours
  v.hours:SetPoint("TOPLEFT", COL2 + 330, -280)

  local more = W.Text(v, "GameFontDisableSmall")
  more:SetPoint("TOPLEFT", COL2, -340)
  more:SetWidth(440)
  more:SetText("Sharing settings are on the Sync tab. These options are also in the game's AddOns settings.")

  v:SetScript("OnShow", function()
    UI:RefreshSettings()
  end)
  return v
end

local function indexOf(values, value)
  for i, o in ipairs(values) do
    if o[1] == value then
      return i
    end
  end
  return 1
end

function UI:RefreshSettings()
  local v = self.settingsView
  if not (v and v:IsShown()) then
    return
  end
  for _, c in ipairs(v.checks) do
    c:SetChecked(ns.Settings:Get(c.key))
  end
  v.style:SetIndex(indexOf(v.style.values, ns.Settings:Get("chartStyle")))
  v.click:SetIndex(indexOf(v.click.values, ns.Settings:Get("clickModifier")))
  v.outliers:SetIndex(indexOf(v.outliers.values, ns.Settings:Get("outlierFactor")))
  v.avgDays:SetIndex(indexOf(v.avgDays.values, ns.Settings:Get("tooltipAvgDays")))
  v.cutFaction:SetText(tostring(ns.Settings:Get("cutFaction")))
  v.cutNeutral:SetText(tostring(ns.Settings:Get("cutNeutral")))
  v.hours:SetIndex(indexOf(v.hours.values, ns.Settings:Get("listingHours")))
  local hasIcon = ns.Settings:HasMinimapLibrary()
  v.minimap:SetChecked(hasIcon and not AME_DB.settings.minimap.hide)
  v.minimap.label:SetText(
    hasIcon and "Show minimap button" or "Show minimap button |cff999999(needs LibDBIcon; included in releases)|r"
  )

  local AME = ns.AME
  local lines = { ("Market: |cffffffff%s|r"):format(ns.ShardLabel(AME:CurrentShard())) }
  if AME:HistoryLoaded() then
    local shards, days, bytes = 0, 0, 0
    for _, data in pairs(AME.history.shards) do
      shards = shards + 1
      for _, buckets in pairs(data.days or {}) do
        days = days + 1
        for _, p in pairs(buckets) do
          bytes = bytes + #p
        end
      end
    end
    local here = AME.history.shards[AME:CurrentShard()]
    local hereDays = 0
    for _ in pairs(here and here.days or {}) do
      hereDays = hereDays + 1
    end
    lines[#lines + 1] = ("This market: %d days of history, %d recent scans kept in full"):format(
      hereDays,
      here and #(here.raw or {}) or 0
    )
    lines[#lines + 1] = ("All markets: %d, %.0f KB of compressed daily history"):format(shards, bytes / 1024)
  else
    lines[#lines + 1] = "History not loaded yet."
  end
  local f = AME_DB.stats.lastFull
  lines[#lines + 1] = f and ("Last full scan: %d items, %s"):format(f.items, ago(f.at)) or "No full scan recorded yet."
  v.storage:SetText(table.concat(lines, "\n"))
end

-- keep ADDON referenced for future per-addon options
UI.ADDON = ADDON
