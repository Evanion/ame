-- Rough performance check of Store at real-AH scale (plain Lua 5.1; WoW's Lua is similar or faster).
-- Run from repo root: lua5.1 bench/store_bench.lua
package.path = "./?.lua;" .. package.path
local addon = require("spec.helpers.addon")
local ns = addon.load({ "Core/Init.lua", "Core/Codec.lua", "Core/Store.lua" })

local ITEMS, DAYS, SCANS_PER_DAY = 6451, 30, 4
local DAY = 86400
local clock = 20000 * DAY
local identity = {
  Compress = function(_, s)
    return s
  end,
  Decompress = function(_, s)
    return s
  end,
}
local data = {}
local store = ns.Store.New(data, {
  compressor = identity,
  now = function()
    return clock
  end,
})

local ids = {}
local id = 700
for i = 1, ITEMS do
  id = id + math.random(1, 30)
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

local worst, total, n = 0, 0, 0
for d = DAYS - 1, 0, -1 do
  for k = 1, SCANS_PER_DAY do
    clock = (20000 - d) * DAY + k * 5 * 3600
    local s = snapshot()
    local t0 = os.clock()
    store:AddScan(s, clock, "me", "full")
    local ms = (os.clock() - t0) * 1000
    worst, total, n = math.max(worst, ms), total + ms, n + 1
  end
end
print(("AddScan full (%d items): avg %.0f ms, worst %.0f ms over %d scans"):format(ITEMS, total / n, worst, n))

local t0 = os.clock()
store:AddScan(
  { ids = { ids[100] }, min = { 1 }, market = { 1 }, median = { 1 }, qty = { 1 }, auctions = { 1 } },
  clock + 60,
  "me",
  "partial"
)
print(("AddScan partial (1 item): %.1f ms"):format((os.clock() - t0) * 1000))

store.cache, store.cacheOrder = {}, {}
t0 = os.clock()
local s = store:Series(ids[1234])
print(("Series cold (%d points): %.1f ms"):format(#s, (os.clock() - t0) * 1000))
t0 = os.clock()
store:Series(ids[1234])
print(("Series warm: %.2f ms"):format((os.clock() - t0) * 1000))

local bytes = 0
for _, b in pairs(data.days) do
  for _, p in pairs(b) do
    bytes = bytes + #p
  end
end
print(
  ("days tier: %.1f KB uncompressed text for %d days (%.1f KB/day)"):format(bytes / 1024, DAYS, bytes / 1024 / DAYS)
)
