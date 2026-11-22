-- Searching the auction house for many items, one after another (the AME shopping tab, Search AH on a recipe), and
-- buying from the results. Without Auctionator the game's window searches one name at a time; this sends one search
-- per item at the pace the game allows (it says when it's ready for the next), and keeps each item's listings.
--
--   AHSearch:Start(keys, onChange)   search them in turn; onChange() after each answer
--   AHSearch.results[key]  { rows = { { price (each), qty, auctionID?, mine?, timeLeft?, band? } } cheapest first,
--                            commodity, at }
--   AHSearch.TimeLeft(book, row, now)  a listing's time left now: seconds, or the game's band; nil when not known
--   AHSearch:Buy(key, qty, row)      commodities: ask the game for the price of qty (then Confirm); gear: row's auction
--   AHSearch:Confirm()               buy what Buy priced (the game wants a click for each purchase)
-- Book is pure (the client API is passed in), so it's tested with a fake C_AuctionHouse.
local _, ns = ...

local S = { queue = {}, results = {}, done = 0, total = 0 }
ns.AHSearch = S

S.TIMEOUT = 6 -- seconds to wait for an answer before moving on
S.GAP = 0.15 -- seconds between searches when the game is ready

-- A listing's time left: the game gives commodities the seconds left at the search (timeLeftSeconds) and gear a
-- band (Enum.AuctionHouseTimeLeftBand: 0 under 30 min, 1 up to 2 h, 2 up to 12 h, 3 up to 48 h). Returns the
-- seconds left now (nil once they've run out: it may have sold or expired), or nil and the band; nil when the game
-- said neither.
function S.TimeLeft(book, row, now)
  if row.timeLeft then
    local since = (book and book.at and now) and math.max(0, now - book.at) or 0 -- searched this long ago
    local left = row.timeLeft - since
    return left > 0 and left or nil
  end
  return nil, row.band
end

-- the listings of an item the game has search results for: { commodity, rows = { { price, qty, auctionID } } }
function S.Book(api, key)
  local id, suffix = ns.BaseID(key), math.floor(key / ns.SUFFIX_STEP)
  local rows = {}
  local n = api.GetNumCommoditySearchResults and api.GetNumCommoditySearchResults(id) or 0
  if n > 0 then
    for i = 1, n do
      local info = api.GetCommoditySearchResultInfo(id, i)
      if info and info.unitPrice and info.quantity then
        rows[#rows + 1] = {
          price = info.unitPrice,
          qty = info.quantity,
          mine = (info.numOwnerItems or 0) > 0,
          timeLeft = info.timeLeftSeconds,
        }
      end
    end
    table.sort(rows, function(a, b)
      return a.price < b.price
    end)
    return { commodity = true, rows = rows }
  end
  local itemKey = api.MakeItemKey and api.MakeItemKey(id, 0, suffix)
  n = itemKey and api.GetNumItemSearchResults and api.GetNumItemSearchResults(itemKey) or 0
  for i = 1, n do
    local info = api.GetItemSearchResultInfo(itemKey, i)
    local q = info and (info.quantity or 1)
    if info and info.buyoutAmount and q > 0 then
      rows[#rows + 1] = {
        price = math.floor(info.buyoutAmount / q),
        qty = q,
        total = info.buyoutAmount,
        auctionID = info.auctionID,
        mine = info.containsOwnerItem or nil,
        timeLeft = info.timeLeftSeconds, -- not on every client: the band otherwise
        band = info.timeLeft,
      }
    end
  end
  table.sort(rows, function(a, b)
    return a.price < b.price
  end)
  return { commodity = false, rows = rows }
end

local function api()
  return C_AuctionHouse
end

function S:Busy()
  return self.current ~= nil or #self.queue > 0
end

function S:Stop()
  self.queue, self.current = {}, nil
end

local function notify()
  if S.onChange then
    S.onChange()
  end
end

local step
local function answered(key)
  local a = api()
  if a then
    local book = S.Book(a, key)
    book.at = GetServerTime()
    S.results[key] = book
  end
  S.current = nil
  S.done = S.done + 1
  notify()
  C_Timer.After(S.GAP, step)
end

step = function()
  if S.current then
    return
  end
  local key = table.remove(S.queue, 1)
  if not key then
    notify()
    return
  end
  local a = api()
  if not (a and a.SendSearchQuery and ns.AME.ahOpen) then
    S:Stop()
    return
  end
  if a.IsThrottledMessageSystemReady and not a.IsThrottledMessageSystemReady() then
    table.insert(S.queue, 1, key) -- the game says when it's ready (AUCTION_HOUSE_THROTTLED_SYSTEM_READY)
    S.waiting = true
    C_Timer.After(1, function() -- ... and if it doesn't, try again in a second
      S:OnReady()
    end)
    return
  end
  S.current = key
  local itemKey = a.MakeItemKey(ns.BaseID(key), 0, math.floor(key / ns.SUFFIX_STEP))
  local sorts = {
    { sortOrder = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0, reverseSort = false },
  }
  pcall(a.SendSearchQuery, itemKey, sorts, true)
  C_Timer.After(S.TIMEOUT, function()
    if S.current == key then -- no answer (nothing listed answers nothing for some items): on to the next
      S.results[key] = { rows = {}, at = GetServerTime() }
      S.current, S.done = nil, S.done + 1
      notify()
      step()
    end
  end)
end

function S:Start(keys, onChange)
  self.onChange = onChange or self.onChange
  self.queue, self.done, self.total = {}, 0, #keys
  for _, k in ipairs(keys) do
    self.queue[#self.queue + 1] = k
  end
  step()
end

-- search results arrived (the game's events)
function S:OnCommodity(itemID)
  if self.current and ns.BaseID(self.current) == itemID then
    answered(self.current)
  end
end

function S:OnItem(itemKey)
  local key = type(itemKey) == "table" and ns.ItemKey(itemKey.itemID, itemKey.itemSuffix)
  if self.current and key and ns.BaseID(self.current) == ns.BaseID(key) then
    answered(self.current)
  end
end

function S:OnReady()
  if self.waiting then
    self.waiting = false
    step()
  end
end

-- buying

-- commodities: ask the game what qty costs (it answers with COMMODITY_PRICE_UPDATED); gear: the listing (row) itself
function S:Buy(key, qty, row)
  local a = api()
  if not a then
    return false
  end
  local book = self.results[key]
  if book and book.commodity then
    self.pending = { key = key, qty = qty, commodity = true }
    pcall(a.StartCommoditiesPurchase, ns.BaseID(key), qty)
  elseif row and row.auctionID then
    self.pending = { key = key, qty = row.qty, total = row.total, row = row }
  else
    return false
  end
  notify()
  return true
end

-- buy what Buy priced: the second click (the game asks for one per purchase)
function S:Confirm()
  local p, a = self.pending, api()
  if not (p and a) then
    return false
  end
  if p.commodity then
    if not p.total then
      return false -- the game hasn't said the price yet
    end
    pcall(a.ConfirmCommoditiesPurchase, ns.BaseID(p.key), p.qty)
  else
    pcall(a.PlaceBid, p.row.auctionID, p.row.total)
  end
  p.sent = true
  notify()
  return true
end

function S:Cancel()
  local a = api()
  if self.pending and self.pending.commodity and a and a.CancelCommoditiesPurchase then
    pcall(a.CancelCommoditiesPurchase)
  end
  self.pending = nil
  notify()
end

local function finished(ok)
  local p = S.pending
  S.pending = nil
  if p then
    S.last = { key = p.key, qty = p.qty, ok = ok }
    if ok then
      if S.onBought then
        S.onBought(p.key, p.qty) -- the list it was bought for counts it off
      end
      S:Start({ p.key }) -- what's left of it now
    end
  end
  notify()
end

local frame = CreateFrame and CreateFrame("Frame")
if frame then
  for _, e in ipairs({
    "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
    "COMMODITY_SEARCH_RESULTS_UPDATED",
    "ITEM_SEARCH_RESULTS_UPDATED",
    "COMMODITY_PRICE_UPDATED",
    "COMMODITY_PURCHASE_SUCCEEDED",
    "COMMODITY_PURCHASE_FAILED",
    "AUCTION_HOUSE_PURCHASE_COMPLETED",
    "AUCTION_HOUSE_CLOSED",
  }) do
    pcall(frame.RegisterEvent, frame, e)
  end
  frame:SetScript("OnEvent", function(_, event, a, b)
    if event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
      S:OnReady()
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
      S:OnCommodity(a)
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
      S:OnItem(a)
    elseif event == "COMMODITY_PRICE_UPDATED" then
      if S.pending and S.pending.commodity then
        S.pending.unit, S.pending.total = a, b
        notify()
      end
    elseif event == "COMMODITY_PURCHASE_SUCCEEDED" or event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
      finished(true)
    elseif event == "COMMODITY_PURCHASE_FAILED" then
      finished(false)
    elseif event == "AUCTION_HOUSE_CLOSED" then
      S:Stop()
      S.pending = nil
    end
  end)
end
