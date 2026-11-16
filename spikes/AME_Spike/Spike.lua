-- AME M0 spike. Throwaway code: answers the questions in docs/design.md "M0", nothing here is production design.
--
-- 1. Piggyback: when Auctionator (or anyone) calls C_AuctionHouse.ReplicateItems(), we also get
--    REPLICATE_ITEM_LIST_UPDATE. Read the whole replicate list ourselves and measure rows, unique items, timing,
--    rows without full info, bid-only rows.
-- 2. Shard: which house (Alliance/Horde/Neutral) and realm(s) the open AH belongs to.
-- 3. SavedVariables cost: store one columnar snapshot; /amespike stress N multiplies it to measure load time.
-- 4. Comms: /amespike comm <self|guild|party|Name-Realm> [n] measures raw addon-message throughput.
--
-- Every result is printed and appended to AME_SpikeDB.log, which is written to
-- WTF\Account\<ACCOUNT>\SavedVariables\AME_Spike.lua on /reload or logout.

local ADDON = ...
local PREFIX = "AMESPK"
local fileLoadedAt = debugprofilestop()

local db
local state = { house = nil, reading = false }

local function now()
  return debugprofilestop()
end

local function out(fmt, ...)
  local msg = select("#", ...) > 0 and fmt:format(...) or fmt
  print("|cff33ccffAME spike:|r " .. msg)
end

