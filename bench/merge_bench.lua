-- Where a received scan's merge (SyncService:Merge) spends its time between pauses, at real-AH scale with real
-- LibDeflate. Prints the longest stretches without a pause and where they ended.
-- Run from repo root: lua5.1 bench/merge_bench.lua
package.path = "./?.lua;" .. package.path
local addon = require("spec.helpers.addon")
local ns = addon.load({ "Core/Init.lua", "Core/Codec.lua", "Core/Store.lua", "Core/Compress.lua", "Core/Sync.lua" })
ns.IsVariant = ns.IsVariant or function(id)
  return id > 2 ^ 31
end
ns.BaseID = ns.BaseID or function(id)
  return id % 2 ^ 31
end
local compressor = ns.Compress.New(dofile("Libs/LibDeflate/LibDeflate.lua"))

local ITEMS = tonumber(os.getenv("AME_ITEMS") or 25000)
local DAY = 86400
local clock = 20000 * DAY
local gaps, last, lastWhere = {}, nil, "start"
local function yield()
  local now = os.clock()
  if last then
    local parts = {}
    for level = 3, 6 do
      local info = debug.getinfo(level, "Sl")
      if not info then
        break
      end
      parts[#parts + 1] = tostring(info.short_src):match("[^/]+$") .. ":" .. tostring(info.currentline)
    end
    local where = table.concat(parts, " < ")
    gaps[#gaps + 1] = { ms = (now - last) * 1000, from = lastWhere, to = where }
    lastWhere = where
  end
  coroutine.yield()
  last = os.clock()
end
local data = {}
local store = ns.Store.New(data, {
  compressor = compressor,
  now = function()
    return clock
  end,
  yield = yield,
})

local ids = {}
local id = 700
for i = 1, ITEMS do
  id = id + math.random(1, 8)
  ids[i] = id
end
local function snapshot()
  local s = { ids = ids, min = {}, market = {}, median = {}, qty = {}, auctions = {} }
  for i = 1, ITEMS do
    local p = math.random(100, 5000000)
    s.min[i], s.market[i], s.median[i], s.qty[i], s.auctions[i] =
      p, p + 50, p + 80, math.random(1, 2000), math.random(1, 60)
  end
  return s
end

local function run(fn)
  local co = coroutine.create(fn)
  last = os.clock()
  while coroutine.status(co) ~= "dead" do
    local ok, err = coroutine.resume(co)
    assert(ok, err)
  end
  local now = os.clock()
  gaps[#gaps + 1] = { ms = (now - last) * 1000, from = lastWhere, to = "end" }
end

-- an earlier full scan of ours (the drain pairs with it)
run(function()
  store:AddScan(snapshot(), clock - 3600, "me", "full")
end)
gaps, lastWhere = {}, "start"

-- the received one, as it travels
local sent = snapshot()
local packed = ns.Codec.Pack(ns.Codec.EncodeSnapshot(sent), compressor)
local wire = compressor:Wire(packed)
run(function()
  local pause = store:pauser()
  local p = compressor:Unwire(wire, pause)
  local snap = ns.Codec.DecodeSnapshot(ns.Codec.Unpack(p, compressor, pause), pause)
  store.yield()
  local t0 = os.clock()
  local ref = {}
  for i, x in ipairs(snap.ids) do
    ref[x] = { market = snap.market[i] }
  end
  print(("(reference table build, not in the job: %.0f ms)"):format((os.clock() - t0) * 1000))
  last = os.clock()
  if ns.Sync and ns.Sync.Plausible then
    ns.Sync.Plausible(snap, ref, pause)
  end
  store:AddScan(snap, clock, "Zakzu", "full", p)
end)

table.sort(gaps, function(a, b)
  return a.ms > b.ms
end)
local total = 0
for _, g in ipairs(gaps) do
  total = total + g.ms
end
print(("%d stretches, %.0f ms in all"):format(#gaps, total))
for i = 1, math.min(12, #gaps) do
  local g = gaps[i]
  print(("%6.1f ms  %s  ->  %s"):format(g.ms, g.from, g.to))
end
