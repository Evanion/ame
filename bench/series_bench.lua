-- Store:Series over a full history: DAYS_KEEP daily and WEEKS_KEEP weekly segments of one item bucket, ~200 items
-- each (a busy house). Plain Lua 5.1; WoW's Lua is similar or faster.
-- Run from repo root: lua5.1 bench/series_bench.lua   (AME_DEFLATE=1 for real LibDeflate, from Libs/)
package.path = "./?.lua;" .. package.path
local addon = require("spec.helpers.addon")
local ns = addon.load({ "Core/Init.lua", "Core/Codec.lua", "Core/Store.lua" })
local Store = ns.Store

local PER_BUCKET, DAYS, WEEKS = 200, Store.DAYS_KEEP, Store.WEEKS_KEEP
local DAY = 86400
local today = 20000
local compressor = {
  Compress = function(_, s)
    return s
  end,
  Decompress = function(_, s)
    return s
  end,
}
if os.getenv("AME_DEFLATE") then
  ns = addon.load({ "Core/Compress.lua" }, ns)
  compressor = ns.Compress.New(dofile("Libs/LibDeflate/LibDeflate.lua"))
end
math.randomseed(1)

local data = {}
local store = Store.New(data, {
  compressor = compressor,
  now = function()
    return today * DAY
  end,
})

-- the item bucket's ids: every BUCKETS-th id, so they all land in bucket b
local b = 7
local ids = {}
for i = 1, PER_BUCKET do
  ids[i] = 1000 * Store.BUCKETS + b + (i - 1) * Store.BUCKETS
end
local item = ids[120]

local function segment(scans)
  local cols = {}
  for _, f in ipairs(Store.SEGMENT_FIELDS) do
    cols[f] = {}
  end
  for i, id in ipairs(ids) do
    local p = math.random(100, 5000000)
    cols.ids[i], cols.min[i], cols.market[i], cols.median[i] = id, p, (p + 50) * scans, (p + 80) * scans
    cols.qty[i], cols.auctions[i], cols.scans[i] = math.random(1, 2000) * scans, math.random(1, 60) * scans, scans
    cols.hours[i], cols.high[i] = scans < 24 and 2 ^ scans - 1 or 0, p + 900
    cols.drain[i], cols.obs[i] = math.random(0, 500), math.random(0, 1440)
  end
  return store:encode(cols, Store.SEGMENT_FIELDS)
end

for d = today - DAYS + 1, today do
  data.days[d] = { [b] = segment(4) }
end
local firstWeek = math.floor((today - DAYS + 1) / 7) - 1
for w = firstWeek - WEEKS + 1, firstWeek do
  data.weeks[w] = { [b] = segment(28) }
end
local segs = DAYS + WEEKS

local function time(fn)
  local t0 = os.clock()
  local r = fn()
  return (os.clock() - t0) * 1000, r
end

local function fresh()
  return Store.New(data, {
    compressor = compressor,
    now = function()
      return today * DAY
    end,
  })
end

local s = fresh()
local cold, pts = time(function()
  return s:Series(item)
end)
print(("Series cold, %d segments (%d points): %.1f ms (%.2f ms/segment)"):format(segs, #pts, cold, cold / segs))
local warm = time(function()
  return s:Series(item)
end)
print(("Series again, same item: %.2f ms"):format(warm))
-- a new scan rewrites today's segment; the chart reloads
data.days[today][b] = segment(5)
local reload = time(function()
  return s:Series(item)
end)
print(("Series after a new scan (today's segment changed): %.2f ms"):format(reload))
local recent = time(function()
  return fresh():Series(item, today - 29, today)
end)
print(("Series cold, last 30 days: %.1f ms"):format(recent))
