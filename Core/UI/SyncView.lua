-- Sharing (shown in the Settings tab): how fresh each auction house's data is, then Guild sharing, Trusted players,
-- Blocked.
local _, ns = ...
local L = ns.L

local W = ns.Widgets
local UI = ns.UI

local function ago(t)
  return W.Ago(t, GetServerTime())
end

---------------------------------------------------------------------------------------------------------------------
-- Sync

local MAX_TRUSTED, MAX_PENDING, MAX_PEERS, MAX_BLOCKED = 8, 3, 5, 4
local LIST_W = 320 -- list rows (their text truncates, buttons sit at the right)

-- the auction houses in the order a player cares about: their own faction's, the goblin one, the other faction's
function UI:SyncHouses()
  local own = UnitFactionGroup and UnitFactionGroup("player") or "Horde"
  if own ~= "Alliance" and own ~= "Horde" then
    own = "Horde"
  end
  return { own, "Neutral", own == "Horde" and "Alliance" or "Horde" }
end

-- How fresh each auction house's data is: the newest full scan kept for it, when, who ran it, how many items.
--   { { house, t, src, items }, ... }
function UI:Freshness()
  local AME, out = ns.AME, {}
  local realm = AME:MarketRealmName()
  for _, house in ipairs(self:SyncHouses()) do
    local shard = ns.ShardKey(realm, house)
    local data = AME:HistoryLoaded() and AME.history.shards[shard]
    local best
    for _, e in ipairs(data and data.raw or {}) do
      if e.k == "full" and (not best or e.t > best.t) then
        best = e
      end
    end
    local index = AME.CachedIndex and AME:CachedIndex(shard)
    out[#out + 1] = { house = house, t = best and best.t, src = best and best.src, items = index and index.count }
  end
  return out
end

-- The Sharing section of the Settings tab (Settings builds it into its section frame `v`): the freshness of each
-- auction house's data, then three cards - Guild sharing, Trusted players, Blocked - in one column.
--   host: { pane = the settings scroll pane, status = the window footer's text for this tab }
function UI:CreateSyncSection(v, host)
  local svc = ns.SyncService
  v.pane = host.pane
  v.statusLine = host.status
  self.syncView = v
  -- freshness per auction house - the age large, then the source
  local defs = {}
  for k, house in ipairs(self:SyncHouses()) do
    defs[k] = { ns.HOUSE_LABEL[house] or house }
  end
  local cards = W.CardRow(v, defs, { width = 560, height = 56, gap = UI.SETTINGS_GAP or 10 })
  cards:SetPoint("TOPLEFT", 0, 0)
  cards:SetPoint("RIGHT", 0, 0)
  for _, c in ipairs(cards.cards) do
    c.value:SetFontObject("GameFontHighlightLarge")
    c.value:ClearAllPoints()
    c.value:SetPoint("TOPLEFT", c.label, "BOTTOMLEFT", 0, -3)
    c.sub = W.Text(c, "GameFontDisableSmall")
    c.sub:SetPoint("BOTTOMLEFT", 8, 6)
    c.sub:SetPoint("RIGHT", -8, 0)
    c.sub:SetWordWrap(false)
  end
  v.fresh = cards.cards

  -- the cards, one column under the freshness row
  local column = CreateFrame("Frame", nil, v)
  column:SetPoint("TOPLEFT", 0, -(56 + (UI.SETTINGS_GAP or 10)))
  column:SetPoint("RIGHT", 0, 0)
  column:SetHeight(1)
  local stack = UI.Stack(column, 0)
  -- the section's height: the freshness row and the cards (the settings tab places the section)
  function v:Measure(width)
    local h = stack:Height(width)
    column:SetHeight(math.max(1, h))
    return 56 + (UI.SETTINGS_GAP or 10) + h
  end
  function v:LayoutColumns()
    if host.relayout then
      host.relayout()
    end
  end
  local function act(method)
    return function(item)
      svc[method](svc, item.name)
      UI:RefreshSync()
    end
  end
  local lists = {}
  local function list(st, rows, rowHeight, opts)
    local holder = st:Row(rowHeight, 4)
    opts.rows, opts.rowHeight, opts.width, opts.fill = rows, rowHeight, LIST_W, true
    local l = W.RowList(holder, opts)
    l:SetPoint("TOPLEFT")
    l:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
    l.holder = holder
    lists[#lists + 1] = l
    return l
  end
  -- the cards follow their lists' heights (call after SetItems)
  function v:FitLists()
    for _, l in ipairs(lists) do
      l.holder:SetHeight(math.max(1, l:GetHeight() or 1))
    end
  end
  local function sublabel(st, text)
    local t = st:Text("GameFontDisableSmall", 10)
    t:SetText(text)
    return t
  end

  -- Guild sharing: the switch, one line of activity, the players heard from
  local st = stack:Card(0).stack
  st:Heading(L["Guild sharing"], 0)
  local row = st:Row(18, 6)
  v.guild = W.SettingCheck(row, L["Share full scans with my guild"], "syncGuild", 0, -1)
  v.activity = st:Text("GameFontDisableSmall", 6)
  v.activity:SetSpacing(2)
  sublabel(st, L["Players heard from"])
  v.peerList = list(st, MAX_PEERS, 20, {
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
    state = true,
    empty = L["No one yet."],
  })
  v.peers = v.peerList.rows

  -- Trusted players: intro, the switch, ask by name, the list, then requests
  st = stack:Card().stack
  st:Heading(L["Trusted players"], 0)
  local intro = st:Text("GameFontDisableSmall", 4)
  intro:SetText(L["Swap scans with friends, or your own characters on other accounts."])
  row = st:Row(18, 6)
  v.trusted = W.SettingCheck(row, L["Share with trusted players"], "syncTrusted", 0, -1)
  local input
  local function add()
    local e, why = svc:AddTrusted(input:GetText())
    if e then
      input:SetText("")
      v.addStatus:SetText(L["Asked %s to share. They'll see a request under Settings, Sharing."]:format(e.name))
    else
      v.addStatus:SetText(W.Color("bad", why))
    end
    input:ClearFocus()
    UI:RefreshSync()
  end
  row = st:Row(22, 8)
  local addButton = W.Button(row, L["Ask to share"], 90, 20, add)
  addButton:SetWidth(math.ceil(addButton.label:GetStringWidth() or 70) + 16)
  addButton:SetPoint("RIGHT", 0, 0)
  input = W.Input(row, { width = 160, hint = L["Character name"], onEnter = add })
  input:SetPoint("LEFT", 0, 0)
  input:SetPoint("RIGHT", addButton, "LEFT", -6, 0)
  v.input = input
  v.addStatus = st:Text("GameFontDisableSmall", 4)
  v.trustedList = list(st, MAX_TRUSTED, 22, {
    buttons = { { key = "remove", close = true, onClick = act("RemoveTrusted") } },
    state = true,
    empty = L["Nobody yet. Add a friend above - they need AME too, and must approve."],
    more = L["+ %d more"],
  })
  v.trustedRows = v.trustedList.rows
  v.pendingHead = sublabel(st, L["Requests"])
  v.pendingList = list(st, MAX_PENDING, 22, {
    buttons = {
      { key = "approve", label = L["Approve"], width = 64, onClick = act("Approve") },
      { key = "decline", label = L["Decline"], width = 64, onClick = act("Decline") },
      { key = "block", label = L["Block"], width = 50, onClick = act("Block") },
    },
    empty = L["No requests."],
  })
  v.pending = v.pendingList.rows

  -- Price checks: answer "!pc <item>" in chat
  st = stack:Card().stack
  st:Heading(L["Price checks"], 0)
  local pcIntro = st:Text("GameFontDisableSmall", 4)
  pcIntro:SetText(
    L["When someone types !pc and an item (link or name), AME answers with its prices at your faction's auction house. If several players run AME, only one of you answers. Your own !pc is always answered in the channel you asked in, even with this off."]
  )
  row = st:Row(18, 4)
  v.priceCheck = W.SettingCheck(row, L["Answer in guild, party and raid chat"], "priceCheck", 0, -1)
  row = st:Row(18, 4)
  v.priceCheckWhisper = W.SettingCheck(
    row,
    L["Answer whispers from guild members, friends, your party or raid, and trusted players"],
    "priceCheckWhisper",
    0,
    -1
  )
  -- one answer every N seconds, however many ask
  row = st:Row(22, 4)
  local cooldowns = {}
  for i, s in ipairs(ns.PriceCheck.COOLDOWNS) do
    cooldowns[i] = { s, L["%d s"]:format(s) }
  end
  v.priceCheckCooldown = W.Dropdown(row, 70, cooldowns, function(value)
    ns.Settings:Set("priceCheckCooldown", value)
  end, { neutral = true })
  v.priceCheckCooldown:SetPoint("RIGHT", 0, 0)
  local cdLabel = W.Text(row, "GameFontHighlightSmall")
  cdLabel:SetPoint("LEFT", 0, 0)
  cdLabel:SetPoint("RIGHT", v.priceCheckCooldown, "LEFT", -6, 0)
  cdLabel:SetText(L["Answer at most once every"])
  cdLabel:SetWordWrap(false)

  -- Blocked: what it does, the list, the last rejected scan
  st = stack:Card().stack
  st:Heading(L["Blocked"], 0)
  v.guildBlocked = st:Text("GameFontDisableSmall", 4)
  v.guildBlocked:SetSpacing(2)
  v.blockedList = list(st, MAX_BLOCKED, 20, {
    buttons = { { key = "unblock", label = L["Unblock"], width = 60, onClick = act("Unblock") } },
    empty = L["You haven't blocked anyone."],
  })
  v.blocked = v.blockedList.rows
  v.lastRejected = st:Text("GameFontDisableSmall", 8)

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
  -- freshness: the age large (green within a day, amber within 3, dim older), the source and size under it
  local me = UnitName("player")
  local now = GetServerTime()
  for i, f in ipairs(self:Freshness()) do
    local card = v.fresh[i]
    card.label:SetText(ns.HOUSE_LABEL[f.house] or f.house)
    if f.t then
      local days = (now - f.t) / ns.DAY
      local role = days < 1 and "good" or days < 3 and "warn" or "dim"
      card.value:SetText(W.Color(role, L["%s old"]:format(W.Age(f.t, now))))
      local who = (not f.src or f.src == me) and L["you"] or f.src
      local sub = L["Full scan by %s"]:format(who)
      if f.items then
        sub = sub .. W.SEP .. L["%s items"]:format(W.Thousands(f.items))
      end
      card.sub:SetText(sub)
    else
      card.value:SetText(W.Dim(L["No data"]))
      card.sub:SetText(L["No full scan yet: scan there, or trust someone who does"])
    end
  end
  v.statusLine:SetText(
    (ns.Settings:Get("syncGuild") or ns.Settings:Get("syncTrusted")) and L["Sync is on"]
      or L["Sync is off: turn on guild or trusted sharing below"]
  )
  v.guild:SetChecked(ns.Settings:Get("syncGuild"))
  v.trusted:SetChecked(ns.Settings:Get("syncTrusted"))
  v.priceCheck:SetChecked(ns.Settings:Get("priceCheck"))
  v.priceCheckWhisper:SetChecked(ns.Settings:Get("priceCheckWhisper"))
  v.priceCheckCooldown:SetValue(ns.Settings:Get("priceCheckCooldown"))

  local s = AME_DB.stats
  if not svc.enabled then
    v.activity:SetText(W.Color("bad", L["Sync is unavailable: the AceComm library didn't load."]))
  else
    local lines = {}
    if ns.Settings:Get("syncGuild") and not (IsInGuild and IsInGuild()) then
      lines[#lines + 1] = L["You're not in a guild."]
    end
    lines[#lines + 1] = L["Announced %d  ·  served %d  ·  received %d  ·  rejected %d"]:format(
      s.syncAnnounced or 0,
      s.syncServed or 0,
      s.syncReceived or 0,
      s.syncRejected or 0
    )
    local last = s.lastSyncReceived
    if last then
      lines[#lines + 1] = L["Last received: %d items from %s, %s"]:format(last.items, last.from, ago(last.at))
    end
    v.activity:SetText(table.concat(lines, "\n"))
  end

  -- every list leaves out my own characters (this account's: listed before AME knew them, or heard on an alt)
  local function others(list)
    local out = {}
    for _, e in ipairs(list or {}) do
      if not svc:IsMine(e.name) then
        out[#out + 1] = e
      end
    end
    return out
  end
  v.peerList:SetItems(others(svc.trust and svc.trust:PeerList()), function(row, p)
    local blocked = svc.trust:IsBlocked(p.name)
    row.text:SetText(p.name)
    row.state:SetText(
      W.Dim(
        (p.via == "GUILD" and L["guild"] or L["whisper"])
          .. "  ·  "
          .. L["heard %s"]:format(ago(p.at))
          .. (blocked and "  ·  " .. W.Color("bad", L["blocked"]) or "")
      )
    )
  end)

  local guildList = {}
  for _, name in pairs(svc.trust and svc.trust.guildBlocked or {}) do
    guildList[#guildList + 1] = name
  end
  table.sort(guildList)
  local blockedText = L["Scans from these players are ignored."]
  if #guildList > 0 then
    blockedText = blockedText
      .. " "
      .. L["By your guild officers: %s"]:format(W.Color("white", table.concat(guildList, ", ")))
  else
    blockedText = blockedText
      .. " "
      .. L['Guild officers can block players for everyone: add a line "%s" to the guild info.']:format(
        "AME block: Name, Name"
      )
  end
  v.guildBlocked:SetText(blockedText)
  v.blockedList:SetItems(others(svc.trust and svc.trust:BlockedList()), function(row, b)
    row.text:SetText(b.name .. "  " .. W.Dim(L["blocked %s"]:format(ago(b.at))))
  end)
  v.lastRejected:SetText(s.lastSyncRejection and (L["Last rejected:"] .. " " .. s.lastSyncRejection) or "")

  v.trustedList:SetItems(others(svc.trust and svc.trust:TrustedList()), function(row, e)
    row.text:SetText(e.name)
    local heard = svc.trust:LastHeard(e.name)
    row.state:SetText(
      e.mutual and W.Dim(L["trusted"] .. "  ·  " .. (heard and L["heard %s"]:format(ago(heard)) or L["not heard yet"]))
        or W.Dim(L["waiting for them to approve"])
    )
  end)
  local pending = others(svc.trust and svc.trust:PendingList())
  v.pendingList:SetItems(pending, function(row, p)
    row.text:SetText(p.name .. "  " .. W.Dim(L["wants to share, %s"]:format(ago(p.at))))
  end)
  v:FitLists()
  v:LayoutColumns()
end
