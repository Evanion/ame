-- WoW glue for the pricing model (Pricing.lua): learns every item's market from your scans, records what you post
-- and how it went, and answers "what should I post this at?" for the item view and the AH sell window.
--
--   AME_DB.pricing[shard][itemID] = Pricing.Encode(profile)     what each item's market does
--   AME_DB.listings = { { itemID, name, unit, qty, hours, t, shard, chance }, ... }   your posts awaiting an outcome
local _, ns = ...

local Posting = { cache = {}, priors = {} }
ns.Posting = Posting

Posting.BOOK_AGE = 1800 -- a search's order book is used for this long (seconds)
Posting.SCAN_AGE = 48 * 3600 -- a scan's ladder stands in for the book for this long
Posting.PRIOR_AGE = 600 -- category behaviour is recomputed at most this often
Posting.KEEP = 30 * 86400 -- profiles of items not seen for this long are dropped

local function itemName(itemID)
  return ns.ItemCache.Name(itemID)
end

local function now()
  return GetServerTime()
end

function Posting:Init()
  AME_DB.pricing = AME_DB.pricing or {}
  AME_DB.listings = AME_DB.listings or {}
  local cutoff = now() - Posting.KEEP
  for _, items in pairs(AME_DB.pricing) do
    for id, s in pairs(items) do
      local t = ns.Pricing.LastSeen(s)
      if t and t < cutoff then
        items[id] = nil
      end
    end
  end
  self:HookPosting()
end

---------------------------------------------------------------------------------------------------------------------
-- profiles

function Posting:Profile(shard, itemID)
  local cache = self.cache[shard]
  if not cache then
    cache = {}
    self.cache[shard] = cache
  end
  local p = cache[itemID]
  if not p then
    local s = AME_DB.pricing[shard] and AME_DB.pricing[shard][itemID]
    p = s and ns.Pricing.Decode(s) or ns.Pricing.NewProfile()
    cache[itemID] = p
  end
  return p
end

-- a profile without keeping it: full scans and category averages touch every item, and holding thousands of decoded
-- profiles for the session (~7.5 MB per house) buys nothing - only items you look at are cached (Profile)
function Posting:Peek(shard, itemID)
  local cached = self.cache[shard] and self.cache[shard][itemID]
  if cached then
    return cached
  end
  local s = AME_DB.pricing[shard] and AME_DB.pricing[shard][itemID]
  return s and ns.Pricing.Decode(s) or ns.Pricing.NewProfile()
end

function Posting:Save(shard, itemID, p)
  AME_DB.pricing[shard] = AME_DB.pricing[shard] or {}
  AME_DB.pricing[shard][itemID] = ns.Pricing.Encode(p)
end

