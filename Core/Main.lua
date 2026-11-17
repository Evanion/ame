-- WoW glue: events, scan hooks, load-on-demand history, background jobs, slash commands. Logic lives in the pure
-- modules (Stats, Codec, Store, Ingest, Backfill); this file only wires them to the client.
local ADDON, ns = ...
local L = ns.L

local AME = {}
ns.AME = AME

local HISTORY_ADDON = ADDON .. "_History"
local GetServerTime, debugprofilestop = GetServerTime, debugprofilestop

local function say(fmt, ...)
  local msg = select("#", ...) > 0 and fmt:format(...) or fmt
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffAME|r " .. msg)
end
AME.Say = say

-- A code error somewhere the UI carries on without the result (a suggestion, a chart, a background pass): saved for
-- /ame status and said in chat once per context and session, instead of passing for "no data".
AME.reported = {}
function AME:ReportError(context, err)
  AME_DB.stats.lastError = { context = context, error = tostring(err), at = GetServerTime() }
  if not self.reported[context] then
    self.reported[context] = true
    say("|cffff5555%s|r %s", context .. ":", tostring(err))
  end
end

local function money(copper)
  if not copper then
    return "-"
  end
  return GetCoinTextureString and GetCoinTextureString(copper) or tostring(copper)
end

---------------------------------------------------------------------------------------------------------------------
-- background jobs

AME.jobs = ns.Jobs.New({ budgetMs = 8, clock = debugprofilestop })
local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function()
  if AME.jobs:Busy() then
    AME.jobs:Tick()
  end
end)

---------------------------------------------------------------------------------------------------------------------
-- history (load on demand)

-- does a shard hold any scans or history? (an empty table can exist from an index build)
function AME:HasData(shard)
  local d = self.history and self.history.shards[shard]
  return d ~= nil and (next(d.raw or {}) ~= nil or next(d.days or {}) ~= nil or next(d.weeks or {}) ~= nil)
end

function AME:HistoryLoaded()
  return self.history ~= nil
end

function AME:LoadHistory()
  if self.history then
    return true
  end
  local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
  local t0 = debugprofilestop()
  local loaded, reason = load(HISTORY_ADDON)
  if not loaded then
    say(L["could not load %s: %s"], HISTORY_ADDON, tostring(reason))
    return false
  end
  AME_HistoryDB = AME_HistoryDB or {}
  AME_HistoryDB.v = AME_HistoryDB.v or 1
  AME_HistoryDB.shards = AME_HistoryDB.shards or {}
  self.history = AME_HistoryDB
  self:MigrateShardKeys()
  AME_DB.stats.historyLoadMs = math.floor(debugprofilestop() - t0)
  return true
end

-- Shard keys used to carry the full realm name; on Forever they're now the ruleset ("PvP|Horde"). Rename old keys,
-- leaving a shard alone if the new key already has data.
function AME:MigrateShardKeys()
  local function migrate(t)
    local moves = {}
    for key in pairs(t) do
      local realm, house = ns.SplitShard(key)
      if realm and ns.HOUSES[house] then
        local newKey = ns.ShardKey(ns.MarketRealm(realm), house)
        if newKey ~= key and t[newKey] == nil then
          moves[key] = newKey
        end
      end
    end
    for old, new in pairs(moves) do
      t[new], t[old] = t[old], nil
    end
  end
  migrate(self.history.shards)
  migrate(AME_DB.backfilled)
end

function AME:CurrentHouse()
  return self.house or AME_DB.lastHouse or UnitFactionGroup("player") or "Neutral"
end

-- Forever (regionally unique names): one economy per ruleset, read from the game's rules like Auctionator does.
-- Elsewhere: the realm name.
local function rulesetFromGameRules()
  if not (RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled()) then
    return nil
  end
  local rules, enum = C_GameRules, Enum and Enum.GameRule
  if not (rules and rules.IsGameRuleActive and enum) then
    return nil
  end
  local function on(rule)
    return rule ~= nil and rules.IsGameRuleActive(rule)
  end
  local pvp, rp = on(enum.PvPRuleset), on(enum.RPRuleset)
  if pvp and rp then
    return "RPPvP"
  elseif pvp then
    return "PvP"
  elseif rp then
    return "RP"
  elseif on(enum.HardcoreRuleset) then
    return "HC"
  end
  return "PvE"
