-- Guild sync glue: announces our full scans, requests ones we lack, serves requests, merges received scans.
-- Transport is injectable (default: AceComm-3.0 at BULK priority via ChatThrottleLib).
local _, ns = ...
local L = ns.L

local Sync = ns.Sync

local Service = {}
ns.SyncService = Service

Service.PREFIX = "AME1"
Service.ANNOUNCE_EVERY = 600 -- seconds
Service.REQUEST_COOLDOWN = 600
Service.MAX_REQUESTS_PER_ANNOUNCE = 4
Service.GONE_QUIET = 600 -- a player who went offline mid-transfer gets nothing for this long (unless heard from)
Service.SENT_RECENTLY = 600 -- "no player named X" counts as ours when we whispered X within this long

local function aceTransport()
  local AceComm = LibStub and LibStub("AceComm-3.0", true)
  if not AceComm then
    return nil
  end
  local t = {}
  AceComm:Embed(t)
  return {
    Register = function(_, prefix, handler)
      t:RegisterComm(prefix, function(_, msg, distribution, sender)
        handler(msg, distribution, sender)
      end)
    end,
    Send = function(_, prefix, msg, distribution, target)
      t:SendCommMessage(prefix, msg, distribution, target, "BULK")
    end,
  }
end

-- Whispers to players who logged off: every queued chunk of a scan would bounce with "No player named X is currently
-- playing" in our chat. The transport remembers whom we whisper; that message for one of them drops the rest of the
-- queue to them (DropQueued), hides the message (ChatFilter), and pauses whispers to them until they're heard again.
function Service:WrapTransport(raw)
  self.sentTo, self.gone = {}, {}
  return {
    Register = function(_, ...)
      return raw:Register(...)
    end,
    Send = function(_, prefix, msg, distribution, target)
      if distribution == "WHISPER" then
        local k = ns.Trust.Key(target)
        local gone = self.gone[k]
        if gone and GetTime() - gone < Service.GONE_QUIET then
          return -- logged off a moment ago: don't bounce more whispers
        end
        self.sentTo[k] = GetTime()
      end
      return raw:Send(prefix, msg, distribution, target)
    end,
  }
end

-- the player a "No player named X is currently playing" system message names, when we whispered them lately
function Service:NotFoundName(msg)
  local secret = _G.issecretvalue
  if type(msg) ~= "string" or (secret and secret(msg)) or not self.sentTo then
    return nil
  end
  self.notFound = self.notFound
    or ns.Trading.Pattern(_G.ERR_CHAT_PLAYER_NOT_FOUND_S, "No player named '%s' is currently playing.")
  local name = msg:match(self.notFound)
  local k = name and ns.Trust.Key(name)
  local sent = k and self.sentTo[k]
  if sent and GetTime() - sent < Service.SENT_RECENTLY then
    return name, k
  end
end

-- the system message, once (CHAT_MSG_SYSTEM): stop sending to that player
function Service:OnSystemMessage(msg)
  local name, k = self:NotFoundName(msg)
  if not name then
    return false
  end
  self.gone[k] = GetTime()
  self.stats.syncGone = (self.stats.syncGone or 0) + 1
  Service.DropQueued(_G.ChatThrottleLib, Service.PREFIX, k)
  return true
end

-- chat filter (runs once per chat frame): hide the bounce when it's about a player we were whispering
function Service:ChatFilter(msg)
  return self:NotFoundName(msg) ~= nil
end

