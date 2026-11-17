-- Market index glue: building, caching and rebuilding each auction house's 30-day summary (MarketIndex.lua),
-- and the watchlist alerts checked against each fresh index.
local _, ns = ...
local L = ns.L

local AME = ns.AME
local say, money = AME.Say, AME.Money

-- Watchlist alerts: checked against each fresh market index (after scans, sync merges and at login).
local ALERT_TEXT = {
  below = L["dropped to %s (alert at %s)"],
  above = L["rose to %s (alert at %s)"],
  buy = L["BUY signal at %s"],
  sell = L["SELL signal at %s"],
}

function AME:CheckAlerts(index)
  if not self.watch then
    return
  end
  local fired = self.watch:Check(index.items)
  for _, a in ipairs(fired) do
    local link = ns.ItemCache.Link(a.itemID)
    local what = ALERT_TEXT[a.kind]:format(money(a.market), a.threshold and money(a.threshold) or "")
    say(ns.Color("warn", L["Alert:"]) .. " %s %s", link or ("item:" .. a.itemID), what)
    if UIErrorsFrame then
      UIErrorsFrame:AddMessage(L["AME alert: %s %s"]:format(link or a.itemID, what), 1, 0.82, 0)
    end
  end
  if #fired > 0 and ns.Settings:Get("alertSound") and PlaySound and SOUNDKIT then
    PlaySound(SOUNDKIT.RAID_WARNING or SOUNDKIT.TELL_MESSAGE or 3081)
  end
  if #fired > 0 and ns.UI and ns.UI.RefreshMarket then
    ns.UI:RefreshMarket()
  end
end

AME.INDEX_DAYS = 30

-- Build a shard's market index inside a store job. The auction house you're at gets rebuilt after every scan, so it
-- keeps its segments decompressed between builds (Store:KeepTexts); other houses' are freed.
function AME:BuildIndex(store, shard, job)
  local current = shard == self:CurrentShard()
  if current then
    for key, other in pairs(self.stores) do
      if key ~= shard then
        other:KeepTexts(false)
      end
    end
  end
  return ns.MarketIndex.Build(store, ns.Today(GetServerTime()), AME.INDEX_DAYS, function()
    job:Checkpoint()
  end, ns.Settings:Get("outlierFactor"), current)
end

-- Market index for any auction house (e.g. the goblin AH while you're at your faction's): cached per shard,
-- dropped when that shard gets new data. cb(index or nil).
AME.indexes = {}
AME.indexWaiters = {}

-- a shard's market index if it's built (nil otherwise; nothing is started)
function AME:CachedIndex(shard)
  if shard == self.indexShard and self.index then
    return self.index
  end
  return self.indexes[shard]
end

function AME:IndexFor(shard, cb)
  local cached = self:CachedIndex(shard)
  if cached then
    return cb(cached)
  end
  if not self:LoadHistory() or not self.history.shards[shard] then
    return cb(nil)
  end
  local waiting = self.indexWaiters[shard]
  if waiting then
    waiting[#waiting + 1] = cb
    return
  end
  self.indexWaiters[shard] = { cb }
  self:WithStore("index-" .. shard, shard, function(store, job)
    return AME:BuildIndex(store, shard, job)
  end, function(ok, index)
    local cbs = self.indexWaiters[shard] or {}
    self.indexWaiters[shard] = nil
    if ok and index then
      self.indexes[shard] = index
    elseif not ok then
      self:ReportError("market index", index)
    end
    for _, f in ipairs(cbs) do
      f(ok and index or nil)
    end
  end)
end

-- Your faction's auction house index (the market you trade in): tooltips and the portfolio value things here, never
-- at the goblin or other faction's house. Built in the background when missing (nil until then).
function AME:FactionIndex()
  local house = UnitFactionGroup("player")
  if house ~= "Horde" and house ~= "Alliance" then
    house = self:CurrentHouse()
  end
  local shard = ns.ShardKey(self:MarketRealmName(), house)
  local cached = self:CachedIndex(shard)
  if not cached and self:HistoryLoaded() and self:HasData(shard) then
    self:IndexFor(shard, function() end)
  end
  return cached
end

-- latest order book for an item at an auction house (from a search there), if fresher than maxAge seconds
function AME:BookFor(shard, itemID, maxAge)
  if not self:HistoryLoaded() or not self.history.shards[shard] then
    return nil
  end
  return self:Store(shard):Book(itemID, maxAge)
end

function AME:InvalidateIndex(shard)
  if shard then
    self.indexes[shard] = nil
  else
    self.indexes = {}
  end
end

-- Rebuild the market index (30-day summary per item) in the background; tooltips and the screener read it.
function AME:RebuildIndex()
  if self.indexing then
    self.indexPending = true
    return
  end
  local shard = self:CurrentShard()
  self.indexing = true
  local t0 = debugprofilestop()
  self:WithStore("index", shard, function(store, job)
    return AME:BuildIndex(store, shard, job)
  end, function(ok, index)
    self.indexing = false
    if ok and index then
      self.index = index
      self.indexShard = shard
      self.indexes[shard] = index
      if shard == self:CurrentShard() then
        self:CheckAlerts(index)
      end
      AME_DB.stats.indexBuild = { ms = math.floor(debugprofilestop() - t0), items = index.count }
      if ns.UI and ns.UI.RefreshMarket then
        ns.UI:RefreshMarket()
      end
    elseif not ok then
      say(ns.Color("bad", L["market index failed:"]) .. " %s", tostring(index))
    end
    if self.indexPending then
      self.indexPending = false
      self:RebuildIndex()
    end
  end)
end