local function log(kind, data)
  data = data or {}
  data.kind = kind
  data.at = GetServerTime()
  db.log[#db.log + 1] = data
end

---------------------------------------------------------------------------------------------------------------------
-- 2. Shard detection

local function shardInfo()
  local info = {
    realm = GetNormalizedRealmName(),
    realmName = GetRealmName(),
    playerFaction = UnitFactionGroup("player"),
    npcFaction = UnitFactionGroup("npc"),
    house = state.house,
    connected = {},
  }
  local ok, realms = pcall(GetAutoCompleteRealms)
  if ok and type(realms) == "table" then
    for i, r in ipairs(realms) do
      info.connected[i] = r
    end
  end
  return info
end

---------------------------------------------------------------------------------------------------------------------
-- 1. Replicate list piggyback

-- GetReplicateItemInfo returns (1-based positions): 3 count, 10 buyoutPrice, 17 itemID, 18 hasAllInfo
local function readReplicate(trigger)
  if state.reading then
    out("replicate read already in progress, ignoring %s", trigger)
    return
  end
  local total = C_AuctionHouse.GetNumReplicateItems()
  if not total or total == 0 then
    out("replicate list is empty (%s)", trigger)
    log("replicate_empty", { trigger = trigger })
    return
  end
  state.reading = true

  local started = now()
  local items = {} -- itemID -> {rows, qty, minUnit}
  local links = {}
  local stats = {
    trigger = trigger,
    total = total,
    unique = 0,
    uniqueLinks = 0,
    notAllInfo = 0,
    bidOnly = 0,
    noItem = 0,
    batches = 0,
    maxBatchMs = 0,
  }
  local BATCH = 1000
  local i = 0

  local function step()
    local batchStart = now()
    local limit = math.min(i + BATCH, total)
    while i < limit do
      local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID, hasAllInfo =
        C_AuctionHouse.GetReplicateItemInfo(i)
      if not itemID then
        stats.noItem = stats.noItem + 1
      else
        if not hasAllInfo then
          stats.notAllInfo = stats.notAllInfo + 1
        end
        count = (count and count > 0) and count or 1
        local e = items[itemID]
        if not e then
          e = { rows = 0, qty = 0, minUnit = nil }
          items[itemID] = e
          stats.unique = stats.unique + 1
        end
        e.rows = e.rows + 1
        e.qty = e.qty + count
        if buyout and buyout > 0 then
          local unit = math.floor(buyout / count)
          if not e.minUnit or unit < e.minUnit then
            e.minUnit = unit
          end
        else
          stats.bidOnly = stats.bidOnly + 1
        end
        local link = C_AuctionHouse.GetReplicateItemLink(i)
        if link and not links[link] then
          links[link] = true
          stats.uniqueLinks = stats.uniqueLinks + 1
        end
      end
      i = i + 1
    end
    stats.batches = stats.batches + 1
    stats.maxBatchMs = math.max(stats.maxBatchMs, now() - batchStart)

    if i < total then
      C_Timer.After(0, step)
      return
    end

    stats.wallMs = math.floor(now() - started)
    stats.maxBatchMs = math.floor(stats.maxBatchMs)
    state.reading = false

    -- columnar snapshot (the shape M1 will use)
    local snap = { t = GetServerTime(), shard = shardInfo(), ids = {}, minUnit = {}, qty = {}, rows = {} }
    local n = 0
    for id, e in pairs(items) do
      n = n + 1
      snap.ids[n], snap.minUnit[n], snap.qty[n], snap.rows[n] = id, e.minUnit or 0, e.qty, e.rows
    end
    db.snapshot = snap

    log("replicate_read", stats)
    out(
      "read %d rows / %d unique itemIDs / %d unique links in %d ms (%d batches, worst %d ms)",
      total,
      stats.unique,
      stats.uniqueLinks,
      stats.wallMs,
      stats.batches,
      stats.maxBatchMs
    )
    out("rows without full info: %d, bid-only: %d, missing itemID: %d", stats.notAllInfo, stats.bidOnly, stats.noItem)
    out(
      "snapshot stored for house %s on %s. /reload to write it to disk.",
      tostring(snap.shard.house),
      tostring(snap.shard.realm)
    )
  end

  step()
end

---------------------------------------------------------------------------------------------------------------------
-- 3. SavedVariables stress

local function stress(n)
  if not db.snapshot then
    out("no snapshot yet; run an Auctionator full scan first")
    return
  end
  db.stress = {}
  for k = 1, n do
    -- copy, so each one is serialized separately (like real daily history would be)
    local s = db.snapshot
    local c = { t = s.t - k * 86400, ids = {}, minUnit = {}, qty = {}, rows = {} }
    for j = 1, #s.ids do
      c.ids[j], c.minUnit[j], c.qty[j], c.rows[j] = s.ids[j], s.minUnit[j], s.qty[j], s.rows[j]
    end
    db.stress[k] = c
  end
  log("stress", { copies = n, itemsPerCopy = #db.snapshot.ids })
  out("stored %d copies of %d items. /reload, then /amespike load to see the load time.", n, #db.snapshot.ids)
end

---------------------------------------------------------------------------------------------------------------------
-- 4. Addon-message throughput

local comm = { recv = nil }

local function sendBurst(target, n)
  local distribution, whisperTarget
  local t = target:lower()
  if t == "self" then
    distribution, whisperTarget = "WHISPER", UnitName("player") .. "-" .. GetNormalizedRealmName()
  elseif t == "guild" then
    distribution = "GUILD"
  elseif t == "party" then
    distribution = "PARTY"
  else
    distribution, whisperTarget = "WHISPER", target
  end
  local pad = string.rep("x", 255)
  local seq, throttled, failed = 0, 0, 0
  local started = now()

  local function pump()
    while seq < n do
      local header = ("%d;%d;"):format(seq, n)
      local msg = header .. pad:sub(1, 255 - #header)
      local r = C_ChatInfo.SendAddonMessage(PREFIX, msg, distribution, whisperTarget)
      if r == Enum.SendAddonMessageResult.AddonMessageThrottle then
        throttled = throttled + 1
        C_Timer.After(0.1, pump)
        return
      elseif r ~= Enum.SendAddonMessageResult.Success then
        failed = failed + 1
      end
      seq = seq + 1
    end
    local ms = now() - started
    local res = {
      distribution = distribution,
      n = n,
      bytes = n * 255,
      ms = math.floor(ms),
      bytesPerSec = math.floor(n * 255 / (ms / 1000)),
      throttleHits = throttled,
      failed = failed,
    }
    log("comm_send", res)
    out(
      "sent %d x 255 B via %s in %.1f s = %d B/s (throttle hits %d, failed %d)",
      n,
      distribution,
      ms / 1000,
      res.bytesPerSec,
      throttled,
      failed
    )
  end
  pump()
end

local function onAddonMessage(prefix, text, channel, sender)
  if prefix ~= PREFIX then
    return
  end
  local seq, n = text:match("^(%d+);(%d+);")
  seq, n = tonumber(seq), tonumber(n)
  if not seq then
    return
  end
  local r = comm.recv
  if not r or r.sender ~= sender or seq == 0 then
    r = { sender = sender, channel = channel, n = n, got = 0, first = now(), seen = {} }
    comm.recv = r
  end
  if not r.seen[seq] then
    r.seen[seq] = true
    r.got = r.got + 1
  end
  r.last = now()
  if seq == n - 1 or r.got == n then
    local ms = math.max(1, r.last - r.first)
    local res = {
      sender = sender,
      channel = channel,
      expected = n,
      got = r.got,
      ms = math.floor(ms),
      bytesPerSec = math.floor(r.got * 255 / (ms / 1000)),
    }
    log("comm_recv", res)
    out("received %d/%d from %s via %s in %.1f s = %d B/s", r.got, n, sender, channel, ms / 1000, res.bytesPerSec)
  end
end

---------------------------------------------------------------------------------------------------------------------
-- Events

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("AUCTION_HOUSE_SHOW")
f:RegisterEvent("AUCTION_HOUSE_CLOSED")
f:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
f:RegisterEvent("CHAT_MSG_ADDON")

f:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then
      return
    end
    AME_SpikeDB = AME_SpikeDB or {}
    db = AME_SpikeDB
    db.log = db.log or {}
    -- time from our file finishing to ADDON_LOADED: dominated by parsing our SavedVariables
    local loadMs = math.floor(now() - fileLoadedAt)
    db.lastLoadMs = loadMs
    log("load", { svParseMsApprox = loadMs, stressCopies = db.stress and #db.stress or 0 })
  elseif event == "PLAYER_LOGIN" then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    if Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.RegisterForDBUpdate then
      Auctionator.API.v1.RegisterForDBUpdate("AME_Spike", function()
        log("auctionator_db_update", {})
        out("Auctionator DB update callback fired")
      end)
      out("loaded; hooked Auctionator. Open the AH and run an Auctionator full scan. /amespike for commands.")
    else
      out("loaded; Auctionator API not found. /amespike for commands.")
    end
  elseif event == "AUCTION_HOUSE_SHOW" then
    state.house = UnitFactionGroup("npc") or "Neutral"
    local s = shardInfo()
    log("ah_show", s)
    out(
      "AH open: house=%s realm=%s (player %s, npc %s), connected realms: %s",
      s.house,
      s.realm,
      tostring(s.playerFaction),
      tostring(s.npcFaction),
      #s.connected > 0 and table.concat(s.connected, ", ") or "none"
    )
  elseif event == "AUCTION_HOUSE_CLOSED" then
    log("ah_closed", {})
  elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
    log("replicate_event", { num = C_AuctionHouse.GetNumReplicateItems() })
    out("REPLICATE_ITEM_LIST_UPDATE (%d rows), reading...", C_AuctionHouse.GetNumReplicateItems() or 0)
    readReplicate("event")
  elseif event == "CHAT_MSG_ADDON" then
    onAddonMessage(...)
  end
end)

---------------------------------------------------------------------------------------------------------------------
-- Slash commands

SLASH_AMESPIKE1 = "/amespike"
SlashCmdList.AMESPIKE = function(msg)
  local cmd, a, b = strsplit(" ", strtrim(msg or ""))
  cmd = (cmd or ""):lower()
  if cmd == "read" then
    readReplicate("manual")
  elseif cmd == "shard" then
    local s = shardInfo()
    out(
      "house=%s realm=%s (%s) player=%s npc=%s connected=%s",
      tostring(s.house),
      s.realm,
      s.realmName,
      tostring(s.playerFaction),
      tostring(s.npcFaction),
      #s.connected > 0 and table.concat(s.connected, ", ") or "none"
    )
  elseif cmd == "stress" then
    stress(tonumber(a) or 30)
  elseif cmd == "load" then
    out(
      "SavedVariables parse took ~%d ms at last load (%d stress copies)",
      db.lastLoadMs or -1,
      db.stress and #db.stress or 0
    )
  elseif cmd == "comm" then
    sendBurst(a or "self", tonumber(b) or 100)
  elseif cmd == "clear" then
    wipe(db)
    db.log = {}
    out("cleared")
  else
    out("commands:")
    out("  /amespike read  - read the current replicate list now (after a full scan)")
    out("  /amespike shard - show house/realm detection")
    out("  /amespike stress [N=30] - store N copies of the snapshot, then /reload")
    out("  /amespike load  - show SavedVariables load time")
    out("  /amespike comm <self|guild|party|Name-Realm> [n=100] - addon-message throughput test")
    out("  /amespike clear - wipe spike data")
  end
end