-- A scan you ran (not synced ones: the model learns from consecutive scans of one market). Full scans touch every
-- item, so they're processed in the background.
function Posting:OnSnapshot(shard, snap, t)
  if not (snap and snap.ids and #snap.ids > 0) then
    return
  end
  local function observe(job)
    for i, id in ipairs(snap.ids) do
      local p = self:Peek(shard, id)
      ns.Pricing.Observe(p, { t = t, min = snap.min[i], qty = snap.qty[i], ladder = snap.ladder and snap.ladder[i] })
      self:Save(shard, id, p)
      if job and i % 50 == 0 then
        job:Checkpoint()
      end
    end
  end
  if #snap.ids <= 50 then
    observe()
  else
    ns.AME.jobs:Add("pricing-observe", observe, function(ok, err)
      if not ok then
        ns.AME:ReportError("pricing", err)
      end
    end)
    self.priors[shard] = nil -- a full scan changes many items: recompute category behaviour
  end
end

-- what items of this one's category (item class) typically do
function Posting:Prior(shard, itemID)
  local info = ns.ItemCache and ns.ItemCache.Get(itemID)
  local class = info and info.classID or -1
  local cached = self.priors[shard] and self.priors[shard][class]
  if cached and now() - cached.at < Posting.PRIOR_AGE then
    return cached.prior
  end
  local list = {}
  for id, s in pairs(AME_DB.pricing[shard] or {}) do
    if ns.Pricing.Samples(s) >= 3 then
      local other = ns.ItemCache and ns.ItemCache.Get(id)
      if (other and other.classID or -1) == class then
        list[#list + 1] = self:Peek(shard, id)
      end
    end
  end
  local prior = ns.Pricing.Prior(list)
  self.priors[shard] = self.priors[shard] or {}
  self.priors[shard][class] = { prior = prior, at = now() }
  return prior
end

---------------------------------------------------------------------------------------------------------------------
-- suggestions

local function summaryFor(shard, itemID)
  local AME = ns.AME
  local index = AME:CachedIndex(shard)
  if not index and AME.IndexFor then
    AME:IndexFor(shard, function() end) -- build it for next time
  end
  return index and index.items[itemID]
end

-- listing times: the game's own labels say how long each option is ("24 Hours"); classic rules otherwise
function Posting.DurationHours(index)
  local key = ({ "AUCTION_DURATION_ONE", "AUCTION_DURATION_TWO", "AUCTION_DURATION_THREE" })[index or 0]
  local label = key and _G[key]
  return type(label) == "string" and tonumber(label:match("%d+")) or ({ 2, 8, 24 })[index or 3] or 24
end

-- Everything the model needs for one item at one auction house, and its suggestion.
--   qty: units you post; hours: listing time; returns advice (see Pricing.Suggest) plus .book, .params, or nil
function Posting:Suggest(shard, itemID, qty, hours)
  local _, house = ns.SplitShard(shard)
  house = house or ns.AME:CurrentHouse()
  local p = self:Profile(shard, itemID)
  local s = summaryFor(shard, itemID)
  local params = ns.Pricing.Params(p, self:Prior(shard, itemID), s)
  local book = ns.AME:BookFor(shard, itemID, Posting.BOOK_AGE)
  if not book and p.last and now() - p.last.t < Posting.SCAN_AGE then
    book = ns.Pricing.BookFromObs(p.last)
  end
  if not book and s and s.min then
    book = { prices = { s.min }, qtys = { s.qty or 1 } }
  end
  book = book or { prices = {}, qtys = {} }
  local info = ns.ItemCache and ns.ItemCache.Get(itemID)
  local vendor = info and info.sellPrice
  qty, hours = qty or 1, hours or 24
  local deposit = ns.Arbitrage.Deposit((vendor or 0) * qty, house, hours)
  local reference = s and (s.avg7 or s.market)
  local advice = ns.Pricing.Suggest(book, params, {
    qty = qty,
    hours = hours,
    now = now(),
    cut = ns.Settings:AuctionCut(house),
    deposit = deposit,
    vendor = vendor,
    reference = reference,
    ceiling = reference and math.max(reference, s.market or 0) * 1.5,
  })
  if advice then
    advice.book, advice.params, advice.deposit, advice.qty, advice.hours = book, params, deposit, qty, hours
    if s and s.market then
      advice.market = { price = math.floor(s.market + 0.5) } -- the item's market price (the sell bar's fourth choice)
    end
  end
  return advice
end

-- the model's chance that a post at `price` sells within its listing time (recorded with each listing you make)
function Posting:ChanceAt(shard, itemID, qty, hours, price)
  local advice = self:Suggest(shard, itemID, qty, hours)
  if not advice then
    return nil
  end
  local need = ns.Pricing.Ahead(advice.book, price) + qty
  return ns.Pricing.Chance(advice.params, need, hours, now())
end

---------------------------------------------------------------------------------------------------------------------
-- your listings and how they went

function Posting:Record(itemID, unit, qty, hours)
  if not (itemID and unit and unit > 0) then
    return
  end
  local shard = ns.AME:CurrentShard()
  -- never let a model error get in the way of posting: record the listing without its chance, and report it
  local ok, chance = pcall(self.ChanceAt, self, shard, itemID, qty or 1, hours, unit)
  if not ok then
    ns.AME:ReportError("posting price", chance)
  end
  table.insert(AME_DB.listings, {
    itemID = itemID,
    name = itemName(itemID),
    unit = unit,
    qty = qty or 1,
    hours = hours,
    t = now(),
    shard = shard,
    chance = ok and chance or nil,
  })
end

-- the game said an auction of `name` sold (or expired): learn from the oldest matching listing
function Posting:OnOutcome(name, sold)
  local list = AME_DB.listings
  local t = now()
  for i = #list, 1, -1 do -- listings past their time (+ a margin) ended without word: cancelled, or missed
    local l = list[i]
    if t - l.t > (l.hours or 48) * 3600 + 3600 then
      table.remove(list, i)
    end
  end
  for i, l in ipairs(list) do
    l.name = l.name or itemName(l.itemID)
    if l.name == name then
      table.remove(list, i)
      local p = self:Profile(l.shard, l.itemID)
      ns.Pricing.Learn(p, l.chance, sold)
      self:Save(l.shard, l.itemID, p)
      self.priors[l.shard] = nil
      return l
    end
  end
  return nil
end

function Posting:HookPosting()
  local ah = C_AuctionHouse
  local function idOf(location)
    local ok, id = pcall(function()
      return C_Item.GetItemID(location)
    end)
    return ok and id or nil
  end
  if ah and ah.PostCommodity then
    hooksecurefunc(ah, "PostCommodity", function(location, duration, quantity, unitPrice)
      self:Record(idOf(location), unitPrice, quantity, Posting.DurationHours(duration))
    end)
  end
  if ah and ah.PostItem then
    hooksecurefunc(ah, "PostItem", function(location, duration, quantity, _, buyout)
      self:Record(idOf(location), buyout, quantity, Posting.DurationHours(duration))
    end)
  end
  if PostAuction and GetAuctionSellItemInfo then -- the old auction house
    hooksecurefunc("PostAuction", function(_, buyout, runTime, stackSize, numStacks)
      local id = select(10, GetAuctionSellItemInfo())
      local size = stackSize or 1
      if buyout and buyout > 0 then
        self:Record(id, buyout / size, size * (numStacks or 1), Posting.DurationHours(runTime))
      end
    end)
  end
end
