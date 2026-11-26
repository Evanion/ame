-- Turns auction house data into per-item snapshots. WoW-facing but dependency-injected (api = C_AuctionHouse), so
-- it's tested with a fake API.
--
-- Full scans (M0 findings): Auctionator calls C_AuctionHouse.ReplicateItems(); REPLICATE_ITEM_LIST_UPDATE then fires
-- ~once per row for over a minute. We read the list ONCE per request, on the first event, time-sliced via Jobs.
-- Prices and counts are present even on rows with hasAllInfo == false, so no item-data loading is needed.
--
-- Browse summary scans (Auctionator's default "Full Scan" when its replicate option is off): an empty
-- C_AuctionHouse.SendBrowseQuery paged with RequestMoreBrowseResults until HasFullBrowseResults(). Each result is one
-- item key with minPrice and totalQuantity only, so the snapshot's market/median equal the minimum (Spread then
-- sets the market from each item's usual spread above its cheapest listing).
--
-- Legacy full scans (Auctionator on classic flavours with the old AH): QueryAuctionItems(..., getAll = true).
-- Auctionator unregisters every other frame's AUCTION_ITEM_LIST_UPDATE during its scan, so instead of waiting for the
-- event we poll GetNumAuctionItems("list") until the list is complete and stable, then read it the same way.
-- Legacy rows have count, buyout and itemID at the same positions as replicate rows.
--
-- Random-suffix gear: every listing is recorded under its item key (ns.ItemKey: item ID plus suffix), read from the
-- row's link (full scans, searches) or its itemKey (browse rows), so "of Magic" and "of the Monkey" get separate
-- prices. Links also teach the item cache the variants' names (opts.learn).
--
-- Searches / sell-tab rechecks: commodity and item search results are collected per item and flushed as one
-- "partial" snapshot after SETTLE seconds without new results. Incomplete result sets (only the cheapest page) are
-- skipped, because they would bias the market price low.
--
-- Legacy searches (any QueryAuctionItems without getAll: Auctionator's shopping and selling searches on Forever, the
-- classic browse window): each page that arrives (AUCTION_ITEM_LIST_UPDATE) is copied, up to 50 rows, and once the
-- page holding the last result is in, every page of that query is recorded as one partial snapshot. A query with
-- other parameters, a getAll scan or the AH closing drops the pages collected so far; a set with a page missing is
-- never recorded, like an incomplete modern search.
local _, ns = ...

local Ingest = {}
Ingest.__index = Ingest
ns.Ingest = Ingest

Ingest.SETTLE = 0.4 -- a search's results arrive together; record them once they stop
Ingest.BROWSE_SETTLE = 2.0 -- browse pages arrive as the list scrolls; record a partial once they pause
Ingest.POLL = 1.0 -- seconds between legacy list checks
Ingest.POLL_LIMIT = 180 -- give up waiting for a getAll list after this many polls
Ingest.PAGE_SIZE = 50 -- legacy search results per page (NUM_AUCTION_ITEMS_PER_PAGE)

-- opts: api, jobs, now, after(seconds, fn), onSnapshot(snap, t, kind, info), onReadStart(rows) (optional),
-- legacy (optional: the legacy AH functions { GetNumAuctionItems, GetAuctionItemInfo, GetAuctionItemLink }),
-- learn(link) -> item key (optional: remembers a variant's name; default ns.ItemIDFrom),
-- pair(link, itemID, suffix) -> item key (optional: a link that belongs to an auction item key; see ItemCache.Pair)
function Ingest.New(opts)
  return setmetatable({
    api = assert(opts.api),
    legacy = opts.legacy,
    jobs = assert(opts.jobs),
    now = assert(opts.now),
    after = assert(opts.after),
    onSnapshot = assert(opts.onSnapshot),
    onReadStart = opts.onReadStart,
    learn = opts.learn or ns.ItemIDFrom,
    pair = opts.pair,
    requested = false,
    reading = false,
    aborted = false,
    pending = {}, -- item key -> { kind = "commodity"|"item", id = itemID, key = itemID|itemKey }
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
  self:read(0, total - 1, total, api.GetReplicateItemInfo, api.GetReplicateItemLink)
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
      local id = r.itemKey and ns.ItemKey(r.itemKey.itemID, r.itemKey.itemSuffix)
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
  self.legacySearch = nil -- a search's pages collected so far are dropped (its list is gone)
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
      end, legacy.GetAuctionItemLink and function(i)
        return legacy.GetAuctionItemLink("list", i)
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

-- a row's item key: from its link when there is one (the suffix), else the plain item ID
function Ingest:keyOf(itemID, link)
  if link then
    local key = self.learn(link)
    if key and ns.BaseID(key) == itemID then
      return key
    end
  end
  return itemID
end

-- read rows first..last (missing rows are skipped) into one full snapshot, time-sliced. getLink(i) is optional.
function Ingest:read(first, last, total, getInfo, getLink)
  self.reading, self.aborted = true, false
  self.progress = { done = 0, total = total } -- read so far (the window's status row shows it)
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
        acc:Add(getLink and self:keyOf(itemID, getLink(i)) or itemID, buyout, count)
      end
      if i % 64 == 0 then
        self.progress.done = i - first + 1
        job:Checkpoint()
      end
    end
    if self.aborted then
      return nil
    end
    self.progress.done = total
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
  self.legacySearch = nil -- a legacy search's pages so far: incomplete, dropped
end

---------------------------------------------------------------------------------------------------------------------
-- searches

function Ingest:queue(itemID, kind, key, suffix)
  self.pending[ns.ItemKey(itemID, suffix)] = { kind = kind, id = itemID, key = key }
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
    self:queue(itemKey.itemID, "item", itemKey, itemKey.itemSuffix)
  end
end

function Ingest:flush()
  local pending = self.pending
  self.pending = {}
  local api, t = self.api, self.now()
  local acc = ns.Stats.NewAccumulator()
  local any = false
  local books = {} -- item key -> order book (price tiers) from this search
  for pkey, p in pairs(pending) do
    local itemID = p.id
    local tiers = {}
    local byKey = {} -- item search rows: one book per variant (a search can list several suffixes)
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
            -- the row's own item key names its suffix; its link learns how links name it
            local rowKey = info.itemKey
            local key
            if rowKey and (rowKey.itemSuffix or 0) ~= 0 then
              key = ns.ItemKey(itemID, rowKey.itemSuffix)
              if info.itemLink and self.pair then
                self.pair(info.itemLink, itemID, rowKey.itemSuffix)
              end
            else
              key = info.itemLink and self:keyOf(itemID, info.itemLink) or pkey
            end
            acc:Add(key, info.buyoutAmount * count, count)
            byKey[key] = byKey[key] or {}
            table.insert(byKey[key], { info.buyoutAmount, count })
            any = true
          end
        end
      end
    end
    if #tiers > 0 and ns.Depth then
      books[pkey] = ns.Depth.Book(tiers, t)
    end
    for key, list in pairs(byKey) do
      if ns.Depth then
        books[key] = ns.Depth.Book(list, t)
      end
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

---------------------------------------------------------------------------------------------------------------------
-- legacy searches (QueryAuctionItems without getAll)

-- what makes two queries the same search: every parameter but the page (filterData by content, not identity)
local function querySig(name, minLevel, maxLevel, isUsable, quality, exact, filterData)
  local parts = { tostring(name or ""), tostring(minLevel), tostring(maxLevel), tostring(isUsable) }
  parts[#parts + 1] = tostring(quality)
  parts[#parts + 1] = tostring(exact)
  if type(filterData) == "table" then
    for _, f in ipairs(filterData) do
      if type(f) == "table" then
        parts[#parts + 1] = tostring(f.classID) .. "." .. tostring(f.subClassID) .. "." .. tostring(f.inventoryType)
      else
        parts[#parts + 1] = tostring(f)
      end
    end
  else
    parts[#parts + 1] = tostring(filterData)
  end
  return table.concat(parts, "|")
end

-- the same rows (the list still showing the previous page when the event fires)
local function samePage(a, b)
  if #a ~= #b then
    return false
  end
  for i, r in ipairs(a) do
    local o = b[i]
    if r[1] ~= o[1] or r[2] ~= o[2] or r[3] ~= o[3] or r[4] ~= o[4] then
      return false
    end
  end
  return true
end

-- a legacy search page asked for (hook on QueryAuctionItems with getAll false). Page 0, or a query with other
-- parameters, starts a new set of pages; the previous set is dropped.
function Ingest:OnLegacyQuery(name, minLevel, maxLevel, page, isUsable, quality, exact, filterData)
  if not self.legacy then
    return
  end
  page = tonumber(page) or 0
  local sig = querySig(name, minLevel, maxLevel, isUsable, quality, exact, filterData)
  local s = self.legacySearch
  if not s or s.sig ~= sig or page == 0 then
    s = { sig = sig, pages = {} }
    self.legacySearch = s
  end
  s.want = page
  self.legacyGen = (self.legacyGen or 0) + 1 -- a flush waiting for the last page is off: more pages are coming
end

-- AUCTION_ITEM_LIST_UPDATE: copy the page the last query asked for; once the last page is in, record the set
function Ingest:OnLegacyListUpdate()
  local s, legacy = self.legacySearch, self.legacy
  if not s or not s.want or not legacy then
    return
  end
  local batch, total = legacy.GetNumAuctionItems("list")
  batch, total = batch or 0, total or 0
  if batch > Ingest.PAGE_SIZE or (batch == 0 and total > 0) then
    return -- not a search page (or not loaded yet)
  end
  local page = s.want
  local rows = {}
  for i = 1, batch do
    local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = legacy.GetAuctionItemInfo("list", i)
    local link = legacy.GetAuctionItemLink and legacy.GetAuctionItemLink("list", i)
    rows[i] = { itemID or 0, buyout or 0, count or 0, link or false }
  end
  local prev = s.pages[page - 1]
  if prev and samePage(rows, prev) then
    return -- still the previous page: this page's results haven't arrived yet
  end
  s.pages[page], s.total = rows, total
  if (page + 1) * Ingest.PAGE_SIZE < total then
    return -- more pages to come
  end
  -- the last page: record once its rows settle (later events for it re-read it and wait again)
  self.legacyGen = (self.legacyGen or 0) + 1
  local gen = self.legacyGen
  self.after(Ingest.SETTLE, function()
    if gen == self.legacyGen and self.legacySearch == s then
      self.legacySearch = nil
      self:flushLegacy(s, page)
    end
  end)
end

-- pages 0..last of one search -> one partial snapshot (and order books), time-sliced. A missing page: nothing.
function Ingest:flushLegacy(s, last)
  for p = 0, last do
    if not s.pages[p] then
      return
    end
  end
  local t = self.now()
  self.jobs:Add("ingest-legacy-search", function(job)
    local acc = ns.Stats.NewAccumulator()
    local tiers = {} -- item key -> { unit price, count } per listing
    local n = 0
    for p = 0, last do
      for _, r in ipairs(s.pages[p]) do
        local itemID, buyout, count, link = r[1], r[2], r[3], r[4]
        if itemID > 0 then
          local key = link and self:keyOf(itemID, link) or itemID
          acc:Add(key, buyout, count) -- no buyout (bid only): skipped
          if buyout > 0 then
            local c = count > 0 and count or 1
            tiers[key] = tiers[key] or {}
            table.insert(tiers[key], { math.floor(buyout / c), c })
          end
        end
        n = n + 1
        if n % 64 == 0 then
          job:Checkpoint()
        end
      end
    end
    local books = {}
    if ns.Depth then
      for key, list in pairs(tiers) do
        books[key] = ns.Depth.Book(list, t)
      end
    end
    return { snap = acc:Finish(), books = books }
  end, function(ok, out)
    if not ok then
      ns.ReportError(out) -- to the game's error handler (BugSack)
    elseif out and out.snap and #out.snap.ids > 0 then
      self.onSnapshot(out.snap, t, "partial", { books = out.books, source = "legacy" })
    end
  end)
end
