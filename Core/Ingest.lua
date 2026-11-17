-- Turns auction house data into per-item snapshots. WoW-facing but dependency-injected (api = C_AuctionHouse), so
-- it's tested with a fake API.
--
-- Full scans (M0 findings): Auctionator calls C_AuctionHouse.ReplicateItems(); REPLICATE_ITEM_LIST_UPDATE then fires
-- ~once per row for over a minute. We read the list ONCE per request, on the first event, time-sliced via Jobs.
-- Prices and counts are present even on rows with hasAllInfo == false, so no item-data loading is needed.
--
-- Browse summary scans (Auctionator's default "Full Scan" when its replicate option is off): an empty
-- C_AuctionHouse.SendBrowseQuery paged with RequestMoreBrowseResults until HasFullBrowseResults(). Each result is one
-- item key with minPrice and totalQuantity only, so the snapshot's market/median equal the minimum.
--
-- Legacy full scans (Auctionator on classic flavours with the old AH): QueryAuctionItems(..., getAll = true).
-- Auctionator unregisters every other frame's AUCTION_ITEM_LIST_UPDATE during its scan, so instead of waiting for the
-- event we poll GetNumAuctionItems("list") until the list is complete and stable, then read it the same way.
-- Legacy rows have count, buyout and itemID at the same positions as replicate rows.
--
-- Searches / sell-tab rechecks: commodity and item search results are collected per item and flushed as one
-- "partial" snapshot after SETTLE seconds without new results. Incomplete result sets (only the cheapest page) are
-- skipped, because they would bias the market price low.
local _, ns = ...

local Ingest = {}
Ingest.__index = Ingest
ns.Ingest = Ingest

Ingest.SETTLE = 1.0
Ingest.BROWSE_SETTLE = 2.0 -- browse pages arrive as the list scrolls; record a partial once they pause
Ingest.POLL = 1.0 -- seconds between legacy list checks
Ingest.POLL_LIMIT = 180 -- give up waiting for a getAll list after this many polls

-- opts: api, jobs, now, after(seconds, fn), onSnapshot(snap, t, kind, info), onReadStart(rows) (optional),
-- legacy (optional: the legacy AH functions { GetNumAuctionItems, GetAuctionItemInfo })
function Ingest.New(opts)
  return setmetatable({
    api = assert(opts.api),
    legacy = opts.legacy,
    jobs = assert(opts.jobs),
    now = assert(opts.now),
    after = assert(opts.after),
    onSnapshot = assert(opts.onSnapshot),
    onReadStart = opts.onReadStart,
    requested = false,
    reading = false,
    aborted = false,
    pending = {}, -- itemID -> { kind = "commodity"|"item", key = itemID|itemKey }
    generation = 0,
  }, Ingest)
end

---------------------------------------------------------------------------------------------------------------------
-- full scans

function Ingest:OnReplicateRequested()
  self.requested = true
end

function Ingest:OnReplicateUpdate()
  if not self.requested or self.reading then
    return
  end
  self.requested = false
  local api = self.api
  local total = api.GetNumReplicateItems() or 0
  self:read(0, total - 1, total, api.GetReplicateItemInfo)
end

-- Browse queries. An unfiltered one paged to the end is a full (summary) scan. Everything else - category browsing,
-- text searches in the browse list, a full scan you only scrolled part of - is recorded as a partial scan once
-- results stop arriving for BROWSE_SETTLE seconds. Only rows not recorded yet for this query are read, so scrolling
-- further later adds the new items without double-counting. Browse rows carry each item's lowest price and total
-- quantity, which is complete per item however much of the list was shown.
function Ingest:OnBrowseQuery(query)
  if type(query) ~= "table" then
    return
  end
  local text = query.searchString or ""
  local filtered = (query.filters and #query.filters > 0) or (query.itemClassFilters and #query.itemClassFilters > 0)
  self.browseRequested = text == "" and not filtered
  self.browseActive = true
  self.browseRecorded = 0
  self.browseGen = (self.browseGen or 0) + 1
end

-- AUCTION_HOUSE_BROWSE_RESULTS_UPDATED / _ADDED
function Ingest:OnBrowseResults()
  local api = self.api
  if not self.browseActive then
    return
  end
  if self.browseRequested and not self.reading and api.HasFullBrowseResults() then
    self.browseRequested, self.browseActive = false, false
    self.browseGen = (self.browseGen or 0) + 1
    self:readBrowse(api.GetBrowseResults() or {}, 1, "full")
    return
  end
  -- partial: once the results settle
  self.browseGen = (self.browseGen or 0) + 1
  local gen = self.browseGen
  self.after(Ingest.BROWSE_SETTLE, function()
    if gen ~= self.browseGen or not self.browseActive then
      return
    end
    local results = api.GetBrowseResults() or {}
    local first = (self.browseRecorded or 0) + 1
    if #results >= first then
      self.browseRecorded = #results
      self:readBrowse(results, first, "partial")
    end
  end)
end

-- browse rows results[first..] -> one snapshot (lowest price and quantity per item), time-sliced
function Ingest:readBrowse(results, first, kind)
  local full = kind == "full"
  if full then
    self.reading, self.aborted = true, false
  end
  local t = self.now()
  if full and self.onReadStart then
    self.onReadStart(#results)
  end
  self.jobs:Add("ingest-browse-" .. kind, function(job)
    local byID = {}
    for i = first, #results do
      if full and self.aborted then
        return nil
      end
      local r = results[i]
      local id = r.itemKey and r.itemKey.itemID
      if id and id > 0 and r.minPrice and r.minPrice > 0 and (r.totalQuantity or 0) > 0 then
        local e = byID[id]
        if not e then
          byID[id] = { min = r.minPrice, qty = r.totalQuantity, keys = 1 }
        else
          e.min = math.min(e.min, r.minPrice)
          e.qty = e.qty + r.totalQuantity
          e.keys = e.keys + 1
        end
      end
      if i % 64 == 0 then
        job:Checkpoint()
      end
    end
    local ids = {}
    for id in pairs(byID) do
      ids[#ids + 1] = id
    end
    table.sort(ids)
    local snap = { ids = ids, min = {}, market = {}, median = {}, qty = {}, auctions = {}, skipped = 0 }
    for i, id in ipairs(ids) do
      local e = byID[id]
      snap.min[i], snap.market[i], snap.median[i] = e.min, e.min, e.min
      snap.qty[i], snap.auctions[i] = e.qty, e.keys
    end
    return snap
  end, function(ok, snap)
    if full then
      self.reading = false
    end
    if not ok then
      self.onSnapshot(nil, t, "error", { error = snap })
    elseif snap and #snap.ids > 0 and not (full and self.aborted) then
      self.onSnapshot(snap, t, kind, { rows = #results - first + 1, skipped = 0, source = "browse" })
    end
  end)
end

-- legacy getAll query sent (hook on QueryAuctionItems with getAll = true)
function Ingest:OnGetAllRequested()
  if not self.legacy or self.reading then
    return
  end
  self.pollGen = (self.pollGen or 0) + 1
  local gen, polls, last = self.pollGen, 0, nil
  local legacy = self.legacy
  local function poll()
    if gen ~= self.pollGen or self.reading then
      return
    end
    polls = polls + 1
    local batch, total = legacy.GetNumAuctionItems("list")
    batch, total = batch or 0, total or 0
    -- complete (one batch holds everything) and unchanged since the last poll
    if batch > 0 and batch >= total and batch == last then
      self.pollGen = gen + 1
      self:read(0, batch, batch, function(i)
        return legacy.GetAuctionItemInfo("list", i)
      end)
      return
    end
    last = batch
    if polls < Ingest.POLL_LIMIT then
      self.after(Ingest.POLL, poll)
    end
  end
  self.after(Ingest.POLL, poll)
end

-- read rows first..last (missing rows are skipped) into one full snapshot, time-sliced
function Ingest:read(first, last, total, getInfo)
  self.reading, self.aborted = true, false
  local t = self.now()
  if self.onReadStart then
    self.onReadStart(total)
  end
  self.jobs:Add("ingest-full", function(job)
    local acc = ns.Stats.NewAccumulator()
    for i = first, last do
      if self.aborted then
        return nil
      end
      local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = getInfo(i)
      if itemID and itemID > 0 then
        acc:Add(itemID, buyout, count)
      end
      if i % 64 == 0 then
        job:Checkpoint()
      end
    end
    if self.aborted then
      return nil
    end
    job:Checkpoint()
    return acc:Finish()
  end, function(ok, snap)
    self.reading = false
    if not ok then
      self.onSnapshot(nil, t, "error", { error = snap })
    elseif snap and not self.aborted then
      self.onSnapshot(snap, t, "full", { rows = total, skipped = snap.skipped })
    end
  end)
end

function Ingest:OnAuctionHouseClosed()
  if self.reading then
    self.aborted = true
  end
  self.requested, self.browseRequested, self.browseActive = false, false, false
  self.browseGen = (self.browseGen or 0) + 1
  self.pollGen = (self.pollGen or 0) + 1 -- stop waiting for a getAll list
end

---------------------------------------------------------------------------------------------------------------------
-- searches

function Ingest:queue(itemID, kind, key)
  self.pending[itemID] = { kind = kind, key = key }
  self.generation = self.generation + 1
  local gen = self.generation
  self.after(Ingest.SETTLE, function()
    if gen == self.generation then
      self:flush()
    end
  end)
end

function Ingest:OnCommodityResults(itemID)
  if itemID then
    self:queue(itemID, "commodity", itemID)
  end
end

function Ingest:OnItemResults(itemKey)
  if itemKey and itemKey.itemID then
    self:queue(itemKey.itemID, "item", itemKey)
  end
end

function Ingest:flush()
  local pending = self.pending
  self.pending = {}
  local api, t = self.api, self.now()
  local acc = ns.Stats.NewAccumulator()
  local any = false
  local books = {} -- itemID -> order book (price tiers) from this search
  for itemID, p in pairs(pending) do
    local tiers = {}
    if p.kind == "commodity" then
      if api.HasFullCommoditySearchResults(itemID) then
        for i = 1, api.GetNumCommoditySearchResults(itemID) do
          local info = api.GetCommoditySearchResultInfo(itemID, i)
          if info and info.unitPrice and info.quantity then
            acc:Add(itemID, info.unitPrice * info.quantity, info.quantity)
            tiers[#tiers + 1] = { info.unitPrice, info.quantity }
            any = true
          end
        end
      end
    else
      if api.HasFullItemSearchResults(p.key) then
        for i = 1, api.GetNumItemSearchResults(p.key) do
          local info = api.GetItemSearchResultInfo(p.key, i)
          if info and info.buyoutAmount then
            -- a row groups identical auctions: quantity of them, buyoutAmount of one (Forever, per AHDB's probes)
            local count = info.quantity or 1
            acc:Add(itemID, info.buyoutAmount * count, count)
            tiers[#tiers + 1] = { info.buyoutAmount, count }
            any = true
          end
        end
      end
    end
    if #tiers > 0 and ns.Depth then
      books[itemID] = ns.Depth.Book(tiers, t)
    end
  end
  if any then
    self.jobs:Add("ingest-partial", function()
      return acc:Finish()
    end, function(ok, snap)
      if ok and snap and #snap.ids > 0 then
        self.onSnapshot(snap, t, "partial", { books = books })
      end
    end)
  end
end