end

function AME:MarketRealmName()
  local ok, rules = pcall(rulesetFromGameRules)
  return ns.MarketRealm(GetNormalizedRealmName(), ok and rules or nil)
end

function AME:CurrentShard()
  return ns.ShardKey(self:MarketRealmName(), self:CurrentHouse())
end

AME.stores = {}
function AME:Store(shardKey)
  shardKey = shardKey or self:CurrentShard()
  if not self:LoadHistory() then
    return nil
  end
  local store = self.stores[shardKey]
  if not store then
    self.history.shards[shardKey] = self.history.shards[shardKey] or {}
    store = ns.Store.New(self.history.shards[shardKey], {
      compressor = self.compressor,
      now = GetServerTime,
    })
    self.stores[shardKey] = store
  end
  return store
end

-- run fn(store) as a background job with time slicing inside the store
function AME:WithStore(name, shardKey, fn, onDone)
  local store = self:Store(shardKey)
  if not store then
    return
  end
  -- No pcall in here: WoW's Lua 5.1 can't yield across pcall. coroutine.resume already catches errors, and
  -- the yield hook is reset in the completion callback instead.
  self.jobs:Add(name, function(job)
    store.yield = function()
      job:Checkpoint()
    end
    return fn(store, job)
  end, function(ok, result)
    store.yield = function() end
    if onDone then
      onDone(ok, result)
    end
  end)
end

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
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local _, link = getInfo(a.itemID)
    local what = ALERT_TEXT[a.kind]:format(money(a.market), a.threshold and money(a.threshold) or "")
    say("|cffffcc00" .. L["Alert:"] .. "|r %s %s", link or ("item:" .. a.itemID), what)
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
function AME:IndexFor(shard, cb)
  if shard == self.indexShard and self.index then
    return cb(self.index)
  end
  if self.indexes[shard] then
    return cb(self.indexes[shard])
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
  if self.indexShard == shard and self.index then
    return self.index
  end
  local cached = self.indexes and self.indexes[shard]
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
      say("|cffff5555" .. L["market index failed:"] .. "|r %s", tostring(index))
    end
    if self.indexPending then
      self.indexPending = false
      self:RebuildIndex()
    end
  end)
end

---------------------------------------------------------------------------------------------------------------------
-- ingestion

-- scan pipeline counters, saved so they can be read after a reload
function AME:ScanDiag()
  AME_DB.stats.scan = AME_DB.stats.scan or {}
  return AME_DB.stats.scan
end

function AME:OnSnapshot(snap, t, kind, info)
  if kind == "full" then
    local d = self:ScanDiag()
    d.readDoneAt, d.readItems = GetServerTime(), #snap.ids
  end
  if kind == "error" then
    say("|cffff5555" .. L["scan read failed:"] .. "|r %s", tostring(info and info.error))
    return
  end
  local shard = self:CurrentShard()
  local src = UnitName("player") or "?"
  local started = self.scanRequestedAt
  ns.Posting:OnSnapshot(shard, snap, t) -- the pricing model learns each item's market from consecutive scans
  self:WithStore("store-" .. kind, shard, function(store)
    local added = store:AddScan(snap, t, src, kind)
    if info and info.books then
      store:SetBooks(info.books)
    end
    return added
  end, function(ok, added)
    if not ok then
      say("|cffff5555%s|r %s", L["storing %s scan failed:"]:format(kind), tostring(added))
      return
    end
    self:InvalidateIndex(shard)
    if ns.UI and ns.UI.frame and ns.UI.frame:IsShown() then
      ns.UI:RefreshViewOptions()
    end
    if kind == "full" then
      local ms = started and math.floor(debugprofilestop() - started) or nil
      AME_DB.stats.lastFull = {
        at = t,
        shard = shard,
        items = #snap.ids,
        rows = info and info.rows,
        skipped = info and info.skipped,
        msSinceRequest = ms,
        added = added,
      }
      if ns.Settings:Get("announceScans") then
        say(
          L["recorded full scan: %d items from %d listings (%s)"],
          #snap.ids,
          info and info.rows or 0,
          ns.ShardLabel(shard)
        )
      end
      self:RebuildIndex()
      ns.SyncService:Announce()
    else
      AME_DB.stats.partials = (AME_DB.stats.partials or 0) + 1
    end
  end)
