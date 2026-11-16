-- WoW glue: events, scan hooks, load-on-demand history, background jobs, slash commands. Logic lives in the pure
-- modules (Stats, Codec, Store, Ingest, Backfill); this file only wires them to the client.
local ADDON, ns = ...

local AME = {}
ns.AME = AME

local HISTORY_ADDON = ADDON .. "_History"
local GetServerTime, debugprofilestop = GetServerTime, debugprofilestop

local function say(fmt, ...)
  local msg = select("#", ...) > 0 and fmt:format(...) or fmt
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffAME|r " .. msg)
end
AME.Say = say

local function money(copper)
  if not copper then
    return "-"
  end
  return GetCoinTextureString and GetCoinTextureString(copper) or tostring(copper)
end
AME.Money = money

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
    say("could not load %s: %s", HISTORY_ADDON, tostring(reason))
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
      local realm, house = key:match("^(.+)|(%a+)$")
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

function AME:CurrentShard()
  return ns.ShardKey(ns.MarketRealm(GetNormalizedRealmName()), self:CurrentHouse())
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
  below = "dropped to %s (alert at %s)",
  above = "rose to %s (alert at %s)",
  buy = "BUY signal at %s",
  sell = "SELL signal at %s",
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
    say("|cffffcc00Alert:|r %s %s", link or ("item:" .. a.itemID), what)
    if UIErrorsFrame then
      UIErrorsFrame:AddMessage(("AME alert: %s %s"):format(link or a.itemID, what), 1, 0.82, 0)
    end
  end
  if #fired > 0 and ns.Settings:Get("alertSound") and PlaySound and SOUNDKIT then
    PlaySound(SOUNDKIT.RAID_WARNING or SOUNDKIT.TELL_MESSAGE or 3081)
  end
  self.lastAlerts = fired
  if #fired > 0 and ns.UI and ns.UI.RefreshMarket then
    ns.UI:RefreshMarket()
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
    return ns.MarketIndex.Build(store, math.floor(GetServerTime() / 86400), 30, function()
      job:Checkpoint()
    end, ns.Settings:Get("outlierFactor"))
  end, function(ok, index)
    self.indexing = false
    if ok and index then
      self.index = index
      self.indexShard = shard
      if shard == self:CurrentShard() then
        self:CheckAlerts(index)
      end
      AME_DB.stats.indexBuild = { ms = math.floor(debugprofilestop() - t0), items = index.count }
      if ns.UI and ns.UI.RefreshMarket then
        ns.UI:RefreshMarket()
      end
    elseif not ok then
      say("|cffff5555market index failed:|r %s", tostring(index))
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
    say("|cffff5555scan read failed:|r %s", tostring(info and info.error))
    return
  end
  local shard = self:CurrentShard()
  local src = UnitName("player") or "?"
  local started = self.scanRequestedAt
  self:WithStore("store-" .. kind, shard, function(store)
    return store:AddScan(snap, t, src, kind)
  end, function(ok, added)
    if not ok then
      say("|cffff5555storing %s scan failed:|r %s", kind, tostring(added))
      return
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
        say("recorded full scan: %d items from %d listings (%s)", #snap.ids, info and info.rows or 0, shard)
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
      say("reading full scan (%d listings) in the background...", rows or 0)
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
-- Auctionator backfill (reads Auctionator internals; guarded)

function AME:Backfill(force)
  local shard = self:CurrentShard()
  if AME_DB.backfilled[shard] and not force then
    return
  end
  local atr = Auctionator
  local db = atr and atr.Database and atr.Database.db
  local day0 = atr and atr.Constants and atr.Constants.SCAN_DAY_0
  if type(db) ~= "table" or type(day0) ~= "number" then
    return
  end
  local ok, days = pcall(ns.Backfill.FromAuctionator, db, day0)
  if not ok then
    say("Auctionator import skipped: %s", tostring(days))
    return
  end
  self:WithStore("backfill", shard, function(store, job)
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
        say("imported %d days of Auctionator price history into %s", n, shard)
        self:RebuildIndex()
      end
    else
      say("Auctionator import failed: %s", tostring(n))
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
end

function handlers.PLAYER_LOGIN()
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
    end
  end)
  if ns.SyncService:Init(AME, AME.syncTransport) then
    ns.SyncService:Start()
  end
end

function handlers.AUCTION_HOUSE_SHOW()
  AME.house = UnitFactionGroup("npc") or "Neutral"
  AME_DB.lastHouse = AME.house
  if ns.UI and ns.UI.frame and ns.UI.frame:IsShown() then
    ns.UI.shardText:SetText(AME:CurrentShard())
    ns.UI:ApplyTheme()
  end
  if AME:LoadHistory() then
    AME:Backfill(false)
  end
end

function handlers.AUCTION_HOUSE_CLOSED()
  if AME.ingest.reading then
    local d = AME:ScanDiag()
    d.aborted = (d.aborted or 0) + 1
    say(
      "|cffffcc00the AH closed before AME finished reading the full scan; it wasn't recorded.|r Keep the AH open "
        .. 'until AME says "recorded full scan".'
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

local function itemIDFrom(arg)
  if not arg or arg == "" then
    return nil
  end
  return tonumber(arg:match("item:(%d+)") or arg:match("^%s*(%d+)%s*$"))
end
AME.ItemIDFrom = itemIDFrom

local function cmdItem(arg)
  local id = itemIDFrom(arg)
  if not id then
    say("usage: /ame item <item link or itemID>")
    return
  end
  local store = AME:Store()
  if not store then
    return
  end
  local l = store:Latest(id)
  if l then
    say(
      "%s latest (%s): min %s, market %s, %d units in %d auctions",
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
    say("no history for %s in %s", arg, AME:CurrentShard())
    return
  end
  for k = math.max(1, #series - 13), #series do
    local p = series[k]
    say(
      "  %s %s: min %s, market %s, qty %d (%d samples)",
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
  say("shard %s, history %s", shard, AME:HistoryLoaded() and "loaded" or "not loaded")
  local s = AME_DB.stats
  if s.lastFull then
    say(
      "last full scan: %d items, %s ago",
      s.lastFull.items,
      SecondsToTime and SecondsToTime(GetServerTime() - s.lastFull.at) or "?"
    )
  else
    say("no full scan recorded yet: open the AH and run an Auctionator full scan")
  end
  if AME:HistoryLoaded() then
    local data = AME.history.shards[shard]
    if data then
      local days, bytes = 0, 0
      for _, buckets in pairs(data.days or {}) do
        days = days + 1
        for _, p in pairs(buckets) do
          bytes = bytes + #p
        end
      end
      say("history: %d raw scans, %d days, %.0f KB", #(data.raw or {}), days, bytes / 1024)
    end
  end
  local d = AME:ScanDiag()
  say(
    "scan pipeline: %d requests, %d events (%d since last request), read %s, aborted %d; ingest requested=%s "
      .. "reading=%s",
    d.requests or 0,
    d.events or 0,
    d.eventsSinceRequest or 0,
    d.readItems and (d.readItems .. " items") or "none",
    d.aborted or 0,
    tostring(AME.ingest.requested),
    tostring(AME.ingest.reading)
  )
  local names = {}
  for _, job in ipairs(AME.jobs.queue) do
    names[#names + 1] = job.name
  end
  say("background jobs: %s", #names > 0 and table.concat(names, ", ") or "idle")
  say(
    "guild sync: %s, announced %d, served %d, received %d, rejected %d",
    ns.SyncService:Active() and "on" or "off",
    s.syncAnnounced or 0,
    s.syncServed or 0,
    s.syncReceived or 0,
    s.syncRejected or 0
  )
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
    say("/ame - open the window  ·  /ame <item link> - chart an item  ·  Alt-click an item - chart it")
    say("/ame item <link> - print history  ·  /ame status  ·  /ame selftest  ·  /ame backfill  ·  /ame config")
  elseif itemIDFrom(msg) then
    ns.UI:ShowItem(itemIDFrom(msg))
  else
    say("unknown command, try /ame help")
  end
end
