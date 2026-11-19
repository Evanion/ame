-- WoW glue: events, scan hooks, load-on-demand history, background jobs. The market index is in Index.lua, slash
-- commands in Commands.lua. Logic lives in the pure modules (Stats, Codec, Store, Ingest, Backfill); this file only
-- wires them to the client.
local ADDON, ns = ...
local L = ns.L

local AME = {}
ns.AME = AME

local HISTORY_ADDON = ADDON .. "_History"
local GetServerTime, debugprofilestop = GetServerTime, debugprofilestop

local function say(fmt, ...)
  local msg = select("#", ...) > 0 and fmt:format(...) or fmt
  DEFAULT_CHAT_FRAME:AddMessage(ns.Color("brand", "AME") .. " " .. msg)
end
AME.Say = say

-- A code error somewhere the UI carries on without the result (a suggestion, a chart, a background pass): saved for
-- /ame status and said in chat once per context and session, instead of passing for "no data".
AME.reported = {}
function AME:ReportError(context, err)
  AME_DB.stats.lastError = { context = context, error = tostring(err), at = GetServerTime() }
  if not self.reported[context] then
    self.reported[context] = true
    say("%s %s", ns.Color("bad", context .. ":"), tostring(err))
  end
end

-- money for chat lines (coin icons)
function AME.Money(copper)
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
      -- yield for whichever job is running: jobs on the same store can now interleave (normal before low priority)
      yield = function()
        local job = AME.jobs.current
        if job then
          job:Checkpoint()
        end
      end,
    })
    self.stores[shardKey] = store
  end
  return store
end

-- run fn(store) as a background job with time slicing inside the store
-- budgetMs (optional): time per frame for low-priority jobs (see Jobs:Add)
function AME:WithStore(name, shardKey, fn, onDone, budgetMs)
  local store = self:Store(shardKey)
  if not store then
    return
  end
  -- No pcall in here: WoW's Lua 5.1 can't yield across pcall; coroutine.resume already catches errors. The store
  -- yields for whichever job is running (AME:Store).
  self.jobs:Add(name, function(job)
    return fn(store, job)
  end, function(ok, result)
    if onDone then
      onDone(ok, result)
    end
  end, budgetMs)
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
    say(ns.Color("bad", L["scan read failed:"]) .. " %s", tostring(info and info.error))
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
      say("%s %s", ns.Color("bad", L["storing %s scan failed:"]:format(kind)), tostring(added))
      return
    end
    if kind ~= "full" then
      -- a search or browse: fold it into the index once searching quiets down, not after every search
      self:InvalidateIndexLater(shard)
    end
    if ns.UI and ns.UI.frame and ns.UI.frame:IsShown() then
      ns.UI:RefreshViewOptions()
    end
    if kind == "partial" and ns.UI and ns.UI.OnItemListings then
      ns.UI:OnItemListings(snap.ids) -- fresh listings: the posting price for those items can update
      if ns.UI.current == "crafting" and ns.UI.frame and ns.UI.frame:IsShown() then
        ns.UI:RefreshCrafting() -- searched items are priced at their listings right away
      end
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
    GetAuctionItemLink = function(...)
      return GetAuctionItemLink and GetAuctionItemLink(...)
    end,
  },
  learn = function(link)
    return ns.ItemCache.Learn(link)
  end,
  pair = function(link, itemID, suffix)
    return ns.ItemCache.Pair(link, itemID, suffix)
  end,
})

---------------------------------------------------------------------------------------------------------------------
-- Search the open auction house for an item, to buy it: Auctionator's shopping search when Auctionator is
-- installed (its public API), otherwise the default auction house window. Returns true when a search started.
function AME:SearchAuctionHouse(itemID)
  if not self.ahOpen then
    say(L["open the auction house first"])
    return false
  end
  -- the auction house searches base names: a variant's search lists every suffix of the item
  local name = ns.ItemCache.Name(itemID and ns.BaseID(itemID))
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
AME.handlers = handlers -- event name -> handler (the dev profiler times them)

function handlers.ADDON_LOADED(name)
  if name ~= ADDON then
    return
  end
  AME_DB = AME_DB or {}
  AME_DB.v = AME_DB.v or 1
  AME_DB.stats = AME_DB.stats or {}
  AME_DB.backfilled = AME_DB.backfilled or {}
  -- random-suffix variants: names, how links name each suffix, and their item strings (see ns.ItemKey)
  AME_DB.variants = AME_DB.variants or {}
  AME_DB.suffixMap = AME_DB.suffixMap or {}
  AME_DB.variantStrings = AME_DB.variantStrings or {}
  ns.ItemCache.Init(AME_DB.variants, AME_DB.suffixMap, AME_DB.variantStrings)
  AME.compressor = ns.Compress.New(LibStub("LibDeflate"))
  ns.Settings:Init()
  AME_DB.watch = AME_DB.watch or {}
  AME.watch = ns.Watch.New(AME_DB.watch)
  AME_DB.shopping = AME_DB.shopping or {}
  AME.shopping = ns.Shopping.New(AME_DB.shopping)
  ns.Trading:Init()
  ns.Posting:Init()
