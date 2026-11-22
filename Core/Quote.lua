-- Quote: one answer to "what is this item worth here". A quote is an auction house's price context - its index, the
-- house whose cut and deposit apply, the outlier cap and the fresh-search overlay - and every price, sales rate and
-- deposit for an item comes from it, so two views can't work one out differently. (Data core, steps 4 and 11;
-- docs/plans/data-core.md.)
--
--   Quote.UnitsPerDay(s)           units a day an item sells: its sell rate, never more than is listed; nil: no rate
--                                  (saved in the index as s.soldPerDay: what every "Sells/day" shows)
--   Quote.CapPrice(s, factor)      the market price, capped at factor x the 30-day average; nil: no price
--   Quote.Net(s, cut, deposit, factor)  what listing one unit nets: the capped price after the cut, less the deposit
--                                  as often as listings fail (SellThrough.Net); nil: no price (saved as s.net)
--   Quote.HouseFor()               the house whose cut and deposit apply to your sales: the one you're at, your
--                                  faction's when you're at the goblin auction house
--   Quote.Cut(house)               a house's cut (0.05): the one you're at with nil
--   Quote.ShardHouse(shard)        a shard's house ("realm|Horde" -> "Horde"), else the one you're at
--   Quote.PostNet(shard, price, deposit, qty)  your money per unit posting qty at price there: after its cut, less
--                                  the deposit you pay to list them
--   Quote.For(shard, index, opts) -> q   (index: that shard's market index; opts.house: whose cut and deposit,
--                                  default HouseFor(); opts.fresh = false: no fresh-search overlay)
--   q:Summary(id)                  the index summary, or a copy priced at a fresh search's cheapest listing
--   q:Price(id), q:SoldPerDay(id)
--   q:Deposit(id, units)           the deposit per unit for listing that many (default 1) here, your usual length
--   q:ListingNet(id)               Quote.Net for one unit at this house
--   q:BestSale(id) -> net, where   the better of the auction house ("ah": ListingNet) and a vendor ("vendor");
--                                  nil, "unsellable" for a bind-on-pickup item; nil without either
--   q:Worth(id)                    what one unit you hold is worth: BestSale's net (the portfolio, the Sell tab)
--   q:WorthOf(counts) -> total, unpriced   { [id] = n } at Worth; unpriced: how many kinds have no price
--   q:Disenchant(id)               gear: { value, outcomes = { { item, name, chance, min, max, price } }, level,
--                                  classID } with the materials at BestSale (value nil while one has no price)
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

function Quote.Net(s, cut, deposit, factor)
  local p = Quote.CapPrice(s, factor)
  if not p then
    return nil
  end
  local capped = { market = p, sellThrough = s.sellThrough, stWeight = s.stWeight }
  if ns.SellThrough then
    return ns.SellThrough.Net(capped, cut, deposit)
  end
  return p * (1 - (cut or 0)) - (deposit or 0)
end

function Quote.Cut(house)
  return ns.Settings:AuctionCut(house or ns.AME:CurrentHouse()) or 0
end

function Quote.ShardHouse(shard)
  local _, house = ns.SplitShard(shard or "")
  return house or ns.AME:CurrentHouse()
end

function Quote.PostNet(shard, price, deposit, qty)
  return price * (1 - Quote.Cut(Quote.ShardHouse(shard))) - (deposit or 0) / math.max(1, qty or 1)
end

function Quote.HouseFor()
  local here = ns.AME:CurrentHouse()
  return here == "Neutral" and (UnitFactionGroup("player") or "Horde") or here
end

function Quote.For(shard, index, opts)
  opts = opts or {}
  local house = opts.house or Quote.HouseFor()
  return setmetatable({
    shard = shard,
    index = index,
    house = house,
    cut = ns.Settings:AuctionCut(house),
    hours = ns.Settings:Get("listingHours"),
    factor = ns.Settings:Get("outlierFactor"),
    fresh = {},
    noFresh = opts.fresh == false,
  }, Quote)
end

-- Prices: the market index (a day's average), but an item searched in the last hour (you do when posting) is priced
-- at its cheapest listing then - what you'd pay, and what you'd have to undercut to sell. The index summary itself is
-- never changed: a copy carries the fresh price.
function Quote:Summary(id)
  local s = self.index and self.index.items[id]
  if self.noFresh then
    return s
  end
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

-- what listing one costs here (lost if it doesn't sell), from what a vendor pays for it; a post of several pays
-- one deposit for them all (rounded once)
function Quote:Deposit(id, units)
  local sell = ns.ItemCache.Get(id).sellPrice
  units = math.max(1, units or 1)
  return sell and ns.Arbitrage.Deposit(sell * units, self.house, self.hours) / units or 0
end

function Quote:ListingNet(id)
  local s = self:Summary(id)
  return s and Quote.Net(s, self.cut, self:Deposit(id), self.factor)
end

function Quote:BestSale(id)
  local info = ns.ItemCache.Get(id)
  if info.bind == 1 then -- binds when picked up
    return nil, "unsellable"
  end
  local best, where = self:ListingNet(id), nil
  if best then
    where = "ah"
  end
  local v = info.sellPrice
  if v and v > 0 and (not best or v > best) then
    best, where = v, "vendor"
  end
  return best, where
end

function Quote:Worth(id)
  return (self:BestSale(id))
end

function Quote:WorthOf(counts)
  local total, unpriced = 0, 0
  for id, n in pairs(counts or {}) do
    local each = self:Worth(id)
    if each then
      total = total + each * n
    else
      unpriced = unpriced + 1
    end
  end
  return total, unpriced
end

function Quote:Disenchant(id)
  local info = ns.ItemCache.Get(id)
  if not (info.classID == 2 or info.classID == 4) or not ns.Disenchant then
    return nil
  end
  local quality = info.quality
  local outcomes = quality and quality >= 2 and ns.Disenchant.Outcomes(info.level, quality, info.classID)
  if not outcomes then
    return nil
  end
  local out, value = { outcomes = {}, level = info.level, classID = info.classID }, 0
  for i, o in ipairs(outcomes) do
    local price = self:BestSale(o[1])
    out.outcomes[i] =
      { item = o[1], name = ns.ItemCache.Name(o[1]), chance = o[2], min = o[3], max = o[4], price = price }
    value = value and price and value + price * o[2] * (o[3] + o[4]) / 2 or nil
  end
  table.sort(out.outcomes, function(a, b)
    return a.chance > b.chance
  end)
  out.value = value
  return out
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
