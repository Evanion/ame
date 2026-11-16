-- /ame selftest: one command that checks every M1 piece in game, records timings to AME_DB.selftest (readable from
-- the SavedVariables file outside the game), then reloads the UI so the results are written to disk.
local _, ns = ...

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
    local color = r.status == "PASS" and "55ff55" or r.status == "WARN" and "ffcc00" or "ff5555"
    say("|cff%s%s|r %s %s", color, r.status, name, r.detail and ("- " .. tostring(r.detail)) or "")
  end

  say("selftest starting (this may pause the game for a moment)")

  check("libraries", function()
    assert(LibStub and LibStub("LibDeflate", true), "LibDeflate not loaded")
    return "PASS", "LibStub + LibDeflate"
  end)

  check("codec+compress 6.4k items", function()
    local snap = syntheticSnapshot(6451)
    local t0 = debugprofilestop()
    local text = ns.Codec.EncodeSnapshot(snap)
    local t1 = debugprofilestop()
    local packed = ns.Codec.Pack(text, AME.compressor)
    local t2 = debugprofilestop()
    local back = ns.Codec.DecodeSnapshot(ns.Codec.Unpack(packed, AME.compressor))
    local t3 = debugprofilestop()
    assert(#back.ids == #snap.ids and back.market[100] == snap.market[100], "round trip mismatch")
    AME_DB.stats.codecBench = {
      encodeMs = t1 - t0,
      compressMs = t2 - t1,
      decodeMs = t3 - t2,
      textBytes = #text,
      packedBytes = #packed,
    }
    return "PASS",
      ("encode %.0f ms, compress %.0f ms, unpack+decode %.0f ms, %d KB -> %d KB"):format(
        t1 - t0,
        t2 - t1,
        t3 - t2,
        #text / 1024,
        #packed / 1024
      )
  end)

  check("history addon", function()
    assert(AME:LoadHistory(), "could not load history addon")
    local shards, bytes = 0, 0
    for _, data in pairs(AME.history.shards) do
      shards = shards + 1
      for _, buckets in pairs(data.days or {}) do
        for _, p in pairs(buckets) do
          bytes = bytes + #p
        end
      end
    end
    AME_DB.stats.historyBytes = bytes
    return "PASS",
      ("loaded in %s ms, %d shard(s), %.0f KB of daily history"):format(
        tostring(AME_DB.stats.historyLoadMs),
        shards,
        bytes / 1024
      )
  end)

  check("shard", function()
    local key = AME:CurrentShard()
    return "PASS", key
  end)

  check("auctionator", function()
    if not (Auctionator and Auctionator.API and Auctionator.API.v1) then
      return "WARN", "Auctionator not loaded: full scans must come from another addon"
    end
    local hasDb = Auctionator.Database and type(Auctionator.Database.db) == "table"
    return "PASS", hasDb and "API + database found" or "API found, database not readable (no backfill)"
  end)

  check("last full scan", function()
    local f = AME_DB.stats.lastFull
    if not f then
      return "WARN", "none yet: open the AH and run an Auctionator full scan, then rerun /ame selftest"
    end
    return "PASS",
      ("%d items from %s listings, stored %s ms after the scan request"):format(
        f.items,
        tostring(f.rows),
        tostring(f.msSinceRequest)
      )
  end)

  check("history lookup (cold)", function()
    local store = AME:Store()
    local data = AME.history.shards[AME:CurrentShard()]
    local raw = data and data.raw and data.raw[#data.raw]
    if not raw then
      return "WARN", "no scans in this shard yet"
    end
    local snap = ns.Codec.DecodeSnapshot(ns.Codec.Unpack(raw.s, AME.compressor))
    local id = snap.ids[math.floor(#snap.ids / 2) + 1]
    store.cache, store.cacheOrder = {}, {}
    local t0 = debugprofilestop()
    local series = store:Series(id)
    local ms = debugprofilestop() - t0
    AME_DB.stats.lookupBench = { itemID = id, points = #series, ms = ms }
    assert(#series > 0, "item from latest scan has no daily points")
    return "PASS", ("item %d: %d points in %.1f ms"):format(id, #series, ms)
  end)

  check("market index", function()
    local b = AME_DB.stats.indexBuild
    if not AME.index then
      return "WARN", AME.indexing and "still building in the background" or "not built yet (needs history)"
    end
    return "PASS", ("%d items summarized%s"):format(AME.index.count, b and (" in " .. b.ms .. " ms wall") or "")
  end)

  check("chart library + window", function()
    assert(LibStub("LibAMEChart-1.0", true), "LibAMEChart-1.0 not loaded")
    ns.UI:Create()
    ns.UI:ShowTab("market")
    ns.UI.frame:Hide()
    return "PASS", "window created, market tab rendered"
  end)

  check("backfill", function()
    local when = AME_DB.backfilled[AME:CurrentShard()]
    if not when then
      return "WARN", "not run for this shard (runs on AH open when Auctionator data is available)"
    end
    return "PASS", "done " .. date("%Y-%m-%d %H:%M", when)
  end)

  AME_DB.selftest = { at = GetServerTime(), results = results, version = ns.VERSION }
  say("selftest: %d passed, %d warnings, %d failed. Reloading in 5 s to save the results...", passed, warned, failed)
  C_Timer.After(5, ReloadUI)
end
