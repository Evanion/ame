-- Sync tab: guild sharing, trusted players, requests, blocklists and sync statistics.
local _, ns = ...
local L = ns.L

local W = ns.Widgets
local UI = ns.UI
local heading, settingCheck = W.Heading, W.SettingCheck

local function ago(t)
  return W.Ago(t, GetServerTime())
end

---------------------------------------------------------------------------------------------------------------------
-- Sync

local MAX_TRUSTED, MAX_PENDING, MAX_PEERS, MAX_BLOCKED = 9, 3, 5, 3
local COL2 = UI.COLUMN2

function UI:CreateSyncView(parent, contentArea)
  local v = contentArea(parent)
  self.syncView = v
  local svc = ns.SyncService

  heading(v, L["Sharing"], 0, 0)
  v.guild = settingCheck(v, L["Share full scans with my guild (members running AME)"], "syncGuild", 0, -24)
  v.trusted = settingCheck(v, L["Share with trusted players (below)"], "syncTrusted", 0, -46)
  local alts = W.Text(v, "GameFontDisableSmall")
  alts:SetPoint("TOPLEFT", 0, -72)
  alts:SetWidth(450)
  alts:SetSpacing(2)
  alts:SetText(
    L["Your alts on this Battle.net account already share everything: AME's history is saved account-wide. Trust players to swap scans with friends, or with your own characters on other accounts. Only your market and auction house are shared, and scans that disagree wildly with your prices are rejected."]
  )

  heading(v, L["Activity"], 0, -128)
  v.activity = W.Text(v, "GameFontHighlightSmall")
  v.activity:SetPoint("TOPLEFT", 0, -150)
  v.activity:SetWidth(450)
  v.activity:SetSpacing(3)

  heading(v, L["Recently heard from"], 0, -236)
  v.peers = {}
  for i = 1, MAX_PEERS do
    local row = CreateFrame("Frame", nil, v)
    row:SetSize(460, 18)
    row:SetPoint("TOPLEFT", 0, -258 - (i - 1) * 20)
    row.text = W.Text(row, "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 0, 0)
    row.text:SetWidth(390)
    row.block = W.Button(row, L["Block"], 50, 16, function()
      svc:Block(row.name)
      UI:RefreshSync()
    end)
    row.block:SetPoint("RIGHT", 0, 0)
    v.peers[i] = row
  end

  heading(v, L["Blocked"], 0, -364)
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
    row.unblock = W.Button(row, L["Unblock"], 60, 16, function()
      svc:Unblock(row.name)
      UI:RefreshSync()
    end)
    row.unblock:SetPoint("RIGHT", 0, 0)
    v.blocked[i] = row
  end

  -- trusted players
  heading(v, L["Trusted players"], COL2, 0)
  local input = W.Input(v)
  input:SetSize(240, 20)
  input:SetPoint("TOPLEFT", COL2, -24)
  input.hint = W.Text(input, "GameFontDisableSmall")
  input.hint:SetPoint("LEFT", 6, 0)
  input.hint:SetPoint("RIGHT", -6, 0) -- clipped to the box (translations run longer)
  input.hint:SetJustifyH("LEFT")
  input.hint:SetWordWrap(false)
  input.hint:SetText(L["Character name, e.g. First Last"])
  local function add()
    local e, why = svc:AddTrusted(input:GetText())
    if e then
      input:SetText("")
      v.addStatus:SetText(L["Asked %s to share. They'll see a request in their Sync tab."]:format(e.name))
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
  local addButton = W.Button(v, L["Add"], 60, 20, add)
  addButton:SetPoint("LEFT", input, "RIGHT", 6, 0)
  v.addStatus = W.Text(v, "GameFontDisableSmall")
  v.addStatus:SetPoint("TOPLEFT", COL2, -48)
  v.addStatus:SetWidth(460)

  v.pendingHead = heading(v, L["Requests"], COL2, -70)
  v.pending = {}
  for i = 1, MAX_PENDING do
    local row = CreateFrame("Frame", nil, v)
    row:SetSize(460, 20)
    row:SetPoint("TOPLEFT", COL2, -92 - (i - 1) * 22)
    row.text = W.Text(row, "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 0, 0)
    row.approve = W.Button(row, L["Approve"], 64, 18, function()
      svc:Approve(row.name)
      UI:RefreshSync()
    end)
    row.approve:SetPoint("RIGHT", -126, 0)
    row.decline = W.Button(row, L["Decline"], 64, 18, function()
      svc:Decline(row.name)
      UI:RefreshSync()
    end)
    row.decline:SetPoint("RIGHT", -56, 0)
    row.block = W.Button(row, L["Block"], 50, 18, function()
      svc:Block(row.name)
      UI:RefreshSync()
    end)
    row.block:SetPoint("RIGHT", 0, 0)
    v.pending[i] = row
  end

  v.trustedHead = heading(v, L["Trusted"], COL2, -164)
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
  v.trustedEmpty:SetText(L["Nobody yet. Add a friend above - they need AME too, and must approve."])
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
    lines[1] = "|cffff6159" .. L["Sync is unavailable: the AceComm library didn't load."] .. "|r"
  else
    local guild = IsInGuild and IsInGuild()
    lines[#lines + 1] = L["Guild: %s"]:format(
      not ns.Settings:Get("syncGuild") and L["off"]
        or guild and "|cff4dd973" .. L["on"] .. "|r"
        or L["on, but you're not in a guild"]
    )
    lines[#lines + 1] = L["Announced %d times, served %d scans, received %d, rejected %d"]:format(
      s.syncAnnounced or 0,
      s.syncServed or 0,
      s.syncReceived or 0,
      s.syncRejected or 0
    )
    local last = s.lastSyncReceived
    lines[#lines + 1] = last and L["Last received: %d items from %s, %s"]:format(last.items, last.from, ago(last.at))
      or L["Nothing received yet - scans arrive when someone you share with runs a full scan."]
    if s.lastSyncRejection then
      lines[#lines + 1] = "|cffffcc00" .. L["Last rejected:"] .. "|r " .. s.lastSyncRejection
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
        ("%s  |cff999999%s%s%s|r"):format(
          p.name,
          L["via %s, %s"]:format(p.via == "GUILD" and L["guild"] or L["whisper"], ago(p.at)),
          (p.received or 0) > 0 and L[", %d scans received"]:format(p.received) or "",
          blocked and ", |cffff6159" .. L["blocked"] .. "|r" or ""
        )
      )
    else
      row.text:SetText(i == 1 and "|cff999999" .. L["No one yet."] .. "|r" or "")
    end
  end

  local guildList = {}
  for _, name in pairs(svc.trust and svc.trust.guildBlocked or {}) do
    guildList[#guildList + 1] = name
  end
  table.sort(guildList)
  v.guildBlocked:SetText(
    #guildList > 0 and L["By your guild officers: %s"]:format("|cffffffff" .. table.concat(guildList, ", ") .. "|r")
      or L['Guild officers can block players for everyone: add a line "%s" to the guild info.']:format(
        "AME block: Name, Name"
      )
  )
  local blocked = svc.trust and svc.trust:BlockedList() or {}
  for i, row in ipairs(v.blocked) do
    local b = blocked[i]
    row:SetShown(b ~= nil or (i == 1 and #blocked == 0))
    row.name = b and b.name
    row.unblock:SetShown(b ~= nil)
    if b then
      row.text:SetText(("%s  |cff999999%s|r"):format(b.name, L["blocked %s"]:format(ago(b.at))))
    else
      row.text:SetText("|cff999999" .. L["You haven't blocked anyone."] .. "|r")
    end
  end

  local pending = svc.trust and svc.trust:PendingList() or {}
  v.pendingHead:SetShown(#pending > 0)
  for i, row in ipairs(v.pending) do
    local p = pending[i]
    row:SetShown(p ~= nil)
    if p then
      row.name = p.name
      row.text:SetText(("%s  |cff999999%s|r"):format(p.name, L["wants to share, %s"]:format(ago(p.at))))
    end
  end

  local trusted = svc.trust and svc.trust:TrustedList() or {}
  local top = #pending > 0 and (-92 - math.min(#pending, MAX_PENDING) * 22 - 10) or -70
  v.trustedHead:ClearAllPoints()
  v.trustedHead:SetPoint("TOPLEFT", COL2, top)
  v.trustedHead:SetText(L["Trusted (%d)"]:format(#trusted))
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
            and ("|cff4dd973%s|r  |cff999999%s|r"):format(
              L["sharing"],
              heard and L["heard %s"]:format(ago(heard)) or L["not heard yet"]
            )
          or "|cff999999" .. L["waiting for them to approve"] .. "|r"
      )
    end
  end
  v.trustedMore:ClearAllPoints()
  v.trustedMore:SetPoint("TOPLEFT", COL2, top - 22 - MAX_TRUSTED * 22)
  v.trustedMore:SetText(#trusted > MAX_TRUSTED and L["+ %d more"]:format(#trusted - MAX_TRUSTED) or "")
end
