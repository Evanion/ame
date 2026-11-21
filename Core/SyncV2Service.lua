-- Sync v2 in game: the engine (Core/SyncV2.lua) on the guild channel under its own prefix, fed by AME's history.
-- docs/plans/sync-v2.md.
--
-- The "Sync protocol" setting (Settings, Sharing) picks v2 (default) or v1 (lighter: v2 traffic isn't even
-- delivered, as the prefix isn't registered). v2 replaces v1's scan announcements and transfers among guild members;
-- everything else (outcomes, lists, Sync now queries, trust) stays on v1's prefix. v2 players keep serving v1
-- players: they answer v1 requests, and announce over v1 while a v1-only player has been heard in the last 3 days.
-- Trusted players outside the guild can't hear the guild channel: they keep getting v1 whispers.
local _, ns = ...
local L = ns.L

local Service = ns.SyncService
local V2 = ns.SyncV2
local Sync = ns.Sync

local floor = math.floor
local DAY, HOUR = 86400, 3600

Service.V1_AROUND = 3 * DAY -- a v1-only player heard this recently: v2 players announce over v1 too
Service.PROTO_FORGET = 14 * DAY
Service.PARTIAL_KEEP = 3600 -- incoming v2 objects saved at logout resume within this long

function Service:Protocol()
  return ns.Settings:Get("syncProtocol") == 1 and 1 or 2
end

-- my name as the engine compares names: the character name, lower-case (senders come as "Name", "Name-Realm" or
-- "First Last")
local function nameKey(name)
  local c = Service.CharName(name)
  return c and c:lower() or ""
end

-- Blocks are raw bytes (any but NUL); SavedVariables get them print-safe (LibDeflate EncodeForPrint).
local function deflate()
  return LibStub and LibStub("LibDeflate", true)
end

local function mapBlocks(items, fn)
  for _, item in ipairs(items) do
    local out = {}
    for i, b in pairs(type(item.blocks) == "table" and item.blocks or {}) do
      out[i] = type(b) == "string" and fn(b) or nil
    end
    item.blocks = out
  end
  return items
end

function Service:InitV2()
  self.v2 = nil
  if not self.transport or self:Protocol() ~= 2 then
    return false
  end
  self.v2 = V2.New({
    name = UnitName("player") or "?",
    nameKey = nameKey,
    send = function(msg)
      if self:GuildActive() then
        self.transport:Send(V2.PREFIX, msg, "GUILD")
      end
    end,
    now = GetTime,
    after = function(seconds, fn)
      C_Timer.After(seconds, fn)
    end,
    random = math.random,
    host = self:V2Host(),
  })
  self.transport:Register(V2.PREFIX, function(msg, distribution, sender)
    local ok, err = pcall(self.OnV2Message, self, msg, distribution, sender)
    if not ok then
      self.stats.syncErrors = (self.stats.syncErrors or 0) + 1
      self.stats.lastSyncError = tostring(err)
    end
  end)
  local saved = AME_DB.sync.v2Partial
  AME_DB.sync.v2Partial = nil
  if saved and saved.at and GetServerTime() - saved.at < Service.PARTIAL_KEEP then
    local lib = deflate()
    if lib and type(saved.items) == "table" then
      self.v2:Restore(mapBlocks(saved.items, function(b)
        return lib:DecodeForPrint(b)
      end))
    end
  end
  return true
end

function Service:OnV2Message(msg, distribution, sender)
  -- guild only; on v1 (switched since login) it's ignored until /reload stops its delivery
  if distribution ~= "GUILD" or not self.v2 or self:Protocol() ~= 2 or not self:GuildActive() then
    return
  end
  if self:IsMine(sender) then
    return
  end
  if self.gone then
    self.gone[ns.Trust.Key(sender)] = nil
  end
  self:HeardProtocol(sender, 2)
  if self.trust:IsBlocked(sender) then
    return
  end
  self.trust:Heard(sender, GetServerTime(), "GUILD")
  self.v2:OnMessage(msg, sender)
end

-- incoming objects, kept for a /reload (PLAYER_LOGOUT)
function Service:SaveV2()
  local lib = deflate()
  if self.v2 and lib then
    local items = mapBlocks(self.v2:Save(), function(b)
      return lib:EncodeForPrint(b)
    end)
    AME_DB.sync.v2Partial = #items > 0 and { at = GetServerTime(), items = items } or nil
  end
end

-- a fresh full scan of mine: to the guild right away
function Service:PushScan(shard, t)
  if self.v2 and self:GuildActive() then
    self.v2:Push(shard, "s", t)
  end
end

---------------------------------------------------------------------------------------------------------------------
-- who speaks what

function Service:HeardProtocol(sender, v)
  local proto = AME_DB.sync.proto or {}
  AME_DB.sync.proto = proto
  local k = ns.Trust.Key(sender)
  proto[k] = proto[k] or {}
  proto[k][v] = GetServerTime()
end

-- which protocol a player was last heard on: 2, 1, or nil (not heard since AME started telling them apart)
function Service:ProtocolOf(sender)
  local p = AME_DB.sync and AME_DB.sync.proto and AME_DB.sync.proto[ns.Trust.Key(sender)]
  if not p then
    return nil
  end
  return self:IsV1Only(sender) and 1 or (p[2] and 2) or (p[1] and 1) or nil
end

-- a player heard over v1 and not over v2 around then (a v2 player announcing over v1 sends v2 manifests too)
function Service:IsV1Only(sender)
  local p = AME_DB.sync.proto and AME_DB.sync.proto[ns.Trust.Key(sender)]
  return p ~= nil and p[1] ~= nil and (p[2] == nil or p[2] < p[1] - HOUR)
end

function Service:V1Around()
  local now = GetServerTime()
  local around = false
  for k, p in pairs(AME_DB.sync.proto or {}) do
    local last = math.max(p[1] or 0, p[2] or 0)
    if now - last > Service.PROTO_FORGET then
      AME_DB.sync.proto[k] = nil
    elseif p[1] and now - p[1] < Service.V1_AROUND and (p[2] == nil or p[2] < p[1] - HOUR) then
      around = true
    end
  end
  return around
end

---------------------------------------------------------------------------------------------------------------------
-- the data side

local function newestFull(data)
  local best = 0
  for _, e in ipairs(data and data.raw or {}) do
    if (e.k or "full") == "full" and e.t > best then
      best = e.t
    end
  end
  return best
end

local function rawFull(data, t)
  for _, e in ipairs(data and data.raw or {}) do
    if e.t == t and (e.k or "full") == "full" then
      return e
    end
  end
end

function Service:V2Host()
  local svc, AME = self, self.AME
  local host = {}

  local function data(shard)
    return AME:LoadHistory() and AME.history.shards[shard] or nil
  end

  function host.Allowed(_, shard, sender)
    return shard ~= nil and ns.SplitShard(shard) == AME:MarketRealmName() and not svc.trust:IsBlocked(sender)
  end

  function host.Shards()
    local out = {}
    if AME:LoadHistory() then
      local realm = AME:MarketRealmName()
      for shard in pairs(AME.history.shards) do
        if ns.SplitShard(shard) == realm then
          out[#out + 1] = shard
        end
      end
      table.sort(out)
    end
    return out
  end

  function host.Manifest(_, shard)
    local d = data(shard)
    if not d then
      return nil
    end
    local now = GetServerTime()
    local hour0, today = floor(now / HOUR), floor(now / DAY)
    local m = { scanT = 0, hour0 = hour0, hours = {}, day0 = today - 1, days = {} }
    local newest = newestFull(d)
    if newest >= now - Sync.WINDOW then
      m.scanT = newest
    end
    local any = m.scanT > 0
    for hour in pairs(d.hours or {}) do
      if hour <= hour0 and hour > hour0 - V2.HOURS then
        m.hours[hour], any = true, true
      end
    end
    for day in pairs(d.days or {}) do
      if day < today and day >= today - V2.DAYS then
        m.days[day], any = true, true
      end
    end
    return any and m or nil
  end

  function host.Has(_, shard, kind, ref)
    local d = data(shard)
    if not d then
      return false
    end
    if kind == "s" then
      return rawFull(d, ref) ~= nil
    elseif kind == "h" then
      return d.hours and d.hours[ref] ~= nil or false
    elseif kind == "d" then
      return d.days[ref] ~= nil and ref < floor(GetServerTime() / DAY)
    end
    return false
  end

  local function wanted(d, kind, ref, now)
    if kind == "s" then
      return ref >= now - Sync.WINDOW and ref <= now + 600 and ref > newestFull(d)
    elseif kind == "h" then
      local hour0 = floor(now / HOUR)
      return ref <= hour0 and ref > hour0 - V2.HOURS and not (d and d.hours and d.hours[ref])
    elseif kind == "d" then
      local today = floor(now / DAY)
      local seen = d and d.seen[ref]
      return ref < today and ref >= today - V2.DAYS and not (d and d.days[ref]) and not (seen and next(seen))
    end
    return false
  end

  function host.Wanted(_, shard, kind, ref)
    if not AME:LoadHistory() then
      return false
    end
    return wanted(AME.history.shards[shard], kind, ref, GetServerTime())
  end

  -- what to ask a manifest's sender's guild for, most useful first: their newest full scan when it's newer than
  -- mine, missing hours of the last 2 days, days I have nothing of, then older hours
  function host.Wants(_, shard, m)
    if not AME:LoadHistory() then
      return {}
    end
    local d, now = AME.history.shards[shard], GetServerTime()
    local out = {}
    if m.scanT and m.scanT > 0 and wanted(d, "s", m.scanT, now) then
      out[#out + 1] = { kind = "s", ref = m.scanT }
    end
    local recent, older, days = {}, {}, {}
    for hour in pairs(m.hours) do
      if wanted(d, "h", hour, now) then
        local list = hour * HOUR >= now - 2 * DAY and recent or older
        list[#list + 1] = hour
      end
    end
    for day in pairs(m.days) do
      if wanted(d, "d", day, now) then
        days[#days + 1] = day
      end
    end
    local function desc(a, b)
      return a > b
    end
    table.sort(recent, desc)
    table.sort(older, desc)
    table.sort(days, desc)
    for _, h in ipairs(recent) do
      out[#out + 1] = { kind = "h", ref = h }
    end
    for _, day in ipairs(days) do
      out[#out + 1] = { kind = "d", ref = day }
    end
    for _, h in ipairs(older) do
      -- an hour inside a day being asked for whole comes with it
      if not m.days[floor(h * HOUR / DAY)] or not wanted(d, "d", floor(h * HOUR / DAY), now) then
        out[#out + 1] = { kind = "h", ref = h }
      end
    end
    return out
  end

  -- the object ready to send (built in a background job: compressing for the wire takes a moment)
  function host.Object(_, shard, kind, ref, done)
    AME:WithStore("sync2-object-" .. kind .. ref, shard, function(store)
      local d = store.data
      local text, t, src, key
      if kind == "s" then
        local e = rawFull(d, ref)
        if e then
          text, t, src = e.s, e.t, e.src
        end
      elseif kind == "h" then
        local e = d.hours and d.hours[ref]
        if e then
          text, t, src, key = e.s, e.t, e.src, e.key
        end
      elseif kind == "d" then
        text, t = store:ExportDay(ref), ref * DAY
      end
      if not text then
        return nil
      end
      return {
        kind = kind,
        ref = ref,
        t = t,
        src = src,
        key = key,
        payload = AME.compressor:Wire(text, store:pauser()),
      }
    end, function(ok, obj)
      done(ok and obj or nil)
    end)
  end

  host.verifiesSum = true -- AcceptV2 checks the checksum in a background job
  function host.Accept(_, shard, obj, sender)
    svc:AcceptV2(shard, obj, sender)
  end

  return host
end

-- a whole object received: checked against our prices and stored in a background job
function Service:AcceptV2(shard, obj, sender)
  if obj.src and obj.src ~= "" and self.trust:IsBlocked(obj.src) then
    self.stats.syncBlocked = (self.stats.syncBlocked or 0) + 1
    return
  end
  local AME = self.AME
  -- first the checksum, in the background (it waits out combat like the rest)
  if obj.sum then
    local sum = obj.sum
    obj.sum = nil
    AME.jobs:Add("sync2-verify", function(job)
      return ns.SyncV2.Checksum(obj.payload, function()
        job:Checkpoint()
      end) == sum
    end, function(ok, good)
      if ok and good then
        self:AcceptV2(shard, obj, sender)
      else
        self.stats.syncRejected = (self.stats.syncRejected or 0) + 1
        self:CountRejection(ok and "checksum" or "checksum error")
        if self.v2 then
          self.v2.stats.bad = self.v2.stats.bad + 1
        end
      end
    end)
    return
  end
  if obj.kind == "s" then
    return self:Merge({ shard = shard, t = obj.t, src = obj.src, kind = "full", wire = obj.payload }, sender)
  end
  AME:WithStore("sync2-merge", shard, function(store)
    local pause = store:pauser()
    local ok, text = ns.Try(AME.compressor.Unwire, AME.compressor, obj.payload, pause)
    if not ok or not text then
      return { rejected = "undecodable" }
    end
    local ref = AME:CachedIndex(shard)
    local prices, add
    if obj.kind == "h" then
      local decoded, point = ns.Try(function()
        return ns.Codec.Decode(ns.Codec.HOUR_FIELDS, ns.Codec.Unpack(text, AME.compressor, pause), true, pause)
      end)
      if not decoded then
        return { rejected = "undecodable" }
      end
      prices = point
      add = function()
        return store:AddHourPoint(obj.t, obj.src, obj.key, text, point)
      end
    elseif obj.kind == "d" then
      local buckets, seen = ns.Store.ParseDay(text)
      if not buckets then
        return { rejected = "undecodable" }
      end
      local decoded, dayPrices = ns.Try(store.DayPrices, store, buckets)
      if not decoded then
        return { rejected = "undecodable" }
      end
      prices = dayPrices
      add = function()
        return store:ImportWholeDay(obj.ref, buckets, seen)
      end
    else
      return { rejected = "unknown" }
    end
    local plausible, why = Sync.Plausible(prices, ref and ref.items or {})
    if not plausible then
      return { rejected = why }
    end
    return { added = add() }
  end, function(done, result)
    self:Received(shard, sender, done, result)
  end)
end

-- why received things were turned down, counted by reason (stats.rejectedWhy) - "undecodable" too, which the last
-- rejection line leaves out
function Service:CountRejection(why)
  local by = self.stats.rejectedWhy or {}
  self.stats.rejectedWhy = by
  why = tostring(why)
  by[why] = (by[why] or 0) + 1
end

-- after merging something received (v1 scan, v2 object): stats, and the market index catches up
function Service:Received(shard, sender, done, result, scanned)
  local AME = self.AME
  local why = done and result and result.rejected
  if why then
    self.stats.syncRejected = (self.stats.syncRejected or 0) + 1
    self:CountRejection(why)
    if why ~= "undecodable" then
      self.stats.lastSyncRejection = ("%s: %s"):format(tostring(sender), tostring(why))
    end
    return
  end
  if not (done and result and result.added) then
    return
  end
  self.stats.syncReceived = (self.stats.syncReceived or 0) + 1
  self.trust:Received(sender)
  if scanned then
    self.stats.lastSyncReceived = { from = sender, at = GetServerTime(), items = scanned.items }
    if ns.Settings:Get("announceScans") then
      AME.Say(
        L["received a full scan from %s via sync (%d items, %s)"],
        scanned.src,
        scanned.items,
        ns.ShardLabel(shard)
      )
    end
  end
  self:Changed()
  if ns.UI and ns.UI.frame and ns.UI.frame:IsShown() then
    ns.UI:RefreshViewOptions()
  end
  if scanned then -- fresh prices: now
    AME:InvalidateIndex(shard)
    if shard == AME:CurrentShard() then
      AME:RebuildIndex()
    end
  else -- hours and days come in runs: once they've been quiet a while
    AME:InvalidateIndexLater(shard)
  end
end

-- for the Sharing status: hours of the last 7 days I hold for the auction house I'm at, and transfers going on
function Service:V2Status()
  if not self.v2 then
    return nil
  end
  local s = self.v2:Status()
  s.hours = 0
  local AME = self.AME
  local d = AME:HistoryLoaded() and AME.history.shards[AME:CurrentShard()]
  local hour0 = floor(GetServerTime() / HOUR)
  for hour in pairs(d and d.hours or {}) do
    if hour > hour0 - V2.HOURS then
      s.hours = s.hours + 1
    end
  end
  return s
end
