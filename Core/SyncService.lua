-- Guild sync glue: announces our full scans, requests ones we lack, serves requests, merges received scans.
-- Transport is injectable (default: AceComm-3.0 at BULK priority via ChatThrottleLib).
local _, ns = ...

local Sync = ns.Sync

local Service = {}
ns.SyncService = Service

Service.PREFIX = "AME1"
Service.ANNOUNCE_EVERY = 600 -- seconds
Service.REQUEST_COOLDOWN = 600
Service.MAX_REQUESTS_PER_ANNOUNCE = 4

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

function Service:Init(AME, transport)
  self.AME = AME
  self.transport = transport or aceTransport()
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
  return self.trust:Block(name, GetServerTime())
end

function Service:Unblock(name)
  self.trust:Unblock(name)
end

-- re-read the officers' blocklist from the guild information text
function Service:RefreshGuildBlocklist()
  local text = IsInGuild and IsInGuild() and GetGuildInfoText and GetGuildInfoText() or nil
  self.trust:SetGuildBlocklist(Sync.ParseBlocklist(text))
  self:Changed()
end

function Service:Changed()
  if self.onChange then
    self.onChange()
  end
end

local function isMe(sender)
  local me = UnitName("player")
  return sender == me or (me and sender and sender:sub(1, #me + 1) == me .. "-")
end

-- Announce the full scans we hold (our own and relayed ones) for every auction house of our market - faction AHs
-- and the goblin AH - so scans reach players who weren't online when they were made.
function Service:Announce()
  if not self:Active() or not self.AME:LoadHistory() then
    return
  end
  local realm = self.AME:MarketRealmName()
  local targets = {}
  if self:TrustActive() then
    for _, name in ipairs(self.trust:OnlineTargets(GetServerTime(), friendOnline)) do
      local e = self.trust.db.trusted[ns.Trust.Key(name)]
      if e and e.mutual then
        targets[#targets + 1] = name
      end
    end
  end
  local any = false
  for shard, data in pairs(self.AME.history.shards) do
    if shard:match("^(.-)|") == realm then
      local inventory = Sync.Inventory(data.raw or {}, Sync.MAX_ANNOUNCE)
      if #inventory > 0 then
        local msg = Sync.EncodeAnnounce(shard, inventory)
        if self:GuildActive() then
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
end

local function sameRealm(shard)
  return shard and shard:match("^(.-)|") == ns.SyncService.AME:MarketRealmName()
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
  local trusted = self:TrustActive() and self.trust:IsTrusted(sender)
  if m.type == "request" then
    return trusted or self:GuildActive()
  elseif m.type == "announce" then
    return trusted
  elseif m.type == "scan" then
    return trusted or self.requestedFrom[ns.Trust.Key(sender) .. ":" .. m.shard .. ":" .. m.t .. ":" .. m.src]
  end
  return false
end

function Service:OnMessage(msg, distribution, sender)
  if isMe(sender) or not self:Active() then
    return
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
  if m.type == "hello" then
    if self.trust:IsTrusted(sender) then
      -- we already trust them: they trust us now too
      self.trust:MarkMutual(sender)
      self.transport:Send(Service.PREFIX, Sync.EncodeAccept(m.shard), "WHISPER", sender)
    elseif self.trust:Request(sender, GetServerTime()) then
      self.AME.Say("%s wants to share auction prices with you. Open |cffffffff/ame|r > Sync to approve.", sender)
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

function Service:Merge(m, sender)
  local AME = self.AME
  local ok, snap = pcall(function()
    return ns.Codec.DecodeSnapshot(ns.Codec.Unpack(m.packed, AME.compressor))
  end)
  if not ok or not snap then
    self.stats.syncRejected = (self.stats.syncRejected or 0) + 1
    return
  end
  local reference = (AME.index and AME.indexShard == m.shard) and AME.index.items or {}
  local plausible, why = Sync.Plausible(snap, reference)
  if not plausible then
    self.stats.syncRejected = (self.stats.syncRejected or 0) + 1
    self.stats.lastSyncRejection = ("%s: %s"):format(tostring(sender), tostring(why))
    return
  end
  AME:WithStore("sync-merge", m.shard, function(store)
    return store:AddScan(snap, m.t, m.src, m.kind == "partial" and "partial" or "full")
  end, function(done, added)
    if done and added then
      self.stats.syncReceived = (self.stats.syncReceived or 0) + 1
      self.trust:Received(sender)
      self.stats.lastSyncReceived = { from = sender, at = GetServerTime(), items = #snap.ids }
      self:Changed()
      if ns.Settings:Get("announceScans") then
        AME.Say("received a full scan from %s via sync (%d items, %s)", m.src, #snap.ids, m.shard)
      end
      AME:InvalidateIndex(m.shard)
      if m.shard == AME:CurrentShard() then
        AME:RebuildIndex()
      end
    end
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
