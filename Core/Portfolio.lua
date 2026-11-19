-- Portfolio (pure): what you hold, what it's worth, and how it's doing.
--
--   holdings = { [charKey] = { bags = { [itemID] = qty }, bank = {...}, auctions = {...}, t = time } }
--   basis    = Ledger:CostBasis()  { [itemID] = { units, unit } }
--   items    = market index items  { [itemID] = { market, signal, sellRate, ... } }
-- Positions without a market price are left out (not tradeable or never seen on the AH).
local _, ns = ...

local Portfolio = {}
ns.Portfolio = Portfolio

-- total held per item across characters and places: { [itemID] = { qty, chars = { [charKey] = qty } } }
function Portfolio.Merge(holdings)
  local out = {}
  for char, h in pairs(holdings or {}) do
    for _, place in ipairs({ "bags", "bank", "auctions" }) do
      for itemID, qty in pairs(h[place] or {}) do
        local e = out[itemID]
        if not e then
          e = { qty = 0, chars = {} }
          out[itemID] = e
        end
        e.qty = e.qty + qty
        e.chars[char] = (e.chars[char] or 0) + qty
      end
    end
  end
  return out
end

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

-- what one unit is worth: its value when real auction outcomes say how often it sells (SellThrough.Apply), else the
-- market price
local function worth(s)
  return s.value or s.market
end

-- positions sorted by value, plus totals { value, cost (of the part with a known cost), unrealized, positions,
-- hidden, hiddenValue }. hide (optional): items left out (hidden from lists), counted in hidden / hiddenValue.
function Portfolio.Build(holdings, basis, items, hide)
  local rows = {}
  local totals = { value = 0, cost = 0, unrealized = 0, positions = 0, hidden = 0, hiddenValue = 0 }
  for itemID, h in pairs(Portfolio.Merge(holdings)) do
    local s = items and items[itemID]
    if s and s.market and h.qty > 0 and hide and hide[itemID] then
      totals.hidden, totals.hiddenValue = totals.hidden + 1, totals.hiddenValue + worth(s) * h.qty
    elseif s and s.market and h.qty > 0 then
      local b = basis and basis[itemID]
      local value = worth(s) * h.qty
      local row = {
        itemID = itemID,
        qty = h.qty,
        chars = h.chars,
        market = s.market,
        value = value,
        signal = s.signal,
        signalRank = s.signalRank,
        sellRate = s.sellRate,
        daysToSell = s.sellRate and s.sellRate > 0 and h.qty / s.sellRate or nil,
      }
      if b then
        -- cost is known for the units bought on the AH (the rest were looted, crafted...)
        local known = math.min(b.units, h.qty)
        row.unitCost = b.unit
        row.cost = known * b.unit
        row.unrealized = known * (worth(s) - b.unit)
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
