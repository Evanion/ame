-- WoW glue for the pricing model (Pricing.lua): learns every item's market from your scans, records what you post
-- and how it went, and answers "what should I post this at?" for the item view and the AH sell window.
--
--   AME_DB.pricing[shard][itemID] = Pricing.Encode(profile)     what each item's market does
--   AME_DB.listings = { { itemID, name, unit, qty, hours, t, shard, chance }, ... }   your posts awaiting an outcome
local _, ns = ...

local Posting = { cache = {}, priors = {}, peerItems = {} }
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
  AME_DB.sellThrough = AME_DB.sellThrough or {}
  AME_DB.sellThroughPeers = AME_DB.sellThroughPeers or {}
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
  -- what guildmates' listings of it taught their posting models counts too
  local p = ns.SellThrough.MergeProfile(self:Profile(shard, itemID), self:SharedOutcomes(shard, itemID))
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
-- and the hours it should take to sell (nil: not within a week)
function Posting:ChanceAt(shard, itemID, qty, hours, price)
  local advice = self:Suggest(shard, itemID, qty, hours)
  if not advice then
    return nil
  end
  local need = ns.Pricing.Ahead(advice.book, price) + qty
  local t = now()
  return ns.Pricing.Chance(advice.params, need, hours, t), ns.Pricing.Hours(advice.params, need, t)
end

Posting.WEEK_HOURS = 168
Posting.KEEP_LISTING = 31 * 86400 -- listings wait this long for word (auction mail is kept 30 days)
Posting.MAIL_SLACK = 2 * 3600 -- expired items come back by mail when the listing ends (a mail's age is approximate)

---------------------------------------------------------------------------------------------------------------------
-- your listings and how they went

function Posting:Record(itemID, unit, qty, hours)
  if not (itemID and unit and unit > 0) then
    return
  end
  local shard = ns.AME:CurrentShard()
  -- never let a model error get in the way of posting: record the listing without its chance, and report it
  local ok, chance, expect = pcall(self.ChanceAt, self, shard, itemID, qty or 1, hours, unit)
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
    expect = ok and chance and (expect or Posting.WEEK_HOURS) or nil, -- hours to sell, as predicted when posted
  })
end