-- Neutralise the whispers still queued to a player in ChatThrottleLib: they drain at once without being sent (the
-- queue is shared by all of AME's sync traffic, so removing them would be unsafe; a no-op send counts as sent).
local function noop() end
function Service.DropQueued(ctl, prefix, key)
  local dropped = 0
  for _, prio in pairs(ctl and ctl.Prio or {}) do
    local pipe = prio.ByName and prio.ByName[prefix]
    for _, m in ipairs(pipe or {}) do
      if m[3] == "WHISPER" and ns.Trust.Key(m[4]) == key and m.f ~= noop then
        m.f, m.nSize = noop, 1
        dropped = dropped + 1
      end
    end
  end
  return dropped
end

function Service:Init(AME, transport)
  self.AME = AME
  self.transport = transport or aceTransport()
  if self.transport then
    self.transport = self:WrapTransport(self.transport)
  end
  self.requested = {}
  self.requestedFrom = {}
  self.stats = AME_DB.stats
  AME_DB.sync = AME_DB.sync or {}
  self.trust = ns.Trust.New(AME_DB.sync)
  self:RefreshGuildBlocklist()
  if not self.transport then
    return false
  end
  self.transport:Register(Service.PREFIX, function(msg, distribution, sender)
    local ok, err = pcall(self.OnMessage, self, msg, distribution, sender)
    if not ok then
      self.stats.syncErrors = (self.stats.syncErrors or 0) + 1
      self.stats.lastSyncError = tostring(err)
    end
  end)
  self.enabled = true
  self:InitV2()
  return true
end

function Service:GuildActive()
  return self.enabled and ns.Settings:Get("syncGuild") and IsInGuild and IsInGuild()
end

function Service:TrustActive()
  return self.enabled and ns.Settings:Get("syncTrusted")
end

function Service:Active()
  return self:GuildActive() or self:TrustActive()
end

local function friendOnline(name)
  if not (C_FriendList and C_FriendList.GetFriendInfo) then
    return false
  end
  local ok, info = pcall(C_FriendList.GetFriendInfo, name)
  return ok and info and info.connected or false
end

-- add a trusted player and ask them to trust us back
function Service:AddTrusted(name)
  if self:IsMine(name) then
    return nil, ns.L["That's one of your characters: they already share AME's data"]
  end
  local e, why = self.trust:Add(name, GetServerTime())
  if e and self.enabled then
    self.transport:Send(Service.PREFIX, Sync.EncodeHello(self.AME:CurrentShard()), "WHISPER", e.name)
  end
  return e, why
end

function Service:Approve(name)
  local e = self.trust:Approve(name, GetServerTime())
  if e and self.enabled then
    self.transport:Send(Service.PREFIX, Sync.EncodeAccept(self.AME:CurrentShard()), "WHISPER", e.name)
    self:Announce()
  end
  return e
end

function Service:Decline(name)
  self.trust:Decline(name, GetServerTime())
end

function Service:RemoveTrusted(name)
  self.trust:Remove(name)
end

function Service:Block(name)
  if self:IsMine(name) then
    return nil
  end
  return self.trust:Block(name, GetServerTime())
end

function Service:Unblock(name)
  self.trust:Unblock(name)
end

-- The game blocks reading the guild information in combat and in instances (ADDON_ACTION_BLOCKED): wait for later.
local function guildInfoBlocked()
  if InCombatLockdown and InCombatLockdown() then
    return true
  end
  local inInstance, kind = false, nil
  if _G.IsInInstance then
    inInstance, kind = _G.IsInInstance()
  end
  return inInstance and kind ~= "none" or false
end

Service.GUILD_INFO_EVERY = 60 -- seconds between re-reads on roster updates (they fire whenever anyone logs on or off)

-- re-read the officers' blocklist from the guild information text; while the game won't allow it, once it does
-- (RetryGuildBlocklist, on leaving combat or an instance)
function Service:RefreshGuildBlocklist()
  if guildInfoBlocked() then
    self.guildInfoPending = true
    return
  end
  self.guildInfoPending = nil
  self.guildInfoAt = GetTime and GetTime() or 0
  local text = IsInGuild and IsInGuild() and GetGuildInfoText and GetGuildInfoText() or nil
  self.trust:SetGuildBlocklist(Sync.ParseBlocklist(text))
  self:Changed()
end

-- a guild roster update: re-read at most once a GUILD_INFO_EVERY; one inside it is done when it's up
function Service:GuildRosterChanged()
  local now = GetTime and GetTime() or 0
  local wait = self.guildInfoAt and self.guildInfoAt + Service.GUILD_INFO_EVERY - now or 0
  if wait <= 0 then
    self:RefreshGuildBlocklist()
  elseif not self.guildInfoTimer and C_Timer then
    self.guildInfoTimer = true
    C_Timer.After(wait, function()
      self.guildInfoTimer = nil
      self:RefreshGuildBlocklist()
    end)
  end
end

-- left combat or an instance: a re-read that had to wait
function Service:RetryGuildBlocklist()
  if self.guildInfoPending and self.trust then
    self:RefreshGuildBlocklist()
  end
end

function Service:Changed()
  if self.onChange then
    self.onChange()
  end
end

-- a sender's character name: senders come as "Name", "Name-Realm", or (WoW Forever) "Name Suffix"
local function charName(sender)
  return type(sender) == "string" and sender:match("^%s*([^%-%s]+)") or nil
end
Service.CharName = charName

local function isMe(sender)
  local me, name = UnitName("player"), charName(sender)
  return me ~= nil and name ~= nil and name:lower() == me:lower()
end

-- one of my characters: this one, or another on this account (AME_DB.holdings: they share AME's saved data, so
-- there's nothing to swap with them, nor to block)
function Service:IsMine(name)
  if type(name) ~= "string" or name == "" then
    return false
  end
  if isMe(name) then
    return true
  end
  local short = charName(name):lower()
  for key in pairs(AME_DB and AME_DB.holdings or {}) do
    local char = key:match(":([^:]+)$")
    if char and char:lower() == short then
      return true
    end
  end
  return false
end

-- Announce the full scans we hold (our own and relayed ones) for every auction house of our market - faction AHs
-- and the goblin AH - so scans reach players who weren't online when they were made.
-- trusted players online who trust us back (they get whispers; guild members the guild broadcast)
function Service:TrustedTargets()
  local targets = {}
  if self:TrustActive() then
    for _, name in ipairs(self.trust:OnlineTargets(GetServerTime(), friendOnline)) do
      local e = self.trust.db.trusted[ns.Trust.Key(name)]
      if e and e.mutual then
        targets[#targets + 1] = name
      end
    end
  end
  return targets
end

Service.SYNC_NOW_EVERY = 60 -- seconds between Sync now clicks
Service.ANSWER_EVERY = 30 -- seconds between answers to Sync now queries (one click reaches the whole guild)

-- Sync now (Settings, Sharing): announce what we hold, and ask guild members and trusted players to announce what
-- they hold, so missing scans are fetched now instead of within the next ANNOUNCE_EVERY. Returns ok, or nil and why.
function Service:SyncNow()
  if not self:Active() then
    return nil, L["Sync is off: turn on guild or trusted sharing below"]
  end
  local t = GetServerTime()
  if self.syncNowAt and t - self.syncNowAt < Service.SYNC_NOW_EVERY then
    return nil, L["Just synced - try again in %d s"]:format(Service.SYNC_NOW_EVERY - (t - self.syncNowAt))
  end
  self.syncNowAt = t
  local shard = self.AME:CurrentShard()
  local msg = Sync.EncodeQuery(shard)
  if self:GuildActive() then
    self.transport:Send(Service.PREFIX, msg, "GUILD")
  end
  for _, name in ipairs(self:TrustedTargets()) do
    self.transport:Send(Service.PREFIX, msg, "WHISPER", name)
  end
  self.outcomesAt = nil -- our auction outcomes go out too
  self:Announce()
  return true
end

function Service:Announce()
  if not self:Active() or not self.AME:LoadHistory() then
    return
  end
  local realm = self.AME:MarketRealmName()
  local targets = self:TrustedTargets()
  local any = false
  -- on v2 the guild hears the v2 manifest; v1 announcements only while a v1-only player is around
  local v1Guild = self:GuildActive() and (not self.v2 or self:V1Around())
  for shard, data in pairs(self.AME.history.shards) do
    if ns.SplitShard(shard) == realm then
      local inventory = Sync.Inventory(data.raw or {}, Sync.MAX_ANNOUNCE)
      if #inventory > 0 then
        local msg = Sync.EncodeAnnounce(shard, inventory)
        if v1Guild then
          self.transport:Send(Service.PREFIX, msg, "GUILD")
        end
        for _, name in ipairs(targets) do
          self.transport:Send(Service.PREFIX, msg, "WHISPER", name)
        end
        any = true
      end
    end
  end
  if any then
    self.stats.syncAnnounced = (self.stats.syncAnnounced or 0) + 1
  end
  if self.v2 and self:GuildActive() then
    self.v2:Announce()
  end
  self:ShareWatchlists()
  self:ShareOutcomes(targets)
end

Service.SHARE_OUTCOMES_EVERY = 3600 -- seconds: your auction outcomes go out at most this often unless they changed

-- Your auction outcomes per item (sold / expired / cancelled, and what they taught your posting model), for every
-- auction house of your market: guildmates' sell-through and posting advice learn from everyone's listings.
-- targets: trusted players to whisper (guild members get the guild broadcast).
function Service:ShareOutcomes(targets)
  local posting = ns.Posting
  if not (posting and AME_DB.sellThrough) then
    return
  end
  local t = GetServerTime()
  if not posting.stChanged and self.outcomesAt and t - self.outcomesAt < Service.SHARE_OUTCOMES_EVERY then
    return
  end
  self.outcomesAt, posting.stChanged = t, false
  local realm = self.AME:MarketRealmName()
  for shard in pairs(AME_DB.sellThrough) do
    if ns.SplitShard(shard) == realm then
      local entries = posting:ShareEntries(shard)
      if #entries > 0 then
        local msg = Sync.EncodeOutcomes(shard, t, ns.SellThrough.EncodeItems(entries))
        if self:GuildActive() then
          self.transport:Send(Service.PREFIX, msg, "GUILD")
        end
        for _, name in ipairs(targets or {}) do
          self.transport:Send(Service.PREFIX, msg, "WHISPER", name)
        end
      end
    end
  end
end

-- a shared list changed: send soon (several quick changes go out once). removed: watchlist names no longer
-- shared; removedShopping: shopping list names no longer shared (they go out empty once)
function Service:QueueShare(removed, removedShopping)
  for _, name in ipairs(removed or {}) do
    self.pendingRemoved = self.pendingRemoved or {}
    self.pendingRemoved[#self.pendingRemoved + 1] = name
  end
  for _, name in ipairs(removedShopping or {}) do
    self.pendingRemovedShop = self.pendingRemovedShop or {}
    self.pendingRemovedShop[#self.pendingRemovedShop + 1] = name
  end
  if self.sharePending then
    return
  end
  self.sharePending = true
  C_Timer.After(3, function()
    self.sharePending = false
    local gone, goneShop = self.pendingRemoved, self.pendingRemovedShop
    self.pendingRemoved, self.pendingRemovedShop = nil, nil
    self:ShareWatchlists(gone, goneShop)
  end)
end

-- Send your shared watchlists and shopping lists to the guild; unshared/deleted names go out empty once so others
-- drop them.
function Service:ShareWatchlists(removed, removedShopping)
  if not self:GuildActive() or not self.AME.watch then
    return
  end
  local shard, t = self.AME:CurrentShard(), GetServerTime()
  for _, l in ipairs(self.AME.watch:SharedLists()) do
    self.transport:Send(Service.PREFIX, Sync.EncodeWatchlist(shard, l.name, t, l.ids), "GUILD")
  end
  for _, name in ipairs(removed or {}) do
    self.transport:Send(Service.PREFIX, Sync.EncodeWatchlist(shard, name, t, {}), "GUILD")
  end
  local shopping = self.AME.shopping
  for _, l in ipairs(shopping and shopping:SharedLists() or {}) do
    self.transport:Send(Service.PREFIX, Sync.EncodeShoppingList(shard, l.name, t, l.entries), "GUILD")
  end
  for _, name in ipairs(removedShopping or {}) do
    self.transport:Send(Service.PREFIX, Sync.EncodeShoppingList(shard, name, t, {}), "GUILD")
  end
end

local function sameRealm(shard)
  return shard and ns.SplitShard(shard) == ns.SyncService.AME:MarketRealmName()
end

-- Is a message over this channel from this sender acceptable?
--   GUILD: guild sync on.  WHISPER: hello/accept always (they only create requests), requests from anyone we'd
--   serve (guild members answer our guild announcements), announcements from trusted players, scans only when we
--   asked that sender for them.
function Service:Allowed(m, distribution, sender)
  if distribution == "GUILD" then
    return self:GuildActive()
  end
  if m.type == "hello" or m.type == "accept" then
    return self.enabled
  end
  if m.type == "watchlist" or m.type == "shopping" then
    return false -- guild only (handled above)
  end
  local trusted = self:TrustActive() and self.trust:IsTrusted(sender)
  if m.type == "request" then
    return trusted or self:GuildActive()
  elseif m.type == "announce" or m.type == "outcomes" or m.type == "query" then
    return trusted
  elseif m.type == "scan" then
    return trusted or self.requestedFrom[ns.Trust.Key(sender) .. ":" .. m.shard .. ":" .. m.t .. ":" .. m.src]
  end
  return false
end

function Service:OnMessage(msg, distribution, sender)
  if self:IsMine(sender) or not self:Active() then
    return
  end
  if self.gone then
    self.gone[ns.Trust.Key(sender)] = nil -- heard from: back online
  end
  local m = Sync.Decode(msg)
  if not m or not sameRealm(m.shard) or not self:Allowed(m, distribution, sender) then
    return
  end
  -- blocked players: by me, or by the guild officers (guild info text); scans relayed from them too
  if self.trust:IsBlocked(sender) or (m.src and self.trust:IsBlocked(m.src)) then
    self.stats.syncBlocked = (self.stats.syncBlocked or 0) + 1
    return
  end
  self.trust:Heard(sender, GetServerTime(), distribution)
  if m.type == "watchlist" then
    if self.AME.watch and self.AME.watch:SetGuildList(sender, m.name, m.t, m.ids) then
      self:Changed()
      if ns.UI and ns.UI.WatchChanged then
        ns.UI:WatchChanged()
      end
    end
    return
  end
  if m.type == "shopping" then
    if self.AME.shopping and self.AME.shopping:SetGuildList(sender, m.name, m.t, m.entries) then
      self:Changed()
      if ns.UI and ns.UI.WatchChanged then
        ns.UI:WatchChanged()
      end
    end
    return
  end
  if m.type == "query" then
    -- someone pressed Sync now: announce what we hold (once for several askers)
    local t = GetServerTime()
    if not self.answeredAt or t - self.answeredAt >= Service.ANSWER_EVERY then
      self.answeredAt = t
      self.outcomesAt = nil
      self:Announce()
    end
    return
  end
  if m.type == "outcomes" then
    if ns.Posting and ns.Posting:SetPeer(m.shard, sender, m.t, m.items) then
      self.stats.syncOutcomes = (self.stats.syncOutcomes or 0) + 1
    end
    return
  end
  if m.type == "hello" then
    if self.trust:IsTrusted(sender) then
      -- we already trust them: they trust us now too
      self.trust:MarkMutual(sender)
      self.transport:Send(Service.PREFIX, Sync.EncodeAccept(m.shard), "WHISPER", sender)
    elseif self.trust:Request(sender, GetServerTime()) then
      self.AME.Say(
        L["%s wants to share auction prices with you. Type |cffffffff/ame config|r and open Sharing to approve."],
        sender
      )
    end
    self:Changed()
    return
  elseif m.type == "accept" then
    self.trust:MarkMutual(sender)
    self:Changed()
    return
  end
  if not self.AME:LoadHistory() then
    return
  end
  local data = self.AME.history.shards[m.shard]

  if m.type == "announce" then
    if distribution == "GUILD" then
      self:HeardProtocol(sender, 1)
      -- on v2, guild members' scans come over v2; a v1-only player's only this way
      if self.v2 and not self:IsV1Only(sender) then
        return
      end
    end
    local want = Sync.Wanted(m, m.shard, data and data.raw or {}, GetServerTime(), Sync.WINDOW)
    local sent = 0
    for _, s in ipairs(want) do
      local key = m.shard .. ":" .. s.t .. ":" .. s.src
      local last = self.requested[key]
      if self.trust:IsBlocked(s.src) then
        self.stats.syncBlocked = (self.stats.syncBlocked or 0) + 1
      elseif not last or GetServerTime() - last > Service.REQUEST_COOLDOWN then
        self.requested[key] = GetServerTime()
        self.requestedFrom[ns.Trust.Key(sender) .. ":" .. key] = true
        self.transport:Send(Service.PREFIX, Sync.EncodeRequest(m.shard, s.t, s.src), "WHISPER", sender)
        sent = sent + 1
        if sent >= Service.MAX_REQUESTS_PER_ANNOUNCE then
          break
        end
      end
    end
  elseif m.type == "request" then
    for _, e in ipairs(data and data.raw or {}) do
      if e.t == m.t and (e.src or ""):gsub("[|;:]", "") == m.src and (e.k or "full") == "full" then
        self.transport:Send(Service.PREFIX, Sync.EncodeScan(m.shard, e), "WHISPER", sender)
        self.stats.syncServed = (self.stats.syncServed or 0) + 1
        break
      end
    end
  elseif m.type == "scan" then
    self:Merge(m, sender)
  end
end

-- A received scan: decoded, checked and stored in a background job (decoding a full scan takes ~60 ms - not in the
-- chat event). The packed payload is the sender's stored string, so it's stored as is, not packed again.
function Service:Merge(m, sender)
  local AME = self.AME
  local snap
  AME:WithStore("sync-merge", m.shard, function(store)
    local ok, decoded = ns.Try(function()
      -- in pieces, pausing between them: a full scan is ~450 KB of text
      local pause = store:pauser()
      if m.wire then -- sync v2: as it travelled (Compress Wire) - stored as the packed string inside it
        m.packed = assert(AME.compressor:Unwire(m.wire, pause))
      end
      return ns.Codec.DecodeSnapshot(ns.Codec.Unpack(m.packed, AME.compressor, pause), pause)
    end)
    if not ok or not decoded then
      return { rejected = "undecodable" }
    end
    snap = decoded
    store.yield()
    -- compare with our own prices for that same auction house (goblin AH scans against goblin AH prices)
    local ref = AME:CachedIndex(m.shard)
    local plausible, why = Sync.Plausible(snap, ref and ref.items or {})
    if not plausible then
      return { rejected = why }
    end
    return { added = store:AddScan(snap, m.t, m.src, m.kind == "partial" and "partial" or "full", m.packed) }
  end, function(done, result)
    self:Received(m.shard, sender, done, result, snap and { src = m.src, items = #snap.ids })
  end)
end

-- start periodic announcements (call after login)
function Service:Start()
  if not self.enabled then
    return
  end
  local function loop()
    self:Announce()
    C_Timer.After(Service.ANNOUNCE_EVERY, loop)
  end
  C_Timer.After(30, loop)
end
