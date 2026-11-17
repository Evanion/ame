-- /ame selftest: one command that checks every part of AME in game, records timings to AME_DB.selftest (readable from
-- the SavedVariables file outside the game), then offers a Reload button so the results are written to disk.
local _, ns = ...
local L = ns.L

local SelfTest = {}
ns.SelfTest = SelfTest

local debugprofilestop = debugprofilestop

-- synthetic snapshot shaped like a real AH (6.4k items) for codec/compression timing
local function syntheticSnapshot(n)
  local s = { ids = {}, min = {}, market = {}, median = {}, qty = {}, auctions = {} }
  local id = 700
  for i = 1, n do
    id = id + (i % 7) + 1
    local p = 100 + (i * 7919) % 2000000
    s.ids[i], s.min[i], s.market[i], s.median[i] = id, p, p + 25, p + 40
    s.qty[i], s.auctions[i] = 1 + i % 200, 1 + i % 20
  end
  return s
end

function SelfTest.Run(AME)
  local say = AME.Say
  local results = {}
  local passed, failed, warned = 0, 0, 0

  local function check(name, fn)
    local t0 = debugprofilestop()
    local ok, status, detail = pcall(fn)
    local ms = math.floor((debugprofilestop() - t0) * 10) / 10
    local r = { name = name, ms = ms }
    if not ok then
      r.status, r.detail = "FAIL", tostring(status)
    else
      r.status, r.detail = status or "PASS", detail
    end
    results[#results + 1] = r
    if r.status == "PASS" then
      passed = passed + 1
    elseif r.status == "WARN" then
      warned = warned + 1
    else
      failed = failed + 1
    end
    local color = r.status == "PASS" and "good" or r.status == "WARN" and "warn" or "bad"
    say("%s %s %s", ns.Color(color, r.status), name, r.detail and ("- " .. tostring(r.detail)) or "")
  end

  say(L["selftest starting (this may pause the game for a moment)"])

  check(L["libraries"], function()
    assert(LibStub and LibStub("LibDeflate", true), L["LibDeflate not loaded"])
    return "PASS", "LibStub + LibDeflate"
  end)

  check(L["codec+compress 6.4k items"], function()
    local snap = syntheticSnapshot(6451)
    local t0 = debugprofilestop()
    local text = ns.Codec.EncodeSnapshot(snap)
    local t1 = debugprofilestop()
    local packed = ns.Codec.Pack(text, AME.compressor)
    local t2 = debugprofilestop()
    local back = ns.Codec.DecodeSnapshot(ns.Codec.Unpack(packed, AME.compressor))
    local t3 = debugprofilestop()
    assert(#back.ids == #snap.ids and back.market[100] == snap.market[100], L["round trip mismatch"])
    AME_DB.stats.codecBench = {
      encodeMs = t1 - t0,
      compressMs = t2 - t1,
      decodeMs = t3 - t2,
      textBytes = #text,
      packedBytes = #packed,
    }
    return "PASS",
      L["encode %.0f ms, compress %.0f ms, unpack+decode %.0f ms, %d KB -> %d KB"]:format(
        t1 - t0,
        t2 - t1,
        t3 - t2,
        #text / 1024,
        #packed / 1024
      )
  end)

  check(L["history addon"], function()
    assert(AME:LoadHistory(), L["could not load history addon"])
    local shards, bytes = 0, 0
    for _, data in pairs(AME.history.shards) do
      local _, b = ns.Store.Footprint(data)
      shards, bytes = shards + 1, bytes + b
    end
    AME_DB.stats.historyBytes = bytes
    return "PASS",
      L["loaded in %s ms, %d shard(s), %.0f KB of daily history"]:format(
        tostring(AME_DB.stats.historyLoadMs),
        shards,
        bytes / 1024
      )
  end)

  check(L["shard"], function()
    local key = ns.ShardLabel(AME:CurrentShard())
    return "PASS", key
  end)

  check(L["auctionator history import"], function()
    if not (Auctionator and Auctionator.API and Auctionator.API.v1) then
      return "PASS", L["Auctionator not installed: nothing to import (scans are recorded from the game either way)"]
    end
    local hasDb = Auctionator.Database and type(Auctionator.Database.db) == "table"
    return "PASS", hasDb and L["API + database found"] or L["API found, database not readable (no backfill)"]
  end)

  check(L["last full scan"], function()
    local f = AME_DB.stats.lastFull
    if not f then
      return "WARN", L["none yet: open the AH and run a full scan, then rerun /ame selftest"]
    end
    return "PASS",
      L["%d items from %s listings, stored %s ms after the scan request"]:format(
        f.items,
        tostring(f.rows),
        tostring(f.msSinceRequest)
      )
  end)

  check(L["history lookup (cold)"], function()
    local store = AME:Store()
    local data = AME.history.shards[AME:CurrentShard()]
    local raw = data and data.raw and data.raw[#data.raw]
    if not raw then
      return "WARN", L["no scans in this shard yet"]
    end
    local snap = ns.Codec.DecodeSnapshot(ns.Codec.Unpack(raw.s, AME.compressor))
    local id = snap.ids[math.floor(#snap.ids / 2) + 1]
    store.cache, store.cacheOrder = {}, {}
    local t0 = debugprofilestop()
    local series = store:Series(id)
    local ms = debugprofilestop() - t0
    AME_DB.stats.lookupBench = { itemID = id, points = #series, ms = ms }
    assert(#series > 0, L["item from latest scan has no daily points"])
    return "PASS", L["item %d: %d points in %.1f ms"]:format(id, #series, ms)
  end)

  check(L["market index"], function()
    local b = AME_DB.stats.indexBuild
    if not AME.index then
      return "WARN", AME.indexing and L["still building in the background"] or L["not built yet (needs history)"]
    end
    return "PASS",
      b and L["%d items summarized in %s ms wall"]:format(AME.index.count, tostring(b.ms))
        or L["%d items summarized"]:format(AME.index.count)
  end)

  check(L["chart library + window"], function()
    assert(LibStub("LibAMEChart-1.0", true), L["LibAMEChart-1.0 not loaded"])
    ns.UI:Create()
    ns.UI:ShowTab("market")
    ns.UI.frame:Hide()
    return "PASS", L["window created, market tab rendered"]
  end)

  check(L["guild sync"], function()
    local svc = ns.SyncService
    if not svc.enabled then
      return "WARN", L["AceComm not available: sync disabled"]
    end
    if not ns.Settings:Get("syncGuild") then
      return "WARN", L["turned off in settings"]
    end
    if not (IsInGuild and IsInGuild()) then
      return "WARN", L["not in a guild"]
    end
    local s = AME_DB.stats
    return "PASS",
      L["announced %d, served %d, received %d, rejected %d"]:format(
        s.syncAnnounced or 0,
        s.syncServed or 0,
        s.syncReceived or 0,
        s.syncRejected or 0
      )
  end)

  check(L["backfill"], function()
    local when = AME_DB.backfilled[AME:CurrentShard()]
    if not when then
      return "PASS", L["nothing imported here (only with Auctionator data, at your faction's auction house)"]
    end
    return "PASS", L["done %s"]:format(date("%Y-%m-%d %H:%M", when))
  end)

  AME_DB.selftest = { at = GetServerTime(), results = results, version = ns.VERSION }
  say(L["selftest: %d passed, %d warnings, %d failed. Reload to save the results (/reload)."], passed, warned, failed)
  SelfTest.PromptReload(passed, warned, failed)
end

-- ReloadUI is protected outside hardware events (a timer callback gets ADDON_ACTION_BLOCKED), so ask with a popup
-- whose button click is the hardware event.
function SelfTest.PromptReload(passed, warned, failed)
  if not (StaticPopupDialogs and StaticPopup_Show) then
    return
  end
  StaticPopupDialogs.AME_SELFTEST_RELOAD = StaticPopupDialogs.AME_SELFTEST_RELOAD
    or {
      text = "Azeroth Mercantile Exchange " .. L["selftest finished:\n%s\n\nReload the UI now to save the results?"],
      button1 = RELOADUI or L["Reload UI"],
      button2 = CANCEL or L["Cancel"],
      OnAccept = function()
        ReloadUI()
      end,
      timeout = 0,
      whileDead = true,
      hideOnEscape = true,
      preferredIndex = 3,
    }
  StaticPopup_Show("AME_SELFTEST_RELOAD", L["%d passed, %d warnings, %d failed"]:format(passed, warned, failed))
end
