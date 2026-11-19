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
  -- VENDOR where selling on this house nets less than a vendor (one listing at your usual length)
  local _, house = ns.SplitShard(shard)
  local cut, hours = ns.Settings:AuctionCut(house), ns.Settings:Get("listingHours")
  local function vendorCheck(s)
    local vendor = ns.ItemCache.Get(s.itemID).sellPrice
    if vendor and vendor > 0 then
      s.vendorPrice = vendor -- kept with the index (saved at logout), so a restored index has it without the client
      ns.Analytics.VendorCheck(s, vendor, cut, ns.Arbitrage.Deposit(vendor, house, hours))
    end
  end
  return ns.MarketIndex.Build(store, ns.Today(GetServerTime()), AME.INDEX_DAYS, function()
    job:Checkpoint()
  end, ns.Settings:Get("outlierFactor"), current, vendorCheck)
end

-- Market indexes, one per auction house, built in the background. An index is never dropped while a new one is built:
-- the old one stays in use (stale but shown; the footer says data is updating) and is swapped when the new one is
-- ready, which also refreshes the open tab. Indexes are saved at logout and restored at login, so the screener and
-- tooltips have data right away; a shard is rebuilt only when its history changed since (Store rev) or the day moved.
AME.indexes = {}
AME.indexWaiters = {}
AME.indexBuilding = {} -- [shard] = true while a build runs
AME.indexAgain = {} -- [shard] = true: rebuild once more after the running build (new data arrived meanwhile)
AME.indexStarted = {} -- [shard] = true once the queued build has begun reading history
AME.INDEX_LOW_BUDGET = 3 -- ms per frame for rebuilds while an older index is shown (normal jobs: 8)

-- a shard's market index if there is one (nil otherwise; nothing is started)
function AME:CachedIndex(shard)
  if shard == self.indexShard and self.index then
    return self.index
  end
  return self.indexes[shard]
end

function AME:IndexBusy()
  return next(self.indexBuilding) ~= nil
end

-- Build a fresh index for a shard in the background (low priority when an older one is shown meanwhile).
function AME:RefreshIndex(shard)
  shard = shard or self:CurrentShard()
  if self.indexBuilding[shard] then
    -- a build that hasn't started yet will see the new data anyway
    if self.indexStarted[shard] then
      self.indexAgain[shard] = true
    end
    return
  end
  if not self:LoadHistory() or not self.history.shards[shard] then
    return
  end
  local shown = self:CachedIndex(shard) ~= nil
  self.indexBuilding[shard] = true
  local t0 = debugprofilestop()
  self:WithStore("index-" .. shard, shard, function(store, job)
    AME.indexStarted[shard] = true
    local rev = store.data.rev or 0
    local index = AME:BuildIndex(store, shard, job)
    index.rev = rev
    return index
  end, function(ok, index)
    self.indexBuilding[shard], self.indexStarted[shard] = nil, nil
    if ok and index then
      self:SetIndex(shard, index)
      if shard == self:CurrentShard() then
        AME_DB.stats.indexBuild = { ms = math.floor(debugprofilestop() - t0), items = index.count }
      end
    elseif not ok then
      self:ReportError("market index", index)
    end
    local cbs = self.indexWaiters[shard] or {}
    self.indexWaiters[shard] = nil
    for _, cb in ipairs(cbs) do
      cb(ok and index or nil)
    end
    if self.indexAgain[shard] then
      self.indexAgain[shard] = nil
      self:RefreshIndex(shard)
    end
  end, shown and AME.INDEX_LOW_BUDGET or nil)
end

-- put an index in use (built, or restored at login) and tell whoever shows it
function AME:SetIndex(shard, index)
  self.indexes[shard] = index
  if shard == self:CurrentShard() then
    self.index, self.indexShard = index, shard
    self:CheckAlerts(index)
  end
  if ns.UI and ns.UI.OnIndexReady then
    ns.UI:OnIndexReady(shard)
  end
end

