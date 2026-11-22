-- AME's public API for other addons (and WeakAuras, macros): what AME knows about an item at your faction's auction
-- house, the numbers its own tooltip and tabs show. Read-only; nothing here changes AME's data.
--
--   local ame = AzerothMercantileExchange and AzerothMercantileExchange.API and AzerothMercantileExchange.API.v1
--
-- Every function takes an item as an item ID, an item link or an item string ("item:2589"); a random-suffix item's
-- link prices that suffix. Prices are copper. nil means AME doesn't know (no scan has seen the item yet, or the
-- market index is still loading after login - IsReady()).
--
--   v1.GetVersion() -> 1, addon version ("0.4.1")
--   v1.IsReady() -> true once your faction's market index is loaded
--   v1.GetMarketPrice(item) -> the market price (the day's average listing price)
--   v1.GetWorth(item) -> copper, where   what one you hold is worth: the better of listing it ("ah", after the cut
--                                        and deposit) and a vendor ("vendor"); nil, "unsellable" for soulbound items
--   v1.GetSignal(item) -> "buy" | "sell" | "hold" | "wait" | "vendor" | "disenchant" | nil
--   v1.GetItemInfo(item) -> table (a copy) or nil:
--        market, lowest, listed, average3, average7, average30, change1, change7, change30 (0.05 = +5%),
--        soldPerDay, sellThrough (0..1), signal, worth, worthWhere, vendor, lastSeen (server time, day it was seen)
--   v1.GetPostingPrice(item, quantity, hours) -> { quick, normal, patient } or nil, each { price, chance, hours }
--        (chance 0..1 that it sells within the listing time; quick is nil when it would be the normal price)
--   v1.RegisterForUpdates(owner, callback) -> callback() whenever new prices are in (a scan, a search, login);
--        owner: any string or table, to unregister with v1.UnregisterForUpdates(owner)
local _, ns = ...

local API = { v1 = {} }
ns.API = API
local v1 = API.v1
v1.VERSION = 1

-- item ID / link / item string -> AME's item key (ns.ItemKey)
local function keyOf(item)
  if type(item) == "number" then
    return item > 0 and item or nil
  end
  if type(item) ~= "string" then
    return nil
  end
  if item:find("|H", 1, true) and ns.ItemCache and ns.ItemCache.Learn then
    return ns.ItemCache.Learn(item)
  end
  return ns.ItemIDFrom(item)
end
API.KeyOf = keyOf

-- the quote for your faction's house, kept while the index stays the same (bag addons ask for every slot)
local cached = {}
local function quote()
  local AME = ns.AME
  local index = AME and AME.FactionIndex and AME:FactionIndex()
  if not index then
    return nil
  end
  if cached.index ~= index then
    cached.index = index
    cached.q = ns.Quote.For(AME:FactionShard(), index, { fresh = false })
  end
  return cached.q, index
end

local function summary(item)
  local key = keyOf(item)
  local q, index = quote()
  return key and index and index.items[key], key, q
end

function v1.GetVersion()
  return v1.VERSION, ns.VERSION
end

function v1.IsReady()
  return quote() ~= nil
end

function v1.GetMarketPrice(item)
  local s = summary(item)
  return s and s.market
end

function v1.GetWorth(item)
  local s, key, q = summary(item)
  if not (key and q) then
    return nil
  end
  local net, where = q:BestSale(key)
  if where == "ah" and not s then
    return nil
  end
  return net, where
end

function v1.GetSignal(item)
  local s = summary(item)
  local signal = s and s.signal
  return signal ~= "none" and signal or nil
end

function v1.GetItemInfo(item)
  local s, key, q = summary(item)
  if not s then
    return nil
  end
  local worth, where = q:BestSale(key)
  local signal = s.signal ~= "none" and s.signal or nil
  return {
    market = s.market,
    lowest = s.min,
    listed = s.qty,
    average3 = s.avg3,
    average7 = s.avg7,
    average30 = s.avg30,
    change1 = s.change1,
    change7 = s.change7,
    change30 = s.change30,
    soldPerDay = q:SoldPerDay(key),
    sellThrough = s.sellThrough,
    signal = signal,
    worth = worth,
    worthWhere = where,
    vendor = ns.ItemCache.Get(key).sellPrice,
    lastSeen = s.day and s.day * ns.DAY or nil,
  }
end

local function option(o)
  return o and o.price and { price = o.price, chance = o.chance, hours = o.hours } or nil
end

function v1.GetPostingPrice(item, quantity, hours)
  local key = keyOf(item)
  local AME = ns.AME
  if not (key and AME and ns.Posting and quote()) then
    return nil
  end
  hours = hours or ns.Settings:Get("listingHours")
  local ok, advice = pcall(ns.Posting.Suggest, ns.Posting, AME:FactionShard(), key, quantity or 1, hours)
  if not (ok and advice and advice.normal) then
    return nil
  end
  return {
    quick = not advice.quickSame and option(advice.quick) or nil,
    normal = option(advice.normal),
    patient = option(advice.patient),
  }
end

-- update callbacks: on every new index for your faction's house
local listeners = {}
API.listeners = listeners

function v1.RegisterForUpdates(owner, callback)
  assert(owner ~= nil and type(callback) == "function", "RegisterForUpdates(owner, callback)")
  listeners[owner] = callback
end

function v1.UnregisterForUpdates(owner)
  listeners[owner] = nil
end

function API.Notify()
  for owner, fn in pairs(listeners) do
    local ok, err = pcall(fn)
    if not ok and ns.AME and ns.AME.ReportError then
      ns.AME:ReportError("API listener " .. tostring(owner), err)
    end
  end
end

if ns.Events then
  ns.Events.On("IndexReady", function(shard)
    if ns.AME and shard == ns.AME:FactionShard() then
      API.Notify()
    end
  end)
end

_G.AzerothMercantileExchange = { API = { v1 = v1 } }
