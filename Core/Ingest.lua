-- Turns auction house data into per-item snapshots. WoW-facing but dependency-injected (api = C_AuctionHouse), so
-- it's tested with a fake API.
--
-- Full scans (M0 findings): Auctionator calls C_AuctionHouse.ReplicateItems(); REPLICATE_ITEM_LIST_UPDATE then fires
-- ~once per row for over a minute. We read the list ONCE per request, on the first event, time-sliced via Jobs.
-- Prices and counts are present even on rows with hasAllInfo == false, so no item-data loading is needed.
--
-- Searches / sell-tab rechecks: commodity and item search results are collected per item and flushed as one
-- "partial" snapshot after SETTLE seconds without new results. Incomplete result sets (only the cheapest page) are
-- skipped, because they would bias the market price low.
local _, ns = ...

local Ingest = {}
Ingest.__index = Ingest
ns.Ingest = Ingest

Ingest.SETTLE = 1.0

-- opts: api, jobs, now, after(seconds, fn), onSnapshot(snap, t, kind, info)
function Ingest.New(opts)
  return setmetatable({
    api = assert(opts.api),
    jobs = assert(opts.jobs),
    now = assert(opts.now),
    after = assert(opts.after),
    onSnapshot = assert(opts.onSnapshot),
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
  self.requested, self.reading, self.aborted = false, true, false
  local api, t = self.api, self.now()
  local total = api.GetNumReplicateItems() or 0
  self.jobs:Add("ingest-full", function(job)
    local acc = ns.Stats.NewAccumulator()
    for i = 0, total - 1 do
      if self.aborted then
        return nil
      end
      local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = api.GetReplicateItemInfo(i)
      if itemID then
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
  self.requested = false
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
