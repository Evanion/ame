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

-- How fresh each auction house's data is: the newest full scan kept for it, when, and who ran it.
--   { { house, t, src }, ... } for the faction houses and the goblin one
UI.SYNC_HOUSES = { "Alliance", "Horde", "Neutral" }
function UI:Freshness()
  local AME, out = ns.AME, {}
  local realm = AME:MarketRealmName()
  for _, house in ipairs(UI.SYNC_HOUSES) do
    local data = AME:HistoryLoaded() and AME.history.shards[ns.ShardKey(realm, house)]
    local best
    for _, e in ipairs(data and data.raw or {}) do
      if e.k == "full" and (not best or e.t > best.t) then
        best = e
      end
    end
    out[#out + 1] = { house = house, t = best and best.t, src = best and best.src }
  end
  return out
end

function UI:CreateSyncView(parent, contentArea)
  local outer = contentArea(parent)
  local slots = UI.Slots(outer, { header = 42, status = true })
  outer.slots = slots
  -- header: data freshness per auction house
  local defs = {}
  for i, house in ipairs(UI.SYNC_HOUSES) do
    defs[i] = { ns.HOUSE_LABEL[house] or house }
  end
  local cards = W.CardRow(slots.header, defs, { width = UI.WIDTH - 20 })
  cards:SetPoint("TOPLEFT", 0, 0)
  cards:SetPoint("RIGHT", 0, 0)
  -- everything else scrolls when the window is shorter than the tab's content
  local pane = W.ScrollPane(slots.main)
  local v = pane.content
  v.pane = pane
  v.fresh = cards.cards
  v.statusLine = slots.status
  self.syncView = v
  local svc = ns.SyncService

  heading(v, L["Sharing"], 0, 0)
  v.guild = settingCheck(v, L["Share full scans with my guild (members running AME)"], "syncGuild", 0, -24)
  v.trusted = settingCheck(v, L["Share with trusted players (below)"], "syncTrusted", 0, -46)
  W.Paragraph(
    v,
    L["Your alts on this Battle.net account already share everything: AME's history is saved account-wide. Trust players to swap scans with friends, or with your own characters on other accounts. Only your market and auction house are shared, and scans that disagree wildly with your prices are rejected."],
    450
  ):SetPoint("TOPLEFT", 0, -72)

  heading(v, L["Activity"], 0, -128)
  v.activity = W.Text(v, "GameFontHighlightSmall")
  v.activity:SetPoint("TOPLEFT", 0, -150)
  v.activity:SetWidth(450)
  v.activity:SetSpacing(3)

  heading(v, L["Recently heard from"], 0, -236)
  local function act(method)
    return function(item)
      svc[method](svc, item.name)
      UI:RefreshSync()
    end
  end
  v.peerList = W.RowList(v, {
    rows = MAX_PEERS,
    buttons = {
      {
        key = "block",
        label = L["Block"],
        width = 50,
        onClick = act("Block"),
        shown = function(p)
          return not svc.trust:IsBlocked(p.name)
        end,
      },
    },
    empty = L["No one yet."],
  })
  v.peerList:SetPoint("TOPLEFT", 0, -258)
  v.peers = v.peerList.rows

  heading(v, L["Blocked"], 0, -364)
  v.guildBlocked = W.Text(v, "GameFontDisableSmall")
  v.guildBlocked:SetPoint("TOPLEFT", 0, -384)
  v.guildBlocked:SetWidth(460)
  v.blockedList = W.RowList(v, {
    rows = MAX_BLOCKED,
    buttons = { { key = "unblock", label = L["Unblock"], width = 60, onClick = act("Unblock") } },
    empty = L["You haven't blocked anyone."],
  })
  v.blockedList:SetPoint("TOPLEFT", 0, -400)
  v.blocked = v.blockedList.rows

  -- trusted players
  heading(v, L["Trusted players"], COL2, 0)
  local input
  local function add()
    local e, why = svc:AddTrusted(input:GetText())
    if e then
      input:SetText("")
      v.addStatus:SetText(L["Asked %s to share. They'll see a request in their Sync tab."]:format(e.name))
    else
      v.addStatus:SetText(W.Color("bad", why))
    end
    input:ClearFocus()
    UI:RefreshSync()
  end
  input = W.Input(v, { width = 240, hint = L["Character name, e.g. First Last"], onEnter = add })
  input:SetPoint("TOPLEFT", COL2, -24)
  v.input = input
  local addButton = W.Button(v, L["Add"], 60, 20, add)
  addButton:SetPoint("LEFT", input, "RIGHT", 6, 0)
  v.addStatus = W.Text(v, "GameFontDisableSmall")
  v.addStatus:SetPoint("TOPLEFT", COL2, -48)
  v.addStatus:SetWidth(460)

  v.pendingHead = heading(v, L["Requests"], COL2, -70)
  v.pendingList = W.RowList(v, {
    rows = MAX_PENDING,
    rowHeight = 22,
    buttons = {
      { key = "approve", label = L["Approve"], width = 64, onClick = act("Approve") },
      { key = "decline", label = L["Decline"], width = 64, onClick = act("Decline") },
      { key = "block", label = L["Block"], width = 50, onClick = act("Block") },
    },
  })
  v.pendingList:SetPoint("TOPLEFT", COL2, -92)
  v.pending = v.pendingList.rows

  v.trustedHead = heading(v, L["Trusted"], COL2, -164)
  v.trustedList = W.RowList(v, {
    rows = MAX_TRUSTED,
    rowHeight = 22,
    buttons = { { key = "remove", close = true, onClick = act("RemoveTrusted") } },
    state = true,
    empty = L["Nobody yet. Add a friend above - they need AME too, and must approve."],
    more = L["+ %d more"],
  })
  v.trustedRows = v.trustedList.rows

  v:SetScript("OnShow", function()
    UI:RefreshSync()
  end)
  svc.onChange = function()
    UI:RefreshSync()
  end
  return outer
end

function UI:RefreshSync()
  local v = self.syncView
  if not (v and v:IsShown()) then
    return
  end
  local svc = ns.SyncService
  -- freshness: green within a day, amber within 3, dim older or none
  local me = UnitName("player")
  local now = GetServerTime()
  for i, f in ipairs(self:Freshness()) do
    local card = v.fresh[i]
    if f.t then
      local days = (now - f.t) / ns.DAY
      local role = days < 1 and "good" or days < 3 and "warn" or "dim"
      local who = (not f.src or f.src == me) and L["you"] or f.src
      card.value:SetText(W.Color(role, ago(f.t)) .. "  " .. W.Dim(L["full scan by %s"]:format(who)))
    else
      card.value:SetText(W.Dim(L["No full scan yet: scan there, or trust someone who does"]))
    end
  end
  v.statusLine:SetText(
    (ns.Settings:Get("syncGuild") or ns.Settings:Get("syncTrusted")) and L["Sync is on."]
      or L["Sync is off: turn on guild or trusted sharing below."]
  )
  v.guild:SetChecked(ns.Settings:Get("syncGuild"))
  v.trusted:SetChecked(ns.Settings:Get("syncTrusted"))

  local s = AME_DB.stats
  local lines = {}
  if not svc.enabled then
    lines[1] = W.Color("bad", L["Sync is unavailable: the AceComm library didn't load."])
  else
    local guild = IsInGuild and IsInGuild()
    lines[#lines + 1] = L["Guild: %s"]:format(
      not ns.Settings:Get("syncGuild") and L["off"]
        or guild and W.Color("good", L["on"])
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
      lines[#lines + 1] = W.Color("warn", L["Last rejected:"]) .. " " .. s.lastSyncRejection
    end
  end
  v.activity:SetText(table.concat(lines, "\n"))

  v.peerList:SetItems(svc.trust and svc.trust:PeerList() or {}, function(row, p)
    local blocked = svc.trust:IsBlocked(p.name)
    row.text:SetText(
      p.name
        .. "  "
        .. W.Dim(
          L["via %s, %s"]:format(p.via == "GUILD" and L["guild"] or L["whisper"], ago(p.at))
            .. ((p.received or 0) > 0 and L[", %d scans received"]:format(p.received) or "")
            .. (blocked and ", " .. W.Color("bad", L["blocked"]) or "")
        )
    )
  end)

  local guildList = {}
  for _, name in pairs(svc.trust and svc.trust.guildBlocked or {}) do
    guildList[#guildList + 1] = name
  end
  table.sort(guildList)
  v.guildBlocked:SetText(
    #guildList > 0 and L["By your guild officers: %s"]:format(W.Color("white", table.concat(guildList, ", ")))
      or L['Guild officers can block players for everyone: add a line "%s" to the guild info.']:format(
        "AME block: Name, Name"
      )
  )
  v.blockedList:SetItems(svc.trust and svc.trust:BlockedList() or {}, function(row, b)
    row.text:SetText(b.name .. "  " .. W.Dim(L["blocked %s"]:format(ago(b.at))))
  end)

  local pending = svc.trust and svc.trust:PendingList() or {}
  v.pendingHead:SetShown(#pending > 0)
  v.pendingList:SetItems(pending, function(row, p)
    row.text:SetText(p.name .. "  " .. W.Dim(L["wants to share, %s"]:format(ago(p.at))))
  end)

  local trusted = svc.trust and svc.trust:TrustedList() or {}
  local top = #pending > 0 and (-92 - math.min(#pending, MAX_PENDING) * 22 - 10) or -70
  v.trustedHead:ClearAllPoints()
  v.trustedHead:SetPoint("TOPLEFT", COL2, top)
  v.trustedHead:SetText(L["Trusted (%d)"]:format(#trusted))
  v.trustedList:ClearAllPoints()
  v.trustedList:SetPoint("TOPLEFT", COL2, top - 22)
  v.trustedList:SetItems(trusted, function(row, e)
    row.text:SetText(e.name)
    local heard = svc.trust:LastHeard(e.name)
    row.state:SetText(
      e.mutual
          and W.Color("good", L["sharing"]) .. "  " .. W.Dim(
            heard and L["heard %s"]:format(ago(heard)) or L["not heard yet"]
          )
        or W.Dim(L["waiting for them to approve"])
    )
  end)
end

-- the Sync tab's lists grow and shrink: its scroll pane re-measures after every refresh
local refreshSync = UI.RefreshSync
function UI:RefreshSync(...)
  refreshSync(self, ...)
  local v = self.syncView
  if v and v.pane then
    v.pane:Measure()
  end
end
