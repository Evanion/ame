-- Portfolio (pure): what you hold, what it's worth, and how it's doing.
--
--   holdings = { [charKey] = { bags = { [itemID] = qty }, bank = {...}, auctions = {...}, t = time } }
--   held     = Holdings.Map of them (Holdings.Of("owned"))
--   basis    = Ledger:CostBasis()  { [itemID] = { units, unit } }
--   items    = market index items  { [itemID] = { market, signal, soldPerDay, ... } }
-- Positions without a market price are left out (not tradeable or never seen on the AH).
local _, ns = ...

local Portfolio = {}
ns.Portfolio = Portfolio

-- What's listed on the auction house right now, across characters:
--   { count, value (asking prices), net (after each house's cut), market (at market price), chars = {...} }
-- cut(house) gives the seller's cut fraction; items = market summaries
function Portfolio.Listed(holdings, cut, items)
  local out = { count = 0, value = 0, net = 0, market = 0, chars = {} }
  for char, h in pairs(holdings or {}) do
    local l = h.listed
    if l and l.count > 0 then
      local net = l.value * (1 - (cut and cut(l.house) or 0))
      local market = 0
      for itemID, qty in pairs(h.auctions or {}) do
        local s = items and items[itemID]
        market = market + (s and s.market or 0) * qty
      end
      out.count, out.value, out.net, out.market =
        out.count + l.count, out.value + l.value, out.net + net, out.market + market
      out.chars[char] = { count = l.count, value = l.value, net = net, house = l.house }
    end
  end
  return out
end

-- what one unit is worth, from the index: what selling it nets - listed (s.net: after the cut and the deposit, as
-- often as listings fail) or at a vendor, whichever is more (Quote:Worth's rule)
function Portfolio.Worth(s)
  local n, v = s.net, s.vendorPrice
  if v and v > 0 and (not n or v > n) then
    return v
  end
  return n
end

-- positions sorted by value, plus totals { value, cost (of the part with a known cost), unrealized, positions,
-- hidden, hiddenValue }. held: what you own, as Holdings.Map counts it (Holdings.Of("owned")). hide (optional):
-- items left out (hidden from lists), counted in hidden / hiddenValue. worth(itemID, s) (optional): what one unit is
-- worth (the view passes Quote:Worth; default Portfolio.Worth)
function Portfolio.Build(held, basis, items, hide, worthOf)
  local rows = {}
  local totals = { value = 0, cost = 0, unrealized = 0, positions = 0, hidden = 0, hiddenValue = 0 }
  for itemID, h in pairs(held or {}) do
    local s = items and items[itemID]
    local each = s and s.market and (worthOf and worthOf(itemID, s) or (not worthOf and Portfolio.Worth(s))) or nil
    if each and h.qty > 0 and hide and hide[itemID] then
      totals.hidden, totals.hiddenValue = totals.hidden + 1, totals.hiddenValue + each * h.qty
    elseif each and h.qty > 0 then
      local b = basis and basis[itemID]
      local value = each * h.qty
      local row = {
        itemID = itemID,
        qty = h.qty,
        chars = h.chars,
        market = s.market,
        value = value,
        signal = s.signal,
        signalRank = s.signalRank,
        soldPerDay = s.soldPerDay,
        daysToSell = s.soldPerDay and s.soldPerDay > 0 and h.qty / s.soldPerDay or nil,
      }
      if b then
        -- cost is known for the units bought on the AH (the rest were looted, crafted...)
        local known = math.min(b.units, h.qty)
        row.unitCost = b.unit
        row.cost = known * b.unit
        row.unrealized = known * (each - b.unit)
        totals.cost = totals.cost + row.cost
        totals.unrealized = totals.unrealized + row.unrealized
      end
      totals.value = totals.value + value
      totals.positions = totals.positions + 1
      rows[#rows + 1] = row
    end
  end
  table.sort(rows, function(a, b)
    if a.value == b.value then
      return a.itemID < b.itemID
    end
    return a.value > b.value
  end)
  return rows, totals
end