end

AME.ingest = ns.Ingest.New({
  api = C_AuctionHouse,
  jobs = AME.jobs,
  now = GetServerTime,
  after = function(seconds, fn)
    C_Timer.After(seconds, fn)
  end,
  onSnapshot = function(...)
    AME:OnSnapshot(...)
  end,
  onReadStart = function(rows)
    local d = AME:ScanDiag()
    d.readStartedAt, d.readRows = GetServerTime(), rows
    if ns.Settings:Get("announceScans") then
      say(L["reading full scan (%d listings) in the background..."], rows or 0)
    end
  end,
  -- legacy AH globals, looked up at call time (only used after a QueryAuctionItems hook fires)
  legacy = {
    GetNumAuctionItems = function(...)
      return GetNumAuctionItems(...)
    end,
    GetAuctionItemInfo = function(...)
      return GetAuctionItemInfo(...)
    end,
  },
})

---------------------------------------------------------------------------------------------------------------------
-- Search the open auction house for an item, to buy it: Auctionator's shopping search when Auctionator is
-- installed (its public API), otherwise the default auction house window. Returns true when a search started.
function AME:SearchAuctionHouse(itemID)
  if not self.ahOpen then
    say(L["open the auction house first"])
    return false
  end
  local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local name = getInfo(itemID)
  if not name then
    say(L["item not loaded yet - try again in a moment"])
    return false
  end
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if api and api.MultiSearchExact and pcall(api.MultiSearchExact, ADDON, { name }) then
    return true
  end
  local frame = AuctionHouseFrame
  if frame and frame:IsShown() and frame.SearchBar then
    if AuctionHouseFrameDisplayMode and frame.SetDisplayMode then
      pcall(frame.SetDisplayMode, frame, AuctionHouseFrameDisplayMode.Buy)
    end
    local ok = pcall(function()
      frame.SearchBar:SetSearchText(name)
      frame.SearchBar:StartSearch()
    end)
    if ok then
      return true
    end
  end
  if AuctionFrame and AuctionFrame:IsShown() and BrowseName and AuctionFrameBrowse_Search then -- classic AH
    BrowseName:SetText(name)
    return pcall(AuctionFrameBrowse_Search)
  end
  say(L["couldn't start an auction house search for %s"], name)
  return false
end

---------------------------------------------------------------------------------------------------------------------
-- Auctionator backfill (reads Auctionator internals; guarded)

function AME:Backfill(force)
  local shard = self:CurrentShard()
  if AME_DB.backfilled[shard] and not force then
    return
  end
  -- Auctionator's database mixes every auction house of the realm (faction and goblin). Import it into the
  -- faction AH only, so the goblin AH's history stays clean for cross-AH comparisons.
  if self:CurrentHouse() == "Neutral" then
    if force then
      say(
        L["history import from Auctionator is only done at your faction's auction house (its data mixes all houses)."]
      )
    end
    return
  end
  local atr = Auctionator
  local db = atr and atr.Database and atr.Database.db
  local day0 = atr and atr.Constants and atr.Constants.SCAN_DAY_0
  if type(db) ~= "table" or type(day0) ~= "number" then
    return
  end
  -- read in the job, a few hundred items per frame (a big Auctionator database took ~0.4 s in one frame). No pcall
  -- in there (no yielding across it); errors end the job and are reported below.
  self:WithStore("backfill", shard, function(store, job)
    local days = ns.Backfill.FromAuctionator(db, day0, function()
      job:Checkpoint()
    end)
    local n = 0
    for day, rows in pairs(days) do
      if store:ImportDay(day, rows, "auctionator") then
        n = n + 1
      end
      job:Checkpoint()
    end
    return n
  end, function(okDone, n)
    if okDone then
      AME_DB.backfilled[shard] = GetServerTime()
      if (n or 0) > 0 then
        say(L["imported %d days of price history from Auctionator into %s"], n, ns.ShardLabel(shard))
        self:RebuildIndex()
      end
    else
      say(L["history import from Auctionator failed: %s"], tostring(n))
    end
  end)
