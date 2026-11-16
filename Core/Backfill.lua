-- One-time import of Auctionator's recent price history (default ~21 days). Pure transform; the caller reads
-- Auctionator.Database.db and Auctionator.Constants.SCAN_DAY_0 in game (internals, so guarded with pcall there).
--
-- Auctionator keeps, per dbKey and Auctionator-day: l = lowest minimum price, h = highest minimum price,
-- a = highest quantity available. It has no market/median, so we store min = l (or h), market = median =
-- midpoint of l and h, qty = a (0 if unknown), auctions = 0, scans = 1. Only plain itemID keys are imported in M1
-- (gear variants like "g:itemID:ilvl" come with variant support).
local _, ns = ...

local floor = math.floor

local Backfill = {}
ns.Backfill = Backfill

local DAY = 86400

-- returns { [ourDay] = { { id, min, market, median, qty, auctions, scans }, ... } }
function Backfill.FromAuctionator(db, scanDay0)
  local out = {}
  if type(db) ~= "table" or type(scanDay0) ~= "number" then
    return out
  end
  for key, entry in pairs(db) do
    local id = tonumber(key)
    if id and type(entry) == "table" and type(entry.h) == "table" then
      local lows = type(entry.l) == "table" and entry.l or {}
      local avail = type(entry.a) == "table" and entry.a or {}
      for dayKey, high in pairs(entry.h) do
        local d = tonumber(dayKey)
        if d and type(high) == "number" then
          local low = lows[dayKey]
          low = type(low) == "number" and low or high
          local mid = floor((low + high) / 2 + 0.5)
          local day = floor((scanDay0 + d * DAY) / DAY)
          out[day] = out[day] or {}
          local list = out[day]
          list[#list + 1] = { id, low, mid, mid, tonumber(avail[dayKey]) or 0, 0, 1, high }
        end
      end
    end
  end
  return out
end
