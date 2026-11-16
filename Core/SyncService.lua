-- Guild sync glue: announces our full scans, requests ones we lack, serves requests, merges received scans.
-- Transport is injectable (default: AceComm-3.0 at BULK priority via ChatThrottleLib).
local _, ns = ...

local Sync = ns.Sync

local Service = {}
ns.SyncService = Service

Service.PREFIX = "AME1"
Service.ANNOUNCE_EVERY = 600 -- seconds
Service.REQUEST_COOLDOWN = 600
Service.MAX_REQUESTS_PER_ANNOUNCE = 2

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
  self.stats = AME_DB.stats
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

function Service:Active()
  return self.enabled and ns.Settings:Get("syncGuild") and IsInGuild and IsInGuild()
end

local function isMe(sender)
  local me = UnitName("player")
  return sender == me or (me and sender and sender:sub(1, #me + 1) == me .. "-")
end

function Service:Announce()
  if not self:Active() or not self.AME:LoadHistory() then
    return
  end
  local shard = self.AME:CurrentShard()
  local data = self.AME.history.shards[shard]
  local inventory = data and Sync.Inventory(data.raw or {}, Sync.MAX_ANNOUNCE) or {}
  if #inventory == 0 then
    return
  end
  self.transport:Send(Service.PREFIX, Sync.EncodeAnnounce(shard, inventory), "GUILD")
  self.stats.syncAnnounced = (self.stats.syncAnnounced or 0) + 1
end

local function sameRealm(shard)
  return shard and shard:match("^(.-)|") == GetNormalizedRealmName()
end

function Service:OnMessage(msg, _, sender)
  if isMe(sender) or not self:Active() then
    return
  end
  local m = Sync.Decode(msg)
  if not m or not sameRealm(m.shard) then
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
      if not last or GetServerTime() - last > Service.REQUEST_COOLDOWN then
        self.requested[key] = GetServerTime()
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
      if ns.Settings:Get("announceScans") then
        AME.Say("received a full scan from %s via guild sync (%d items, %s)", m.src, #snap.ids, m.shard)
      end
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