end

---------------------------------------------------------------------------------------------------------------------
-- events

local events = CreateFrame("Frame")
local handlers = {}

function handlers.ADDON_LOADED(name)
  if name ~= ADDON then
    return
  end
  AME_DB = AME_DB or {}
  AME_DB.v = AME_DB.v or 1
  AME_DB.stats = AME_DB.stats or {}
  AME_DB.backfilled = AME_DB.backfilled or {}
  AME.compressor = ns.Compress.New(LibStub("LibDeflate"))
  ns.Settings:Init()
  AME_DB.watch = AME_DB.watch or {}
  AME.watch = ns.Watch.New(AME_DB.watch)
  ns.Trading:Init()
  ns.Posting:Init()
end

function handlers.PLAYER_LOGIN()
  C_Timer.After(2, function()
    ns.Trading:ScanBags()
  end)
  if C_AuctionHouse and C_AuctionHouse.ReplicateItems then
    hooksecurefunc(C_AuctionHouse, "ReplicateItems", function()
      AME.scanRequestedAt = debugprofilestop()
      local d = AME:ScanDiag()
      d.requests, d.lastRequestAt, d.eventsSinceRequest = (d.requests or 0) + 1, GetServerTime(), 0
      AME.ingest:OnReplicateRequested()
    end)
  end
  -- browse summary scan (Auctionator's default full scan): an unfiltered browse query paged to the end
  if C_AuctionHouse and C_AuctionHouse.SendBrowseQuery then
    hooksecurefunc(C_AuctionHouse, "SendBrowseQuery", function(query)
      AME.ingest:OnBrowseQuery(query)
      if AME.ingest.browseRequested then
        AME.scanRequestedAt = debugprofilestop()
        local d = AME:ScanDiag()
        d.requests, d.browseRequests = (d.requests or 0) + 1, (d.browseRequests or 0) + 1
        d.lastRequestAt, d.eventsSinceRequest = GetServerTime(), 0
      end
    end)
  end
  -- legacy AH API (classic flavours): a getAll query is a full scan
  if QueryAuctionItems then
    hooksecurefunc("QueryAuctionItems", function(_, _, _, _, _, _, getAll)
      if getAll then
        AME.scanRequestedAt = debugprofilestop()
        local d = AME:ScanDiag()
        d.requests, d.getAllRequests = (d.requests or 0) + 1, (d.getAllRequests or 0) + 1
        d.lastRequestAt, d.eventsSinceRequest = GetServerTime(), 0
        AME.ingest:OnGetAllRequested()
      end
    end)
  end
  for _, e in ipairs({
    "AUCTION_HOUSE_SHOW",
    "AUCTION_HOUSE_CLOSED",
    "REPLICATE_ITEM_LIST_UPDATE",
    "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
    "GUILD_ROSTER_UPDATE",
    "PLAYER_GUILD_UPDATE",
    "MAIL_INBOX_UPDATE",
    "CHAT_MSG_SYSTEM",
    "BAG_UPDATE_DELAYED",
    "BANKFRAME_OPENED",
    "PLAYERBANKSLOTS_CHANGED",
    "OWNED_AUCTIONS_UPDATED",
    "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
    "COMMODITY_SEARCH_RESULTS_UPDATED",
    "ITEM_SEARCH_RESULTS_UPDATED",
  }) do
    pcall(events.RegisterEvent, events, e) -- tolerate events a client flavour doesn't have
  end
  if ns.Tooltip then
    ns.Tooltip:Install()
  end
  -- load history shortly after login (not during it) so tooltips have market data
  C_Timer.After(3, function()
    if AME:LoadHistory() then
      AME:RebuildIndex()
      -- other auction houses of this market (e.g. the goblin AH), for tooltips and arbitrage
      local realm, current = AME:MarketRealmName(), AME:CurrentHouse()
      for _, house in ipairs(ns.HOUSE_ORDER) do
        local shard = ns.ShardKey(realm, house)
        if house ~= current and AME:HasData(shard) then
          AME:IndexFor(shard, function() end)
        end
      end
    end
  end)
  if ns.SyncService:Init(AME, AME.syncTransport) then
    ns.SyncService:Start()
  end
end

function handlers.AUCTION_HOUSE_SHOW()
  AME.ahOpen = true
  AME.house = UnitFactionGroup("npc") or "Neutral"
  AME_DB.lastHouse = AME.house
  if ns.UI and ns.UI.frame and ns.UI.frame:IsShown() then
    ns.UI.viewHouse = nil -- follow the auction house you're at
    ns.UI:ViewChanged()
    ns.UI:ApplyTheme()
  end
  if AME:LoadHistory() then
    AME:Backfill(false)
  end
  ns.Trading:QueryAuctions()
end

function handlers.GUILD_ROSTER_UPDATE()
  if ns.SyncService.trust then
    ns.SyncService:RefreshGuildBlocklist()
  end
end
handlers.PLAYER_GUILD_UPDATE = handlers.GUILD_ROSTER_UPDATE

-- portfolio: auction mail, bags, bank, own auctions
function handlers.CHAT_MSG_SYSTEM(msg)
  ns.Trading:OnSystemMessage(msg)
end

function handlers.MAIL_INBOX_UPDATE()
  ns.Trading:ScanMail()
end

function handlers.BAG_UPDATE_DELAYED()
  ns.Trading:ScanBags()
end

function handlers.BANKFRAME_OPENED()
  ns.Trading:ScanBank()
end
handlers.PLAYERBANKSLOTS_CHANGED = handlers.BANKFRAME_OPENED

function handlers.OWNED_AUCTIONS_UPDATED()
  ns.Trading:ScanAuctions()
end

function handlers.AUCTION_HOUSE_CLOSED()
  AME.ahOpen = false
  if ns.UI and ns.UI.RenderArbitrage then
    ns.UI:RenderArbitrage()
  end
  if AME.ingest.reading then
    local d = AME:ScanDiag()
    d.aborted = (d.aborted or 0) + 1
    say(
      "|cffffcc00"
        .. L["the AH closed before AME finished reading the full scan; it wasn't recorded."]
        .. "|r "
        .. L['Keep the AH open until AME says "recorded full scan".']
    )
  end
  AME.ingest:OnAuctionHouseClosed()
end

function handlers.REPLICATE_ITEM_LIST_UPDATE()
  local d = AME:ScanDiag()
  d.events = (d.events or 0) + 1
  d.eventsSinceRequest = (d.eventsSinceRequest or 0) + 1
  AME.ingest:OnReplicateUpdate()
end

function handlers.AUCTION_HOUSE_BROWSE_RESULTS_UPDATED()
  local d = AME:ScanDiag()
  d.events = (d.events or 0) + 1
  d.eventsSinceRequest = (d.eventsSinceRequest or 0) + 1
  AME.ingest:OnBrowseResults()
end
handlers.AUCTION_HOUSE_BROWSE_RESULTS_ADDED = handlers.AUCTION_HOUSE_BROWSE_RESULTS_UPDATED

function handlers.COMMODITY_SEARCH_RESULTS_UPDATED(itemID)
  AME.ingest:OnCommodityResults(itemID)
end

function handlers.ITEM_SEARCH_RESULTS_UPDATED(itemKey)
  AME.ingest:OnItemResults(itemKey)
end

events:SetScript("OnEvent", function(_, event, ...)
  local h = handlers[event]
  if h then
    h(...)
  end
end)
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")

---------------------------------------------------------------------------------------------------------------------
-- slash commands

local itemIDFrom = ns.ItemIDFrom

local function cmdItem(arg)
  local id = itemIDFrom(arg)
  if not id then
    say(L["usage: /ame item <item link or itemID>"])
    return
  end
  local store = AME:Store()
  if not store then
    return
  end
  local l = store:Latest(id)
  if l then
    say(
      L["%s latest (%s): min %s, market %s, %d units in %d auctions"],
      arg,
      date("%H:%M", l.t),
      money(l.min),
      money(l.market),
      l.qty,
      l.auctions
    )
  end
  local series = store:Series(id)
  if #series == 0 then
    say(L["no history for %s in %s"], arg, ns.ShardLabel(AME:CurrentShard()))
    return
  end
  for k = math.max(1, #series - 13), #series do
    local p = series[k]
    say(
      "  " .. L["%s %s: min %s, market %s, qty %d (%d samples)"],
      p.res,
      date("!%Y-%m-%d", p.day * 86400),
      money(p.min),
      money(p.market),
      p.qty,
      p.scans
    )
  end
end

local function cmdStatus()
  local shard = AME:CurrentShard()
  say(L["market %s, history %s"], ns.ShardLabel(shard), AME:HistoryLoaded() and L["loaded"] or L["not loaded"])
  local s = AME_DB.stats
  if s.lastFull then
    say(
      L["last full scan: %d items, %s ago"],
      s.lastFull.items,
      SecondsToTime and SecondsToTime(GetServerTime() - s.lastFull.at) or "?"
    )
  else
    say(L["no full scan recorded yet: open the AH and run a full scan (your scanning addon's or the game's)"])
  end
  if AME:HistoryLoaded() then
    local data = AME.history.shards[shard]
    if data then
      local days, bytes = ns.Store.Footprint(data)
      say(L["history: %d raw scans, %d days, %.0f KB"], #(data.raw or {}), days, bytes / 1024)
    end
  end
  local d = AME:ScanDiag()
  say(
    L["scan pipeline: %d requests, %d events (%d since last request), read %s, aborted %d; ingest requested=%s reading=%s"],
    d.requests or 0,
    d.events or 0,
    d.eventsSinceRequest or 0,
    d.readItems and L["%d items"]:format(d.readItems) or L["none"],
    d.aborted or 0,
    tostring(AME.ingest.requested),
    tostring(AME.ingest.reading)
  )
  local names = {}
  for _, job in ipairs(AME.jobs.queue) do
    names[#names + 1] = job.name
  end
  say(L["background jobs: %s"], #names > 0 and table.concat(names, ", ") or L["idle"])
  say(
    L["guild sync: %s, announced %d, served %d, received %d, rejected %d"],
    ns.SyncService:Active() and L["on"] or L["off"],
    s.syncAnnounced or 0,
    s.syncServed or 0,
    s.syncReceived or 0,
    s.syncRejected or 0
  )
  if (s.syncErrors or 0) > 0 then
    say("|cffff5555" .. L["sync errors: %d (last: %s)"] .. "|r", s.syncErrors, tostring(s.lastSyncError))
  end
  local err = AME_DB.stats.lastError
  if err then
    say("|cffff5555" .. L["last error (%s, %s): %s"] .. "|r", err.context, date("%b %d %H:%M", err.at), err.error)
  end
end

SLASH_AZEROTHMERCANTILEEXCHANGE1 = "/ame"
SlashCmdList.AZEROTHMERCANTILEEXCHANGE = function(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  if cmd == "item" then
    cmdItem(rest)
  elseif cmd == "status" then
    cmdStatus()
  elseif cmd == "selftest" then
    ns.SelfTest.Run(AME)
  elseif cmd == "backfill" then
    AME:Backfill(true)
  elseif cmd == "config" or cmd == "settings" or cmd == "options" then
    ns.Settings:Open()
  elseif cmd == "" then
    ns.UI:Toggle()
  elseif cmd == "help" then
    say(L["/ame - open the window  ·  /ame <item link> - chart an item  ·  Alt-click an item - chart it"])
    say(L["/ame item <link> - print history  ·  /ame status  ·  /ame selftest  ·  /ame backfill  ·  /ame config"])
  elseif itemIDFrom(msg) then
    ns.UI:ShowItem(itemIDFrom(msg))
  else
    say(L["unknown command, try /ame help"])
  end
end
