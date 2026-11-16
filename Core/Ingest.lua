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

-- browse query sent; only an unfiltered one is a full (summary) scan
function Ingest:OnBrowseQuery(query)
  if type(query) ~= "table" then
    return
  end
  local text = query.searchString or ""
  local filtered = (query.filters and #query.filters > 0) or (query.itemClassFilters and #query.itemClassFilters > 0)
  self.browseRequested = text == "" and not filtered
end

-- AUCTION_HOUSE_BROWSE_RESULTS_UPDATED / _ADDED
function Ingest:OnBrowseResults()
  local api = self.api
  if not self.browseRequested or self.reading or not api.HasFullBrowseResults() then
    return
  end
  self.browseRequested = false
  local results = api.GetBrowseResults() or {}
  self.reading, self.aborted = true, false
  local t = self.now()
  if self.onReadStart then
    self.onReadStart(#results)
  end
  self.jobs:Add("ingest-browse", function(job)
    local byID = {}
    for i, r in ipairs(results) do
      if self.aborted then
        return nil
      end
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
    self.reading = false
    if not ok then
      self.onSnapshot(nil, t, "error", { error = snap })
    elseif snap and not self.aborted then
      self.onSnapshot(snap, t, "full", { rows = #results, skipped = 0, source = "browse" })
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
  self.requested, self.browseRequested = false, false
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
  for itemID, p in pairs(pending) do
    if p.kind == "commodity" then
      if api.HasFullCommoditySearchResults(itemID) then
        for i = 1, api.GetNumCommoditySearchResults(itemID) do
          local info = api.GetCommoditySearchResultInfo(itemID, i)
          if info and info.unitPrice and info.quantity then
            acc:Add(itemID, info.unitPrice * info.quantity, info.quantity)
            any = true
          end
        end
      end
    else
      if api.HasFullItemSearchResults(p.key) then
        for i = 1, api.GetNumItemSearchResults(p.key) do
          local info = api.GetItemSearchResultInfo(p.key, i)
          if info and info.buyoutAmount then
            acc:Add(itemID, info.buyoutAmount, info.quantity)
            any = true
          end
        end
      end
    end
  end
  if any then
    self.jobs:Add("ingest-partial", function()
      return acc:Finish()
    end, function(ok, snap)
      if ok and snap and #snap.ids > 0 then
        self.onSnapshot(snap, t, "partial", {})
      end
    end)
  end
end
