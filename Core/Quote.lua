-- Quote: one answer to "what is this item worth here". A quote is an auction house's price context - its index, the
-- house whose cut and deposit apply, the outlier cap and the fresh-search overlay - and every price, sales rate and
-- deposit for an item comes from it, so two views can't work one out differently. (Data core, step 4: today's rules,
-- moved here; docs/plans/data-core.md.)
--
--   Quote.UnitsPerDay(s)           units a day an item sells: its sell rate, never more than is listed; nil: no rate
--   Quote.CapPrice(s, factor)      the market price, capped at factor x the 30-day average; nil: no price
--   Quote.HouseFor()               the house whose cut and deposit apply to your sales: the one you're at, your
--                                  faction's when you're at the goblin auction house
--   Quote.For(shard, index) -> q   (index: that shard's market index)
--   q:Summary(id)                  the index summary, or a copy priced at a fresh search's cheapest listing
--   q:Price(id), q:SoldPerDay(id), q:Deposit(id)
--   q:CraftEnv(producers)          the Crafting env (Core/Crafting.lua) on this quote
local _, ns = ...

local Quote = {}
Quote.__index = Quote
ns.Quote = Quote

-- an item's listings searched this recently price it instead of the day's average
Quote.FRESH_BOOK = 3600

function Quote.UnitsPerDay(s)
  local rate = s and s.sellRate
  if rate and s.qty and s.qty < rate then
    rate = s.qty
  end
  return rate
end

function Quote.CapPrice(s, factor)
  local p = s and s.market
  if not p or p <= 0 then
    return nil
  end
  if factor and factor > 1 and s.avg30 and s.avg30 > 0 then
    p = math.min(p, factor * s.avg30)
  end
  return p
end

function Quote.HouseFor()
  local here = ns.AME:CurrentHouse()
  return here == "Neutral" and (UnitFactionGroup("player") or "Horde") or here
end

function Quote.For(shard, index)
  local house = Quote.HouseFor()
  return setmetatable({
    shard = shard,
    index = index,
    house = house,
    cut = ns.Settings:AuctionCut(house),
    hours = ns.Settings:Get("listingHours"),
    factor = ns.Settings:Get("outlierFactor"),
    fresh = {},
  }, Quote)
end

-- Prices: the market index (a day's average), but an item searched in the last hour (you do when posting) is priced
-- at its cheapest listing then - what you'd pay, and what you'd have to undercut to sell. The index summary itself is
-- never changed: a copy carries the fresh price.
function Quote:Summary(id)
  local s = self.index and self.index.items[id]
  if self.fresh[id] == nil then
    local book = self.shard and ns.AME:BookFor(self.shard, id, Quote.FRESH_BOOK)
    local p = book and book.prices and book.prices[1]
    if p then
      local copy = {}
      for k, val in pairs(s or {}) do
        copy[k] = val
      end
      local listed = 0
      for _, q in ipairs(book.qtys or {}) do
        listed = listed + q
      end
      copy.market, copy.fresh = p, book.t
      copy.qty = copy.qty or listed
      self.fresh[id] = copy
    else
      self.fresh[id] = false
    end
  end
  return self.fresh[id] or s
end

function Quote:Price(id)
  return Quote.CapPrice(self:Summary(id), self.factor)
end

function Quote:SoldPerDay(id)
  return Quote.UnitsPerDay(self:Summary(id))
end

-- what listing one costs here (lost if it doesn't sell), from what a vendor pays for it
function Quote:Deposit(id)
  local sell = ns.ItemCache.Get(id).sellPrice
  return sell and ns.Arbitrage.Deposit(sell, self.house, self.hours) or 0
end

-- producers: product -> recipes that make it (chains), optional
function Quote:CraftEnv(producers)
  producers = producers or {}
  return ns.Crafting.New({
    market = function(id)
      return self:Summary(id)
    end,
    vendorBuy = function(id)
      return ns.CraftingData:VendorPrice(id)
    end,
    vendorSell = function(id)
      return ns.ItemCache.Get(id).sellPrice
    end,
    cut = self.cut,
    deposit = function(id)
      return self:Deposit(id)
    end,
    sellable = function(id)
      return ns.ItemCache.Get(id).bind ~= 1 -- 1: binds when picked up
    end,
    producers = function(id)
      return producers[id]
    end,
    factor = self.factor,
  })
end