-- cb(index or nil): right away when there is one (a stale one is refreshed in the background), else once built
function AME:IndexFor(shard, cb)
  local cached = self:CachedIndex(shard)
  if cached then
    return cb(cached)
  end
  if not self:LoadHistory() or not self.history.shards[shard] then
    return cb(nil)
  end
  local waiting = self.indexWaiters[shard] or {}
  self.indexWaiters[shard] = waiting
  waiting[#waiting + 1] = cb
  self:RefreshIndex(shard)
end

-- Your faction's auction house index (the market you trade in): tooltips and the portfolio value things here, never
-- at the goblin or other faction's house. Built in the background when missing (nil until then).
-- your faction's auction house (the market tooltips quote)
function AME:FactionShard()
  local house = UnitFactionGroup("player")
  if house ~= "Horde" and house ~= "Alliance" then
    house = self:CurrentHouse()
  end
  return ns.ShardKey(self:MarketRealmName(), house)
end

function AME:FactionIndex()
  local shard = self:FactionShard()
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

-- New data for a shard (nil: every shard, e.g. a changed outlier setting): rebuild in the background, keeping the
-- current index in use meanwhile.
function AME:InvalidateIndex(shard)
  if shard then
    if self:CachedIndex(shard) or self.indexWaiters[shard] then
      self:RefreshIndex(shard)
    end
    return
  end
  for key in pairs(self.indexes) do
    self:RefreshIndex(key)
  end
end

-- Searches and browsing add a little data at a time: refresh the index once they've been quiet for a while instead
-- of rebuilding it after each one (a rebuild is seconds of background work).
AME.INDEX_QUIET = 60
AME.indexLater = {}
-- shard nil: every house; delay: seconds of quiet (INDEX_QUIET by default)
function AME:InvalidateIndexLater(shard, delay)
  local key = shard or "*"
  local gen = (self.indexLater[key] or 0) + 1
  self.indexLater[key] = gen
  C_Timer.After(delay or AME.INDEX_QUIET, function()
    if self.indexLater[key] == gen then
      self:InvalidateIndex(shard)
    end
  end)
end

-- the index of the auction house you're at
function AME:RebuildIndex()
  self:RefreshIndex(self:CurrentShard())
end

-- Saved indexes: written at logout, read back at login (MarketIndex.Encode / Decode).
function AME:SaveIndexes()
  local saved = {}
  for shard, index in pairs(self.indexes) do
    local ok, text = pcall(ns.MarketIndex.Encode, index)
    if ok then
      saved[shard] = { rev = index.rev or 0, v = ns.MarketIndex.SAVE_VERSION, s = text }
    end
  end
  AME_DB.indexCache = saved
end

-- Login: put the saved indexes in use, then rebuild (low priority) those whose history changed or day moved on, and
-- build the ones with history but nothing saved.
function AME:RestoreIndexes()
  local saved = AME_DB.indexCache or {}
  AME_DB.indexCache = nil -- in memory now; written again at logout
  local today = ns.Today(GetServerTime())
  self:WithStore("index-restore", self:CurrentShard(), function(_, job)
    local restored = {}
    for shard, entry in pairs(saved) do
      if self.history.shards[shard] then
        local ok, index = pcall(ns.MarketIndex.Decode, entry.s)
        if ok and index then
          index.rev, index.saveVersion = entry.rev, entry.v or 1 -- saves before versioning: 1
          restored[shard] = index
        end
        job:Checkpoint()
      end
    end
    return restored
  end, function(ok, restored)
    for shard, index in pairs(ok and restored or {}) do
      self:SetIndex(shard, index)
    end
    for shard, data in pairs(self.history.shards) do
      local index = self.indexes[shard]
      local outdated = index and index.saveVersion and index.saveVersion ~= ns.MarketIndex.SAVE_VERSION
      if not index or outdated or index.rev ~= (data.rev or 0) or index.day ~= today then
        if index or shard == self:CurrentShard() or self:HasData(shard) then
          self:RefreshIndex(shard)
        end
      end
    end
  end)
end