end

-- save the market indexes so the next login has data right away (AME:RestoreIndexes)
function handlers.PLAYER_LOGOUT()
  if AME:HistoryLoaded() then
    AME:SaveIndexes()
  end
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
    "PLAYER_LOGOUT",
  }) do
    pcall(events.RegisterEvent, events, e) -- tolerate events a client flavour doesn't have
  end
  if ns.Tooltip then
    ns.Tooltip:Install()
  end
  -- load history shortly after login (not during it) so tooltips have market data
  C_Timer.After(3, function()
    if AME:LoadHistory() then
      -- last session's market indexes right away; rebuilt in the background where the history changed since
      AME:RestoreIndexes()
    end
  end)
  -- build the AME window in idle moments, so opening it the first time doesn't stutter
  C_Timer.After(6, function()
    if ns.UI and ns.UI.Prebuild then
      ns.UI:Prebuild()
    end
  end)
  ns.Professions:Start()
  if ns.SyncService:Init(AME, AME.syncTransport) then
    -- hide "No player named X is currently playing" when X logged off while AME was whispering them
    local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or _G.ChatFrame_AddMessageEventFilter
    if addFilter then
      addFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
        return ns.SyncService:ChatFilter(msg)
      end)
    end
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
  -- once the auction house window is up (next frame): an open AME window docks beside it, or takes its "with the
  -- auction house" place
  C_Timer.After(0, function()
    if ns.UI and ns.UI.frame and ns.UI.frame:IsShown() then
      ns.UI:ApplyPlacement()
    end
  end)
  if ns.Settings:Get("openWithAH") and ns.UI and not (ns.UI.frame and ns.UI.frame:IsShown()) then
    ns.UI:Toggle()
    AME.openedWithAH = true -- it may close with the AH (closeWithAH)
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
  if ns.SyncService.enabled then
    ns.SyncService:OnSystemMessage(msg)
  end
end

function handlers.MAIL_INBOX_UPDATE()
  ns.Trading:ScanMail()
end

function handlers.BAG_UPDATE_DELAYED()
  ns.Trading:ScanBags()
  -- a shopping list on screen counts what you hold
  local ui = ns.UI
  if ui and ui.marketView and ui.marketView:IsShown() and ui.ShoppingSelected and ui:ShoppingSelected() then
    ui:RenderMarket()
  end
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
  if AME.openedWithAH then
    AME.openedWithAH = false
    if ns.Settings:Get("closeWithAH") and ns.UI and ns.UI.frame and ns.UI.frame:IsShown() then
      ns.UI.frame:Hide()
    end
  end
  if ns.UI and ns.UI.frame and ns.UI.frame:IsShown() then
    ns.UI:ApplyPlacement() -- back to where it sits without the auction house
  end
  if ns.UI and ns.UI.RenderArbitrage then
    ns.UI:RenderArbitrage()
  end
  if AME.ingest.reading then
    local d = AME:ScanDiag()
    d.aborted = (d.aborted or 0) + 1
    say(
      ns.Color("warn", L["the AH closed before AME finished reading the full scan; it wasn't recorded."])
        .. " "
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

-- The AH searched one item (you picked it to sell or buy - in the game's window or an addon's, like Auctionator's
-- sell tab): the Item tab shows it right away. Debounced, so a shopping list searching item after item doesn't flick
-- through them all.
local followGen = 0
local function followSearch(itemID)
  if not (itemID and ns.UI and ns.UI.FollowAuctionItem) then
    return
  end
  followGen = followGen + 1
  local gen = followGen
  C_Timer.After(0.25, function()
    if gen == followGen then
      ns.UI:FollowAuctionItem(itemID)
    end
  end)
end

function handlers.COMMODITY_SEARCH_RESULTS_UPDATED(itemID)
  AME.ingest:OnCommodityResults(itemID)
  followSearch(itemID)
end

function handlers.ITEM_SEARCH_RESULTS_UPDATED(itemKey)
  AME.ingest:OnItemResults(itemKey)
  followSearch(type(itemKey) == "table" and ns.ItemKey(itemKey.itemID, itemKey.itemSuffix) or nil)
end

events:SetScript("OnEvent", function(_, event, ...)
  local h = handlers[event]
  if h then
    h(...)
  end
end)
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