-- An auction of `name` sold or expired. The listing it was (the one that fits best) teaches the posting model
-- whether it sold (calibration) and how fast (speed) - once - and its units count for the item's sell-through.
--   mailTime: the news came with auction mail (a sale's invoice, or the expired items coming back), which arrives
--             when the auction ends; nil: the chat message the game shows the moment it happens
--   units:    how many (the invoice's count, the items returned). The chat message doesn't say, so a sale's units
--             are counted when its mail comes; a listing of which nothing sold is counted expired right away.
function Posting:OnOutcome(name, sold, mailTime, units)
  local list = AME_DB.listings
  local t = now()
  for i = #list, 1, -1 do -- listings that never got word (the mail was never opened)
    if t - list[i].t > Posting.KEEP_LISTING then
      table.remove(list, i)
    end
  end
  local best, at, score
  for i, l in ipairs(list) do
    l.name = l.name or itemName(l.itemID)
    if l.name == name then
      local ends = l.t + (l.hours or 48) * 3600
      local fits, rank
      if not mailTime then
        -- live news: a listing still running (for an expiry, the one ending now)
        fits = t <= ends + 3600 and l.heard ~= "expired"
        rank = sold and l.t or math.abs(ends - t)
      elseif sold then
        -- a sale's invoice: a listing posted before it, one the chat already said sold first
        fits = l.t <= mailTime
        rank = (l.heard == "sold" and 0 or 1e10) + l.t
      else
        -- expired items back in the mail: a listing that ended when the mail came (or the chat said expired)
        fits = l.t <= mailTime and (l.heard ~= nil or math.abs(ends - mailTime) <= Posting.MAIL_SLACK)
        rank = (l.heard == "expired" and 0 or 1e10) + math.abs(ends - mailTime)
      end
      if fits and (not score or rank < score) then
        best, at, score = l, i, rank
      end
    end
  end
  local l = best
  if not l then
    return nil
  end
  if not l.heard then
    local p = self:Profile(l.shard, l.itemID)
    ns.Pricing.Learn(p, l.chance, sold)
    if sold and mailTime then
      ns.Pricing.LearnSpeed(p, l.expect, "within", (mailTime - l.t) / 3600)
    elseif sold then
      ns.Pricing.LearnSpeed(p, l.expect, "exact", (t - l.t) / 3600)
    else
      ns.Pricing.LearnSpeed(p, l.expect, "expired", l.hours or 48)
    end
    self:Save(l.shard, l.itemID, p)
    self.priors[l.shard] = nil
  end
  if mailTime then
    self:Settle(at, l, sold and "sold" or "expired", units)
  elseif not sold and l.heard ~= "sold" then
    self:Settle(at, l, "expired") -- nothing of it sold: all of it came back
  else
    l.heard = l.heard or (sold and "sold" or "expired")
  end
  return l
end

-- Units of a listing that ended one way ("sold" / "expired" / "cancelled") count for its item's sell-through; the
-- listing is done once all its units are accounted for.
function Posting:Settle(i, l, kind, units)
  local left = l.left or l.qty or 1
  units = math.min(units or left, left)
  self:Tally(l.shard, l.itemID, kind, units)
  l.left = left - units
  l.heard = l.heard or (kind == "sold" and "sold" or "expired")
  if l.left <= 0 and AME_DB.listings[i] == l then
    table.remove(AME_DB.listings, i)
  end
end

-- You cancelled an auction: its units count as not sold (as TradeSkillMaster counts them).
function Posting:OnCancel(key, qty)
  for i, l in ipairs(AME_DB.listings) do
    if l.itemID == key then
      self:Settle(i, l, "cancelled", qty)
      return l
    end
  end
  self:Tally(ns.AME:CurrentShard(), key, "cancelled", qty or 1) -- posted before AME recorded listings
  return nil
end

-- the owned auction the game is cancelling (C_AuctionHouse.CancelAuction's ID)
function Posting:Cancelled(auctionID)
  local ah = C_AuctionHouse
  for i = 1, ah.GetNumOwnedAuctions() or 0 do
    local info = ah.GetOwnedAuctionInfo(i)
    local k = info and info.itemKey
    if k and info.auctionID == auctionID then
      local key = ns.ItemKey(k.itemID, k.itemSuffix)
      if info.itemLink then
        key = ns.ItemCache.Pair(info.itemLink, k.itemID, k.itemSuffix)
      end
      self:OnCancel(key, info.quantity or 1)
      return
    end
  end
end

---------------------------------------------------------------------------------------------------------------------
-- sell-through (SellThrough.lua): yours, and your guildmates' over sync
--
--   AME_DB.sellThrough[shard][key] = SellThrough.Encode(record)              your listings' outcomes
--   AME_DB.sellThroughPeers[shard][playerKey] = { name, t, items = text }    what each guildmate last shared

function Posting:Tally(shard, key, kind, units)
  if not (shard and key) then
    return
  end
  local own = AME_DB.sellThrough
  own[shard] = own[shard] or {}
  local s = own[shard][key]
  local r = s and ns.SellThrough.Decode(s) or ns.SellThrough.New()
  if ns.SellThrough.Add(r, kind, units, now()) then
    own[shard][key] = ns.SellThrough.Encode(r)
    self.stChanged = true
    self:SellThroughChanged(shard, 5)
  end
end

-- sell-through changed for a house: its market index picks it up once things have been quiet for `delay` seconds
-- (nil: a minute)
function Posting:SellThroughChanged(shard, delay)
  self.peerItems[shard] = nil
  if ns.AME.InvalidateIndexLater then
    ns.AME:InvalidateIndexLater(shard, delay)
  end
end

local function blocked(name)
  local trust = ns.SyncService and ns.SyncService.trust
  return trust and trust:IsBlocked(name) and true or false
end

-- every guildmate's shared items for a house, decoded once: { { name, t, items = { [key] = shared } }, ... }
function Posting:Peers(shard)
  local cached = self.peerItems[shard]
  if cached then
    return cached
  end
  local out, cutoff = {}, now() - ns.SellThrough.PEER_AGE
  local peers = AME_DB.sellThroughPeers[shard] or {}
  for k, p in pairs(peers) do
    if (p.t or 0) < cutoff then
      peers[k] = nil
    else
      out[#out + 1] = { name = p.name, t = p.t, items = ns.SellThrough.DecodeItems(p.items, p.t) }
    end
  end
  self.peerItems[shard] = out
  return out
end

-- A guildmate's numbers arrived. They send all of theirs each time: the newest replace the last.
function Posting:SetPeer(shard, sender, t, text)
  if type(text) ~= "string" or #text > 20000 then
    return false
  end
  AME_DB.sellThroughPeers[shard] = AME_DB.sellThroughPeers[shard] or {}
  AME_DB.sellThroughPeers[shard][ns.Trust.Key(sender)] =
    { name = sender, t = math.min(t or now(), now()), items = text }
  self:SellThroughChanged(shard) -- once guildmates have been quiet a minute
  return true
end

-- Sell-through totals for every item with data at an auction house: { [key] = SellThrough.Combine totals }.
-- Blocked players' numbers are left out.
function Posting:SellThroughTotals(shard)
  local t = now()
  local shared = {}
  for _, p in ipairs(self:Peers(shard)) do
    if not blocked(p.name) then
      for key, o in pairs(p.items) do
        shared[key] = shared[key] or {}
        table.insert(shared[key], { t = p.t, r = o.r })
      end
    end
  end
  local own = AME_DB.sellThrough[shard] or {}
  local out = {}
  for key, s in pairs(own) do
    out[key] = ns.SellThrough.Combine(ns.SellThrough.Decode(s), shared[key], t)
  end
  for key, list in pairs(shared) do
    if not own[key] then
      out[key] = ns.SellThrough.Combine(nil, list, t)
    end
  end
  return out
end

-- guildmates' posting outcomes for one item (calibration and speed), for SellThrough.MergeProfile
function Posting:SharedOutcomes(shard, key)
  local out = {}
  for _, p in ipairs(self:Peers(shard)) do
    local o = p.items[key]
    if o and not blocked(p.name) and (o.no > 0 or o.sn > 0) then
      out[#out + 1] = o
    end
  end
  return out
end

-- what you share for a house: your items, the ones with the most outcomes first (SellThrough.EncodeItems entries)
function Posting:ShareEntries(shard)
  local t, out = now(), {}
  for key, s in pairs(AME_DB.sellThrough[shard] or {}) do
    local r = ns.SellThrough.Decay(ns.SellThrough.Decode(s), t)
    if r.n >= 0.05 then
      local p = self:Peek(shard, key)
      out[#out + 1] = { key, r, p.calib, p.no, p.speed, p.sn }
    end
  end
  table.sort(out, function(a, b)
    return a[2].n > b[2].n
  end)
  return out
end

function Posting:HookPosting()
  local ah = C_AuctionHouse
  local function idOf(location)
    return ns.ItemCache.KeyAt(location)
  end
  if ah and ah.PostCommodity then
    hooksecurefunc(ah, "PostCommodity", function(location, duration, quantity, unitPrice)
      self:Record(idOf(location), unitPrice, quantity, Posting.DurationHours(duration))
    end)
  end
  if ah and ah.CancelAuction and ah.GetOwnedAuctionInfo then
    hooksecurefunc(ah, "CancelAuction", function(auctionID)
      local ok, err = pcall(self.Cancelled, self, auctionID)
      if not ok then
        ns.AME:ReportError("cancel", err)
      end
    end)
  end
  if ah and ah.PostItem then
    hooksecurefunc(ah, "PostItem", function(location, duration, quantity, _, buyout)
      self:Record(idOf(location), buyout, quantity, Posting.DurationHours(duration))
    end)
  end
  if PostAuction and GetAuctionSellItemInfo then -- the old auction house
    hooksecurefunc("PostAuction", function(_, buyout, runTime, stackSize, numStacks)
      local name, _, _, _, _, _, _, _, _, id = GetAuctionSellItemInfo()
      id = id and ns.ItemCache.KeyFor(id, name)
      local size = stackSize or 1
      if buyout and buyout > 0 then
        self:Record(id, buyout / size, size * (numStacks or 1), Posting.DurationHours(runTime))
      end
    end)
  end
end
