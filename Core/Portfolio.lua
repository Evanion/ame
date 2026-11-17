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

-- positions sorted by value, plus totals { value, cost (of the part with a known cost), unrealized }
function Portfolio.Build(holdings, basis, items)
  local rows = {}
  local totals = { value = 0, cost = 0, unrealized = 0, positions = 0 }
  for itemID, h in pairs(Portfolio.Merge(holdings)) do
    local s = items and items[itemID]
    if s and s.market and h.qty > 0 then
      local b = basis and basis[itemID]
      local value = s.market * h.qty
      local row = {
        itemID = itemID,
        qty = h.qty,
        chars = h.chars,
        market = s.market,
        value = value,
        signal = s.signal,
        sellRate = s.sellRate,
        daysToSell = s.sellRate and s.sellRate > 0 and h.qty / s.sellRate or nil,
      }
      if b then
        -- cost is known for the units bought on the AH (the rest were looted, crafted...)
        local known = math.min(b.units, h.qty)
        row.unitCost = b.unit
        row.cost = known * b.unit
        row.unrealized = known * (s.market - b.unit)
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
